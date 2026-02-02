import { useCallback, useEffect, useRef, useState } from "react";
import Excalidraw, {
  exportToBlob,
  exportToSvg,
  type ExcalidrawImperativeAPI
} from "@excalidraw/excalidraw";
import {
  addBridgeListener,
  initializeBridge,
  sendEnvelope,
  sendToNative
} from "./bridge";
import type {
  AppStateUpdate,
  LoadScenePayload,
  RequestExportPayload,
  SaveScenePayload,
  SetAppStatePayload
} from "./types";
import "./styles.css";

type LoadState = {
  docId: string;
  sceneJson: Record<string, unknown> | null;
  readOnly: boolean;
};

const SAVE_DEBOUNCE_MS = 3000;

const getAppStateUpdate = (
  payload: SetAppStatePayload
): AppStateUpdate | null => {
  const nextAppState: Partial<AppStateUpdate> = {};

  if (payload.theme !== undefined) {
    nextAppState.theme = payload.theme;
  }
  if (payload.viewModeEnabled !== undefined) {
    nextAppState.viewModeEnabled = payload.viewModeEnabled;
  }
  if (payload.zenModeEnabled !== undefined) {
    nextAppState.zenModeEnabled = payload.zenModeEnabled;
  }
  if (payload.gridModeEnabled !== undefined) {
    nextAppState.gridModeEnabled = payload.gridModeEnabled;
  }
  if (payload.gridSize !== undefined) {
    nextAppState.gridSize = payload.gridSize;
  }
  if (payload.gridStep !== undefined) {
    nextAppState.gridStep = payload.gridStep;
  }
  if (payload.showWelcomeScreen !== undefined) {
    nextAppState.showWelcomeScreen = payload.showWelcomeScreen;
  }

  if (Object.keys(nextAppState).length === 0) {
    return null;
  }

  return nextAppState as AppStateUpdate;
};

export default function App() {
  const excalidrawApi = useRef<ExcalidrawImperativeAPI | null>(null);
  const [loadState, setLoadState] = useState<LoadState>({
    docId: "",
    sceneJson: null,
    readOnly: false
  });
  const saveTimeout = useRef<number | null>(null);

  const scheduleSave = useCallback(
    (docId: string) => {
      if (saveTimeout.current) {
        window.clearTimeout(saveTimeout.current);
      }
      saveTimeout.current = window.setTimeout(() => {
        const api = excalidrawApi.current;
        if (!api) {
          return;
        }
        const payload: SaveScenePayload = {
          docId,
          sceneJson: {
            elements: api.getSceneElements(),
            appState: api.getAppState()
          }
        };
        sendToNative(sendEnvelope("saveScene", payload));
      }, SAVE_DEBOUNCE_MS);
    },
    []
  );

  const handleBridgeMessage = useCallback(
    async (message: { type: string; payload: unknown }) => {
      if (message.type === "loadScene") {
        const payload = message.payload as LoadScenePayload;
        setLoadState({
          docId: payload.docId,
          sceneJson: payload.sceneJson,
          readOnly: payload.readOnly
        });
      }
      if (message.type === "setAppState") {
        const api = excalidrawApi.current;
        if (!api) {
          return;
        }
        const payload = message.payload as SetAppStatePayload;
        const appStateUpdate = getAppStateUpdate(payload);
        if (!appStateUpdate) {
          return;
        }
        api.updateScene({ appState: appStateUpdate });
      }
      if (message.type === "requestExport") {
        const api = excalidrawApi.current;
        if (!api) {
          return;
        }
        const payload = message.payload as RequestExportPayload;
        const elements = api.getSceneElements();
        const appState = api.getAppState();
        if (payload.format === "json") {
          const data = btoa(
            unescape(
              encodeURIComponent(JSON.stringify({ elements, appState }))
            )
          );
          sendToNative(
            sendEnvelope("exportResult", {
              format: payload.format,
              dataBase64: data
            })
          );
          return;
        }

        if (payload.format === "svg") {
          const svg = await exportToSvg({
            elements,
            appState,
            embedScene: payload.embedScene
          });
          const svgString = new XMLSerializer().serializeToString(svg);
          const data = btoa(unescape(encodeURIComponent(svgString)));
          sendToNative(
            sendEnvelope("exportResult", {
              format: payload.format,
              dataBase64: data
            })
          );
          return;
        }

        if (payload.format === "png") {
          const blob = await exportToBlob({
            elements,
            appState,
            embedScene: payload.embedScene,
            mimeType: "image/png"
          });
          const arrayBuffer = await blob.arrayBuffer();
          const bytes = new Uint8Array(arrayBuffer);
          let binary = "";
          bytes.forEach((byte) => {
            binary += String.fromCharCode(byte);
          });
          const data = btoa(binary);
          sendToNative(
            sendEnvelope("exportResult", {
              format: payload.format,
              dataBase64: data
            })
          );
        }
      }
    },
    []
  );

  useEffect(() => {
    initializeBridge();
    return addBridgeListener((message) => {
      handleBridgeMessage(message);
    });
  }, [handleBridgeMessage]);

  return (
    <div className="app-root">
      <Excalidraw
        ref={excalidrawApi}
        initialData={loadState.sceneJson ?? undefined}
        viewModeEnabled={loadState.readOnly}
        UIOptions={{
          canvasActions: {
            loadScene: false,
            saveAsImage: false,
            export: false,
            saveToActiveFile: false
          }
        }}
        onChange={() => {
          if (!loadState.docId || loadState.readOnly) {
            return;
          }
          sendToNative(
            sendEnvelope("didChange", {
              docId: loadState.docId,
              dirty: true
            })
          );
          scheduleSave(loadState.docId);
        }}
      />
    </div>
  );
}
