export type RichDocument = { type: string; attrs?: Record<string, unknown>; text?: string; marks?: { type: string; attrs?: Record<string, unknown> }[]; content?: RichDocument[] };
export type MapNode = { id: string; content: RichDocument; note: string; expanded: boolean; children: MapNode[] };
export type MapDocument = {
  format: "siye-mindmap"; version: 2; nodeData: MapNode;
  settings: { layout: "side" | "left" | "right" | "down"; palette: "gray" | "blue" | "green"; noteDisplay: "all" | "first" };
  views: { mode: "map" | "outline"; outlineScroll: number; map: { scale: number; x: number; y: number }; focusId: string | null; selectedIds: string[] };
};
export type Cursor = { id: string; from: number; to: number; field: "content" | "note" };
export const plainContent = (text = ""): RichDocument => ({ type: "doc", content: [{ type: "paragraph", ...(text ? { content: [{ type: "text", text }] } : {}) }] });
export const textContent = (doc: RichDocument): string => doc.text ?? (doc.content ?? []).map(textContent).join(doc.type === "doc" ? "\n" : "");
export const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
export const newNode = (text = ""): MapNode => ({ id: crypto.randomUUID(), content: plainContent(text), note: "", expanded: true, children: [] });
export const newDocument = (): MapDocument => ({ format: "siye-mindmap", version: 2, nodeData: newNode("中心主题"), settings: { layout: "side", palette: "gray", noteDisplay: "all" }, views: { mode: "outline", outlineScroll: 0, map: { scale: 1, x: 0, y: 0 }, focusId: null, selectedIds: [] } });
export function findNode(root: MapNode, id: string): MapNode | null {
  if (root.id === id) return root;
  for (const child of root.children) { const found = findNode(child, id); if (found) return found; }
  return null;
}
export function parentOf(root: MapNode, id: string): MapNode | null {
  for (const child of root.children) { if (child.id === id) return root; const found = parentOf(child, id); if (found) return found; }
  return null;
}
export function visibleNodes(root: MapNode): MapNode[] {
  return [root, ...(root.expanded ? root.children.flatMap(visibleNodes) : [])];
}
export const descendantCount = (node: MapNode): number => node.children.reduce((count, child) => count + 1 + descendantCount(child), 0);
export function topLevelSelection(root: MapNode, ids: string[]): MapNode[] {
  const selected = new Set(ids);
  const visit = (node: MapNode): MapNode[] => selected.has(node.id) ? [node] : node.children.flatMap(visit);
  return visit(root).filter(node => node.id !== root.id);
}
export function moveNodes(root: MapNode, ids: string[], targetId: string, placement: "before" | "after" | "inside"): boolean {
  const target = findNode(root, targetId);
  const moving = topLevelSelection(root, ids);
  if (!target || !moving.length || moving.some(node => findNode(node, targetId))) return false;
  const destination = placement === "inside" ? target : parentOf(root, targetId);
  if (!destination) return false;
  for (const node of moving) { const parent = parentOf(root, node.id); if (parent) parent.children = parent.children.filter(child => child.id !== node.id); }
  const index = placement === "inside" ? destination.children.length : destination.children.findIndex(node => node.id === targetId) + (placement === "after" ? 1 : 0);
  destination.children.splice(index, 0, ...moving);
  destination.expanded = true;
  return true;
}
export type StructureAction = "child" | "sibling" | "indent" | "outdent" | "delete" | "fold";
export function structure(root: MapNode, ids: string[], action: StructureAction): string | null {
  const node = findNode(root, ids[0]);
  if (!node) return null;
  const parent = parentOf(root, node.id);
  const index = parent?.children.indexOf(node) ?? -1;
  if (action === "fold") { node.expanded = !node.expanded; return node.id; }
  if (action === "child" || action === "sibling") {
    const target = action === "child" ? node : parent;
    if (!target) return null;
    const added = newNode();
    target.children.splice(action === "child" ? target.children.length : index + 1, 0, added);
    target.expanded = true;
    return added.id;
  }
  if (!parent) return null;
  if (action === "delete") {
    for (const item of topLevelSelection(root, ids)) { const p = parentOf(root, item.id); if (p) p.children = p.children.filter(child => child.id !== item.id); }
    return parent.children[Math.max(0, index - 1)]?.id ?? parent.id;
  }
  if (action === "indent") {
    const previous = parent.children[index - 1];
    return previous && moveNodes(root, ids, previous.id, "inside") ? node.id : null;
  }
  const grandparent = parentOf(root, parent.id);
  return grandparent && moveNodes(root, ids, parent.id, "after") ? node.id : null;
}
export function parseDocument(data: unknown): MapDocument | null {
  try {
    const doc = copy(data) as MapDocument;
    if (doc.format !== "siye-mindmap" || doc.version !== 2 || !doc.settings || !doc.views) return null;
    const ids = new Set<string>();
    const validate = (node: MapNode, depth: number): boolean => {
      if (!node || depth > 100 || typeof node.id !== "string" || !node.id || ids.has(node.id) || node.content?.type !== "doc" || typeof node.note !== "string" || typeof node.expanded !== "boolean" || !Array.isArray(node.children)) return false;
      ids.add(node.id); return node.children.every(child => validate(child, depth + 1));
    };
    if (!validate(doc.nodeData, 0) || !["side", "left", "right", "down"].includes(doc.settings.layout) || !["gray", "blue", "green"].includes(doc.settings.palette) || !["all", "first"].includes(doc.settings.noteDisplay)) return null;
    if (!["map", "outline"].includes(doc.views.mode) || !Array.isArray(doc.views.selectedIds) || !doc.views.selectedIds.every(id => typeof id === "string") || !Number.isFinite(doc.views.outlineScroll) || !doc.views.map || ![doc.views.map.scale, doc.views.map.x, doc.views.map.y].every(Number.isFinite)) return null;
    doc.views.map.scale = Math.max(.25, Math.min(3, doc.views.map.scale));
    doc.views.selectedIds = doc.views.selectedIds.filter(id => ids.has(id));
    if (doc.views.focusId && !ids.has(doc.views.focusId)) doc.views.focusId = null;
    // Preserve legacy notes as editable quote blocks in the node's rich text.
    const mergeNotes = (node: MapNode) => {
      if (node.note) {
        node.content.content = [...(node.content.content ?? []), {
          type: "blockquote", content: node.note.split("\n").map(line => plainContent(line).content![0])
        }];
        node.note = "";
      }
      node.children.forEach(mergeNotes);
    };
    mergeNotes(doc.nodeData);
    return doc;
  } catch { return null; }
}

