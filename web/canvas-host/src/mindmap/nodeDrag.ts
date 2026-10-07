import type { Topic } from "mind-elixir";
import { findNode, parentOf, type MapNode, type MapDocument } from "./document";

export type NodeRect = { id: string; left: number; top: number; width: number; height: number };

type Layout = MapDocument["settings"]["layout"];
type Branch = {
  id: string; u: number; v: number; minV: number; maxV: number;
  maxU: number; previous: boolean; children: Branch[];
};

// Normalize every layout to an outward axis (u) and a sibling axis (v).
export function inferParent(root: MapNode, movingId: string, movingRect: NodeRect, candidates: NodeRect[], layout: Layout, scale = 1, previousId: string | null = null): string | null {
  const moving = findNode(root, movingId);
  if (!moving || movingId === root.id || scale <= 0) return null;
  const excluded = new Set<string>();
  const visit = (node: MapNode) => { excluded.add(node.id); node.children.forEach(visit); };
  visit(moving);
  const rects = new Map(candidates.filter(rect => !excluded.has(rect.id)).map(rect => [rect.id, rect]));
  const rootRect = rects.get(root.id);
  if (!rootRect) return null;
  let left = layout === "left";
  if (layout === "side") {
    const offset = (movingRect.left + movingRect.width / 2 - rootRect.left - rootRect.width / 2) / scale;
    const previousRect = previousId ? rects.get(previousId) : null;
    left = Math.abs(offset) < 8 && previousRect && previousId !== root.id
      ? previousRect.left + previousRect.width / 2 < rootRect.left + rootRect.width / 2 : offset < 0;
  }
  const axes = (rect: NodeRect) => layout === "down"
    ? { u: rect.top / scale, end: (rect.top + rect.height) / scale, minV: rect.left / scale, maxV: (rect.left + rect.width) / scale }
    : { u: (left ? -rect.left - rect.width : rect.left) / scale, end: (left ? -rect.left : rect.left + rect.width) / scale,
      minV: rect.top / scale, maxV: (rect.top + rect.height) / scale };
  const position = axes(movingRect), u = position.u, v = (position.minV + position.maxV) / 2;
  const build = (node: MapNode): Branch | null => {
    const rect = rects.get(node.id);
    if (!rect) return null;
    if (layout === "side" && node.id !== root.id && (rect.left + rect.width / 2 < rootRect.left + rootRect.width / 2) !== left) return null;
    const axis = axes(rect);
    const children = node.expanded ? node.children.map(build).filter((child): child is Branch => child !== null) : [];
    return { id: node.id, ...axis, v: (axis.minV + axis.maxV) / 2,
      minV: Math.min(axis.minV, ...children.map(child => child.minV)), maxV: Math.max(axis.maxV, ...children.map(child => child.maxV)),
      maxU: Math.max(axis.end, ...children.map(child => child.maxU)),
      previous: node.id === previousId || children.some(child => child.previous), children };
  };
  const tree = build(root);
  if (!tree) return null;
  const distance = (value: number, min: number, max: number) => Math.max(min - value, 0, value - max);
  // Empty space near a branch remains useful; remote drops cancel the move.
  if (u < tree.u - 40 || u > tree.maxU + 180 || distance(v, tree.minV, tree.maxV) > 120) return null;
  const descend = (branch: Branch): string | null => {
    if (!branch.children.length) return distance(v, branch.minV, branch.maxV) <= 120 && u <= branch.maxU + 180 ? branch.id : null;
    const score = (child: Branch) => distance(v, child.minV, child.maxV) + Math.min(Math.abs(v - child.v) * 0.1, 9) - (child.previous ? 10 : 0);
    const child = branch.children.reduce((best, next) => score(next) < score(best) ? next : best);
    // The alignment band belongs to the child's parent. Hysteresis stabilizes the boundary.
    const alignment = 18 + (previousId ? child.previous ? -6 : 6 : 0);
    if (u <= child.u + alignment) return branch.id;
    if (distance(v, child.minV, child.maxV) > 120) return null;
    return descend(child);
  };
  return descend(tree);
}

export type DropTarget = { parentId: string; targetId: string; placement: "before" | "after" | "inside"; side?: "left" | "right"; changed: boolean };

