import { Schema, DOMSerializer, type Node as PMNode } from "prosemirror-model";
import { tableNodes } from "prosemirror-tables";
import type { RichDocument } from "./document";

export function safeLink(value: string): string | null {
  try { const url = new URL(value); return ["https:", "http:", "mailto:"].includes(url.protocol) ? url.href : null; } catch { return null; }
}
export function attachmentSource(path: string, docId: string): string {
  const relative = path.replace(/^(?:(?:\.\.\/|\.\/))*/, "");
  const parts = relative.split("/");
  if (parts.length < 2 || parts.some(part => !part || part === "." || part === "..") || /[\\:%?#\x00-\x1f]/.test(relative) || !/\.(png|jpe?g|gif|webp)$/i.test(relative)) return "";
  return `app:///mindmap-attachment?docId=${encodeURIComponent(docId)}&path=${encodeURIComponent(path)}`;
}
export const schema = new Schema({
  nodes: {
    doc: { content: "block+" },
    paragraph: { content: "inline*", group: "block", parseDOM: [{ tag: "p" }], toDOM: () => ["p", 0] },
    heading: { attrs: { level: { default: 1 } }, content: "inline*", group: "block", defining: true,
      parseDOM: [1, 2, 3].map(level => ({ tag: `h${level}`, attrs: { level } })), toDOM: node => [`h${Math.max(1, Math.min(3, node.attrs.level))}`, 0] },
    blockquote: { content: "block+", group: "block", defining: true, parseDOM: [{ tag: "blockquote" }], toDOM: () => ["blockquote", 0] },
    text: { group: "inline" },
    hard_break: { inline: true, group: "inline", selectable: false, parseDOM: [{ tag: "br" }], toDOM: () => ["br"] },
    bullet_list: { content: "list_item+", group: "block", attrs: { marker: { default: "bullet" } },
      parseDOM: [{ tag: "ul", getAttrs: dom => ({ marker: (dom as HTMLElement).getAttribute("data-list-marker") === "dash" ? "dash" : "bullet" }) }],
      toDOM: node => ["ul", { "data-list-marker": node.attrs.marker }, 0] },
    ordered_list: { content: "list_item+", group: "block", attrs: { order: { default: 1 } }, parseDOM: [{ tag: "ol", getAttrs: dom => ({ order: Number((dom as HTMLElement).getAttribute("start")) || 1 }) }], toDOM: node => ["ol", { start: node.attrs.order }, 0] },
    list_item: { content: "paragraph block*", defining: true, parseDOM: [{ tag: "li" }], toDOM: () => ["li", 0] },
    code_block: { content: "text*", group: "block", marks: "", code: true, defining: true, parseDOM: [{ tag: "pre", preserveWhitespace: "full" }], toDOM: () => ["pre", ["code", 0]] },
    image: { group: "block", atom: true, draggable: true, attrs: { path: { default: "" }, width: { default: 240 }, alt: { default: "图片" } },
      parseDOM: [{ tag: "img[data-attachment]", getAttrs: dom => { const path = (dom as HTMLElement).dataset.attachment ?? ""; return attachmentSource(path, "validation") ? { path, width: Number((dom as HTMLElement).getAttribute("width")) || 240 } : false; } }],
      toDOM: node => ["img", { "data-attachment": node.attrs.path, width: Math.max(40, Math.min(640, Number(node.attrs.width) || 240)), alt: node.attrs.alt }] },
    ...tableNodes({ tableGroup: "block", cellContent: "block+", cellAttributes: {} })
  },
  marks: {
    bold: { parseDOM: [{ tag: "strong" }, { tag: "b" }], toDOM: () => ["strong", 0] },
    italic: { parseDOM: [{ tag: "em" }, { tag: "i" }], toDOM: () => ["em", 0] },
    strike: { parseDOM: [{ tag: "s" }, { tag: "del" }], toDOM: () => ["s", 0] },
    code: { parseDOM: [{ tag: "code" }], toDOM: () => ["code", 0] },
    link: { attrs: { href: {} }, inclusive: false,
      parseDOM: [{ tag: "a[href]", getAttrs: dom => { const href = safeLink((dom as HTMLElement).getAttribute("href") ?? ""); return href ? { href } : false; } }],
      toDOM: mark => ["a", { href: safeLink(mark.attrs.href) ?? "", rel: "noopener noreferrer" }, 0] }
  }
});
export function readContent(json: RichDocument): PMNode {
  const doc = schema.nodeFromJSON(json);
  doc.check();
  doc.descendants(node => {
    if (node.type.name === "image" && !attachmentSource(node.attrs.path, "validation")) throw new Error("附件路径无效");
    if (node.type.name === "heading" && ![1, 2, 3].includes(node.attrs.level)) throw new Error("标题级别无效");
    if (node.marks.some(mark => mark.type.name === "link" && !safeLink(mark.attrs.href))) throw new Error("链接地址无效");
  });
  return doc;
}
export function renderContent(json: RichDocument, docId: string): string {
  const holder = document.createElement("div");
  holder.append(DOMSerializer.fromSchema(schema).serializeFragment(readContent(json).content));
  holder.querySelectorAll<HTMLImageElement>("img[data-attachment]").forEach(image => {
    image.src = attachmentSource(image.dataset.attachment ?? "", docId);
  });
  return holder.innerHTML;
}
export const contentText = (json: RichDocument): string => readContent(json).textBetween(0, readContent(json).content.size, "\n");
