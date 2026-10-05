import React from "react";
import { createRoot } from "react-dom/client";
import App from "../src/App";
import { newDocument, newNode, plainContent } from "../src/mindmap/document";
import { exportHTML } from "../src/mindmap/htmlExport";
import { interchangeText } from "../src/mindmap/interchange";
const pause = (ms = 100) => new Promise(resolve => setTimeout(resolve, ms));
const assert = (value: unknown, message: string) => { if (!value) throw new Error(message); };
const send = (type: string, payload: unknown) => window.postMessage({ version: "1.0", type, payload }, "*");
const results = new Map<string, string>();
window.addEventListener("message", event => {
  const message = typeof event.data === "string" ? JSON.parse(event.data) : event.data;
  if (message.type === "exportResult") results.set(message.payload.format, message.payload.dataBase64);
  if (message.type === "exportFailed") throw new Error(message.payload.error);
  if (message.type === "saveScene") send("saveResult", { requestId: message.payload.requestId, success: true });
});
const handlers = () => window.webkit?.messageHandlers as unknown as Record<string, { postMessage(value: unknown): void }> | undefined;
createRoot(document.getElementById("root")!).render(<App />);
async function run() {
  await pause(1000);
  const doc = newDocument();
  doc.nodeData.content = { type: "doc", content: [plainContent('导入 / 导出 & <中文>').content![0], { type: "blockquote", content: plainContent("备注第一行\n第二行").content }] };
  doc.nodeData.children = [newNode("HTML 离线阅读"), newNode("长文本自动换行：这个节点应完整显示在节点框内，文字、备注和行间距在独立 SVG 中保持一致。"), newNode("XMind / FreeMind / OPML")];
  doc.nodeData.children[0].content.content!.push({ type: "heading", attrs: { level: 2 }, content: [{ type: "text", text: "第二行标题" }] });
  send("loadScene", { docId: "synthetic.mindmap", sceneJson: doc, readOnly: false });
  for (let attempt = 0; attempt < 100 && !window.siyeExport; attempt++) await pause();
  assert(window.siyeExport, "Mind map exporter mounted");
  for (const format of ["html", "png", "svg", "mindmap", "xmind", "mm", "opml"]) {
    send("requestExport", { format, embedScene: true });
    for (let attempt = 0; attempt < 150 && !results.has(format); attempt++) await pause();
    assert(results.has(format), `${format} returned through bridge`);
    assert(results.get(format)!.length > 50, `${format} nonempty`);
  }
  const png = atob(results.get("png")!);
  assert(png.slice(1, 4) === "PNG", "PNG signature");
  assert(interchangeText(doc.nodeData).note === "备注第一行\n第二行", "Quotes export as notes");
  const html = new TextDecoder().decode(Uint8Array.from(atob(results.get("html")!), char => char.charCodeAt(0)));
  const parsed = new DOMParser().parseFromString(html, "text/html");
  assert(parsed.querySelector("blockquote") && parsed.querySelectorAll("details").length === 1 && parsed.querySelector("script"), "Offline HTML preserves rich text, folding and switching controls");
  const imageDoc = newDocument();
  imageDoc.nodeData.content.content!.push({ type: "image", attrs: { path: ".siye/attachments/synthetic.png", width: 240 } });
  const originalFetch = window.fetch;
  window.fetch = async () => {
    const response = new Response(Uint8Array.from(atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOioAAAAASUVORK5CYII="), char => char.charCodeAt(0)));
    // Match WKURLSchemeHandler's non-HTTP response with empty MIME metadata.
    Object.defineProperties(response, { status: { value: 0 }, ok: { value: false } });
    return response;
  };
  try { assert((await exportHTML(imageDoc, "synthetic.mindmap")).includes('src="data:image/png;base64,'), "HTML embeds attachment bytes"); }
  finally { window.fetch = originalFetch; }
  const preview = document.createElement("iframe"); preview.srcdoc = html; preview.style.cssText = "position:fixed;inset:0;width:100%;height:100%;border:0;z-index:10000;background:white"; document.body.append(preview);
  await pause(400);
  const exported = preview.contentDocument!;
  assert(exported.querySelector("#map-view")?.hasAttribute("hidden"), "HTML starts in saved outline view");
  (exported.querySelector("#show-map") as HTMLButtonElement).click();
  assert(exported.querySelector("#outline-view")?.hasAttribute("hidden"), "Switch to map hides outline");
  assert(!exported.querySelector("#map-view")?.hasAttribute("hidden"), "Switch to map reveals SVG");
  const svg = exported.querySelector<SVGSVGElement>("#map-view>svg")!;
  const width = svg.style.width;
  (exported.querySelector("#zoom-in") as HTMLButtonElement).click();
  assert(svg.style.width !== width, "Map zoom works offline");
  (exported.querySelector("#zoom-fit") as HTMLButtonElement).click();
  await pause(100);
  for (const object of Array.from(exported.querySelectorAll("foreignObject"))) {
    const rect = object.parentElement!.querySelector("rect")!.getBoundingClientRect();
    const canvas = svg.getBoundingClientRect();
    assert(rect.left >= canvas.left - 1 && rect.right <= canvas.right + 1 && rect.top >= canvas.top - 1 && rect.bottom <= canvas.bottom + 1, "SVG canvas includes every node without clipping");
    const body = object.firstElementChild!.getBoundingClientRect();
    assert(body.left >= rect.left - 1 && body.right <= rect.right + 1 && body.top >= rect.top - 1 && body.bottom <= rect.bottom + 1, "Standalone SVG rich content stays inside node rectangle");
  }
  (exported.querySelector("#show-outline") as HTMLButtonElement).click();
  assert(!exported.querySelector("#outline-view")?.hasAttribute("hidden"), "Switch back preserves outline");
  (exported.querySelector("#show-map") as HTMLButtonElement).click();

  if (handlers()?.performanceSnapshot) {
    const finished = new Promise<void>(resolve => window.addEventListener("performance-snapshot-finished", () => resolve(), { once: true }));
    handlers()!.performanceSnapshot.postMessage("interchange-html"); await finished;
  }
  const standalone = document.createElement("iframe");
  const svgText = new TextDecoder().decode(Uint8Array.from(atob(results.get("svg")!), char => char.charCodeAt(0)));
  standalone.srcdoc = `<html><body style="margin:0">${svgText}</body></html>`;
  standalone.style.cssText = preview.style.cssText;
  document.body.append(standalone); await pause(200);
  const svgDoc = standalone.contentDocument!;
  const standaloneSVG = svgDoc.querySelector<SVGSVGElement>("svg")!;
  standaloneSVG.style.width = "100%"; standaloneSVG.style.height = "auto";
  for (const object of Array.from(svgDoc.querySelectorAll("foreignObject"))) {
    const rect = object.parentElement!.querySelector("rect")!.getBoundingClientRect();
    const content = object.firstElementChild!.getBoundingClientRect();
    assert(content.left >= rect.left - 1 && content.right <= rect.right + 1 && content.top >= rect.top - 1 && content.bottom <= rect.bottom + 1, "SVG opened without editor/HTML styles retains node text bounds");
  }
  if (handlers()?.performanceSnapshot) {
    const finished = new Promise<void>(resolve => window.addEventListener("performance-snapshot-finished", () => resolve(), { once: true }));
    handlers()!.performanceSnapshot.postMessage("standalone-svg"); await finished;
  }
  handlers()?.performanceResult?.postMessage({ passed: true, formats: [...results.keys()], pngBytes: png.length, htmlBytes: html.length, offlineImage: true, viewSwitching: true, standaloneSvgBounds: true });
  document.title = "PASS: import/export";
}
run().catch(error => { document.title = "FAIL: " + String(error); handlers()?.performanceResult?.postMessage({ error: String(error) }); });