// Resolve the sibling slot only after the layout has selected a parent.
export function inferSiblingSlot(root: MapNode, movingId: string, parentId: string, movingRect: NodeRect, candidates: NodeRect[], layout: Layout, scale = 1, previous: DropTarget | null = null): DropTarget | null {
  const parent = findNode(root, parentId), moving = findNode(root, movingId);
  if (!parent || !moving || findNode(moving, parentId)) return null;
  const rects = new Map(candidates.map(rect => [rect.id, rect]));
  const rootRect = rects.get(root.id);
  const center = (rect: NodeRect) => layout === "down" ? rect.left + rect.width / 2 : rect.top + rect.height / 2;
  const left = rootRect && movingRect.left + movingRect.width / 2 < rootRect.left + rootRect.width / 2;
  const siblings = parent.expanded ? parent.children.filter(node => node.id !== movingId).flatMap(node => {
    const rect = rects.get(node.id);
    if (!rect || layout === "side" && parentId === root.id && rootRect &&
      (rect.left + rect.width / 2 < rootRect.left + rootRect.width / 2) !== left) return [];
    return [{ id: node.id, rect }];
  }).sort((a, b) => center(a.rect) - center(b.rect)) : [];
  const position = center(movingRect);
  let slot = siblings.findIndex(node => position < center(node.rect));
  if (slot < 0) slot = siblings.length;
  if (previous?.parentId === parentId && previous.placement !== "inside") {
    const anchor = siblings.findIndex(node => node.id === previous.targetId);
    const previousSlot = anchor + (previous.placement === "after" ? 1 : 0);
    if (anchor >= 0 && Math.abs(previousSlot - slot) === 1 &&
      Math.abs(position - center(siblings[Math.min(previousSlot, slot)].rect)) <= 6 * scale) slot = previousSlot;
  }
  const targetId = siblings[slot]?.id ?? siblings[siblings.length - 1]?.id ?? parentId;
  const placement = !siblings.length ? "inside" : slot < siblings.length ? "before" : "after";
  const remaining = parent.children.filter(node => node.id !== movingId);
  const index = placement === "inside" ? remaining.length : remaining.findIndex(node => node.id === targetId) + (placement === "after" ? 1 : 0);
  const side = layout === "side" && parentId === root.id ? left ? "left" : "right" : undefined;
  const sourceRect = rects.get(movingId);
  const crossedSide = side && sourceRect && rootRect &&
    (sourceRect.left + sourceRect.width / 2 < rootRect.left + rootRect.width / 2) !== left;
  const changed = parentOf(root, movingId)?.id !== parentId || parent.children.findIndex(node => node.id === movingId) !== index || !!crossedSide;
  return { parentId, targetId, placement, side, changed };
}

type Options = {
  host: HTMLElement;
  overlayHost: HTMLElement;
  root: () => MapNode;
  topics: () => Map<string, Topic>;
  scale: () => number;
  layout: () => Layout;
  canStart: (id: string) => boolean;
  pan: (dx: number, dy: number) => void;
  press: (id: string) => void;
  start: (id: string) => void;
  move: (id: string, drop: DropTarget) => void;
  end: () => void;
};
type Session = {
  pointerId: number; id: string; x: number; y: number; rect: DOMRect;
  touch: boolean; panning: boolean; timer: number | null; lastX: number; lastY: number;
  active: boolean; moved: boolean; parentId: string | null; drop: DropTarget | null; ghost: HTMLElement | null;
  svg: SVGSVGElement | null; path: SVGPathElement | null; slot: SVGPathElement | null; target: Topic | null;
  source: HTMLElement; opacity: string;
};

