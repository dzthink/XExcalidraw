import type MindElixir from "mind-elixir";
import { embedImages } from "./htmlExport";

const properties = ["display", "position", "top", "right", "bottom", "left", "box-sizing", "width", "height", "min-width", "max-width", "min-height", "max-height", "padding", "margin", "border", "border-collapse", "border-radius", "background-color", "color", "font-family", "font-size", "font-weight", "font-style", "line-height", "letter-spacing", "text-align", "text-decoration", "white-space", "overflow-wrap", "word-break", "vertical-align", "list-style-type", "list-style-position", "gap", "align-items", "flex-direction", "flex-shrink"];

/** Freeze rich-text layout so standalone SVG does not fall back to browser paragraph defaults. */
export async function exportMapSVG(instance: MindElixir): Promise<Blob> {
  const source = instance.nodes;
  await document.fonts.ready;
  await Promise.all(Array.from(source.querySelectorAll("img")).map(image => image.complete ? Promise.resolve() : new Promise<void>(resolve => {
    image.addEventListener("load", () => resolve(), { once: true }); image.addEventListener("error", () => resolve(), { once: true }); setTimeout(resolve, 3000);
  })));
  instance.linkDiv();
  const svg = new DOMParser().parseFromString(await instance.exportSvg().text(), "image/svg+xml");
  const topics = Array.from(source.querySelectorAll<HTMLElement>("me-tpc"));
  const objects = Array.from(svg.querySelectorAll("foreignObject"));
  const bounds: { left: number; top: number; right: number; bottom: number }[] = [];
  for (const [index, object] of objects.entries()) {
    const topic = topics[index];
    if (!topic) continue;
    const rect = object.parentElement?.querySelector("rect");
    const body = topic.querySelector<HTMLElement>(".mindmap-node-body");
    if (!rect || !body) continue;
    const style = getComputedStyle(topic);
    const left = parseFloat(style.paddingLeft), top = parseFloat(style.paddingTop);
    const right = parseFloat(style.paddingRight), bottom = parseFloat(style.paddingBottom);
    rect.setAttribute("width", String(topic.offsetWidth)); rect.setAttribute("height", String(topic.offsetHeight));
    const x = Number(rect.getAttribute("x")), y = Number(rect.getAttribute("y"));
    bounds.push({ left: x, top: y, right: x + topic.offsetWidth, bottom: y + topic.offsetHeight });
    object.setAttribute("x", String(Number(rect.getAttribute("x")) + left));
    object.setAttribute("y", String(Number(rect.getAttribute("y")) + top));
    object.setAttribute("width", String(Math.max(1, topic.clientWidth - left - right)));
    object.setAttribute("height", String(Math.max(1, topic.clientHeight - top - bottom)));
    const clone = body.cloneNode(true) as HTMLElement;
    const originalElements = [body, ...Array.from(body.querySelectorAll<HTMLElement>("*"))];
    const clonedElements = [clone, ...Array.from(clone.querySelectorAll<HTMLElement>("*"))];
    originalElements.forEach((element, i) => {
      const computed = getComputedStyle(element);
      for (const property of properties) clonedElements[i].style.setProperty(property, computed.getPropertyValue(property));
    });
    clone.querySelectorAll<HTMLElement>("ul:not([data-list-marker='task'])>li,ol>li").forEach(item => {
      const marker = document.createElement("span");
      marker.textContent = item.parentElement!.tagName === "OL" ? `${Array.from(item.parentElement!.children).indexOf(item) + 1}.` : "•";
      marker.style.cssText = "position:absolute;right:calc(100% + 8px);top:0";
      item.prepend(marker);
    });
    clone.style.display = "block";
    clone.style.width = "100%";
    clone.style.height = "auto";
    clone.style.margin = "0";
    clone.setAttribute("xmlns", "http://www.w3.org/1999/xhtml");
    await embedImages(clone);
    object.replaceChildren(svg.importNode(clone, true));
  }
  if (bounds.length) {
    const left = Math.min(...bounds.map(box => box.left)), top = Math.min(...bounds.map(box => box.top));
    const right = Math.max(...bounds.map(box => box.right)), bottom = Math.max(...bounds.map(box => box.bottom));
    const width = right - left + 200, height = bottom - top + 200;
    const root = svg.documentElement;
    root.setAttribute("width", String(width)); root.setAttribute("height", String(height));
    root.setAttribute("viewBox", `0 0 ${width} ${height}`);
    const drawing = Array.from(root.children).find(child => child.localName === "svg")!;
    drawing.setAttribute("x", String(100 - left)); drawing.setAttribute("y", String(100 - top));
    const background = Array.from(root.children).find(child => child.localName === "rect")!;
    background.setAttribute("width", String(width)); background.setAttribute("height", String(height));
    background.setAttribute("fill", getComputedStyle(instance.container).backgroundColor);
  }
  // The library also emits images separately, duplicating rich-content images.
  svg.querySelectorAll("image").forEach(image => image.remove());
  return new Blob([new XMLSerializer().serializeToString(svg.documentElement)], { type: "image/svg+xml" });
}

export async function exportMapImage(instance: MindElixir, format: "svg" | "png"): Promise<Blob> {
  const svg = await exportMapSVG(instance);
  if (format === "svg") return svg;
  const url = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader(); reader.onload = () => resolve(String(reader.result)); reader.onerror = () => reject(new Error("无法读取 SVG")); reader.readAsDataURL(svg);
  });
  const image = new Image();
  await new Promise<void>((resolve, reject) => { image.onload = () => resolve(); image.onerror = () => reject(new Error("无法生成导出图片")); image.src = url; });
  const canvas = document.createElement("canvas"); canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
  canvas.getContext("2d")!.drawImage(image, 0, 0);
  return await new Promise<Blob>((resolve, reject) => canvas.toBlob(blob => blob ? resolve(blob) : reject(new Error("无法生成 PNG")), "image/png"));
}
