import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { EditorView } from "prosemirror-view";
import RichEditor, { type EditorHandle } from "./mindmap/RichEditor";
import type { MapNode, Cursor, RichDocument, StructureAction } from "./mindmap/document";
export type OutlineProps = {
  root: MapNode; docId: string; readOnly: boolean; selected: string[]; restore: Cursor | null;
  scroll: number; onScroll: (top: number) => void; select: (id: string, multiple?: boolean) => void;
  content: (id: string, content: RichDocument, previous: Cursor, next: Cursor) => void;
  active: (handle: EditorHandle) => void; onKey: (id: string, view: EditorView, event: KeyboardEvent) => boolean;
  image: (file: File, view: EditorView) => void; blur: () => void;
  action: (action: StructureAction, ids?: string[]) => void; focus: (id: string) => void;
  move: (ids: string[], target: string, position: "before" | "after" | "inside") => void;
};
export default function MindMapOutline(props: OutlineProps) {
  const scroll = useRef<HTMLDivElement>(null);
  const [menu, setMenu] = useState<string | null>(null);
  const [drop, setDrop] = useState<{ id: string; position: "before" | "after" | "inside" } | null>(null);
  useLayoutEffect(() => { if (scroll.current) scroll.current.scrollTop = props.scroll; }, []);
  useEffect(() => {
    if (!menu) return;
    const dismiss = (event: PointerEvent) => {
      const target = event.target;
      if (!(target instanceof Element) || !target.closest(".outline-menu, [data-outline-menu-trigger]")) setMenu(null);
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); setMenu(null); }
    };
    document.addEventListener("pointerdown", dismiss, true);
    document.addEventListener("keydown", escape, true);
    return () => {
      document.removeEventListener("pointerdown", dismiss, true);
      document.removeEventListener("keydown", escape, true);
    };
  }, [menu]);
  const editor = (node: MapNode) => <RichEditor id={node.id} content={node.content} docId={props.docId} readOnly={props.readOnly}
    label={node === props.root ? "文档标题" : "节点正文"} onChange={(content, before, after) => props.content(node.id, content, before, after)}
    onActive={props.active} onBlur={props.blur} onKey={(view, event) => props.onKey(node.id, view, event)} onImage={props.image} onResize={() => {}} restore={props.restore} />;
  const row = (node: MapNode) => <div className="outline-item" key={node.id}>
    <div className={`outline-row ${props.selected.includes(node.id) ? "is-selected" : ""} ${drop?.id === node.id ? `drop-${drop.position}` : ""}`} data-outline-id={node.id}
      onClick={event => { if (event.shiftKey) { event.preventDefault(); props.select(node.id, true); } }}
      onDragOver={event => { if (props.readOnly || !event.dataTransfer.types.includes("application/x-siye-node")) return; event.preventDefault(); const box = event.currentTarget.getBoundingClientRect(); const y = (event.clientY - box.top) / box.height; setDrop({ id: node.id, position: y < .25 ? "before" : y > .75 ? "after" : "inside" }); }}
      onDragLeave={event => { if (!event.currentTarget.contains(event.relatedTarget as Node)) setDrop(null); }}
      onDrop={event => { event.preventDefault(); try { const ids = JSON.parse(event.dataTransfer.getData("application/x-siye-node")); if (Array.isArray(ids) && drop) props.move(ids, node.id, drop.position); } finally { setDrop(null); } }}>
      <div className="outline-controls">
        <button aria-label="节点菜单" aria-haspopup="menu" aria-expanded={menu === node.id} data-outline-menu-trigger draggable={!props.readOnly} onClick={event => { event.stopPropagation(); setMenu(current => current === node.id ? null : node.id); }} onDragStart={event => { event.dataTransfer.setData("application/x-siye-node", JSON.stringify(props.selected.includes(node.id) ? props.selected : [node.id])); event.dataTransfer.effectAllowed = "move"; }}>···</button>
        {node.children.length > 0 && <button aria-label={node.expanded ? "折叠节点" : "展开节点"} onClick={() => props.action("fold", [node.id])}>{node.expanded ? "▾" : "▸"}</button>}
      </div>
      <button className="outline-bullet" aria-label="选择节点" onClick={event => props.select(node.id, event.shiftKey)} onDoubleClick={() => props.focus(node.id)}>•</button>
      <div className="outline-body">{editor(node)}{!node.expanded && node.children.length > 0 && <span className="outline-fold-count">{node.children.length} 个子节点</span>}</div>
      {menu === node.id && <div className="outline-menu" onPointerDown={event => event.stopPropagation()}>
        {!props.readOnly && ([ ["child", "添加子级"], ["sibling", "添加同级"], ["delete", "删除"] ] as const).map(([action, label]) => <button key={action} onClick={() => { props.action(action, [node.id]); setMenu(null); }}>{label}</button>)}
        <button onClick={() => { props.focus(node.id); setMenu(null); }}>进入此节点</button>
      </div>}
    </div>
    {node.expanded && node.children.length > 0 && <div className="outline-children">{node.children.map(row)}</div>}
  </div>;
  return <div className="mindmap-outline-document" ref={scroll} onScroll={event => props.onScroll(event.currentTarget.scrollTop)}>
    <main className="mindmap-outline-page"><div className="outline-title">{editor(props.root)}</div>
      <div className="outline-list">{props.root.expanded && props.root.children.map(row)}</div>
      {!props.readOnly && <button className="outline-add" onClick={() => props.action("child", [props.root.id])}>＋ 添加条目</button>}
    </main>
  </div>;
}
