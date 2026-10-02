import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal, flushSync } from "react-dom";
import MindElixir, { type NodeObj, type Topic, type MindElixirData, type SubLineParams } from "mind-elixir";
import { EditorView } from "prosemirror-view";
import { TextSelection, AllSelection } from "prosemirror-state";
import { splitListItem } from "prosemirror-schema-list";
import { addBridgeListener, sendEnvelope, sendToNative } from "./bridge";
import MindMapOutline from "./MindMapOutline";
import RichEditor, { type EditorHandle } from "./mindmap/RichEditor";
import NodeToolbar from "./mindmap/NodeToolbar";
import { trackKeyboardViewport } from "./mindmap/keyboardViewport";
import { DocumentStore, parseDocument, newDocument, findNode, parentOf, visibleNodes, structure, moveNodes, newNode, descendantCount, type MapDocument, type MapNode, type Cursor, type RichDocument, type StructureAction } from "./mindmap/document";
import { readContent, renderContent, contentText, schema, safeLink } from "./mindmap/richText";
import "mind-elixir/style.css";
import "./mindmap/editor.css";

declare global { interface Window { siyeFlush?: () => Promise<boolean>; siyeExport?: (format: "svg" | "png") => Promise<Blob | null> } }
type Props = { docId: string; data: Record<string, unknown> | null; readOnly: boolean; theme: "light" | "dark"; onReady: (instance: MindElixir | null) => void; onDocumentReady?: (getDocument: (() => MapDocument) | null) => void };
type Pending = { resolve: (payload: Record<string, unknown>) => void; reject: (error: Error) => void; timeout: number };
function validated(data: Props["data"]): MapDocument | null {
  const parsed = data === null ? newDocument() : parseDocument(data);
  if (!parsed) return null;
  try { const visit = (node: MapNode) => { readContent(node.content); node.children.forEach(visit); }; visit(parsed.nodeData); return parsed; } catch { return null; }
}
export default function MindMapEditor(props: Props) {
  const [store] = useState(() => { const document = validated(props.data); return document ? new DocumentStore(document) : null; });
  const [, redraw] = useState(0);
  const [editing, setEditing] = useState<string | null>(null);
  const [restore, setRestore] = useState<Cursor | null>(null), [anchor, setAnchor] = useState<HTMLElement | null>(null);
  const [active, setActive] = useState<EditorHandle | null>(null), [error, setError] = useState(""), [saving, setSaving] = useState(false);
  const [nodeMenu, setNodeMenu] = useState<{ id: string; x: number; y: number } | null>(null);
  const longPress = useRef<{ timer: number; x: number; y: number } | null>(null);
  const suppressTap = useRef(false);
  const cancelLongPress = () => {
    if (longPress.current) window.clearTimeout(longPress.current.timer);
    longPress.current = null;
  };
  useEffect(() => () => cancelLongPress(), []);
  const editorHost = useRef<HTMLDivElement>(null);
  const host = useRef<HTMLDivElement>(null), mind = useRef<MindElixir | null>(null), activeRef = useRef<EditorHandle | null>(null);
  const latest = useRef(props); latest.current = props;
  const uploads = useRef(new Set<Promise<void>>());
  const pending = useRef(new Map<string, Pending>()), timer = useRef<number>(), savedRevision = useRef(0), flight = useRef<Promise<boolean> | null>(null);
  const contentCursors = useRef(new Map<string, Cursor>());
  const renderedNodes = useRef(new Map<string, { content: RichDocument; docId: string; expanded: boolean; children: number; html: string }>());
  const shape = useRef(""), syncing = useRef(false), raf = useRef(0);
  const doc = store?.document, mode = doc?.views.mode ?? "outline";
  useEffect(() => { cancelLongPress(); setNodeMenu(null); }, [mode, props.readOnly]);
  const root = doc && (doc.views.focusId ? findNode(doc.nodeData, doc.views.focusId) : null) || doc?.nodeData;
  const selected = doc?.views.selectedIds ?? [], selectedId = selected[0] ?? active?.id;
  const callbacks = useRef({} as { focus: (id: string | null) => void; select: (id: string, multiple?: boolean) => void; edit: (id: string, atEnd?: boolean) => void; action: (action: StructureAction, ids?: string[]) => void; move: (ids: string[], target: string, placement: "before" | "after" | "inside") => void; change: (fn: (doc: MapDocument) => void, group?: string | null) => void; view: (fn: (doc: MapDocument) => void) => void });
  useEffect(() => {
    const nativePress = (event: Event) => {
      if (latest.current.readOnly) return;
      const { x, y } = (event as CustomEvent<{ x: number; y: number }>).detail;
      const target = document.elementFromPoint(x, y);
      if (!target || target.closest("button,input,textarea,.mindmap-node-menu")) return;
      const topic = target.closest("me-tpc") as Topic | null;
      const id = topic?.nodeObj.id ?? target.closest<HTMLElement>("[data-editor-id]")?.dataset.editorId ?? target.closest<HTMLElement>("[data-outline-id]")?.dataset.outlineId;
      if (!id) return;
      cancelLongPress();
      (document.activeElement as HTMLElement | null)?.blur();
      callbacks.current.select(id);
      setNodeMenu({ id, x, y });
    };
    window.addEventListener("siye-node-long-press", nativePress);
    return () => window.removeEventListener("siye-node-long-press", nativePress);
  }, []);
  const request = (type: string, payload: Record<string, unknown>): Promise<Record<string, unknown>> => new Promise((resolve, reject) => {
    const requestId = crypto.randomUUID();
    const timeout = window.setTimeout(() => { pending.current.delete(requestId); reject(new Error("保存未收到应用确认，请重试")); }, 10000);
    pending.current.set(requestId, { resolve, reject, timeout }); sendToNative(sendEnvelope(type, { ...payload, requestId }));
  });
  const captureMap = () => { if (!store || !mind.current || syncing.current) return; const map = mind.current; store.document.views.map = { scale: map.scaleVal, x: new DOMMatrixReadOnly(map.map.style.transform).m41, y: new DOMMatrixReadOnly(map.map.style.transform).m42 }; };
  const flush = async (): Promise<boolean> => {
    window.clearTimeout(timer.current); if (!store || latest.current.readOnly) return true;
    if (uploads.current.size) { await Promise.all([...uploads.current]); window.clearTimeout(timer.current); }
    if (flight.current) { const okay = await flight.current; return okay ? flush() : false; }
    captureMap(); if (savedRevision.current === store.revision) return true;
    const revision = store.revision, sceneJSON = JSON.stringify(store.document); setSaving(true);
    const task = (async () => { try { await request("saveScene", { docId: latest.current.docId, sceneJson: sceneJSON, source: "web" }); savedRevision.current = revision; setError(""); return true; } catch (failure) { setError(failure instanceof Error ? failure.message : "保存失败"); return false; } finally { setSaving(false); flight.current = null; } })();
    flight.current = task; const okay = await task;
    if (okay && store.revision !== revision) return flush(); return okay;
  };
  const schedule = () => { if (props.readOnly || !store) return; const alreadyScheduled = timer.current !== undefined; window.clearTimeout(timer.current); timer.current = window.setTimeout(() => { timer.current = undefined; void flush(); }, 500); if (!alreadyScheduled) sendToNative(sendEnvelope("didChange", { docId: props.docId, dirty: true })); };
  const update = () => redraw(value => value + 1);
  const change = (mutate: (doc: MapDocument) => void, group: string | null = null) => { if (!store || props.readOnly) return; if (store.change(mutate, group)) { update(); schedule(); } };
  const updateView = (mutate: (doc: MapDocument) => void) => { if (!store) return; mutate(store.document); update(); if (!props.readOnly) { store.revision++; schedule(); } };
  const select = (id: string, multiple = false) => {
    if (!store || !findNode(store.document.nodeData, id)) return;
    if (!multiple && store.document.views.selectedIds.length === 1 && selectedId === id) return;
    store.boundary(); if (editing !== id || multiple) { setEditing(null); activeRef.current = null; setActive(null); }
    updateView(document => { document.views.selectedIds = multiple ? document.views.selectedIds.includes(id) ? document.views.selectedIds.filter(item => item !== id) : [...document.views.selectedIds, id] : [id]; });
  };
  const edit = (id: string, atEnd = false) => {
    if (props.readOnly || !store) return;
    const node = findNode(store.document.nodeData, id); if (!node) return;
    const end = TextSelection.atEnd(readContent(node.content)).from;
    select(id); setEditing(id);
    setRestore(!atEnd && contentCursors.current.get(id) || { id, from: end, to: end, field: "content" });
  };
  const action = (action: StructureAction, ids = store?.document.views.selectedIds ?? []) => {
    if (!store || props.readOnly) return; if (action === "sibling" && ids[0] === root?.id) action = "child"; activeRef.current = null; setActive(null); setEditing(null); let next: string | null = null;
    change(document => { next = structure(document.nodeData, ids, action); if (next) document.views.selectedIds = [next]; });
    if (next && ["child", "sibling"].includes(action)) { setEditing(next); setRestore({ id: next, from: 1, to: 1, field: "content" }); }
  };
  const move = (ids: string[], target: string, placement: "before" | "after" | "inside") => { setEditing(null); activeRef.current = null; setActive(null); change(document => { if (moveNodes(document.nodeData, ids, target, placement)) document.views.selectedIds = ids; }); };
  callbacks.current = { focus: id => focus(id), select, edit, action, move, change, view: updateView };
  const onActive = (handle: EditorHandle) => {
    if (!store) return;
    const changedNode = activeRef.current?.id !== handle.id;
    activeRef.current = handle; setActive({ ...handle });
    store.cursor = { id: handle.id, from: handle.view.state.selection.from, to: handle.view.state.selection.to, field: "content" };
    contentCursors.current.set(handle.id, { ...store.cursor });
    if (changedNode) { store.boundary(); if (!store.document.views.selectedIds.includes(handle.id)) { store.document.views.selectedIds = [handle.id]; update(); } }
  };
  const content = (id: string, value: RichDocument, before: Cursor, after: Cursor) => {
    if (!store) return; store.cursor = before; change(document => { const node = findNode(document.nodeData, id); if (node) node.content = value; }, `content:${id}`); store.cursor = after;
  };
  const undo = (redo = false) => {
    if (!store || props.readOnly || !(redo ? store.redo() : store.undo())) return;
    const cursor = store.cursor; setEditing(cursor?.id ?? null); setRestore(cursor && { ...cursor }); activeRef.current = null; setActive(null); update(); schedule();
  };
  const focusCursor = (id: string, end = false) => { if (!store) return; select(id); const size = readContent(findNode(store.document.nodeData, id)!.content).content.size; setEditing(id); setRestore({ id, from: end ? Math.max(1, size - 1) : 1, to: end ? Math.max(1, size - 1) : 1, field: "content" }); };
  const onKey = (id: string, view: EditorView, event: KeyboardEvent): boolean => {
    if (!store || props.readOnly || event.isComposing || view.composing) return false;
    if (event.key === "Enter" && event.shiftKey) {
      const mobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
      if (mode === "outline" && !mobile && !event.metaKey && !event.ctrlKey && !event.altKey) {
        action("sibling", [id]); return true;
      }
      return false;
    }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "z") { undo(event.shiftKey); return true; }
    if (event.key === "Escape") { view.dom.blur(); setEditing(null); activeRef.current = null; setActive(null); return true; }
    const selection = view.state.selection, inComplex = selection.$from.depth > 1 || selection.$from.parent.type.name === "code_block";
    if (event.key === "Enter" && selection.$from.parent.type.name === "paragraph" && selection.$from.depth > 1) {
      if (splitListItem(schema.nodes.list_item)(view.state, view.dispatch)) return true;
    }
    if (mode !== "outline" || inComplex) return false;
    if (event.key === "Tab") { action(event.shiftKey ? "outdent" : "indent", [id]); return true; }
    const node = findNode(store.document.nodeData, id)!;
    if (event.key === "Backspace" && !contentText(node.content) && !node.note && !node.children.length && id !== store.document.nodeData.id) { action("delete", [id]); requestAnimationFrame(() => { const target = store.document.views.selectedIds[0]; if (target) focusCursor(target, true); }); return true; }
    if (selection.empty && ((event.key === "ArrowUp" || event.key === "ArrowLeft") && selection.from <= 1 || (event.key === "ArrowDown" || event.key === "ArrowRight") && selection.to >= view.state.doc.content.size - 1)) {
      const nodes = visibleNodes(root!), index = nodes.findIndex(node => node.id === id), previous = ["ArrowUp", "ArrowLeft"].includes(event.key); const target = nodes[index + (previous ? -1 : 1)]; if (target) { focusCursor(target.id, previous); return true; }
    }
    return false;
  };
  const ensureEditor = async (wholeNode = false): Promise<EditorHandle | null> => {
    if (!store || props.readOnly) return null;
    if (activeRef.current?.view.dom.isConnected && activeRef.current.id === (store.document.views.selectedIds[0] ?? activeRef.current.id)) {
      const handle = activeRef.current;
      if (!wholeNode && handle.view.state.selection instanceof AllSelection) handle.view.dispatch(handle.view.state.tr.setSelection(TextSelection.atEnd(handle.view.state.doc)));
      return handle;
    }
    const id = store.document.views.selectedIds[0]; if (!id) return null; edit(id);
    await new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    const handle = activeRef.current; if (!handle || handle.id !== id) return null;
    handle.view.dispatch(handle.view.state.tr.setSelection(wholeNode ? new AllSelection(handle.view.state.doc) : TextSelection.atEnd(handle.view.state.doc))); return handle;
  };
  const image = async (file: File, view: EditorView) => {
    if (props.readOnly) return;
    if (!/^image\/(png|jpeg|gif|webp)$/.test(file.type) || file.size > 10 * 1024 * 1024) { setError("图片支持 PNG、JPEG、GIF、WebP，大小不超过 10MB"); return; }
    const id = activeRef.current?.id, bookmark = view.state.selection.getBookmark();
    try {
      const base64 = await new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result).split(",")[1]); reader.onerror = () => reject(new Error("读取图片失败")); reader.readAsDataURL(file); });
      const response = await request("saveAttachment", { docId: props.docId, fileName: file.name, mimeType: file.type, dataBase64: base64 });
      if (!view.dom.isConnected || !id || activeRef.current?.id !== id) { setError("图片已保存，请在目标节点中重新插入"); return; }
      const selection = bookmark.resolve(view.state.doc); store?.boundary(); view.dispatch(view.state.tr.setSelection(selection).replaceSelectionWith(schema.nodes.image.create({ path: response.relativePath, width: 240, alt: file.name })).scrollIntoView()); store?.boundary(); view.focus(); setError("");
    } catch (failure) { setError(failure instanceof Error ? failure.message : "图片保存失败"); }
  };
  const upload = (file: File, view: EditorView) => { const task = image(file, view); uploads.current.add(task); void task.finally(() => uploads.current.delete(task)); };
  const resize = () => { cancelAnimationFrame(raf.current); raf.current = requestAnimationFrame(() => { if (mind.current && mode === "map") mind.current.linkDiv(); }); };
  useEffect(() => {
    const unsubscribe = addBridgeListener(message => {
      if (!["saveResult", "attachmentSaved", "attachmentSaveFailed"].includes(message.type)) return;
      const payload = message.payload as Record<string, unknown>, requestId = String(payload.requestId); const task = pending.current.get(requestId); if (!task) return;
      clearTimeout(task.timeout); pending.current.delete(requestId);
      if (message.type === "attachmentSaveFailed" || payload.success === false) task.reject(new Error(String(payload.error || "保存失败"))); else task.resolve(payload);
    });
    window.siyeFlush = flush; props.onDocumentReady?.(store ? () => store.document : null);
    const openLink = (event: Event) => { const href = safeLink((event as CustomEvent<string>).detail); if (href) sendToNative(sendEnvelope("openLink", { url: href })); };
    window.addEventListener("mindmap-open-link", openLink);
    const leave = () => { void flush(); }; window.addEventListener("pagehide", leave);
    const stopKeyboardTracking = editorHost.current ? trackKeyboardViewport(editorHost.current) : () => {};
    return () => { unsubscribe(); stopKeyboardTracking(); window.removeEventListener("mindmap-open-link", openLink); window.removeEventListener("pagehide", leave); clearTimeout(timer.current); cancelAnimationFrame(raf.current); delete window.siyeFlush; delete window.siyeExport; props.onDocumentReady?.(null); for (const task of pending.current.values()) { clearTimeout(task.timeout); task.reject(new Error("文档已关闭")); } pending.current.clear(); };
  }, []);
  useEffect(() => { window.siyeFlush = flush; });
  useEffect(() => {
    let frame = 0;
    const reveal = (event: Event) => {
      const bottom = (event as CustomEvent<{ bottom: number }>).detail.bottom - 16;
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const instance = mind.current, handle = activeRef.current;
        if (!instance || !handle || !handle.view.hasFocus()) return;
        const topic = handle.view.dom.closest("me-tpc");
        if (!topic) return;
        const rect = topic.getBoundingClientRect(), top = (editorHost.current?.getBoundingClientRect().top ?? 0) + 64;
        const dy = rect.bottom > bottom ? bottom - rect.bottom : rect.top < top ? top - rect.top : 0;
        if (Math.abs(dy) < 1) return;
        const transform = new DOMMatrixReadOnly(instance.map.style.transform);
        instance.map.style.transform = `translate3d(${transform.m41}px, ${transform.m42 + dy}px, 0) scale(${instance.scaleVal})`;
      });
    };
    window.addEventListener("siye-visible-editor-area", reveal);
    return () => { cancelAnimationFrame(frame); window.removeEventListener("siye-visible-editor-area", reveal); };
  }, []);

  const nodeHTML = (node: MapNode) => {
    const previous = renderedNodes.current.get(node.id);
    if (previous && previous.content === node.content && previous.docId === props.docId && previous.expanded === node.expanded && previous.children === node.children.length) return previous.html;
    const holder = document.createElement("div"); holder.className = "mindmap-node-body mindmap-rich-content"; holder.innerHTML = renderContent(node.content, props.docId);
    if (!node.expanded && node.children.length) { const count = document.createElement("small"); count.className = "mindmap-fold-count"; count.textContent = `+${descendantCount(node)}`; holder.append(count); }
    const html = holder.outerHTML;
    renderedNodes.current.set(node.id, { content: node.content, docId: props.docId, expanded: node.expanded, children: node.children.length, html });
    return html;
  };
  const adapter = (node: MapNode, depth = 0): NodeObj => ({ id: node.id, topic: contentText(node.content) || " ", expanded: node.expanded, branchColor: props.theme === "dark" ? "#555b65" : "#c6cad0", dangerouslySetInnerHTML: nodeHTML(node), metadata: { depth }, children: node.children.map(child => adapter(child, depth + 1)) });
  const mapData = (): MindElixirData => ({ nodeData: adapter(root!), direction: doc!.settings.layout === "down" ? MindElixir.DOWN : doc!.settings.layout === "left" ? MindElixir.LEFT : doc!.settings.layout === "right" ? MindElixir.RIGHT : MindElixir.SIDE });
  useEffect(() => {
    window.siyeExport = async format => {
      if (!store) return null;
      if (mind.current) return format === "svg" ? mind.current.exportSvg() : mind.current.exportPng();
      const wrapper = document.createElement("div"); wrapper.className = `siye-editor theme-${props.theme} palette-${store.document.settings.palette}`;
      wrapper.style.cssText = "position:fixed;left:-10000px;top:0;width:1200px;height:800px";
      const surface = document.createElement("div"); surface.className = "mindmap-canvas"; wrapper.append(surface); document.body.append(wrapper);
      const exporter = new MindElixir({ el: surface, toolBar: false, contextMenu: false, keypress: false, allowUndo: false });
      try {
        exporter.init(mapData());
        surface.querySelectorAll<HTMLElement>("me-tpc").forEach(element => { const node = (element as HTMLElement & {nodeObj: NodeObj<{depth:number}>}).nodeObj; element.dataset.depth = String(node.metadata?.depth ?? 0); });
        await Promise.all(Array.from(surface.querySelectorAll("img")).map(image => image.complete ? Promise.resolve() : new Promise<void>(resolve => { image.onload = () => resolve(); image.onerror = () => resolve(); setTimeout(resolve, 3000); })));
        exporter.linkDiv(); return format === "svg" ? exporter.exportSvg() : await exporter.exportPng();
      } finally { exporter.destroy(); wrapper.remove(); }
    };
  });
  useLayoutEffect(() => {
    if (!store || !host.current || mode !== "map") return;
    const menuCommand = (command: "edit" | "fold") => {
      const instance = mind.current, id = instance?.currentNode?.nodeObj.id;
      if (!id) return;
      const menu = instance.container.querySelector<HTMLElement>(".context-menu");
      if (menu) menu.hidden = true;
      if (command === "edit") callbacks.current.edit(id);
      else callbacks.current.action("fold", [id]);
    };
    const instance = new MindElixir({ el: host.current, direction: mapData().direction, editable: !props.readOnly, allowUndo: false, scaleMax: 3, scaleMin: .25, keypress: false, contextMenu: { focus: true, link: false, locale: { addChild: "添加子节点", addParent: "添加父节点", addSibling: "添加同级节点", removeNode: "删除节点", focus: "进入此节点", cancelFocus: "返回完整导图", moveUp: "上移", moveDown: "下移", link: "连线", linkBidirectional: "双向连线", clickTips: "请选择目标节点", summary: "概要" }, extend: [{ name: "编辑节点", onclick: () => menuCommand("edit") }, { name: "折叠 / 展开", onclick: () => menuCommand("fold") }] }, toolBar: true, overflowHidden: false,
      generateSubBranch: ({pT,pL,pW,pH,cT,cL,cW,cH,direction,isFirst}: SubLineParams) => {
        if (direction === "down") { const x=pL+pW/2,y=pT+pH,tx=cL+cW/2,ty=cT; return `M ${x} ${y} C ${x} ${(y+ty)/2}, ${tx} ${(y+ty)/2}, ${tx} ${ty}`; }
        const left=direction === "lhs",x=left?pL:pL+pW,y=pT+(isFirst?pH/2:pH-1),tx=left?cL+cW:cL,ty=cT+cH-1;
        return `M ${x} ${y} C ${(x+tx)/2} ${y}, ${(x+tx)/2} ${ty}, ${tx} ${ty}`;
      },
      before: {
        beginEdit: el => { const id = el?.nodeObj.id; if (id) callbacks.current.edit(id, true); return false; },
        addChild: el => { el ??= mind.current?.currentNode ?? undefined; if (el) callbacks.current.action("child", [el.nodeObj.id]); return false; },
        insertSibling: (_type, el) => { el ??= mind.current?.currentNode ?? undefined; if (el) callbacks.current.action("sibling", [el.nodeObj.id]); return false; },
        insertParent: el => {
          const id = (el ?? mind.current?.currentNode)?.nodeObj.id;
          if (id) callbacks.current.change(document => {
            const parent = parentOf(document.nodeData, id), node = findNode(document.nodeData, id);
            if (!parent || !node) return;
            const added = newNode("新节点"); added.children = [node];
            parent.children.splice(parent.children.indexOf(node), 1, added);
            document.views.selectedIds = [added.id];
          });
          return false;
        },
        moveUpNode: el => {
          const id = (el ?? mind.current?.currentNode)?.nodeObj.id;
          if (id) { const parent = parentOf(store.document.nodeData, id), index = parent?.children.findIndex(node => node.id === id) ?? -1; if (parent && index > 0) callbacks.current.move([id], parent.children[index - 1].id, "before"); }
          return false;
        },
        moveDownNode: el => {
          const id = (el ?? mind.current?.currentNode)?.nodeObj.id;
          if (id) { const parent = parentOf(store.document.nodeData, id), index = parent?.children.findIndex(node => node.id === id) ?? -1; if (parent && index >= 0 && index < parent.children.length - 1) callbacks.current.move([id], parent.children[index + 1].id, "after"); }
          return false;
        },
        removeNodes: nodes => { callbacks.current.action("delete", nodes.map(node => node.nodeObj.id)); return false; },
        moveNodeIn: (nodes, target) => { callbacks.current.move(nodes.map(node => node.nodeObj.id), target.nodeObj.id, "inside"); return false; },
        moveNodeBefore: (nodes, target) => { callbacks.current.move(nodes.map(node => node.nodeObj.id), target.nodeObj.id, "before"); return false; },
        moveNodeAfter: (nodes, target) => { callbacks.current.move(nodes.map(node => node.nodeObj.id), target.nodeObj.id, "after"); return false; }
      }
    });
    mind.current = instance; syncing.current = true; instance.init(mapData()); syncing.current = false;
    const menu = instance.container.querySelector<HTMLElement>(".context-menu");
    const focusItem = menu?.querySelector<HTMLElement>("#cm-fucus"), returnItem = menu?.querySelector<HTMLElement>("#cm-unfucus");
    if (focusItem) focusItem.onclick = () => { if (menu) menu.hidden = true; callbacks.current.focus(instance.currentNode?.nodeObj.id ?? null); };
    if (returnItem) returnItem.onclick = () => { if (menu) menu.hidden = true; callbacks.current.focus(null); };
    menu?.querySelectorAll("li").forEach(item => { item.setAttribute("role", "menuitem"); });
    menu?.querySelector("ul")?.setAttribute("role", "menu");
    const position = store.document.views.map; instance.scale(position.scale); if (position.x || position.y) { instance.map.style.transform = `translate3d(${position.x}px, ${position.y}px, 0) scale(${position.scale})`; }
    instance.bus.addListener("selectNodes", nodes => { if (!syncing.current) {
      if (activeRef.current && !nodes.some(node => node.id === activeRef.current!.id)) { setEditing(null); activeRef.current = null; setActive(null); }
      callbacks.current.view(document => { document.views.selectedIds = instance.currentNodes.map(node => node.nodeObj.id); });
    } });
    instance.bus.addListener("unselectNodes", () => { if (!syncing.current) { setEditing(null); activeRef.current = null; setActive(null); callbacks.current.view(document => { document.views.selectedIds = []; }); } });
    instance.bus.addListener("expandNode", node => { if (!syncing.current) callbacks.current.change(document => { const item = findNode(document.nodeData, node.id); if (item) item.expanded = node.expanded !== false; }); });
    const viewport = () => { if (syncing.current) return; captureMap(); store.revision++; schedule(); };
    instance.bus.addListener("scale", viewport); instance.bus.addListener("move", viewport);
    instance.bus.addListener("changeDirection", direction => { callbacks.current.change(document => { document.settings.layout = direction === MindElixir.LEFT ? "left" : direction === MindElixir.RIGHT ? "right" : direction === MindElixir.DOWN ? "down" : "side"; }); });
    const observe = new ResizeObserver(resize); observe.observe(instance.nodes);
    props.onReady(instance); shape.current = ""; update();
    return () => { captureMap(); observe.disconnect(); instance.destroy(); mind.current = null; shape.current = ""; setAnchor(null); props.onReady(null); };
  }, [mode]);
  useLayoutEffect(() => {
    const instance = mind.current; if (!instance || !store || !root || mode !== "map") return;
    instance.editable = !props.readOnly;
    const topology = (node: MapNode): unknown => [node.id, node.expanded, node.children.map(topology)];
    const key = JSON.stringify([topology(root), doc!.settings.layout, doc!.settings.palette, props.theme]);
    syncing.current = true;
    if (shape.current !== key) {
      // Unmount React portals before MindElixir replaces their parent nodes.
      if (anchor) { syncing.current = false; setAnchor(null); return; }
      const transform = instance.map.style.transform, scale = instance.scaleVal;
      setAnchor(null); const nextData = mapData(); instance.direction = nextData.direction!; instance.refresh(nextData); instance.scaleVal = scale; instance.map.style.transform = transform; shape.current = key;
      const topics = store.document.views.selectedIds.flatMap(id => { try { return [instance.findEle(id)]; } catch { return []; } });
      instance.clearSelection(); instance.selectNodes(topics);
      if (editing && store.cursor?.id === editing) setRestore({ ...store.cursor });
    }
    let geometryChanged = false;
    let nextAnchor: HTMLElement | null = null;
    const visit = (node: MapNode, depth: number) => { let element; try { element = instance.findEle(node.id); } catch { return; } if (!element) return;
      element.dataset.depth = String(depth); element.classList.toggle("siye-selected", store.document.views.selectedIds.includes(node.id)); element.classList.toggle("siye-editing", editing === node.id);
      if (editing !== node.id) { const html = nodeHTML(node); if (element.innerHTML !== html) { element.innerHTML = html; geometryChanged = true; } }
      if (editing === node.id) nextAnchor = element;
      if (node.expanded) node.children.forEach(child => visit(child, depth + 1));
    };
    visit(root, 0); syncing.current = false;
    if (anchor !== nextAnchor) setAnchor(nextAnchor);
    if (geometryChanged) resize();
  });
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.isComposing || props.readOnly || !store) return;
      const element = event.target as HTMLElement;
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "z" && !element.closest("input")) { event.preventDefault(); undo(event.shiftKey); return; }
      if (event.key === "Escape") { const menu = mind.current?.container.querySelector<HTMLElement>(".context-menu"); if (menu && !menu.hidden) { menu.hidden = true; event.preventDefault(); return; } }
      if (element.closest("input,textarea,.ProseMirror")) return;
      if (mode === "map" && selected.length && mind.current) {
        if ((event.ctrlKey || event.metaKey) && event.key === "Enter") { event.preventDefault(); void mind.current.insertParent(); return; }
        if (event.key === "PageUp" || event.key === "PageDown") { event.preventDefault(); void (event.key === "PageUp" ? mind.current.moveUpNode() : mind.current.moveDownNode()); return; }
      }
      if (selected.length && ["Enter", "Tab", "Delete", "Backspace"].includes(event.key)) { event.preventDefault(); if (event.key === "Enter" && event.shiftKey) edit(selectedId); else action(event.key === "Tab" ? event.shiftKey ? "outdent" : "child" : event.key === "Enter" ? "sibling" : "delete"); }
    };
    window.addEventListener("keydown", key); return () => window.removeEventListener("keydown", key);
  });
  const focus = (id: string | null) => { setEditing(null); activeRef.current = null; setActive(null); updateView(document => { document.views.focusId = id === document.nodeData.id ? null : id; document.views.selectedIds = id ? [id] : []; }); };
  const switchView = async (nextMode: "outline" | "map") => { if (mode === nextMode || !(await flush())) return; setEditing(null); activeRef.current = null; setActive(null); updateView(document => { document.views.mode = nextMode; }); };
  if (!store || !doc || !root) return <div className="mindmap-unsupported" role="alert"><h2>此文档使用旧版或不支持的思维导图格式</h2><p>请新建思维导图。原文件保持不变。</p></div>;
  const editNode = editing ? findNode(doc.nodeData, editing) : null;
  return <div ref={editorHost} className={`mindmap-editor siye-editor theme-${props.theme} palette-${doc.settings.palette}`}
    onTouchStartCapture={event => {
      cancelLongPress();
      suppressTap.current = false;
      if (event.touches.length !== 1 || props.readOnly) return;
      const target = event.target as HTMLElement;
      if (target.closest("button,input,textarea,.mindmap-node-menu")) return;
      const topic = target.closest("me-tpc") as Topic | null;
      const id = topic?.nodeObj.id ?? target.closest<HTMLElement>("[data-editor-id]")?.dataset.editorId ?? target.closest<HTMLElement>("[data-outline-id]")?.dataset.outlineId;
      if (!id) { setNodeMenu(null); return; }
      const { clientX: x, clientY: y } = event.touches[0];
      longPress.current = { x, y, timer: window.setTimeout(() => {
        longPress.current = null;
        suppressTap.current = true;
        (document.activeElement as HTMLElement | null)?.blur();
        select(id);
        setNodeMenu({ id, x, y });
      }, 350) };
    }}
    onTouchMoveCapture={event => {
      const press = longPress.current, touch = event.touches[0];
      if (press && (!touch || event.touches.length !== 1 || Math.hypot(touch.clientX - press.x, touch.clientY - press.y) > 10)) cancelLongPress();
      if (suppressTap.current) event.preventDefault();
    }}
    onTouchEndCapture={event => { cancelLongPress(); if (suppressTap.current) event.preventDefault(); }}
    onTouchCancelCapture={() => { cancelLongPress(); suppressTap.current = false; }}
    onClickCapture={event => { if ((event.target as HTMLElement).closest(".mindmap-node-menu")) { suppressTap.current = false; return; } if (suppressTap.current) { suppressTap.current = false; event.preventDefault(); event.stopPropagation(); } }}
    onContextMenuCapture={event => { if (nodeMenu || longPress.current) { event.preventDefault(); event.stopPropagation(); } }}
    onPointerDown={event => {
    if (!(event.target as HTMLElement).closest(".mindmap-node-menu")) { setNodeMenu(null); suppressTap.current = false; }
    if ((event.target as HTMLElement).closest("me-tpc,.context-menu,.mind-elixir-toolbar,.outline-row,.outline-title,.mindmap-node-toolbar,.mindmap-controls,.mindmap-settings,.mindmap-breadcrumbs")) return;
    if (!selected.length && !editing) return;
    setEditing(null); activeRef.current = null; setActive(null); updateView(document => { document.views.selectedIds = []; });
  }}>
    {doc.views.focusId && <nav className="mindmap-breadcrumbs" aria-label="节点导航"><button onClick={() => focus(parentOf(doc.nodeData, root.id)?.id ?? null)}>返回上级</button></nav>}
    <div className="mindmap-controls" role="tablist" aria-label="文档视图">
      <button role="tab" aria-selected={mode === "outline"} onClick={() => { void switchView("outline"); }}>大纲</button>
      <button role="tab" aria-selected={mode === "map"} onClick={() => { void switchView("map"); }}>思维导图</button>
    </div>
      <span className="mindmap-save-status">{props.readOnly ? "只读" : saving ? "保存中…" : savedRevision.current === store.revision ? "已保存" : "待保存"}</span>
    {mode === "map" ? <div ref={host} className="mindmap-canvas" onContextMenuCapture={event => {
      const instance = mind.current;
      const topic = (event.target as HTMLElement).closest("me-tpc") as Topic | null;
      if (!instance || !topic || props.readOnly) return;
      event.preventDefault(); event.stopPropagation();
      flushSync(() => { setEditing(null); setAnchor(null); setActive(null); });
      activeRef.current = null;
      if (!instance.currentNodes.includes(topic)) instance.selectNode(topic);
      const menuEvent = new MouseEvent("contextmenu", { clientX: event.clientX, clientY: event.clientY });
      Object.defineProperty(menuEvent, "target", { value: topic });
      instance.bus.fire("showContextMenu", menuEvent);
    }} onPointerDownCapture={event => {
      // Native layout/fold commands replace nodes synchronously. Detach the editor first.
      if ((event.target as HTMLElement).closest(".mind-elixir-toolbar.lt,me-epd") && anchor) {
        flushSync(() => { setEditing(null); setAnchor(null); setActive(null); });
        activeRef.current = null;
      }
      if (!event.shiftKey || (event.target as HTMLElement).closest(".ProseMirror,textarea")) return;
      const topic = (event.target as HTMLElement).closest("me-tpc") as (HTMLElement & { nodeObj: NodeObj }) | null;
      if (!topic || !mind.current) return;
      event.preventDefault(); event.stopPropagation(); const id = topic.nodeObj.id;
      const ids = selected.includes(id) ? selected.filter(item => item !== id) : [...selected, id];
      syncing.current = true; mind.current.clearSelection(); mind.current.selectNodes(ids.map(item => mind.current!.findEle(item))); syncing.current = false;
      setEditing(null); activeRef.current = null; setActive(null); updateView(document => { document.views.selectedIds = ids; });
    }} onClick={event => { const link = (event.target as HTMLElement).closest("a"); if (link) { event.preventDefault(); const href = safeLink(link.getAttribute("href") ?? ""); if (href) sendToNative(sendEnvelope("openLink", { url: href })); return; } }} /> : <MindMapOutline root={root} docId={props.docId} readOnly={props.readOnly} selected={selected} restore={restore}
      scroll={doc.views.outlineScroll} onScroll={top => { doc.views.outlineScroll = top; if (!props.readOnly) { store.revision++; schedule(); } }} select={select} content={content} active={onActive} onKey={onKey} image={upload} blur={() => { store.boundary(); void flush(); }} action={action} focus={focus} move={move} />}
    {mode === "map" && anchor?.isConnected && editNode && (anchor as HTMLElement & { nodeObj: NodeObj }).nodeObj.id === editNode.id && createPortal(<div className="mindmap-node-edit-content" onPointerDown={event => event.stopPropagation()}>
      <RichEditor id={editNode.id} content={editNode.content} docId={props.docId} readOnly={props.readOnly} label="节点正文" onChange={(value, before, after) => content(editNode.id, value, before, after)} onActive={onActive} onBlur={() => { store.boundary(); void flush(); }} onKey={(view, event) => onKey(editNode.id, view, event)} onImage={upload} onResize={resize} restore={restore} />
    </div>, anchor)}
    {(selected.length > 0 || active) && <NodeToolbar getEditor={ensureEditor} active={active} action={action} focusNode={() => focus(selectedId)} image={upload} undo={() => undo()} redo={() => undo(true)} boundary={() => store.boundary()} readOnly={props.readOnly} />}
    {nodeMenu && !props.readOnly && <div className="mindmap-node-menu-backdrop" onPointerDown={event => { event.stopPropagation(); setNodeMenu(null); }}>
      <div className="mindmap-node-menu" role="menu" aria-label="节点操作" style={{ left: Math.max(8, Math.min(nodeMenu.x, window.innerWidth - 192)), top: Math.max(8, Math.min(nodeMenu.y, window.innerHeight - 400)) }} onPointerDown={event => event.stopPropagation()}>
        <button role="menuitem" onClick={() => { edit(nodeMenu.id); setNodeMenu(null); }}>编辑节点</button>
        {([ ["child", "添加子节点"], ["sibling", "添加同级节点"], ["fold", "折叠 / 展开"], ["indent", "增加缩进"], ["outdent", "减少缩进"], ["delete", "删除节点"] ] as const).map(([command, label]) => <button role="menuitem" key={command} onClick={() => { action(command, [nodeMenu.id]); setNodeMenu(null); }}>{label}</button>)}
        <button role="menuitem" onClick={() => { focus(nodeMenu.id); setNodeMenu(null); }}>进入此节点</button>
        <button role="menuitem" onClick={() => setNodeMenu(null)}>取消</button>
      </div>
    </div>}
    {error && <div className="mindmap-save-error" role="alert">{error}<button onClick={() => { void flush(); }}>重试保存</button><button aria-label="关闭提示" onClick={() => setError("")}>×</button></div>}
  </div>;
}
