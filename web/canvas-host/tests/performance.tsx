// Synthetic fixture only. No user documents or production preferences are used.
import React from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import { EditorView } from "prosemirror-view";
import type MindElixir from "mind-elixir";
import MindMapEditor from "../src/MindMapEditor";
import { initializeBridge } from "../src/bridge";
import { newDocument, newNode } from "../src/mindmap/document";

const views = new Set<EditorView>();
// Capture production editors without adding hooks to the application.
const prototype = EditorView.prototype as unknown as { updatePluginViews: (state?: unknown) => void };
const original = prototype.updatePluginViews;
prototype.updatePluginViews = function (this: EditorView, state?: unknown) {
  views.add(this); original.call(this, state);
};
initializeBridge();

let pauseAcks = false;
const waitingAcks = new Map<string, string>();
const acknowledge = (requestId: string) => {
  waitingAcks.delete(requestId);
  window.postMessage({ version: "1.0", type: "saveResult", payload: { requestId, success: true } }, "*");
};
window.addEventListener("message", event => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  if (message.type !== "saveScene") return;
  if (pauseAcks) waitingAcks.set(message.payload.requestId, message.payload.docId);
  else acknowledge(message.payload.requestId);
});
const frame = () => new Promise<number>(resolve => requestAnimationFrame(resolve));
const progress = (stage: string) => {
  (window.webkit?.messageHandlers as unknown as { performanceProgress?: { postMessage: (value: unknown) => void } })?.performanceProgress?.postMessage(stage);
};
const percentile = (values: number[], fraction: number) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * fraction) - 1];
const savedScenes = new Map<string, unknown>();
window.addEventListener("message", event => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  if (message.type === "saveScene") savedScenes.set(message.payload.docId, JSON.parse(message.payload.sceneJson));
});
const assert = (okay: unknown, message: string) => { if (!okay) throw new Error(message); };
const settle = async () => { await frame(); await frame(); await frame(); };
const snapshot = async (name: string) => {
  const handler = (window.webkit?.messageHandlers as unknown as { performanceSnapshot?: { postMessage: (value: string) => void } })?.performanceSnapshot;
  if (!handler) return;
  await new Promise<void>(resolve => {
    window.addEventListener("performance-snapshot-finished", () => resolve(), { once: true });
    handler.postMessage(name);
  });
};
const mouse = async (events: { type: string; x: number; y: number }[]) => {
  const handler = (window.webkit?.messageHandlers as unknown as { performanceMouse?: { postMessage: (value: unknown) => void } })?.performanceMouse;
  assert(handler, "Trusted gesture regression requires the native runner");
  await new Promise<void>(resolve => {
    window.addEventListener("performance-mouse-finished", () => resolve(), { once: true });
    handler!.postMessage(events);
  });
  await settle();
};
async function regression() {
  const checks: string[] = [], host = document.getElementById("root")!;
  const outlineDoc = newDocument(), child = newNode("子节点正文");
  child.content = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "带格式的中文正文", marks: [{ type: "bold" }] }] }] };
  child.children.push(newNode("下级节点")); outlineDoc.nodeData.children.push(child, newNode("另一个分支"));
  outlineDoc.views.mode = "outline";
  let root = createRoot(host);
  flushSync(() => root.render(<MindMapEditor docId="regression.mindmap" data={outlineDoc as never} readOnly={false} theme="light" onReady={() => {}} />));
  await settle();
  assert(host.querySelectorAll(".ProseMirror").length === 1, "Outline must mount only one editor");
  const target = host.querySelector<HTMLElement>(`[data-editor-id="${child.id}"]`)!;
  const rect = target.getBoundingClientRect();
  flushSync(() => target.dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: rect.left + 45, clientY: rect.top + 12 })));
  await settle();
  let view = [...views].find(view => view.dom.isConnected && view.dom.dataset.editorId === child.id)!;
  assert(view && view.hasFocus(), "Click must activate and focus the selected outline node");
  flushSync(() => view.dispatch(view.state.tr.insertText("新文字", 1)));
  assert(host.querySelectorAll(".ProseMirror").length === 1, "Switching nodes must release the old editor");
  assert(await window.siyeFlush?.(), "Save must be acknowledged");
  assert(savedScenes.has("regression.mindmap"), "Save must reach the bridge");
  checks.push("Outline single editor, pointer activation, rich content and confirmed save");
  flushSync(() => view.dom.dispatchEvent(new KeyboardEvent("keydown", { key: "z", ctrlKey: true, bubbles: true })));
  await settle();
  view = [...views].find(view => view.dom.isConnected && view.dom.dataset.editorId === child.id)!;
  assert(view.state.doc.textContent === "带格式的中文正文", "Undo must restore the active node");
  flushSync(() => view.dom.dispatchEvent(new KeyboardEvent("keydown", { key: "z", ctrlKey: true, shiftKey: true, bubbles: true })));
  await settle();
  assert(view.state.doc.textContent.startsWith("新文字"), "Redo must restore input");
  await snapshot("outline");
  checks.push("Outline undo/redo retains the active editor and formatting");
  pauseAcks = true;
  flushSync(() => view.dispatch(view.state.tr.insertText("第一批", 1)));
  let finished = false;
  const inflight = window.siyeFlush!().then(okay => { finished = true; return okay; });
  await settle();
  assert(waitingAcks.size === 1, "First save must await acknowledgement");
  flushSync(() => view.dispatch(view.state.tr.insertText("第二批", 1)));
  acknowledge([...waitingAcks.keys()][0]); await settle();
  assert(!finished && waitingAcks.size === 1, "Input during saving must require another confirmed save");
  acknowledge([...waitingAcks.keys()][0]);
  assert(await inflight, "Flush must confirm the newest revision");
  pauseAcks = false;
  checks.push("Input during in-flight save waits for the newest revision acknowledgement");
  assert(await window.siyeFlush?.(), "Flush before switching");
  flushSync(() => (host.querySelectorAll('[role="tab"]')[1] as HTMLElement).click());
  await settle(); await settle();
  const mapNode = host.querySelector(`me-tpc[data-nodeid="${child.id}"]`) ?? [...host.querySelectorAll("me-tpc")].find(node => (node as unknown as { nodeObj: { id: string } }).nodeObj.id === child.id);
  assert(mapNode, "Map must show outline edits");
  await snapshot("map");
  checks.push("View switch preserves rich content and replaces editor portals safely");
  flushSync(() => root.unmount()); await settle();
  for (const layout of ["side", "left", "right", "down"] as const) {
    const doc = newDocument(); doc.views.mode = "map"; doc.settings.layout = layout;
    for (let i = 0; i < 8; i++) { const node = newNode(`分支${i}`); node.children.push(newNode("下级"), newNode("末级")); doc.nodeData.children.push(node); }
    let map: MindElixir | null = null;
    views.clear(); root = createRoot(host);
    flushSync(() => root.render(<MindMapEditor docId={`${layout}.mindmap`} data={doc as never} readOnly={false} theme="light" onReady={value => { map = value; }} />));
    await settle();
    if (layout === "side") {
      const instance = map as unknown as MindElixir;
      const topic = instance.findEle(doc.nodeData.id), rect = topic.getBoundingClientRect();
      const cx = rect.left + rect.width / 2, cy = rect.top + rect.height / 2;
      assert(document.elementFromPoint(cx, cy)?.closest("me-tpc") === topic, "Background must not cover node hit targets");
      const x = rect.left - 20, y = rect.top - 20;
      assert((document.elementFromPoint(x, y) as HTMLElement)?.dataset.siyeMapBackground !== undefined, "Blank area must hit the solid background");
      await mouse([{ type: "leftDown", x, y }]);
      assert(instance.ptState === 5, "Blank left drag must enter box selection");
      await mouse([{ type: "leftDrag", x: rect.right + 20, y: rect.bottom + 20 }, { type: "leftUp", x: rect.right + 20, y: rect.bottom + 20 }]);
      assert(instance.currentNodes.includes(topic), "Box selection must select the root");
      const before = instance.map.style.transform;
      await mouse([{ type: "rightDown", x, y }, { type: "rightDrag", x: x + 50, y: y + 30 }, { type: "rightUp", x: x + 50, y: y + 30 }]);
      assert(instance.map.style.transform !== before, "Blank right drag must pan the map");
      checks.push("Trusted mouse hit testing, empty-canvas box selection and panning");
    }
    for (const id of [doc.nodeData.id, doc.nodeData.children[0].children[0].id]) {
      const instance = map as unknown as MindElixir;
      const topic = instance.findEle(id);
      flushSync(() => topic.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, clientX: 500, clientY: 300 })));
      flushSync(() => (host.querySelector('.context-menu [id="编辑节点"]') as HTMLElement).click());
      await settle();
      const editor = [...views].find(item => item.dom.isConnected)!;
      flushSync(() => editor.dispatch(editor.state.tr.insertText("增加尺寸的中文内容".repeat(5), 1)));
      await settle(); await settle();
      const paths = () => [...instance.map.querySelectorAll(".lines path,.subLines path")].map(path => path.getAttribute("d"));
      const before = paths(); instance.linkDiv(); const after = paths();
      assert(JSON.stringify(before) === JSON.stringify(after), `Partial links must match a full rebuild for ${layout} ${id}`);
    }
    assert(await window.siyeFlush?.(), "Map save must be acknowledged");
    flushSync(() => root.unmount()); await settle();
    checks.push(`Root and descendant resize paths match a full rebuild (${layout})`);
  }
  views.clear(); root = createRoot(host);
  flushSync(() => root.render(<MindMapEditor docId="readonly.mindmap" data={outlineDoc as never} readOnly theme="light" onReady={() => {}} />));
  await settle(); assert(host.querySelectorAll(".ProseMirror").length === 0, "Read-only outline must use static rich content");
  checks.push("Read-only outline mounts no editable instances");
  flushSync(() => root.unmount());
  return { checks };
}
async function drawingRegression() {
  const { default: App } = await import("../src/App");
  const host = document.getElementById("root")!, root = createRoot(host), checks: string[] = [];
  flushSync(() => root.render(<App />)); await settle();
  window.postMessage({ version: "1.0", type: "loadScene", payload: { docId: "drawing.excalidraw", sceneJson: { type: "excalidraw", version: 2, elements: [], appState: {}, files: {} }, readOnly: false } }, "*");
  for (let i = 0; i < 40; i++) await frame();
  const tool = host.querySelector<HTMLElement>('[data-testid="toolbar-rectangle"]');
  assert(tool, "Drawing toolbar must load");
  const draw = async (x: number, y: number) => {
    const rect = tool!.getBoundingClientRect(), tx = rect.left + rect.width / 2, ty = rect.top + rect.height / 2;
    await mouse([{ type: "leftDown", x: tx, y: ty }, { type: "leftUp", x: tx, y: ty }]);
    await mouse([{ type: "leftDown", x, y }, { type: "leftDrag", x: x + 100, y: y + 70 }, { type: "leftUp", x: x + 100, y: y + 70 }]);
  };
  pauseAcks = true;
  await draw(430, 350);
  let finished = false;
  const inflight = window.siyeFlush!().then(okay => { finished = true; return okay; });
  await settle(); assert(waitingAcks.size === 1, "Drawing save must wait for native acknowledgement");
  const first = savedScenes.get("drawing.excalidraw") as { elements: unknown[] };
  assert(first.elements.length === 1, "First drawing must contain one shape");
  await draw(650, 450);
  const canvas = host.querySelector("canvas");
  window.postMessage({ version: "1.0", type: "updateDocId", payload: { docId: "renamed.excalidraw" } }, "*");
  await settle();
  assert(host.querySelector("canvas") === canvas, "Rename must retain the live canvas");
  acknowledge([...waitingAcks.keys()][0]); await settle();
  assert(!finished && waitingAcks.size === 1, "New drawing edits must remain dirty until confirmed");
  const latest = savedScenes.get("renamed.excalidraw") as { elements: unknown[] };
  assert(latest?.elements.length === 2, "Retry must save both shapes with the renamed document ID");
  acknowledge([...waitingAcks.keys()][0]); assert(await inflight, "Latest drawing save must be confirmed");
  pauseAcks = false;
  checks.push("Trusted rectangle drawing and native save acknowledgement", "In-flight edits save the latest drawing revision", "Rename keeps the canvas and saves new edits to the new document ID");
  await snapshot("drawing");
  flushSync(() => root.unmount()); await settle();
  return { checks };
}
async function run() {
  const results = [];
  const host = document.getElementById("root")!;
  const profile = new URLSearchParams(location.search).has("profile");
  for (const count of profile ? [1000] : [100, 500, 1000]) {
    const modes: ("outline" | "map")[] = profile ? ["map"] : ["outline", "map"];
    for (const mode of modes) {
      progress(`Starting ${count} ${mode}`);
      const document = newDocument(), nodes = [document.nodeData];
      for (let index = 1; index < count; index++) {
        const node = newNode("用于 WebKit 性能审计的节点正文，包含常规中文内容。");
        nodes[Math.floor((index - 1) / 8)].children.push(node); nodes.push(node);
      }
      document.views.mode = mode;
      views.clear();
      let map: MindElixir | null = null;
      const root = createRoot(host);
      const start = performance.now();
      flushSync(() => root.render(<MindMapEditor docId="synthetic.mindmap" data={document as never} readOnly={false} theme="light" onReady={instance => { map = instance; }} />));
      await frame(); await frame();
      const mount = performance.now() - start;
      progress(`Mounted ${count} ${mode}`);
      const lookupSamples: number[] = [], linkSamples: number[] = [], partialSamples: number[] = [];
      let branches = 0;
      if (mode === "map" && map) {
        const instance = map as MindElixir;
        const wrappers = [...instance.nodes.querySelectorAll("me-main > me-wrapper")]; branches = wrappers.length;
        const branch = wrappers[wrappers.length - 1];
        for (let index = 0; index < 15; index++) {
          await frame();
          const startLookup = performance.now();
          nodes.forEach(node => instance.findEle(node.id));
          const lookup = performance.now() - startLookup;
          const startLinks = performance.now(); instance.linkDiv(); const links = performance.now() - startLinks;
          const partialStart = performance.now(); if (branch) instance.linkDiv(branch as never); const partial = performance.now() - partialStart;
          if (index >= 5) { lookupSamples.push(lookup); linkSamples.push(links); partialSamples.push(partial); }
        }
      }
      if (mode === "map") {
        host.querySelector("me-tpc")!.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, clientX: 500, clientY: 300 }));
        (host.querySelector('.context-menu [id="编辑节点"]') as HTMLElement).click();
        await frame(); await frame();
      }
      const view = [...views].find(item => item.dom.isConnected);
      if (!view) throw new Error(`No editor captured in ${mode}`);
      const editors = host.querySelectorAll(".ProseMirror").length;
      view.focus();
      const transactions = [], intervals = [], idle = [];
      for (let index = 0; index < 10; index++) { const prior = await frame(); idle.push(await frame() - prior); }
      for (let index = 0; index < (profile ? 400 : 35); index++) {
        const priorFrame = await frame();
        const begin = performance.now();
        flushSync(() => view.dispatch(view.state.tr.insertText("字", 1)));
        const elapsed = performance.now() - begin;
        const nextFrame = await frame();
        if (index >= 5) { transactions.push(elapsed); intervals.push(nextFrame - priorFrame); }
      }
      results.push({ raw_frame_intervals_ms: intervals, idle_frame_p95_ms: percentile(idle, .95), nodes: count, mode, mounted_editors: editors, mount_to_two_raf_ms: +mount.toFixed(2), transaction_with_react_commit_p50_ms: +percentile(transactions, .5).toFixed(2), transaction_with_react_commit_p95_ms: +percentile(transactions, .95).toFixed(2), raf_interval_p95_ms: +percentile(intervals, .95).toFixed(2), ...(lookupSamples.length ? { all_node_lookups_p95_ms: percentile(lookupSamples, .95), full_link_div_p95_ms: percentile(linkSamples, .95), branches, partial_link_div_p95_ms: percentile(partialSamples, .95) } : {}) });
      progress(`Edited ${count} ${mode}`);
      await window.siyeFlush?.();
      flushSync(() => root.unmount());
      await frame();
    }
  }
  return { userAgent: navigator.userAgent, viewport: [innerWidth, innerHeight], warmup: 5, samples: profile ? 395 : 30, results };
}
(new URLSearchParams(location.search).has("drawing") ? drawingRegression() : new URLSearchParams(location.search).has("regression") ? regression() : run()).then(result => {
  document.getElementById("root")!.textContent = JSON.stringify(result, null, 2);
  (window.webkit?.messageHandlers as unknown as { performanceResult?: { postMessage: (value: unknown) => void } })?.performanceResult?.postMessage(result);
}).catch(error => {
  document.getElementById("root")!.textContent = String(error);
  (window.webkit?.messageHandlers as unknown as { performanceResult?: { postMessage: (value: unknown) => void } })?.performanceResult?.postMessage({ error: String(error) });
});
