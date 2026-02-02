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
}
