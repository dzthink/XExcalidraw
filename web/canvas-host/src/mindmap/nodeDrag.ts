import type { Topic } from "mind-elixir";
import { findNode, parentOf, type MapNode } from "./document";

export type NodeRect = { id: string; left: number; top: number; width: number; height: number };

// Use distance to the node's bounds, so wide rich-text nodes remain easy targets.
export function nearestParent(root: MapNode, movingId: string, x: number, y: number, candidates: NodeRect[]): string | null {
  const moving = findNode(root, movingId);
  if (!moving || movingId === root.id) return null;
  const excluded = new Set<string>();
  const visit = (node: MapNode) => { excluded.add(node.id); node.children.forEach(visit); };
  visit(moving);
  let closest: string | null = null, distance = Infinity;
  for (const rect of candidates) {
    if (excluded.has(rect.id)) continue;
    const dx = Math.max(rect.left - x, 0, x - rect.left - rect.width);
    const dy = Math.max(rect.top - y, 0, y - rect.top - rect.height);
    const next = Math.hypot(dx, dy);
    if (next < distance) { closest = rect.id; distance = next; }
  }
  return closest;
}

type Options = {
  host: HTMLElement;
  overlayHost: HTMLElement;
  root: () => MapNode;
  topics: () => Map<string, Topic>;
  scale: () => number;
  canStart: (id: string) => boolean;
  pan: (dx: number, dy: number) => void;
  press: (id: string) => void;
  start: (id: string) => void;
  move: (id: string, parentId: string) => void;
  end: () => void;
};
type Session = {
  pointerId: number; id: string; x: number; y: number; rect: DOMRect;
  touch: boolean; panning: boolean; timer: number | null; lastX: number; lastY: number;
  active: boolean; moved: boolean; parentId: string | null; ghost: HTMLElement | null;
  svg: SVGSVGElement | null; path: SVGPathElement | null; target: Topic | null;
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
      rect: topic.getBoundingClientRect(), active: false, moved: false, parentId: null, ghost: null, svg: null, path: null,
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
      svg.append(path); overlayHost.append(svg); drag.svg = svg; drag.path = path;
    }
    if (Math.hypot(dx, dy) > 10) drag.moved = true;
    const left = drag.rect.left + dx, top = drag.rect.top + dy;
    drag.ghost!.style.left = `${left}px`; drag.ghost!.style.top = `${top}px`;
    const x = left + drag.rect.width / 2, y = top + drag.rect.height / 2;
    const candidates = [...options.topics()].map(([id, topic]) => ({ id, ...rectValues(topic.getBoundingClientRect()) }));
    drag.parentId = drag.moved ? nearestParent(options.root(), drag.id, x, y, candidates) : parentOf(options.root(), drag.id)?.id ?? null;
    const target = drag.parentId ? options.topics().get(drag.parentId) ?? null : null;
    if (target !== drag.target) { drag.target?.classList.remove("siye-drop-parent"); target?.classList.add("siye-drop-parent"); drag.target = target; }
    if (target) {
      const rect = target.getBoundingClientRect();
      const horizontal = Math.abs(x - rect.left - rect.width / 2) >= Math.abs(y - rect.top - rect.height / 2);
      const sx = horizontal ? x < rect.left + rect.width / 2 ? rect.left : rect.right : rect.left + rect.width / 2;
      const sy = horizontal ? rect.top + rect.height / 2 : y < rect.top + rect.height / 2 ? rect.top : rect.bottom;
      const tx = horizontal ? x < sx ? left + drag.rect.width : left : x;
      const ty = horizontal ? y : y < sy ? top + drag.rect.height : top;
      drag.path!.setAttribute("d", horizontal
        ? `M ${sx} ${sy} C ${(sx + tx) / 2} ${sy}, ${(sx + tx) / 2} ${ty}, ${tx} ${ty}`
        : `M ${sx} ${sy} C ${sx} ${(sy + ty) / 2}, ${tx} ${(sy + ty) / 2}, ${tx} ${ty}`);
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
    const parentId = drag.parentId;
    const commit = drag.active && drag.moved && parentId && parentOf(options.root(), drag.id)?.id !== parentId;
    clear();
    if (commit && parentId) options.move(drag.id, parentId);
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
