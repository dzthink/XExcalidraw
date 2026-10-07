// Exercise layout inference through the real editor, preview, commit and undo paths.
import React from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import MindMapEditor from "../src/MindMapEditor";
import { initializeBridge } from "../src/bridge";
import { newDocument, newNode, parentOf, type MapDocument } from "../src/mindmap/document";
initializeBridge();
window.addEventListener("message", event => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  if (message.type === "saveScene") window.postMessage({ version: "1.0", type: "saveResult", payload: { requestId: message.payload.requestId, success: true } }, "*");
});
const app = createRoot(document.getElementById("root")!);
const pause = () => new Promise(resolve => setTimeout(resolve, 60));
const topic = (id: string) => document.querySelector<HTMLElement>(`me-tpc[data-nodeid="me${id}"]`)!;
const check = (value: unknown, message: string) => { if (!value) throw new Error(message); };
async function run() {
  const results: string[] = [];
  for (const layout of ["right", "left", "side", "down"] as const) {
    const doc = newDocument(), b = newNode("B"), c = newNode("C"), d = newNode("D"), child = newNode("D 的子节点");
    doc.views.mode = "map"; doc.settings.layout = layout; doc.views.map.scale = 0.65;
    doc.nodeData.content = newNode("A").content; doc.nodeData.children.push(b, d); b.children.push(c); d.children.push(child);
    let getDocument: (() => MapDocument) | null = null;
    flushSync(() => app.render(<div key={layout} style={{ height: "100vh" }}>
      <MindMapEditor key={layout} docId={`layout-drag-${layout}`} data={doc} readOnly={false} theme="light" onReady={() => {}} onDocumentReady={getter => { getDocument = getter; }} />
      <div id="result" role="status" style={{ position: "fixed", top: 90, left: 8, zIndex: 50, background: "white", padding: 8 }}>{results.join("；")}；正在检查 {layout}</div>
    </div>));
    await pause();
    const host = document.querySelector<HTMLElement>(".mindmap-canvas")!;
    host.setPointerCapture = () => {}; host.hasPointerCapture = () => false; host.releasePointerCapture = () => {};
    const drag = (gap: boolean, expected: string, commit: boolean) => {
      const source = topic(d.id).getBoundingClientRect(), target = topic(b.id).getBoundingClientRect(), next = topic(c.id).getBoundingClientRect();
      const root = topic(doc.nodeData.id).getBoundingClientRect();
      const left = layout === "left" || layout === "side" && target.left < root.left;
      const x = source.left + source.width / 2, y = source.top + source.height / 2;
      const offset = gap ? 0.5 : 0;
      const tx = layout === "down" ? target.left + target.width / 2 + 35
        : left ? target.right + (next.right - target.right) * offset - source.width / 2
        : target.left + (next.left - target.left) * offset + source.width / 2;
      const ty = layout === "down" ? target.top + (next.top - target.top) * offset + source.height / 2 : target.top + target.height / 2 + 35;
      const pointer = (type: string, px: number, py: number) => {
        const event = new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 1, pointerType: "mouse", button: 0, clientX: px, clientY: py });
        (type === "pointerdown" ? topic(d.id) : window).dispatchEvent(event);
      };
      const before = parentOf(getDocument!().nodeData, d.id)?.id;
      pointer("pointerdown", x, y); pointer("pointermove", tx, ty);
      check(topic(expected).classList.contains("siye-drop-parent"), `${layout}: wrong ${gap ? "gap" : "aligned"} preview`);
      check(parentOf(getDocument!().nodeData, d.id)?.id === before, `${layout}: committed before release`);
      check(document.querySelector(".siye-node-drag-line path")?.getAttribute("d"), `${layout}: missing connection preview`);
      if (commit) pointer("pointerup", tx, ty);
      else pointer("pointercancel", tx, ty);
    };
    try {
      drag(true, b.id, true); await pause();
      check(parentOf(getDocument!().nodeData, d.id)?.id === b.id, `${layout}: gap drop did not attach to B`);
      check(parentOf(getDocument!().nodeData, child.id)?.id === d.id, `${layout}: lost subtree`);
      drag(false, doc.nodeData.id, true); await pause();
      check(parentOf(getDocument!().nodeData, d.id)?.id === doc.nodeData.id, `${layout}: aligned drop did not attach to A`);
      document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "z", metaKey: true, bubbles: true, cancelable: true }));
      await pause();
      check(parentOf(getDocument!().nodeData, d.id)?.id === b.id, `${layout}: undo failed`);
      drag(false, doc.nodeData.id, false);
      check(parentOf(getDocument!().nodeData, d.id)?.id === b.id, `${layout}: cancellation changed parent`);
      results.push(`${layout} 通过`);
      document.getElementById("result")!.textContent = results.join("；");
    } catch (error) { document.getElementById("result")!.textContent = `${results.join("；")}；失败：${String(error)}`; return; }
  }
}
flushSync(() => app.render(<button onClick={() => { void run(); }}>运行布局拖拽回归测试</button>));
