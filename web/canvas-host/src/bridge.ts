import type {
  BridgeEnvelope,
  NativeToWebMessage,
  WebToNativeMessage
} from "./types";

const BRIDGE_VERSION = "1.0" as const;

type NativeBridgeHandler = (message: NativeToWebMessage) => void;

const listeners = new Set<NativeBridgeHandler>();

export function addBridgeListener(handler: NativeBridgeHandler) {
  listeners.add(handler);
  return () => listeners.delete(handler);
}

function postToNative(message: WebToNativeMessage) {
  const payload = JSON.stringify(message);
  const webkit = window.webkit;
  if (webkit?.messageHandlers?.bridge) {
    webkit.messageHandlers.bridge.postMessage(payload);
  } else {
    window.parent?.postMessage(payload, "*");
  }
}

export function sendEnvelope<TPayload>(
  type: string,
  payload: TPayload
): BridgeEnvelope<TPayload> {
  return {
    version: BRIDGE_VERSION,
    type,
    payload
  };
}

export function sendToNative(message: WebToNativeMessage) {
  postToNative(message);
}

function parseMessage(data: unknown): NativeToWebMessage | null {
  if (typeof data === "string") {
    try {
      return JSON.parse(data) as NativeToWebMessage;
    } catch {
      return null;
    }
  }
  if (typeof data === "object" && data !== null) {
    return data as NativeToWebMessage;
  }
  return null;
}

let bridgeUsers = 0;
let releaseBridge: (() => void) | null = null;

/** Shared setup is reference counted so StrictMode and multiple consumers cannot duplicate listeners. */
export function initializeBridge(): () => void {
  if (bridgeUsers++ === 0) {
    const dispatch = (data: unknown) => {
      const message = parseMessage(data);
      if (!message || message.version !== BRIDGE_VERSION) return;
      for (const listener of listeners) listener(message);
    };
    const receive = (event: MessageEvent) => dispatch(event.data);
    window.addEventListener("message", receive);
    const nativeWindow = window as Window & { bridgeDispatch?: (data: string) => void };
    const nativeDispatch = (data: string) => dispatch(data);
    if (window.webkit?.messageHandlers?.bridge) nativeWindow.bridgeDispatch = nativeDispatch;
    const stopCursor = initializeCursorTracking();
    releaseBridge = () => {
      window.removeEventListener("message", receive);
      if (nativeWindow.bridgeDispatch === nativeDispatch) delete nativeWindow.bridgeDispatch;
      stopCursor();
    };
  }
  let released = false;
  return () => {
    if (released) return;
    released = true;
    if (--bridgeUsers === 0) { releaseBridge?.(); releaseBridge = null; }
  };
}

function initializeCursorTracking(): () => void {
  // iOS uses UIKit's responder. Desktop needs updates only when a pointer or tool changes.
  if (!window.webkit?.messageHandlers?.bridge || !window.matchMedia("(hover: hover) and (pointer: fine)").matches) return () => {};
  let frame = 0, lastCursor = "", target: HTMLElement | null = null;
  const update = () => {
    frame = 0;
    if (document.hidden || !target?.isConnected) return;
    const cursor = getComputedStyle(target).cursor;
    if (cursor !== lastCursor) { lastCursor = cursor; postToNative(sendEnvelope("cursorChanged", { cursor })); }
  };
  const schedule = () => { if (!frame && !document.hidden) frame = requestAnimationFrame(update); };
  const targetObserver = new MutationObserver(schedule);
  const move = (event: MouseEvent) => {
    const next = event.target instanceof HTMLElement ? event.target : (event.target as Element | null)?.closest<HTMLElement>(".excalidraw") ?? null;
    if (next !== target) {
      targetObserver.disconnect(); target = next;
      for (let element: HTMLElement | null = target; element; element = element.parentElement) {
        targetObserver.observe(element, { attributes: true, attributeFilter: ["style", "class"] });
        if (element.classList.contains("excalidraw") || element.classList.contains("siye-editor")) break;
      }
    }
    schedule();
  };
  document.addEventListener("mousemove", move, { passive: true });
  document.addEventListener("pointerup", schedule, { passive: true });
  document.addEventListener("keydown", schedule);
  document.addEventListener("visibilitychange", schedule);
  return () => {
    cancelAnimationFrame(frame); targetObserver.disconnect();
    document.removeEventListener("mousemove", move);
    document.removeEventListener("pointerup", schedule);
    document.removeEventListener("keydown", schedule);
    document.removeEventListener("visibilitychange", schedule);
  };
}
