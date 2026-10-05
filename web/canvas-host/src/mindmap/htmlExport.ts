import { type MapDocument, type MapNode } from "./document";
import { renderContent } from "./richText";
import { escapeXML, htmlPage, interchangeText } from "./interchange";

export async function embedImages(holder: HTMLElement): Promise<void> {
  await Promise.all(Array.from(holder.querySelectorAll("img")).map(async image => {
    const response = await fetch(image.src, { signal: AbortSignal.timeout(15000) });
    if (!response.ok && response.status !== 0) throw new Error("无法读取导出图片");
    // WKURLSchemeHandler's URLResponse exposes no HTTP status or Content-Type to fetch.
    const bytes = new Uint8Array(await response.arrayBuffer());
    const signature = String.fromCharCode(...bytes.subarray(0, 12));
    const mime = bytes[0] === 137 && signature.slice(1, 4) === "PNG" ? "image/png"
      : bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 ? "image/jpeg"
      : signature.startsWith("GIF87a") || signature.startsWith("GIF89a") ? "image/gif"
      : signature.startsWith("RIFF") && signature.slice(8, 12) === "WEBP" ? "image/webp" : null;
    if (!mime) throw new Error("导出图片数据无效");
    const blob = new Blob([bytes], { type: mime });
    image.src = await new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result)); reader.onerror = () => reject(new Error("无法导出图片")); reader.readAsDataURL(blob); });
  }));
}

export async function exportHTML(doc: MapDocument, docId: string, mapSVG?: string): Promise<string> {
  const node = async (item: MapNode): Promise<string> => {
    const holder = document.createElement("div");
    holder.innerHTML = renderContent(item.content, docId);
    await embedImages(holder);
    const content = `<div>${holder.innerHTML}</div>${item.note ? `<div class="note">${escapeXML(item.note)}</div>` : ""}`;
    const children = await Promise.all(item.children.map(node));
    return `<li>${children.length ? `<details open><summary><div>${content}</div></summary><ul class="tree">${children.join("")}</ul></details>` : content}</li>`;
  };
  const outline = `<section id="outline-view"><ul class="tree">${await node(doc.nodeData)}</ul></section>`;
  if (!mapSVG) return htmlPage(interchangeText(doc.nodeData).title || "思维导图", outline);
  const initialMap = doc.views.mode === "map";
  const controls = `<nav class="view-controls" aria-label="视图"><button id="show-outline" aria-pressed="${!initialMap}">大纲</button><button id="show-map" aria-pressed="${initialMap}">思维导图</button><span id="map-controls"><button id="zoom-out" aria-label="缩小">−</button><button id="zoom-fit">适应窗口</button><button id="zoom-in" aria-label="放大">+</button></span></nav>`;
  const page = htmlPage(interchangeText(doc.nodeData).title || "思维导图", `${controls}${outline}<section id="map-view" tabindex="0" aria-label="思维导图">${mapSVG}</section>`);
  const css = `.view-controls{display:flex;flex-wrap:wrap;gap:8px;align-items:center;position:sticky;top:0;background:white;padding:12px 0;z-index:1}.view-controls button{font:inherit;padding:6px 14px;border:1px solid #ccc;border-radius:8px;background:#fff;color:#25302c;cursor:pointer}.view-controls button[aria-pressed=true]{background:#25302c;color:white}#map-view{overflow:auto;border:1px solid #eee;border-radius:12px;height:75vh}#map-view>svg{display:block;max-width:none;height:auto}#map-controls{margin-left:auto;display:flex;gap:8px}[hidden]{display:none!important}main{max-width:none}@media print{.view-controls{display:none}#map-view{height:auto;overflow:visible}}`;
  const script = `<script>(()=>{const outline=document.getElementById('outline-view'),map=document.getElementById('map-view'),svg=map.querySelector('svg'),buttons=[document.getElementById('show-outline'),document.getElementById('show-map')],controls=document.getElementById('map-controls');let scale=1;const width=parseFloat(svg.getAttribute('width'));const zoom=value=>{scale=Math.max(.2,Math.min(3,value));svg.style.width=(width*scale)+'px';};const fit=()=>zoom((map.clientWidth-24)/width);const show=isMap=>{outline.hidden=isMap;map.hidden=!isMap;controls.hidden=!isMap;buttons[0].setAttribute('aria-pressed',String(!isMap));buttons[1].setAttribute('aria-pressed',String(isMap));if(isMap)fit();};buttons[0].onclick=()=>show(false);buttons[1].onclick=()=>show(true);document.getElementById('zoom-in').onclick=()=>zoom(scale*1.2);document.getElementById('zoom-out').onclick=()=>zoom(scale/1.2);document.getElementById('zoom-fit').onclick=fit;show(${initialMap});})();</script>`;
  return page.replace("</style>", css + "</style>").replace("</html>", script + "</html>");
}