export function installNodeDrag(options: Options): () => void {
  const { host, overlayHost } = options;
  let session: Session | null = null, suppressClick = false;
  const clear = () => {
    const drag = session;
    if (!drag) return;
    session = null;
    if (drag.timer !== null) window.clearTimeout(drag.timer);
    drag.ghost?.remove(); drag.svg?.remove();
    drag.target?.classList.remove("siye-drop-parent");
    drag.source.style.opacity = drag.opacity;
    if (host.hasPointerCapture(drag.pointerId)) host.releasePointerCapture(drag.pointerId);
    if (drag.active) options.end();
  };
  const down = (event: PointerEvent) => {
    if (session && event.pointerId !== session.pointerId) { clear(); return; }
    suppressClick = false;
    if (event.button !== 0 || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;
    const element = event.target as HTMLElement;
    if (element.closest('button,input,textarea,a,[contenteditable="true"],.mindmap-node-edit-content')) return;
    const topic = element.closest("me-tpc") as Topic | null;
    if (!topic || !options.canStart(topic.nodeObj.id) || topic.nodeObj.id === options.root().id) return;
    // Own node gestures; leave empty-canvas pan, zoom and editing to MindElixir.
    event.stopImmediatePropagation();
    const source = topic.closest<HTMLElement>("me-wrapper") ?? topic;
    session = { pointerId: event.pointerId, id: topic.nodeObj.id, x: event.clientX, y: event.clientY,
      touch: event.pointerType === "touch", panning: false, timer: null, lastX: event.clientX, lastY: event.clientY,
      rect: topic.getBoundingClientRect(), active: false, moved: false, parentId: null, drop: null, ghost: null, svg: null, path: null, slot: null,
      target: null, source, opacity: source.style.opacity };
    if (session.touch) {
      session.timer = window.setTimeout(() => {
        if (!session || session.panning) return;
        session.timer = null;
        options.press(session.id);
        render(event, true);
      }, 350);
    } else options.press(topic.nodeObj.id);
  };
  const render = (event: PointerEvent, held = false) => {
    const drag = session;
    if (!drag || drag.pointerId !== event.pointerId) return;
    if (!drag.source.isConnected || !options.canStart(drag.id)) { clear(); return; }
    const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
    if (drag.touch && !drag.active && !held) {
      if (!drag.panning && Math.hypot(dx, dy) <= 10) return;
      if (drag.timer !== null) window.clearTimeout(drag.timer);
      drag.timer = null; drag.panning = true; suppressClick = true;
      options.pan(event.clientX - drag.lastX, event.clientY - drag.lastY);
      drag.lastX = event.clientX; drag.lastY = event.clientY;
      event.preventDefault(); event.stopImmediatePropagation();
      return;
    }
    if (!held && !drag.active && Math.hypot(dx, dy) <= 10) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (!drag.active) {
      drag.active = true; suppressClick = true;
      options.start(drag.id);
      host.setPointerCapture(event.pointerId);
      const topic = options.topics().get(drag.id);
      if (!topic) { clear(); return; }
      const ghost = document.createElement("div"); ghost.className = "siye-node-drag-ghost";
      ghost.setAttribute("aria-hidden", "true");
      const clone = topic.cloneNode(true) as HTMLElement;
      clone.removeAttribute("data-nodeid"); clone.classList.remove("siye-editing");
      const scale = options.scale();
      ghost.style.width = `${drag.rect.width / scale}px`;
      ghost.style.transform = `scale(${scale})`;
      ghost.append(clone); overlayHost.append(ghost); drag.ghost = ghost;
      drag.source.style.opacity = "0.3";
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.classList.add("siye-node-drag-line"); svg.setAttribute("aria-hidden", "true");
      const path = document.createElementNS(svg.namespaceURI, "path") as SVGPathElement;
      const slot = document.createElementNS(svg.namespaceURI, "path") as SVGPathElement;
      slot.classList.add("siye-node-drag-slot");
      svg.append(path, slot); overlayHost.append(svg); drag.svg = svg; drag.path = path; drag.slot = slot;
    }
    if (Math.hypot(dx, dy) > 10) drag.moved = true;
    const left = drag.rect.left + dx, top = drag.rect.top + dy;
    drag.ghost!.style.left = `${left}px`; drag.ghost!.style.top = `${top}px`;
    const x = left + drag.rect.width / 2, y = top + drag.rect.height / 2;
    const candidates = [...options.topics()].map(([id, topic]) => ({ id, ...rectValues(topic.getBoundingClientRect()) }));
    drag.parentId = drag.moved ? inferParent(options.root(), drag.id,
      { id: drag.id, left, top, width: drag.rect.width, height: drag.rect.height },
      candidates, options.layout(), options.scale(), drag.parentId) : parentOf(options.root(), drag.id)?.id ?? null;
    drag.drop = drag.moved && drag.parentId ? inferSiblingSlot(options.root(), drag.id, drag.parentId,
      { id: drag.id, left, top, width: drag.rect.width, height: drag.rect.height },
      candidates, options.layout(), options.scale(), drag.drop) : null;
    const sibling = drag.drop && drag.drop.placement !== "inside" ? options.topics().get(drag.drop.targetId) : null;
    if (sibling) {
      const rect = sibling.getBoundingClientRect(), padding = 6 * options.scale();
      const before = drag.drop!.placement === "before";
      const position = options.layout() === "down" ? before ? rect.left - padding : rect.right + padding : before ? rect.top - padding : rect.bottom + padding;
      drag.slot!.setAttribute("d", options.layout() === "down"
        ? `M ${position} ${rect.top} L ${position} ${rect.bottom}`
        : `M ${rect.left} ${position} L ${rect.right} ${position}`);
    } else drag.slot!.removeAttribute("d");
    const target = drag.parentId ? options.topics().get(drag.parentId) ?? null : null;
    if (target !== drag.target) { drag.target?.classList.remove("siye-drop-parent"); target?.classList.add("siye-drop-parent"); drag.target = target; }
    if (target) {
      const rect = target.getBoundingClientRect();
      const down = options.layout() === "down";
      const leftward = options.layout() === "left" || options.layout() === "side" && x < rect.left + rect.width / 2;
      const sx = down ? rect.left + rect.width / 2 : leftward ? rect.left : rect.right;
      const sy = down ? rect.bottom : rect.top + rect.height / 2;
      const tx = down ? x : leftward ? left + drag.rect.width : left;
      const ty = down ? top : y;
      drag.path!.setAttribute("d", down
        ? `M ${sx} ${sy} C ${sx} ${(sy + ty) / 2}, ${tx} ${(sy + ty) / 2}, ${tx} ${ty}`
        : `M ${sx} ${sy} C ${(sx + tx) / 2} ${sy}, ${(sx + tx) / 2} ${ty}, ${tx} ${ty}`);
    } else drag.path!.removeAttribute("d");
  };
  const up = (event: PointerEvent) => {
    const drag = session;
    if (!drag || event.pointerId !== drag.pointerId) return;
    if (!drag.source.isConnected || !options.canStart(drag.id)) { clear(); return; }
    if (drag.touch && !drag.active) {
      if (!drag.panning) options.press(drag.id);
      else { event.preventDefault(); event.stopImmediatePropagation(); }
    }
    if (drag.active) { render(event); event.preventDefault(); event.stopImmediatePropagation(); }
    const drop = drag.drop;
    const commit = drag.active && drag.moved && drop?.changed;
    clear();
    if (commit && drop) options.move(drag.id, drop);
  };
  const cancel = (event: PointerEvent) => { if (event.pointerId === session?.pointerId) clear(); };
  const key = (event: KeyboardEvent) => { if (event.key === "Escape" && session) { event.preventDefault(); event.stopImmediatePropagation(); clear(); } };
  const click = (event: MouseEvent) => { if (suppressClick) { suppressClick = false; event.preventDefault(); event.stopImmediatePropagation(); } };
  const contextMenu = (event: MouseEvent) => { if (session || suppressClick) { event.preventDefault(); event.stopImmediatePropagation(); } };
  host.addEventListener("pointerdown", down, true);
  const additionalPointer = (event: PointerEvent) => { if (session && event.pointerId !== session.pointerId) clear(); };
  window.addEventListener("pointerdown", additionalPointer, true);
  const pointerMove = (event: PointerEvent) => render(event);
  window.addEventListener("pointermove", pointerMove, { capture: true, passive: false });
  window.addEventListener("pointerup", up, true);
  window.addEventListener("pointercancel", cancel, true);
  host.addEventListener("lostpointercapture", cancel, true);
  window.addEventListener("keydown", key, true);
  host.addEventListener("click", click, true);
  host.addEventListener("contextmenu", contextMenu, true);
  window.addEventListener("blur", clear);
  return () => {
    clear(); host.removeEventListener("pointerdown", down, true);
    window.removeEventListener("pointerdown", additionalPointer, true);
    window.removeEventListener("pointermove", pointerMove, true); window.removeEventListener("pointerup", up, true);
    window.removeEventListener("pointercancel", cancel, true); host.removeEventListener("lostpointercapture", cancel, true);
    window.removeEventListener("keydown", key, true); host.removeEventListener("click", click, true);
    host.removeEventListener("contextmenu", contextMenu, true); window.removeEventListener("blur", clear);
  };
}
function rectValues(rect: DOMRect) { return { left: rect.left, top: rect.top, width: rect.width, height: rect.height }; }
