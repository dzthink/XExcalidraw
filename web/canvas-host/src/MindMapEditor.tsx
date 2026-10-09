import { exportMapImage } from "./mindmap/imageExport";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal, flushSync } from "react-dom";
import MindElixir, { type NodeObj, type Topic, type MindElixirData, type SubLineParams, type Wrapper } from "mind-elixir";
import { EditorView } from "prosemirror-view";
import { TextSelection, AllSelection } from "prosemirror-state";
import { splitUnfinishedListItem } from "./mindmap/list";
import { addBridgeListener, sendEnvelope, sendToNative } from "./bridge";
import type { DesktopToolbarActionPayload, DesktopToolbarStatePayload } from "./types";
import MindMapOutline from "./MindMapOutline";
import RichEditor, { type EditorHandle } from "./mindmap/RichEditor";
import NodeToolbar from "./mindmap/NodeToolbar";
import MobileNodeToolbar from "./mindmap/MobileNodeToolbar";
import { refreshRichTextLinks } from "./mindmap/links";
import { trackKeyboardViewport } from "./mindmap/keyboardViewport";
import { allowsNodeLongPress } from "./mindmap/nodeInteraction";
import { installNodeDrag } from "./mindmap/nodeDrag";
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
  const suppressTap = useRef(false);
  const [touchUI, setTouchUI] = useState(() => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || navigator.maxTouchPoints > 0 && window.matchMedia("(pointer: coarse)").matches);
  const nativeDesktop = document.documentElement.dataset.nativeDesktop === "true";
  const [draggingNode, setDraggingNode] = useState(false);
  const editorHost = useRef<HTMLDivElement>(null);
  const host = useRef<HTMLDivElement>(null), mind = useRef<MindElixir | null>(null), activeRef = useRef<EditorHandle | null>(null);
  const latest = useRef(props); latest.current = props;
  const uploads = useRef(new Set<Promise<void>>());
  const pending = useRef(new Map<string, Pending>()), timer = useRef<number>(), savedRevision = useRef(0), flight = useRef<Promise<boolean> | null>(null);
  const contentCursors = useRef(new Map<string, Cursor>());
  const renderedNodes = useRef(new Map<string, { content: RichDocument; docId: string; expanded: boolean; children: number; html: string }>());
  const topicElements = useRef(new Map<string, Topic>());
  const pendingContent = useRef(new Set<string>());
  const appliedSelected = useRef<string[]>([]);
  const appliedEditing = useRef<string | null>(null);
  const shape = useRef(""), syncing = useRef(false), raf = useRef(0);
  const doc = store?.document, mode = doc?.views.mode ?? "outline";
  const interaction = useRef({ mode, editing, readOnly: props.readOnly });
  interaction.current = { mode, editing, readOnly: props.readOnly };
  const root = doc && (doc.views.focusId ? findNode(doc.nodeData, doc.views.focusId) : null) || doc?.nodeData;
  const selected = doc?.views.selectedIds ?? [], selectedId = selected[0] ?? active?.id ?? doc?.views.focusId ?? undefined;
  const callbacks = useRef({} as { focus: (id: string | null) => void; select: (id: string, multiple?: boolean) => void; edit: (id: string, atEnd?: boolean) => void; action: (action: StructureAction, ids?: string[]) => void; move: (ids: string[], target: string, placement: "before" | "after" | "inside", sides?: Map<string, "left" | "right">) => void; change: (fn: (doc: MapDocument) => void, group?: string | null) => void; view: (fn: (doc: MapDocument) => void) => void });
  const request = (type: string, payload: Record<string, unknown>): Promise<Record<string, unknown>> => new Promise((resolve, reject) => {
    const requestId = crypto.randomUUID();
    const timeout = window.setTimeout(() => { pending.current.delete(requestId); reject(new Error("保存未收到应用确认，请重试")); }, 10000);
    pending.current.set(requestId, { resolve, reject, timeout }); sendToNative(sendEnvelope(type, { ...payload, requestId }));
  });
  const captureMap = () => { if (!store || !mind.current || syncing.current) return; const map = mind.current; store.document.views.map = { scale: map.scaleVal, x: new DOMMatrixReadOnly(map.map.style.transform).m41, y: new DOMMatrixReadOnly(map.map.style.transform).m42 }; };
  const flush = async (): Promise<boolean> => {
    window.clearTimeout(timer.current); timer.current = undefined; if (!store || latest.current.readOnly) return true;
    if (uploads.current.size) { await Promise.all([...uploads.current]); window.clearTimeout(timer.current); timer.current = undefined; }
    if (flight.current) { const okay = await flight.current; return okay ? flush() : false; }
    captureMap(); if (savedRevision.current === store.revision) return true;
    const revision = store.revision, sceneJSON = JSON.stringify(store.document); setSaving(true);
    const task = (async () => { try { await request("saveScene", { docId: latest.current.docId, sceneJson: sceneJSON, source: "web" }); savedRevision.current = revision; setError(""); return true; } catch (failure) { setError(failure instanceof Error ? failure.message : "保存失败"); return false; } finally { setSaving(false); flight.current = null; } })();
    flight.current = task; const okay = await task;
    if (okay && store.revision !== revision) return flush();
    if (okay) sendToNative(sendEnvelope("didChange", { docId: latest.current.docId, dirty: false }));
    return okay;
  };
  const schedule = () => { if (props.readOnly || !store) return; const alreadyScheduled = timer.current !== undefined; window.clearTimeout(timer.current); timer.current = window.setTimeout(() => { timer.current = undefined; void flush(); }, 500); if (!alreadyScheduled) sendToNative(sendEnvelope("didChange", { docId: props.docId, dirty: true })); };
  const update = () => redraw(value => value + 1);
  const change = (mutate: (doc: MapDocument) => void, group: string | null = null) => { if (!store || props.readOnly) return; if (store.change(mutate, group)) { update(); schedule(); } };
  const updateView = (mutate: (doc: MapDocument) => void) => { if (!store) return; mutate(store.document); update(); if (!props.readOnly) { store.revision++; schedule(); } };
  const select = (id: string, multiple = false) => {
    if (!store || !store.node(id)) return;
    if (!multiple && store.document.views.selectedIds.length === 1 && selectedId === id) return;
    store.boundary(); if (editing !== id || multiple) { setEditing(null); activeRef.current = null; setActive(null); }
    updateView(document => { document.views.selectedIds = multiple ? document.views.selectedIds.includes(id) ? document.views.selectedIds.filter(item => item !== id) : [...document.views.selectedIds, id] : [id]; });
  };
  const edit = (id: string, atEnd = false) => {
    if (props.readOnly || !store) return;
    const node = store.node(id); if (!node) return;
    const end = TextSelection.atEnd(readContent(node.content)).from;
    select(id); setEditing(id);
    setRestore(!atEnd && contentCursors.current.get(id) || { id, from: end, to: end, field: "content" });
  };
  const action = (action: StructureAction, ids = store?.document.views.selectedIds ?? []) => {
    if (!store || props.readOnly) return; if (action === "sibling" && ids[0] === root?.id) action = "child"; activeRef.current = null; setActive(null); setEditing(null); let next: string | null = null;
    change(document => { next = structure(document.nodeData, ids, action); if (next) document.views.selectedIds = [next]; });
    if (next && ["child", "sibling"].includes(action)) { setEditing(next); setRestore({ id: next, from: 1, to: 1, field: "content" }); }
  };
  const onDoubleEnter = (id: string) => {
    flushSync(() => action("sibling", [id]));
    activeRef.current?.view.focus();
  };
  const move = (ids: string[], target: string, placement: "before" | "after" | "inside", sides?: Map<string, "left" | "right">) => {
    setEditing(null); activeRef.current = null; setActive(null);
    change(document => {
      if (!moveNodes(document.nodeData, ids, target, placement)) return;
      sides?.forEach((side, id) => { const node = findNode(document.nodeData, id); if (node) node.side = side; });
      document.views.selectedIds = ids;
    });
  };
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
    if (!store || props.readOnly) return; store.cursor = before;
    if (store.changeContent(id, value)) { pendingContent.current.add(id); update(); schedule(); }
    store.cursor = after;
  };
  const undo = (redo = false) => {
    if (!store || props.readOnly || !(redo ? store.redo() : store.undo())) return;
    if (store.cursor) pendingContent.current.add(store.cursor.id);
    const cursor = store.cursor; setEditing(cursor?.id ?? null); setRestore(cursor && { ...cursor }); activeRef.current = null; setActive(null); update(); schedule();
  };
  const focusCursor = (id: string, end = false) => { if (!store) return; select(id); const size = readContent(store.node(id)!.content).content.size; setEditing(id); setRestore({ id, from: end ? Math.max(1, size - 1) : 1, to: end ? Math.max(1, size - 1) : 1, field: "content" }); };
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
      if (splitUnfinishedListItem(view.state, view.dispatch)) return true;
    }
    if (mode !== "outline" || inComplex) return false;
    if (event.key === "Tab") { action(event.shiftKey ? "outdent" : "indent", [id]); return true; }
    const node = store.node(id)!;
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
  const resizedTopics = useRef(new Set<string>());
  const resizeAll = useRef(false);
  const resize = (id?: string) => {
    if (id) resizedTopics.current.add(id); else resizeAll.current = true;
    if (raf.current) return;
    raf.current = requestAnimationFrame(() => {
      raf.current = 0;
      const instance = mind.current;
      if (!instance || mode !== "map") return;
      const ids = [...resizedTopics.current]; resizedTopics.current.clear();
      const all = resizeAll.current; resizeAll.current = false;
      const branches = new Set<Wrapper>();
      for (const id of ids) {
        const topic = topicElements.current.get(id);
        if (!topic) continue;
        let wrapper = topic.closest<Wrapper>("me-wrapper");
        while (wrapper && wrapper.parentElement?.tagName !== "ME-MAIN") wrapper = wrapper.parentElement?.closest<Wrapper>("me-wrapper") ?? null;
        if (wrapper) branches.add(wrapper);
      }
      // Root edits translate entire branches without changing branch-local paths.
      refreshRichTextLinks(instance, all || !ids.length ? null : branches);
    });
  };
  useEffect(() => {
    const unsubscribe = addBridgeListener(message => {
      if (message.type === "syncScene") {
        const payload = message.payload as import("./types").SyncScenePayload;
        if (payload.docId !== latest.current.docId || !store || store.revision !== savedRevision.current || flight.current || uploads.current.size) return;
        let data: Props["data"];
        try { data = typeof payload.sceneJson === "string" ? JSON.parse(payload.sceneJson) : payload.sceneJson; } catch { return; }
        const document = validated(data);
        if (!document) return;
        captureMap(); store.replaceFromExternal(document);
        setEditing(null); activeRef.current = null; setActive(null);
        update();
        return;
      }
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
        if (!handle || !handle.view.hasFocus()) return;
        const outline = handle.view.dom.closest<HTMLElement>(".mindmap-outline-document");
        if (outline) {
          const rect = outline.getBoundingClientRect();
          const toolbar = editorHost.current?.querySelector<HTMLElement>(".mindmap-toolbar-actions")?.getBoundingClientRect();
          const visibleBottom = Math.min(bottom, rect.bottom - 16, toolbar && toolbar.height > 0 ? toolbar.top - 16 : Infinity);
          const top = Math.max(rect.top, window.visualViewport?.offsetTop ?? 0) + 64;
          const caret = handle.view.coordsAtPos(handle.view.state.selection.head);
          const dy = caret.bottom > visibleBottom ? caret.bottom - visibleBottom : caret.top < top ? caret.top - top : 0;
          if (Math.abs(dy) >= 1) outline.scrollTop += dy;
          return;
        }
        if (!instance) return;
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
  const adapter = (node: MapNode, depth = 0): NodeObj => ({ id: node.id, topic: contentText(node.content) || " ", expanded: node.expanded, branchColor: props.theme === "dark" ? "#555b65" : "#c6cad0", dangerouslySetInnerHTML: nodeHTML(node), metadata: { depth }, ...(depth === 1 && doc?.settings.layout === "side" && node.side ? { direction: node.side === "left" ? MindElixir.LEFT : MindElixir.RIGHT } : {}), children: node.children.map(child => adapter(child, depth + 1)) });
  const mapData = (): MindElixirData => ({ nodeData: adapter(root!), direction: doc!.settings.layout === "down" ? MindElixir.DOWN : doc!.settings.layout === "left" ? MindElixir.LEFT : doc!.settings.layout === "right" ? MindElixir.RIGHT : MindElixir.SIDE });
  useEffect(() => {
    window.siyeExport = async format => {
      if (!store) return null;
      const wrapper = document.createElement("div"); wrapper.className = `siye-editor theme-${props.theme} palette-${store.document.settings.palette}`;
      wrapper.style.cssText = "position:fixed;left:-10000px;top:0;width:1200px;height:800px";
      const surface = document.createElement("div"); surface.className = "mindmap-canvas"; wrapper.append(surface); document.body.append(wrapper);
      const exporter = new MindElixir({ el: surface, toolBar: false, contextMenu: false, keypress: false, allowUndo: false });
      try {
        exporter.init(mapData());
        surface.querySelectorAll<HTMLElement>("me-tpc").forEach(element => { const node = (element as HTMLElement & {nodeObj: NodeObj<{depth:number}>}).nodeObj; element.dataset.depth = String(node.metadata?.depth ?? 0); });
        await Promise.all(Array.from(surface.querySelectorAll("img")).map(image => image.complete ? Promise.resolve() : new Promise<void>(resolve => { image.onload = () => resolve(); image.onerror = () => resolve(); setTimeout(resolve, 3000); })));
        exporter.linkDiv(); return await exportMapImage(exporter, format);
      } finally { exporter.destroy(); wrapper.remove(); }
    };
  });
  const mapShape = () => `${store?.structureRevision}:${root?.id}:${doc?.settings.layout}:${doc?.settings.palette}:${props.theme}`;
  const indexTopics = (instance: MindElixir) => {
    topicElements.current.clear();
    for (const id of renderedNodes.current.keys()) if (!store?.node(id)) { renderedNodes.current.delete(id); contentCursors.current.delete(id); }
    instance.nodes.querySelectorAll<Topic>("me-tpc").forEach(element => {
      topicElements.current.set(element.nodeObj.id, element);
      element.dataset.depth = String((element.nodeObj.metadata as { depth?: number } | undefined)?.depth ?? 0);
      pendingContent.current.add(element.nodeObj.id);
    });
  };
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
    instance.container.querySelector(".mind-elixir-toolbar #fullscreen")?.remove();
    // A solid background hit region avoids expensive WebKit region unions.
    // Its class preserves the library's empty-canvas selection and pan gestures.
    const background = document.createElement("div");
    background.className = "map-container"; background.dataset.siyeMapBackground = ""; background.setAttribute("aria-hidden", "true");
    background.style.cssText = "position:absolute;inset:0;pointer-events:auto;background:transparent";
    instance.map.prepend(background);
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
    const observe = new ResizeObserver(() => resize()); observe.observe(instance.nodes);
    indexTopics(instance); shape.current = mapShape();
    const removeNodeDrag = installNodeDrag({
      host: host.current, overlayHost: editorHost.current!,
      root: () => store.document.views.focusId ? findNode(store.document.nodeData, store.document.views.focusId) ?? store.document.nodeData : store.document.nodeData,
      topics: () => topicElements.current, scale: () => instance.scaleVal, layout: () => store.document.settings.layout,
      canStart: id => allowsNodeLongPress(interaction.current.mode, interaction.current.editing, id, interaction.current.readOnly) && !instance.spacePressed,
      pan: (dx, dy) => { instance.move(dx, dy); },
      press: id => {
        callbacks.current.select(id);
        const topic = topicElements.current.get(id);
        if (topic) { syncing.current = true; instance.selectNode(topic); syncing.current = false; }
      },
      start: id => {
        setDraggingNode(true); suppressTap.current = true;
        const menu = instance.container.querySelector<HTMLElement>(".context-menu"); if (menu) menu.hidden = true;
        callbacks.current.select(id);
      },
      move: (id, drop) => {
        const sides = new Map<string, "left" | "right">();
        if (store.document.settings.layout === "side") {
          const visibleRoot = store.document.views.focusId ? store.node(store.document.views.focusId) : store.document.nodeData;
          for (const child of visibleRoot?.children ?? []) {
            const direction = topicElements.current.get(child.id)?.nodeObj.direction;
            if (direction === MindElixir.LEFT || direction === MindElixir.RIGHT) sides.set(child.id, direction === MindElixir.LEFT ? "left" : "right");
          }
          if (drop.side) sides.set(id, drop.side);
        }
        callbacks.current.move([id], drop.targetId, drop.placement, sides);
      },
      end: () => { setDraggingNode(false); }
    });
    props.onReady(instance); update();
    return () => { removeNodeDrag(); captureMap(); observe.disconnect(); instance.destroy(); mind.current = null; shape.current = ""; topicElements.current.clear(); setAnchor(null); props.onReady(null); };
  }, [mode]);
  useLayoutEffect(() => {
    const instance = mind.current; if (!instance || !store || !root || mode !== "map") return;
    instance.editable = !props.readOnly;
    const key = mapShape();
    syncing.current = true;
    if (shape.current !== key) {
      // Detach the portal before the library replaces its parent nodes.
      if (anchor) { syncing.current = false; setAnchor(null); return; }
      const transform = instance.map.style.transform, scale = instance.scaleVal;
      const nextData = mapData(); instance.direction = nextData.direction!; instance.refresh(nextData);
      instance.scaleVal = scale; instance.map.style.transform = transform; shape.current = key;
      indexTopics(instance);
      const topics = store.document.views.selectedIds.flatMap(id => topicElements.current.get(id) ?? []);
      instance.clearSelection(); instance.selectNodes(topics);
      if (editing && store.cursor?.id === editing) setRestore({ ...store.cursor });
    }
    const changedIds = new Set([...pendingContent.current, ...appliedSelected.current, ...selected]);
    if (appliedEditing.current) changedIds.add(appliedEditing.current);
    if (editing) changedIds.add(editing);
    let geometryChanged = false;
    for (const id of changedIds) {
      const element = topicElements.current.get(id), node = store.node(id);
      if (!element || !node) continue;
      const isSelected = selected.includes(id), isEditing = editing === id;
      if (element.classList.contains("siye-selected") !== isSelected) element.classList.toggle("siye-selected", isSelected);
      if (element.classList.contains("siye-editing") !== isEditing) element.classList.toggle("siye-editing", isEditing);
      if (editing !== id) {
        const html = nodeHTML(node);
        if (element.innerHTML !== html) { element.innerHTML = html; geometryChanged = true; resizedTopics.current.add(id); }
      }
    }
    pendingContent.current.clear(); appliedSelected.current = [...selected]; appliedEditing.current = editing;
    syncing.current = false;
    const nextAnchor = editing ? topicElements.current.get(editing) ?? null : null;
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
  const switchViewRef = useRef(switchView);
  switchViewRef.current = switchView;
  useEffect(() => {
    if (document.documentElement.dataset.nativeDesktop !== "true") return;
    const payload: DesktopToolbarStatePayload = { docId: props.docId, kind: "mindmap", viewMode: mode, readOnly: props.readOnly, nodeActionsEnabled: !draggingNode && !!(selected.length || active || doc?.views.focusId) };
    sendToNative(sendEnvelope("desktopToolbarState", payload));
  }, [props.docId, props.readOnly, mode, draggingNode, selected.length, active, doc?.views.focusId]);
  const undoRef = useRef(undo);
  undoRef.current = undo;
  useEffect(() => {
    const removeListener = addBridgeListener(message => {
      if (message.type !== "desktopToolbarAction") return;
      const payload = message.payload as DesktopToolbarActionPayload;
      if (payload.action === "view" && (payload.value === "outline" || payload.value === "map")) {
        void switchViewRef.current(payload.value);
      } else if (payload.action === "node" && payload.value) {
        if (payload.value === "撤销" || payload.value === "重做") {
          void undoRef.current(payload.value === "重做");
        } else {
          window.dispatchEvent(new CustomEvent("siye-node-toolbar-action", { detail: payload.value }));
        }
      } else if (payload.action === "nodeImage" && payload.image) {
        window.dispatchEvent(new CustomEvent("siye-node-toolbar-image", { detail: payload.image }));
      }
    });
    return () => { removeListener(); };
  }, []);
  if (!store || !doc || !root) return <div className="mindmap-unsupported" role="alert"><h2>此文档使用旧版或不支持的思维导图格式</h2><p>请新建思维导图。原文件保持不变。</p></div>;
  const editNode = editing ? store.node(editing) : null;
  return <div ref={editorHost} data-map-editing={mode === "map" && editing !== null} className={`mindmap-editor siye-editor theme-${props.theme} palette-${doc.settings.palette}`}
    onPointerDownCapture={event => { if (event.pointerType === "touch") setTouchUI(true); suppressTap.current = false; }}
    onClickCapture={event => { if (suppressTap.current) { suppressTap.current = false; event.preventDefault(); event.stopPropagation(); } }}
    onContextMenuCapture={event => {
      const topic = (event.target as HTMLElement).closest("me-tpc") as Topic | null;
      if (mode === "outline" || topic?.nodeObj.id === editing) { event.stopPropagation(); return; }
      if ((event.target as HTMLElement).closest('[contenteditable="true"],input,textarea,.mindmap-node-edit-content')) {
        event.stopPropagation(); return;
      }
      if (touchUI && topic) { event.preventDefault(); event.stopPropagation(); }
    }}
    onPointerDown={event => {
    if ((event.target as HTMLElement).closest("me-tpc,.context-menu,.mind-elixir-toolbar,.outline-row,.outline-title,.mindmap-node-toolbar,.mindmap-controls,.mindmap-settings")) return;
    if (!selected.length && !editing) return;
    setEditing(null); activeRef.current = null; setActive(null); updateView(document => { document.views.selectedIds = []; });
  }}>
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
      const focused = !!store.document.views.focusId;
      instance.container.querySelector("#cm-fucus")?.classList.toggle("disabled", focused);
      instance.container.querySelector("#cm-unfucus")?.classList.toggle("disabled", !focused);
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
      syncing.current = true; mind.current.clearSelection(); mind.current.selectNodes(ids.map(item => topicElements.current.get(item)!)); syncing.current = false;
      setEditing(null); activeRef.current = null; setActive(null); updateView(document => { document.views.selectedIds = ids; });
    }} onClick={event => { const link = (event.target as HTMLElement).closest("a"); if (link) { event.preventDefault(); const href = safeLink(link.getAttribute("href") ?? ""); if (href) sendToNative(sendEnvelope("openLink", { url: href })); return; } }} /> : <MindMapOutline root={root} docId={props.docId} readOnly={props.readOnly} selected={selected} restore={restore}
      scroll={doc.views.outlineScroll} onScroll={top => { doc.views.outlineScroll = top; if (!props.readOnly) { store.revision++; schedule(); } }} select={select} content={content} active={onActive} onKey={onKey} onDoubleEnter={onDoubleEnter} image={upload} blur={() => { store.boundary(); void flush(); }} action={action} focus={focus} move={move} />}
    {mode === "map" && anchor?.isConnected && editNode && (anchor as HTMLElement & { nodeObj: NodeObj }).nodeObj.id === editNode.id && createPortal(<div className="mindmap-node-edit-content" onPointerDown={event => event.stopPropagation()}>
      <RichEditor id={editNode.id} content={editNode.content} docId={props.docId} readOnly={props.readOnly} label="节点正文" onChange={(value, before, after) => content(editNode.id, value, before, after)} onActive={onActive} onBlur={() => { store.boundary(); void flush(); }} onKey={(view, event) => onKey(editNode.id, view, event)} onDoubleEnter={() => onDoubleEnter(editNode.id)} onImage={upload} onResize={() => resize(editing ?? undefined)} restore={restore} />
    </div>, anchor)}
    {!draggingNode && touchUI && mode === "map" && !editing && (selected.length > 0 || !!doc.views.focusId) && !props.readOnly ? <MobileNodeToolbar
      selection={selected.length > 0} selectedId={selectedId} expanded={store.node(selectedId)?.expanded ?? true}
      edit={() => edit(selectedId)} action={action} focusNode={() => focus(selectedId)}
      exitFocus={doc.views.focusId ? () => focus(null) : undefined}
      dismiss={() => { mind.current?.clearSelection(); updateView(document => { document.views.selectedIds = []; }); }} />
      : !draggingNode && (nativeDesktop || selected.length > 0 || active || doc.views.focusId) && <NodeToolbar key={nativeDesktop ? mode : undefined} docId={props.docId} getEditor={ensureEditor} active={active} action={action} focusNode={() => focus(selectedId)} exitFocus={doc.views.focusId ? () => focus(null) : undefined} image={upload} undo={() => undo()} redo={() => undo(true)} boundary={() => store.boundary()} readOnly={props.readOnly || !selected.length && !active} onDismissKeyboard={touchUI && mode === "map" ? () => { setEditing(null); activeRef.current = null; setActive(null); } : undefined} />}
    {error && <div className="mindmap-save-error" role="alert">{error}<button onClick={() => { void flush(); }}>重试保存</button><button aria-label="关闭提示" onClick={() => setError("")}>×</button></div>}
  </div>;
}
