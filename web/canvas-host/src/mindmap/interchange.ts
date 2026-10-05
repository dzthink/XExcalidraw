import { type MapDocument, type MapNode } from "./document";
import { contentText } from "./richText";

export const escapeXML = (text: string): string => text.replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[char]!).replace(/\n/g, "&#10;").replace(/\r/g, "&#13;").replace(/\t/g, "&#9;");

// Quote blocks are the editor's note representation.
export function interchangeText(item: MapNode): { title: string; note: string } {
  const blocks = item.content.content ?? [];
  const titles = blocks.filter(block => block.type !== "blockquote");
  const notes = blocks.filter(block => block.type === "blockquote");
  const text = (content: typeof blocks) => content.length ? contentText({ type: "doc", content }) : "";
  return { title: text(titles), note: [text(notes), item.note].filter(Boolean).join("\n") };
}

export function exportFreeMind(doc: MapDocument): string {
  const node = (item: MapNode): string => `<node ID="${escapeXML(item.id)}" TEXT="${escapeXML(interchangeText(item).title)}" FOLDED="${!item.expanded}">${interchangeText(item).note ? `<richcontent TYPE="NOTE"><html><head/><body><p>${escapeXML(interchangeText(item).note)}</p></body></html></richcontent>` : ""}${item.children.map(node).join("")}</node>`;
  return `<?xml version="1.0" encoding="UTF-8"?><map version="1.0.1">${node(doc.nodeData)}</map>`;
}

export function exportOPML(doc: MapDocument): string {
  const node = (item: MapNode): string => `<outline text="${escapeXML(interchangeText(item).title)}" _note="${escapeXML(interchangeText(item).note)}">${item.children.map(node).join("")}</outline>`;
  return `<?xml version="1.0" encoding="UTF-8"?><opml version="2.0"><head><title>${escapeXML(interchangeText(doc.nodeData).title)}</title></head><body>${node(doc.nodeData)}</body></opml>`;
}

export function exportXMind(doc: MapDocument): Uint8Array {
  type Topic = { id: string; class: string; title: string; branch: string; notes: { plain: { content: string } }; children: { attached: Topic[] } };
  const node = (item: MapNode): Topic => ({ id: item.id, class: "topic", title: interchangeText(item).title, branch: item.expanded ? "expanded" : "folded", notes: { plain: { content: interchangeText(item).note } }, children: { attached: item.children.map(node) } });
  return zipStored({
    "content.json": JSON.stringify([{ id: crypto.randomUUID(), class: "sheet", title: interchangeText(doc.nodeData).title, rootTopic: node(doc.nodeData) }]),
    "metadata.json": JSON.stringify({ creator: { name: "Siye", version: "1.0" } }),
    "manifest.json": JSON.stringify({ "file-entries": { "content.json": {}, "metadata.json": {} } })
  });
}

/** Standard ZIP with UTF-8 filenames and stored entries; no runtime dependency. */
export function zipStored(files: Record<string, string>): Uint8Array {
  const encoder = new TextEncoder(), parts: Uint8Array[] = [], central: Uint8Array[] = [];
  let offset = 0;
  const header = (size: number) => { const bytes = new Uint8Array(size); return { bytes, view: new DataView(bytes.buffer) }; };
  for (const [name, text] of Object.entries(files)) {
    const filename = encoder.encode(name), data = encoder.encode(text);
    let crc = 0xffffffff;
    for (const byte of data) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = header(30 + filename.length), directory = header(46 + filename.length);
    local.view.setUint32(0, 0x04034b50, true); local.view.setUint16(4, 20, true); local.view.setUint16(6, 0x800, true); local.view.setUint16(12, 33, true);
    local.view.setUint32(14, crc, true); local.view.setUint32(18, data.length, true); local.view.setUint32(22, data.length, true); local.view.setUint16(26, filename.length, true); local.bytes.set(filename, 30);
    directory.view.setUint32(0, 0x02014b50, true); directory.view.setUint16(4, 20, true); directory.view.setUint16(6, 20, true); directory.view.setUint16(8, 0x800, true); directory.view.setUint16(14, 33, true);
    directory.view.setUint32(16, crc, true); directory.view.setUint32(20, data.length, true); directory.view.setUint32(24, data.length, true); directory.view.setUint16(28, filename.length, true); directory.view.setUint32(42, offset, true); directory.bytes.set(filename, 46);
    parts.push(local.bytes, data); central.push(directory.bytes); offset += local.bytes.length + data.length;
  }
  const end = header(22), centralSize = central.reduce((sum, item) => sum + item.length, 0);
  end.view.setUint32(0, 0x06054b50, true); end.view.setUint16(8, central.length, true); end.view.setUint16(10, central.length, true); end.view.setUint32(12, centralSize, true); end.view.setUint32(16, offset, true);
  const result = new Uint8Array(offset + centralSize + 22); let cursor = 0;
  for (const part of [...parts, ...central, end.bytes]) { result.set(part, cursor); cursor += part.length; }
  return result;
}

export function htmlPage(title: string, body: string): string {
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeXML(title)}</title><style>body{font:16px/1.6 system-ui,sans-serif;color:#25302c;background:#fff;margin:0;padding:32px;overflow-wrap:anywhere}main{max-width:1100px;margin:auto}.tree{padding-left:24px;list-style:none}.tree>li{margin:12px 0;border-left:2px solid #ddd;padding-left:16px}blockquote{border-left:3px solid #ccc;margin:8px 0;padding-left:12px;color:#666}ul[data-list-marker="task"]{list-style:none}summary{cursor:pointer;display:flex;gap:8px;align-items:flex-start;list-style:none}summary::-webkit-details-marker{display:none}summary::before{content:"▸"}details[open]>summary::before{content:"▾"}img,svg{max-width:100%;height:auto}pre{overflow:auto;background:#f4f5f4;padding:12px}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px}.note{white-space:pre-wrap;color:#666}p{margin:4px 0;white-space:pre-wrap}@media print{body{padding:0}}</style><main><h1>${escapeXML(title)}</h1>${body}</main></html>`;
}