// One history for both views. Input from one field forms a group until focus or structure changes.
type HistoryEntry = { cursor: Cursor | null; selectedIds: string[]; bytes: number } & (
  { kind: "document"; doc: MapDocument } | { kind: "content"; id: string; content: RichDocument }
);
const HISTORY_BYTES = 16 * 1024 * 1024;
export class DocumentStore {
  document: MapDocument;
  cursor: Cursor | null = null;
  private past: HistoryEntry[] = [];
  private future: HistoryEntry[] = [];
  private group: string | null = null;
  private lastChange = 0;
  revision = 0;
  structureRevision = 0;
  private nodes = new Map<string, MapNode>();
  private indexedRevision = -1;
  constructor(document: MapDocument) { this.document = copy(document); }
  node(id: string) {
    if (this.indexedRevision !== this.structureRevision) {
      this.nodes.clear();
      const visit = (node: MapNode) => { this.nodes.set(node.id, node); node.children.forEach(visit); };
      visit(this.document.nodeData); this.indexedRevision = this.structureRevision;
    }
    return this.nodes.get(id) ?? null;
  }
  private push(to: HistoryEntry[], entry: HistoryEntry) {
    to.push(entry);
    let bytes = to.reduce((sum, item) => sum + item.bytes, 0);
    while (to.length > 1 && (to.length > 200 || bytes > HISTORY_BYTES)) bytes -= to.shift()!.bytes;
  }
  private metadata() { return { cursor: this.cursor && { ...this.cursor }, selectedIds: [...this.document.views.selectedIds] }; }
  private changed(group: string | null) {
    this.group = group; this.lastChange = Date.now(); this.future = []; this.revision++;
  }
  boundary() { this.group = null; }
  // Rich text is a node-local history entry, even in a very large document.
  changeContent(id: string, content: RichDocument, group = `content:${id}`) {
    const node = this.node(id);
    if (!node || JSON.stringify(node.content) === JSON.stringify(content)) return false;
    const last = this.past[this.past.length - 1];
    if (group !== this.group || Date.now() - this.lastChange > 1000 || last?.kind !== "content" || last.id !== id) {
      const previous = copy(node.content);
      this.push(this.past, { kind: "content", id, content: previous, ...this.metadata(), bytes: JSON.stringify(previous).length * 2 });
    }
    node.content = copy(content); this.changed(group); return true;
  }
  change(mutate: (document: MapDocument) => void, group: string | null = null) {
    const before = copy(this.document);
    mutate(this.document);
    this.indexedRevision = -1;
    if (JSON.stringify(before) === JSON.stringify(this.document)) return false;
    if (!group || group !== this.group || Date.now() - this.lastChange > 1000 || this.past[this.past.length - 1]?.kind !== "document") {
      this.push(this.past, { kind: "document", doc: before, ...this.metadata(), selectedIds: [...before.views.selectedIds], bytes: JSON.stringify(before).length * 2 });
    }
    this.structureRevision++; this.changed(group);
    return true;
  }
  undo() { return this.restore(this.past, this.future); }
  redo() { return this.restore(this.future, this.past); }
  private restore(from: typeof this.past, to: typeof this.past) {
    const snapshot = from.pop(); if (!snapshot) return false;
    if (snapshot.kind === "content") {
      const node = this.node(snapshot.id);
      if (!node) { from.push(snapshot); return false; }
      const content = copy(node.content);
      this.push(to, { kind: "content", id: node.id, content, ...this.metadata(), bytes: JSON.stringify(content).length * 2 });
      node.content = copy(snapshot.content);
    } else {
      const current = copy(this.document);
      this.push(to, { kind: "document", doc: current, ...this.metadata(), bytes: JSON.stringify(current).length * 2 });
      const views = this.document.views;
      this.document = copy(snapshot.doc); this.document.views = { ...views }; this.structureRevision++;
    }
    // Viewport position belongs to the view, not content undo.
    this.document.views.selectedIds = snapshot.selectedIds.length ? [...snapshot.selectedIds] : snapshot.cursor ? [snapshot.cursor.id] : [];
    this.cursor = snapshot.cursor; this.boundary(); this.revision++; return true;
  }
}
