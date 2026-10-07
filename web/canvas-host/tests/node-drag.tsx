// Standalone interaction regression fixture; synthetic pointer capture is mocked only here.
import React from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import MindMapEditor from "../src/MindMapEditor";
import { initializeBridge } from "../src/bridge";
import { newDocument, newNode, parentOf, type MapDocument } from "../src/mindmap/document";
initializeBridge();
const initial = newDocument(); initial.views.mode = "map"; initial.settings.layout = "down"; initial.views.map.scale = 0.55;
const a = newNode("移动节点 A"), b = newNode("候选父节点 B"), c = newNode("随节点移动的子节点 C");
a.children.push(c); b.expanded = false; initial.nodeData.children.push(a, b);
let getDocument: (() => MapDocument) | null = null;
window.addEventListener("message", event => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  if (message.type === "saveScene") window.postMessage({ version: "1.0", type: "saveResult", payload: { requestId: message.payload.requestId, success: true } }, "*");
});
const pause = (ms = 30) => new Promise(resolve => setTimeout(resolve, ms));
function check(value: unknown, message: string) { if (!value) throw new Error(message); }
function topic(id: string) { return document.querySelector<HTMLElement>(`me-tpc[data-nodeid="me${id}"]`)!; }
function point(id: string) { const rect = topic(id).getBoundingClientRect(); return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }; }
function pointer(type: string, x: number, y: number, touch = false, pointerId = 1) {
  const event = new PointerEvent(type, { bubbles: true, cancelable: true, pointerId, pointerType: touch ? "touch" : "mouse", button: 0, clientX: x, clientY: y });
  (type === "pointerdown" ? document.elementFromPoint(x, y)! : window).dispatchEvent(event);
}
async function run() {
  const output = document.getElementById("result")!;
  output.textContent = "运行中…";
  const host = document.querySelector<HTMLElement>(".mindmap-canvas")!;
  for (const element of [host, ...host.querySelectorAll<HTMLElement>(".map-container,.map-canvas")]) {
    element.setPointerCapture = () => {}; element.hasPointerCapture = () => false; element.releasePointerCapture = () => {};
  }
  try {
    const source = point(a.id), destination = point(b.id);
    pointer("pointerdown", source.x, source.y);
    pointer("pointermove", destination.x, destination.y + 35);
    check(document.querySelector(".siye-node-drag-line path")?.getAttribute("d"), "desktop: missing dashed line");
    check(topic(b.id).classList.contains("siye-drop-parent"), "desktop: nearby node not inferred");
    check(parentOf(getDocument!().nodeData, a.id)?.id === initial.nodeData.id, "structure changed before release");
    pointer("pointerup", destination.x, destination.y + 35);
    await pause();
    check(parentOf(getDocument!().nodeData, a.id)?.id === b.id, "desktop: reparent failed");
    check(parentOf(getDocument!().nodeData, c.id)?.id === a.id, "subtree lost");
    check(getDocument!().nodeData.children[0].expanded, "destination did not expand");
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "z", metaKey: true, bubbles: true, cancelable: true }));
    await pause();
    check(parentOf(getDocument!().nodeData, a.id)?.id === initial.nodeData.id, "undo failed");
    topic(a.id).dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerType: "mouse", button: 2 }));
    topic(a.id).dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: source.x, clientY: source.y }));
    await pause();
    document.querySelector<HTMLElement>("#cm-fucus")!.click();
    await pause();
    check(getDocument!().views.focusId === a.id, "desktop context menu did not focus");
    document.querySelector<HTMLButtonElement>('button[aria-label="节点操作"]')!.click();
    await pause();
    check(!document.querySelector('button[aria-label="进入此节点"]'), "desktop toolbar focus state did not synchronize");
    check(!document.querySelector('.mindmap-breadcrumbs'), "desktop editor contains redundant navigation");
    document.querySelector<HTMLButtonElement>('button[aria-label="返回完整导图"]')!.click();
    await pause();
    check(!getDocument!().views.focusId && topic(b.id), "desktop toolbar did not exit focus");
    let start = point(a.id), end = point(b.id);
    pointer("pointerdown", start.x, start.y, true);
    pointer("pointerup", start.x, start.y, true);
    await pause();
    check(document.querySelector('[role="toolbar"][aria-label="节点操作栏"]'), "touch: tap did not show node actions");
    check(document.querySelector('button[aria-label="编辑节点"]'), "touch: edit action missing");
    check(!document.querySelector('[role="toolbar"][aria-label="节点编辑操作栏"]'), "touch: formatting toolbar shown for selection");
    document.querySelector<HTMLButtonElement>('button[aria-label="更多节点操作"]')!.click();
    await pause();
    for (const label of ["增加缩进", "减少缩进"]) check(!document.querySelector(`button[aria-label="${label}"]`), `unexpected node action: ${label}`);
    for (const label of ["进入此节点", "删除节点"]) check(document.querySelector(`button[aria-label="${label}"]`), `missing node action: ${label}`);
    document.querySelector<HTMLButtonElement>('button[aria-label="进入此节点"]')!.click();
    await pause();
    check(getDocument!().views.focusId === a.id && !topic(b.id), "focus did not isolate subtree");
    document.querySelector<HTMLButtonElement>('button[aria-label="取消选中"]')!.click();
    await pause();
    check(!document.querySelector('.mindmap-breadcrumbs'), "editor contains redundant focus navigation");
    const exit = document.querySelector<HTMLButtonElement>('button[aria-label="返回完整导图"]')!;
    const exitRect = exit.getBoundingClientRect();
    check(document.elementFromPoint(exitRect.left + exitRect.width / 2, exitRect.top + exitRect.height / 2)?.closest('button') === exit, "toolbar exit unavailable without selection");
    exit.click();
    await pause();
    check(!getDocument!().views.focusId && topic(b.id), "toolbar did not restore full map without selection");
    start = point(a.id);
    pointer("pointerdown", start.x, start.y, true); pointer("pointerup", start.x, start.y, true);
    await pause();
    document.querySelector<HTMLButtonElement>('button[aria-label="更多节点操作"]')!.click();
    await pause();
    document.querySelector<HTMLButtonElement>('button[aria-label="进入此节点"]')!.click();
    await pause();
    document.querySelector<HTMLButtonElement>('button[aria-label="更多节点操作"]')!.click();
    await pause();
    check(!document.querySelector('button[aria-label="进入此节点"]'), "mobile focus action did not synchronize");
    for (const hit of [() => ({ x: 20, y: 300 }), () => point(a.id)]) {
      const at = hit(), outside = document.elementFromPoint(at.x, at.y)!;
      check(outside.classList.contains("mindmap-mobile-menu-backdrop"), "outside tap did not hit menu dismiss layer");
      outside.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true, pointerType: "touch", pointerId: 9 }));
      outside.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, cancelable: true, pointerType: "touch", pointerId: 9 }));
      (outside as HTMLElement).click();
      await pause();
      check(getDocument!().views.selectedIds[0] === a.id, "closing More cleared the selected node");
      check(document.querySelector('button[aria-label="编辑节点"]'), "closing More collapsed the main action bar");
      check(!document.querySelector('.mindmap-mobile-menu-backdrop'), "dismiss layer remained after closing More");
      check(document.querySelector('button[aria-label="更多节点操作"]')?.getAttribute("aria-expanded") === "false", "outside tap did not close More");
      document.querySelector<HTMLButtonElement>('button[aria-label="更多节点操作"]')!.click();
      await pause();
    }
    document.querySelector<HTMLButtonElement>('.mindmap-mobile-node-toolbar button[aria-label="返回完整导图"]')!.click();
    await pause();
    check(!getDocument!().views.focusId && topic(b.id), "toolbar did not restore full map");
    start = point(a.id);
    pointer("pointerdown", start.x, start.y, true); pointer("pointerup", start.x, start.y, true);
    await pause();
    window.siyeNativeKeyboardAccessory = true;
    window.dispatchEvent(new Event("siye-native-keyboard"));
    await pause();
    check(getComputedStyle(document.querySelector('.mindmap-mobile-node-toolbar .mindmap-toolbar-actions')!).display !== "none", "native accessory setting hid selection actions");
    window.siyeNativeKeyboardAccessory = false;
    window.dispatchEvent(new Event("siye-native-keyboard"));
    document.querySelector<HTMLButtonElement>('button[aria-label="编辑节点"]')!.click();
    await pause();
    check(document.querySelector('.siye-editing .ProseMirror'), "edit did not open text editor");
    check(document.querySelector('[role="toolbar"][aria-label="节点编辑操作栏"]'), "editing did not switch to formatting actions");
    window.dispatchEvent(new CustomEvent("siye-node-toolbar-action", { detail: "收起键盘" }));
    await pause();
    check(document.querySelector('[role="toolbar"][aria-label="节点操作栏"]'), "keyboard dismissal did not return to node actions");
    start = point(a.id);
    const viewport = document.querySelector<HTMLElement>(".map-canvas")!.style.transform;
    pointer("pointerdown", start.x, start.y, true);
    pointer("pointermove", start.x + 20, start.y + 20, true);
    check(!document.querySelector(".siye-node-drag-ghost"), "touch: quick swipe started a node drag");
    pointer("pointerup", start.x + 20, start.y + 20, true);
    check(parentOf(getDocument!().nodeData, a.id)?.id === initial.nodeData.id, "quick swipe changed parent");
    check(document.querySelector<HTMLElement>(".map-canvas")!.style.transform !== viewport, "quick swipe did not pan");
    start = point(a.id); end = point(b.id);
    pointer("pointerdown", start.x, start.y, true);
    await pause(380);
    check(!document.querySelector('[role="menu"][aria-label="节点操作"]'), "touch: long press opened old menu");
    check(document.querySelector(".siye-node-drag-ghost"), "touch: long press did not lift node");
    check(!document.querySelector('[role="toolbar"][aria-label="节点操作栏"]'), "touch: toolbar stayed open during drag");
    pointer("pointerup", start.x, start.y, true);
    check(parentOf(getDocument!().nodeData, a.id)?.id === initial.nodeData.id, "stationary hold changed parent");
    pointer("pointerdown", start.x, start.y, true);
    await pause(380);
    pointer("pointermove", end.x, end.y + 35, true);
    await pause();
    check(document.querySelector(".siye-node-drag-line"), "touch: preview missing");
    pointer("pointerup", end.x, end.y + 35, true);
    await pause();
    check(parentOf(getDocument!().nodeData, a.id)?.id === b.id, "touch: reparent failed");
    check(!document.querySelector(".siye-node-drag-line"), "preview leaked after release");
    check(document.querySelector('[role="toolbar"][aria-label="节点操作栏"]'), "touch: actions did not return after drop");
    const cancelStart = point(a.id), cancelEnd = point(initial.nodeData.id);
    pointer("pointerdown", cancelStart.x, cancelStart.y);
    pointer("pointermove", cancelEnd.x, cancelEnd.y);
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
    pointer("pointerup", cancelEnd.x, cancelEnd.y);
    check(parentOf(getDocument!().nodeData, a.id)?.id === b.id, "escape committed a move");
    check(!document.querySelector(".siye-node-drag-ghost"), "escape left a ghost");
    for (const reason of ["pointercancel", "second pointer", "blur"]) {
      const from = point(a.id), to = point(initial.nodeData.id);
      pointer("pointerdown", from.x, from.y, true);
      await pause(380);
      pointer("pointermove", to.x, to.y, true);
      if (reason === "pointercancel") pointer("pointercancel", to.x, to.y, true);
      else if (reason === "second pointer") pointer("pointerdown", 5, 100, true, 2);
      else window.dispatchEvent(new Event("blur"));
      pointer("pointerup", to.x, to.y, true);
      check(parentOf(getDocument!().nodeData, a.id)?.id === b.id, `${reason} committed a move`);
      check(!document.querySelector(".siye-node-drag-ghost"), `${reason} left a ghost`);
    }
    // Leave the touch preview visible for screenshot review; it is never saved.
    const previewStart = point(a.id), previewEnd = point(initial.nodeData.id);
    pointer("pointerdown", previewStart.x, previewStart.y, true);
    await pause(380);
    pointer("pointermove", previewEnd.x + 60, previewEnd.y - 80, true);
    output.textContent = "通过：单击操作栏、进入与退出节点、滑动画布、长按移动、松开提交、子树保留、撤销、取消";
  } catch (error) { output.textContent = `失败：${String(error)}`; }
}
flushSync(() => createRoot(document.getElementById("root")!).render(<div style={{ height: "100vh" }}>
  <MindMapEditor docId="node-drag-qa" data={initial} readOnly={false} theme="light" onReady={() => {}} onDocumentReady={getter => { getDocument = getter; }} />
  <div style={{ position: "fixed", left: 8, top: 130, zIndex: 50, background: "white", padding: 8, maxWidth: "90%", fontSize: 12 }}>
    <button onClick={() => { void run(); }}>运行拖动回归测试</button><span id="result" role="status" />
  </div>
</div>));
