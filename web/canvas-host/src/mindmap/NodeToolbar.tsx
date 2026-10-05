import { useState, useRef, useEffect } from "react";
import { setBlockType, toggleMark } from "prosemirror-commands";
import { liftListItem, sinkListItem } from "prosemirror-schema-list";
import { AllSelection, NodeSelection, type Command } from "prosemirror-state";
import { addRowAfter, addColumnAfter, deleteRow, deleteColumn, deleteTable, isInTable } from "prosemirror-tables";
import type { EditorView } from "prosemirror-view";
import { setList } from "./list";
import { toggleQuote } from "./quote";
import { schema, safeLink } from "./richText";
import type { EditorHandle } from "./RichEditor";
import type { StructureAction } from "./document";
import ToolbarIcon, { type ToolbarIconName } from "./ToolbarIcon";

type Props = { getEditor: (wholeNode?: boolean) => Promise<EditorHandle | null>; active: EditorHandle | null;
  action: (action: StructureAction) => void; focusNode: () => void;
  image: (file: File, view: EditorView) => void; undo: () => void; redo: () => void;
  boundary: () => void; readOnly: boolean;
};
export default function NodeToolbar(props: Props) {
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const [panel, setPanel] = useState<"style" | "table" | "list" | "code" | "link" | "more" | null>(null);
  const linkRange = useRef<{ from: number; to: number } | null>(null);
  const [rows, setRows] = useState(3), [columns, setColumns] = useState(3);
  const [linkText, setLinkText] = useState(""), [href, setHref] = useState(""), [error, setError] = useState("");
  const run = async (command: Command, wholeNode = false) => {
    const handle = await props.getEditor(wholeNode); if (!handle) return;
    props.boundary(); command(handle.view.state, handle.view.dispatch, handle.view); props.boundary(); handle.view.focus(); setPanel(null);
  };
  const closePanel = () => {
    // Removing a focused menu button must not dismiss WebKit's text responder.
    props.active?.view.focus();
    setPanel(null);
  };
  const toggle = (value: typeof panel) => { setError(""); setPanel(panel === value ? null : value); };
  const openLink = async () => {
    const handle = await props.getEditor(); if (!handle) return;
    const { state } = handle.view;
    let { from, to } = state.selection;
    let href = state.selection.$from.marks().find(mark => mark.type === schema.marks.link)?.attrs.href ?? "";
    if (from === to) {
      const parent = state.selection.$from.parent, start = state.selection.$from.start(), point = from;
      parent.forEach((node, offset) => { const mark = node.marks.find(mark => mark.type === schema.marks.link); if (mark && start + offset <= point && start + offset + node.nodeSize >= point) { from = start + offset; to = from + node.nodeSize; href = mark.attrs.href; } });
      if (href) parent.forEach((node, offset) => { if (node.marks.some(mark => mark.type === schema.marks.link && mark.attrs.href === href) && start + offset <= to && start + offset + node.nodeSize >= from) { from = Math.min(from, start + offset); to = Math.max(to, start + offset + node.nodeSize); } });
    }
    linkRange.current = { from, to };
    setLinkText(state.doc.textBetween(from, to)); setHref(href); toggle("link");
  };
  const insertLink = async () => {
    const valid = safeLink(href); if (!valid) { setError("请输入 http、https 或 mailto 链接"); return; }
    const handle = await props.getEditor(); if (!handle) return;
    const { view } = handle, { from, to } = linkRange.current ?? view.state.selection;
    const text = linkText || href;
    props.boundary(); view.dispatch(view.state.tr.replaceWith(from, to, schema.text(text, [schema.marks.link.create({ href: valid })])));
    props.boundary(); view.focus(); setPanel(null);
  };
  const insertTable = async () => {
    const handle = await props.getEditor(); if (!handle) return;
    const countRows = Math.max(1, Math.min(10, Number(rows) || 3)), countColumns = Math.max(1, Math.min(10, Number(columns) || 3));
    const cells = () => Array.from({ length: countColumns }, () => schema.nodes.table_cell.createAndFill()!);
    const table = schema.nodes.table.create(null, Array.from({ length: countRows }, () => schema.nodes.table_row.create(null, cells())));
    props.boundary(); handle.view.dispatch(handle.view.state.tr.replaceSelectionWith(table).scrollIntoView());
    props.boundary(); handle.view.focus(); setPanel(null);
  };
  // Native actions call React handlers directly; hidden DOM controls are not a bridge.
  useEffect(() => {
    const action = (event: Event) => {
      if (props.readOnly) return;
      const handlers: Record<string, () => void> = {
        "文字样式": () => toggle("style"), "列表": () => toggle("list"),
        "表格": () => toggle("table"), "代码": () => toggle("code"),
        "链接": () => { void openLink(); },
        "撤销": props.undo, "重做": props.redo, "节点操作": () => toggle("more"),
        "收起键盘": () => setPanel(null),
        "恢复编辑": () => { if (props.active?.view.dom.isConnected) props.active.view.focus(); },
      };
      handlers[(event as CustomEvent<string>).detail]?.();
    };
    const image = async (event: Event) => {
      const { base64, name, mime } = (event as CustomEvent<{ base64: string; name: string; mime: string }>).detail;
      const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
      const handle = await props.getEditor();
      if (handle && !props.readOnly) props.image(new File([bytes], name, { type: mime }), handle.view);
    };
    window.addEventListener("siye-node-toolbar-action", action);
    window.addEventListener("siye-node-toolbar-image", image);
    return () => {
      window.removeEventListener("siye-node-toolbar-action", action);
      window.removeEventListener("siye-node-toolbar-image", image);
    };
  });
  const primaryPanels = { "文字样式": "style", "表格": "table", "列表": "list", "代码": "code", "链接": "link", "节点操作": "more" } as const;
  const button = (label: string, action: () => void, icon?: ToolbarIconName) => {
    const targetPanel = primaryPanels[label as keyof typeof primaryPanels];
    return <button key={label} type="button" aria-label={label} title={label}
      aria-expanded={targetPanel ? panel === targetPanel : undefined} onClick={action}>
      {icon ? <ToolbarIcon name={icon} /> : label}
    </button>;
  };
  const iconButton = (label: string, icon: ToolbarIconName, action: () => void, options: { pressed?: boolean; destructive?: boolean; primary?: boolean } = {}) => (
    <button key={label} type="button" className={`mindmap-panel-action${options.destructive ? " is-destructive" : ""}${options.primary ? " is-primary" : ""}`}
      aria-label={label} title={label} aria-pressed={options.pressed} onClick={action}>
      <ToolbarIcon name={icon} />
    </button>
  );
  const state = props.active?.view.state;
  const markActive = (name: string) => {
    if (!state) return false;
    const mark = schema.marks[name];
    return state.selection.empty ? Boolean(mark.isInSet(state.storedMarks ?? state.selection.$from.marks())) : state.doc.rangeHasMark(state.selection.from, state.selection.to, mark);
  };
  const blockActive = (name: string, level?: number, marker?: string) => {
    if (!state) return false;
    for (let depth = state.selection.$from.depth; depth > 0; depth--) {
      const node = state.selection.$from.node(depth);
      if (node.type.name === name && (level === undefined || node.attrs.level === level) && (marker === undefined || node.attrs.marker === marker)) return true;
    }
    return false;
  };
  const panelNames = { style: "文字样式", table: "表格", list: "列表", code: "代码", link: "链接", more: "节点操作" };
  const imageSelection = props.active?.view.state.selection;
  return <div className="mindmap-node-toolbar" role="toolbar" aria-label="节点编辑操作栏"
    onPointerDown={event => { event.stopPropagation(); if ((event.target as HTMLElement).closest("button")) event.preventDefault(); }}>
    <div className="mindmap-toolbar-actions">
    {!props.readOnly && <>
      {button("文字样式", () => toggle("style"), "textStyle")}
      {button("表格", () => toggle("table"), "table")}
      {button("列表", () => toggle("list"), "bullet")}
      <label className="mindmap-image-picker" title="插入图片"><ToolbarIcon name="image" /><input type="file" accept="image/png,image/jpeg,image/gif,image/webp" aria-label="插入图片" onChange={async event => {
        const file = event.target.files?.[0]; event.target.value = "";
        const handle = await props.getEditor(); if (file && handle) props.image(file, handle.view);
      }} /></label>
      {button("代码", () => toggle("code"), "inlineCode")}
      {button("链接", () => { void openLink(); }, "link")}
      <span className="mindmap-toolbar-separator" />
      {button("撤销", props.undo, "undo")}{button("重做", props.redo, "redo")}
      {!isIOS && button("节点操作", () => toggle("more"), "more")}
    </>}
    {props.readOnly && button("进入此节点", props.focusNode)}
    </div>
    {!props.readOnly && <button className="mindmap-keyboard-dismiss" type="button" aria-label="收起键盘" title="收起键盘" onClick={() => {
      if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
      setPanel(null);
    }}>⌄</button>}
    {panel && !props.readOnly && <div className={`mindmap-toolbar-panel mindmap-panel-${panel}`} role="group" aria-label={panel === "more" ? "节点操作" : `${panelNames[panel]}操作`}>
      <div className="mindmap-panel-content">
      {panel === "style" && <>
        <div className="mindmap-panel-section" role="group" aria-label="段落格式">
          <div className="mindmap-panel-grid">
            {[0, 1, 2, 3].map(level => iconButton(level ? `H${level}` : "正文", level ? `h${level}` as ToolbarIconName : "paragraph", () => { void run(setBlockType(level ? schema.nodes.heading : schema.nodes.paragraph, level ? { level } : undefined), true); }, { pressed: blockActive(level ? "heading" : "paragraph", level || undefined) }))}
          </div>
        </div>
        <div className="mindmap-panel-section" role="group" aria-label="文字格式">
          <div className="mindmap-panel-grid">
            {iconButton("加粗", "bold", () => { void run(toggleMark(schema.marks.bold), true); }, { pressed: markActive("bold") })}
            {iconButton("斜体", "italic", () => { void run(toggleMark(schema.marks.italic), true); }, { pressed: markActive("italic") })}
            {iconButton("删除线", "strike", () => { void run(toggleMark(schema.marks.strike), true); }, { pressed: markActive("strike") })}
            {iconButton("引用", "quote", () => { void run(toggleQuote); }, { pressed: blockActive("blockquote") })}
            {iconButton("减少缩进", "outdent", () => { void run(liftListItem(schema.nodes.list_item)); })}
            {iconButton("增加缩进", "indent", () => { void run(sinkListItem(schema.nodes.list_item)); })}
          </div>
        </div>
      </>}
      {panel === "list" && <div className="mindmap-panel-grid">
        {iconButton("无序列表", "bullet", () => { void run(setList("bullet")); }, { pressed: blockActive("bullet_list", undefined, "bullet") })}
        {iconButton("有序列表", "ordered", () => { void run(setList("ordered")); }, { pressed: blockActive("ordered_list") })}
        {iconButton("待办列表", "task", () => { void run(setList("task")); }, { pressed: blockActive("bullet_list", undefined, "task") })}
      </div>}
      {panel === "code" && <div className="mindmap-panel-grid is-two-columns">
        {iconButton("行内代码", "inlineCode", () => { void run(toggleMark(schema.marks.code)); }, { pressed: markActive("code") })}
        {iconButton("代码块", "codeBlock", () => { void run(setBlockType(schema.nodes.code_block)); }, { pressed: blockActive("code_block") })}
      </div>}
      {panel === "table" && <>
        <div className="mindmap-table-size">
          <label>行<input aria-label="表格行数" type="number" inputMode="numeric" min="1" max="10" value={rows} onChange={event => setRows(Number(event.target.value))} /></label>
          <span aria-hidden="true">×</span>
          <label>列<input aria-label="表格列数" type="number" inputMode="numeric" min="1" max="10" value={columns} onChange={event => setColumns(Number(event.target.value))} /></label>
          {iconButton("插入表格", "table", () => { void insertTable(); }, { primary: true })}
        </div>
        {props.active && isInTable(props.active.view.state) && <div className="mindmap-panel-section" role="group" aria-label="编辑表格">
          <div className="mindmap-panel-grid">
            {iconButton("添加行", "addRow", () => { void run(addRowAfter); })}
            {iconButton("添加列", "addColumn", () => { void run(addColumnAfter); })}
            {iconButton("删除行", "deleteRow", () => { void run(deleteRow); }, { destructive: true })}
            {iconButton("删除列", "deleteColumn", () => { void run(deleteColumn); }, { destructive: true })}
          </div>
          <div className="mindmap-panel-footer">{iconButton("删除表格", "trash", () => { void run(deleteTable); }, { destructive: true })}</div>
        </div>}
      </>}
      {panel === "link" && <>
        <div className="mindmap-link-fields">
          <label><span>文字</span><input aria-label="链接文字" placeholder="显示文字" value={linkText} onChange={event => setLinkText(event.target.value)} /></label>
          <label><span>地址</span><input aria-label="链接地址" type="url" inputMode="url" autoCapitalize="none" autoCorrect="off" spellCheck={false} placeholder="https://…" value={href} onChange={event => setHref(event.target.value)} /></label>
        </div>
        <div className="mindmap-panel-footer">
          {iconButton("移除链接", "unlink", () => { void run((state, dispatch) => {
            let { from, to } = linkRange.current ?? state.selection;
            if (from === to) {
              const parent = state.selection.$from.parent, start = state.selection.$from.start();
              parent.forEach((node, offset) => { if (start + offset <= from && start + offset + node.nodeSize >= from && node.marks.some(mark => mark.type === schema.marks.link)) { from = start + offset; to = from + node.nodeSize; } });
            }
            dispatch?.(state.tr.removeMark(from, to, schema.marks.link)); return true;
          }); }, { destructive: true })}
          {iconButton("确认链接", "check", () => { void insertLink(); }, { primary: true })}
        </div>
      </>}
      {panel === "more" && <>
        <div className="mindmap-panel-grid">
          {iconButton("添加同级", "sibling", () => { props.action("sibling"); setPanel(null); })}
          {iconButton("添加子级", "child", () => { props.action("child"); setPanel(null); })}
        </div>
        <div className="mindmap-panel-footer">
          {iconButton("折叠或展开", "fold", () => { props.action("fold"); setPanel(null); })}
          {iconButton("进入此节点", "focus", () => { props.focusNode(); setPanel(null); })}
          {iconButton("删除节点", "trash", () => { props.action("delete"); setPanel(null); }, { destructive: true })}
        </div>
      </>}
      </div>
      <div className="mindmap-panel-close">{iconButton("关闭菜单", "close", closePanel)}</div>
      {error && <span role="alert">{error}</span>}
    </div>}
    {!panel && !props.readOnly && imageSelection instanceof NodeSelection && imageSelection.node.type === schema.nodes.image && <div className="mindmap-toolbar-panel mindmap-panel-image" role="group" aria-label="图片操作">
      <div className="mindmap-panel-grid is-three-columns">
      {iconButton("缩小图片", "smaller", () => { void run((state, dispatch) => { const selected = state.selection as NodeSelection; dispatch?.(state.tr.setNodeMarkup(selected.from, undefined, { ...selected.node.attrs, width: Math.max(40, selected.node.attrs.width - 40) })); return true; }); })}
      {iconButton("放大图片", "larger", () => { void run((state, dispatch) => { const selected = state.selection as NodeSelection; dispatch?.(state.tr.setNodeMarkup(selected.from, undefined, { ...selected.node.attrs, width: Math.min(640, selected.node.attrs.width + 40) })); return true; }); })}
      {iconButton("删除图片", "trash", () => { void run((state, dispatch) => { dispatch?.(state.tr.deleteSelection()); return true; }); }, { destructive: true })}
      </div>
    </div>}
  </div>;
}
export function selectAllContent(view: EditorView) {
  view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)));
}
