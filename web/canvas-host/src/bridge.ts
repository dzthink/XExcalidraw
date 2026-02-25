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

export function initializeBridge() {
  window.addEventListener("message", (event) => {
    const message = parseMessage(event.data);
    if (!message || message.version !== BRIDGE_VERSION) {
      return;
    }
    for (const listener of listeners) {
      listener(message);
    }
  });

  const webkit = window.webkit;
  if (webkit?.messageHandlers?.bridge) {
    (window as Window & { bridgeDispatch?: (data: string) => void })
      .bridgeDispatch = (data) => {
        const message = parseMessage(data);
        if (!message || message.version !== BRIDGE_VERSION) {
          return;
        }
        for (const listener of listeners) {
          listener(message);
        }
      };
  }

  // Monitor cursor changes and notify native layer
  initializeCursorTracking();
}

function initializeCursorTracking() {
  let lastCursor = "";

  // Helper to get the current effective cursor
  const getCurrentCursor = (): string => {
    // Check the element under the mouse first
    const hoveredElement = document.querySelector(".excalidraw canvas:hover") as HTMLElement | null;
    if (hoveredElement) {
      return getComputedStyle(hoveredElement).cursor;
    }
    // Check canvas element
    const canvas = document.querySelector(".excalidraw canvas") as HTMLElement | null;
    if (canvas) {
      const cursor = getComputedStyle(canvas).cursor;
      if (cursor && cursor !== "auto") {
        return cursor;
      }
    }
    // Check excalidraw container
    const excalidraw = document.querySelector(".excalidraw") as HTMLElement | null;
    if (excalidraw) {
      return getComputedStyle(excalidraw).cursor;
    }
    // Default to body cursor
    return getComputedStyle(document.body).cursor;
  };

  // Check cursor on mouse move
  document.addEventListener("mousemove", () => {
    const cursor = getCurrentCursor();
    if (cursor !== lastCursor) {
      lastCursor = cursor;
      postToNative(
        sendEnvelope("cursorChanged", { cursor })
      );
    }
  }, { passive: true });

  // Also check periodically to catch cursor changes from interactions
  setInterval(() => {
    const cursor = getCurrentCursor();
    if (cursor !== lastCursor) {
      lastCursor = cursor;
      postToNative(
        sendEnvelope("cursorChanged", { cursor })
      );
    }
  }, 50);
}
