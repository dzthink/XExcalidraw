// Isolated WebKit regression fixture; never accesses native documents.
import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { DOMParser, DOMSerializer } from "prosemirror-model";
import RichEditor, { type EditorHandle } from "../src/mindmap/RichEditor";
import NodeToolbar from "../src/mindmap/NodeToolbar";
import { schema } from "../src/mindmap/richText";
import { setList, splitUnfinishedListItem } from "../src/mindmap/list";
import "../src/mindmap/editor.css";

const emptyContent = { type: "doc", content: [{ type: "paragraph" }] };
let handle: EditorHandle | null = null;
const pause = () => new Promise(resolve => setTimeout(resolve, 80));
const assert = (condition: unknown, message: string) => { if (!condition) throw new Error(message); };
function Fixture() {
  const [active, setActive] = useState<EditorHandle | null>(null);
  return <div className="siye-editor" style={{ height: 900, padding: "90px 90px", boxSizing: "border-box" }}>
    <RichEditor id="lists" docId="lists.mindmap" label="列表测试" content={emptyContent}
      readOnly={false} onChange={() => {}} onActive={editor => { handle = editor; setActive({ ...editor }); }} onBlur={() => {}}
      onKey={(view, event) => event.key === "Enter" && splitUnfinishedListItem(view.state, view.dispatch)}
      onDoubleEnter={() => {}} onImage={() => {}} onResize={() => {}} />
    <NodeToolbar active={active} getEditor={async () => handle} action={() => {}} focusNode={() => {}}
      image={() => {}} undo={() => {}} redo={() => {}} boundary={() => {}} readOnly={false} />
  </div>;
}
createRoot(document.getElementById("root")!).render(<Fixture />);
async function run() {
  await pause();
  (document.querySelector(".ProseMirror") as HTMLElement).focus();
  await pause();
  const view = handle!.view;
  const button = (label: string) => document.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`);
  for (const style of ["bullet", "ordered", "task"] as const) {
    setList(style)(view.state, view.dispatch);
    await pause();
    const li = view.dom.querySelector("li")!;
    assert(li.textContent === "☐", "Empty list has no typed content");
    const marker = style === "task" ? getComputedStyle(li.querySelector("[data-task-checkbox]")!) : getComputedStyle(li, "::before");
    assert(style === "task" ? marker.display !== "none" : marker.content !== "none", `${style} marker is visible before typing`);
  }
  button("列表")!.click(); await pause();
  assert(button("待办列表") && !button("短横线列表") && !button("减少缩进") && !button("增加缩进"), "List menu contains only list styles");
  button("关闭菜单")!.click(); await pause();
  const checkbox = view.dom.querySelector<HTMLButtonElement>("[data-task-checkbox]")!;
  checkbox.click(); await pause();
  assert(view.state.doc.firstChild!.firstChild!.attrs.checked === true, "Checkbox click updates saved completion");
  assert(view.dom.querySelector("[data-task-checkbox]")!.getAttribute("aria-checked") === "true", "Checkbox displays completion");
  view.dispatch(view.state.tr.insertText("完成的待办"));
  view.dom.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })); await pause();
  assert(view.state.doc.firstChild!.childCount === 2 && view.state.doc.firstChild!.child(1).attrs.checked === false, "Return creates unfinished empty task");
  button("文字样式")!.click(); await pause();
  assert(button("减少缩进") && button("增加缩进"), "Indent actions belong to format menu");
  button("增加缩进")!.click(); await pause();
  assert(view.state.selection.$from.depth > 3, "Format indent nests current task");
  button("文字样式")!.click(); await pause();
  button("减少缩进")!.click(); await pause();
  assert(view.state.selection.$from.depth === 3, "Format outdent restores current task");
  const fragment = document.createElement("div");
  fragment.append(DOMSerializer.fromSchema(schema).serializeFragment(view.state.doc.content));
  const copied = DOMParser.fromSchema(schema).parse(fragment);
  assert(copied.eq(view.state.doc), "HTML copy round trip preserves tasks without checkbox glyphs");
  // Show all marker kinds side by side in the captured regression artifact.
  const paragraph = schema.nodes.paragraph;
  const item = (text = "", checked = false) => schema.nodes.list_item.create({ checked }, paragraph.create(null, text ? schema.text(text) : null));
  view.dispatch(view.state.tr.replaceWith(0, view.state.doc.content.size, [
    schema.nodes.bullet_list.create(null, [item("无序列表"), item()]),
    schema.nodes.ordered_list.create({ order: 3 }, [item("有序列表（从 3 开始）"), item()]),
    schema.nodes.bullet_list.create({ marker: "task" }, [item("已完成的待办", true), item()])
  ]));
  await pause();
  const native = (window as any).webkit?.messageHandlers;
  if (native?.performanceSnapshot) {
    const snapshot = new Promise(resolve => window.addEventListener("performance-snapshot-finished", resolve, { once: true }));
    native.performanceSnapshot.postMessage("lists"); await snapshot;
  }
  // Desktop menus must remain visible over the document in both themes.
  const root = document.querySelector<HTMLElement>(".siye-editor")!;
  const luminance = (color: string) => {
    const channels = color.match(/[\d.]+/g)!.slice(0, 3).map(value => {
      const channel = Number(value) / 255;
      return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  for (const theme of ["light", "dark"]) {
    root.classList.toggle("theme-dark", theme === "dark");
    for (const label of ["文字样式", "表格", "列表", "代码", "链接", "节点操作"]) {
      button(label)!.click(); await pause();
      const panel = document.querySelector<HTMLElement>(".mindmap-toolbar-panel")!;
      const style = getComputedStyle(panel);
      const toolbarStyle = getComputedStyle(document.querySelector(".mindmap-node-toolbar")!);
      assert(style.backgroundColor === toolbarStyle.backgroundColor && style.color === toolbarStyle.color &&
        style.borderRadius === toolbarStyle.borderRadius && style.boxShadow === toolbarStyle.boxShadow,
        `${theme} primary and secondary surfaces share a theme and shape`);
      assert(button(label)!.getAttribute("aria-expanded") === "true", `${label} exposes expanded state`);
      const primaryBounds = button(label)!.getBoundingClientRect();
      const secondaryBounds = panel.querySelector(".mindmap-panel-action")!.getBoundingClientRect();
      assert(primaryBounds.width === secondaryBounds.width && primaryBounds.height === secondaryBounds.height,
        `${label} primary and secondary buttons share dimensions`);
      assert(style.backgroundColor !== "rgba(0, 0, 0, 0)", `${theme} ${label} has an opaque background`);
      const foreground = luminance(style.color), background = luminance(style.backgroundColor);
      assert((Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05) >= 4.5,
        `${theme} ${label} has readable foreground contrast`);
      for (const action of panel.querySelectorAll<HTMLButtonElement>(".mindmap-panel-action:not(:disabled)")) {
        const actionStyle = getComputedStyle(action);
        const ink = luminance(actionStyle.color);
        const fill = action.classList.contains("is-primary") ? luminance(actionStyle.backgroundColor) : background;
        assert((Math.max(ink, fill) + 0.05) / (Math.min(ink, fill) + 0.05) >= 3, `${theme} ${label} action icon contrast`);
      }
      if (native?.performanceSnapshot) {
        const snapshot = new Promise(resolve => window.addEventListener("performance-snapshot-finished", resolve, { once: true }));
        native.performanceSnapshot.postMessage(`desktop-${theme}-${panel.className.split("mindmap-panel-")[1]}`);
        await snapshot;
      }
      button("关闭菜单")!.click(); await pause();
    }
  }
  native?.performanceResult.postMessage({ passed: true, checks: ["empty markers", "completion toggle", "unfinished Return", "menu placement", "indent/outdent", "HTML round trip", "desktop light/dark menu contrast", "unified toolbar surfaces and button dimensions", "expanded menu state"] });
}
run().catch(error => (window as any).webkit?.messageHandlers.performanceResult.postMessage({ error: String(error) }));
