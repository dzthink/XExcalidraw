// Exercise same-parent sorting, side preservation, touch, cancellation and history.
import React from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import MindMapEditor from "../src/MindMapEditor";
import { initializeBridge } from "../src/bridge";
import { newDocument, newNode, type MapDocument } from "../src/mindmap/document";
initializeBridge();
window.addEventListener("message", event => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  if (message.type === "saveScene") window.postMessage({ version: "1.0", type: "saveResult", payload: { requestId: message.payload.requestId, success: true } }, "*");
});
const app = createRoot(document.getElementById("root")!);
const pause = (ms = 60) => new Promise(resolve => setTimeout(resolve, ms));
const topic = (id: string) => document.querySelector<HTMLElement>(`me-tpc[data-nodeid="me${id}"]`)!;
const check = (value: unknown, message: string) => { if (!value) throw new Error(message); };
async function run() {
  const results: string[] = [];
  for (const layout of ["right", "left", "down", "side"] as const) {
    const doc = newDocument(), b1 = newNode("B1"), b2 = newNode("B2"), b3 = newNode("B3"), child = newNode("B3 的子节点");
    doc.views.mode = "map"; doc.settings.layout = layout; doc.views.map.scale = 0.75;
    doc.nodeData.content = newNode("A").content; doc.nodeData.children.push(b1, b2, b3); b3.children.push(child);
    if (layout === "side") {
      for (const node of doc.nodeData.children) node.side = "right";
      const l1 = newNode("左侧 1"), l2 = newNode("左侧 2"); l1.side = l2.side = "left";
      doc.nodeData.children.splice(1, 0, l1); doc.nodeData.children.splice(3, 0, l2);
    }
    let getDocument: (() => MapDocument) | null = null;
    flushSync(() => app.render(<div key={layout} style={{ height: "100vh" }}>
      <MindMapEditor docId={`sibling-drag-${layout}`} data={doc} readOnly={false} theme="light" onReady={() => {}} onDocumentReady={getter => { getDocument = getter; }} />
      <div id="result" role="status" style={{ position: "fixed", top: 90, left: 8, zIndex: 50, background: "white", padding: 8 }}>{results.join("；")}；正在检查 {layout}</div>
    </div>));
    await pause();
    const host = document.querySelector<HTMLElement>(".mindmap-canvas")!;
    host.setPointerCapture = () => {}; host.hasPointerCapture = () => false; host.releasePointerCapture = () => {};
    const order = () => getDocument!().nodeData.children.filter(node => [b1.id, b2.id, b3.id].includes(node.id)).map(node => node.id).join();
    const assertOrder = (ids: string[]) => check(order() === ids.join(), `${layout}: unexpected sibling order`);
    const drag = async (slot: "middle" | "last", touch = false, cancel = false) => {
      const source = topic(b3.id).getBoundingClientRect(), first = topic(b1.id).getBoundingClientRect(), second = topic(b2.id).getBoundingClientRect();
      const root = topic(doc.nodeData.id).getBoundingClientRect();
      const left = layout === "left" || layout === "side" && first.left < root.left;
      const x = source.left + source.width / 2, y = source.top + source.height / 2;
      const tx = layout === "down" ? slot === "middle" ? (first.left + first.width / 2 + second.left + second.width / 2) / 2 : second.right + 25
        : left ? first.right - source.width / 2 : first.left + source.width / 2;
      const ty = layout === "down" ? first.top + source.height / 2
        : slot === "middle" ? (first.top + first.height / 2 + second.top + second.height / 2) / 2 : second.bottom + 25;
      const pointer = (type: string, px: number, py: number) => {
        const event = new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 1, pointerType: touch ? "touch" : "mouse", button: 0, clientX: px, clientY: py });
        (type === "pointerdown" ? topic(b3.id) : window).dispatchEvent(event);
      };
      const before = order();
      pointer("pointerdown", x, y);
      if (touch) await pause(380);
      pointer("pointermove", layout === "down" ? x : x + 15, layout === "down" ? y + 15 : y);
      pointer("pointermove", tx, ty);
      check(topic(doc.nodeData.id).classList.contains("siye-drop-parent"), `${layout}: parent changed while sorting`);
      check(document.querySelector(".siye-node-drag-slot")?.getAttribute("d"), `${layout}: missing insertion marker`);
      check(order() === before, `${layout}: sorting committed before release`);
      pointer(cancel ? "pointercancel" : "pointerup", tx, ty);
      await pause();
      check(!document.querySelector(".siye-node-drag-slot"), `${layout}: insertion marker leaked`);
    };
    const undo = async (redo = false) => {
      document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "z", metaKey: true, shiftKey: redo, bubbles: true, cancelable: true }));
      await pause();
    };
    try {
      await drag("middle"); assertOrder([b1.id, b3.id, b2.id]);
      check(getDocument!().nodeData.children.find(node => node.id === b3.id)!.children[0].id === child.id, `${layout}: lost subtree`);
      await undo(); assertOrder([b1.id, b2.id, b3.id]);
      await undo(true); assertOrder([b1.id, b3.id, b2.id]);
      await drag("last", false, true); assertOrder([b1.id, b3.id, b2.id]);
      await drag("middle"); assertOrder([b1.id, b3.id, b2.id]); // No-op must not consume undo.
      await undo(); assertOrder([b1.id, b2.id, b3.id]);
      await drag("middle", true); assertOrder([b1.id, b3.id, b2.id]);
      if (layout === "side") {
        const root = topic(doc.nodeData.id).getBoundingClientRect();
        for (const node of getDocument!().nodeData.children) {
          const rect = topic(node.id).getBoundingClientRect();
          check((rect.left < root.left) === (node.side === "left"), "side: sorting moved a branch to the other half");
        }
      }
      results.push(`${layout} 同级排序通过`);
      document.getElementById("result")!.textContent = results.join("；");
    } catch (error) { document.getElementById("result")!.textContent = `${results.join("；")}；失败：${String(error)}`; return; }
  }
}
flushSync(() => app.render(<button onClick={() => { void run(); }}>运行同级排序回归测试</button>));
