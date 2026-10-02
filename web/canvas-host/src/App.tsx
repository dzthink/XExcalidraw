import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Excalidraw,
  exportToBlob,
  exportToSvg,
  serializeAsJSON
} from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import "./excalidraw.css";
import MindElixir from "mind-elixir";
import MindMapEditor from "./MindMapEditor";
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

const SAVE_DEBOUNCE_MS = 1000;

const getInitialPreferredTheme = (): "light" | "dark" | null => {
  if (window.__XEXCALIDRAW_THEME === "light" || window.__XEXCALIDRAW_THEME === "dark") {
    return window.__XEXCALIDRAW_THEME;
  }
  if (window.matchMedia?.("(prefers-color-scheme: dark)").matches) {
    return "dark";
  }
  return "light";
};

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
  const [sceneLoadKey, setSceneLoadKey] = useState(0);
  const mindMapApi = useRef<MindElixir | null>(null);
  const mindMapDocument = useRef<(() => unknown) | null>(null);
  const preferredThemeRef = useRef<"light" | "dark" | null>(getInitialPreferredTheme());
  const [isApiReady, setIsApiReady] = useState(false);
  const [mapReady, setMapReady] = useState(false);
  const [theme, setTheme] = useState<"light" | "dark">(getInitialPreferredTheme() ?? "light");
  const [loadState, setLoadState] = useState<LoadState>({
    docId: "",
    sceneJson: null,
    readOnly: false
  });
  const [fontsReady, setFontsReady] = useState(false);
  const saveTimeout = useRef<number | null>(null);
  const didSendReady = useRef(false);
  const isApplyingScene = useRef(false);

  const coerceSceneJson = useCallback((sceneJson: unknown) => {
    if (typeof sceneJson === "string") {
      try {
        return JSON.parse(sceneJson) as Record<string, unknown>;
      } catch {
        return {};
      }
    }
    if (sceneJson && typeof sceneJson === "object") {
      return sceneJson as Record<string, unknown>;
    }
    return {};
  }, []);

  const normalizeScene = useCallback((sceneJson: Record<string, unknown> | null) => {
    const scene = coerceSceneJson(sceneJson ?? {});
    const elements = Array.isArray(scene.elements) ? scene.elements : [];
    const appStateSource =
      scene.appState && typeof scene.appState === "object" ? scene.appState : {};
    const appState: Record<string, unknown> = { ...appStateSource };
    if (preferredThemeRef.current) {
      appState.theme = preferredThemeRef.current;
    }
    const files =
      scene.files && typeof scene.files === "object" ? scene.files : {};
    return {
      elements,
      appState,
      files
    } as unknown as Parameters<ExcalidrawImperativeAPI["updateScene"]>[0];
  }, [coerceSceneJson]);

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
        const elements = api.getSceneElements();
        const appState = api.getAppState();
        const files = api.getFiles();
        let sceneJson: string;
        try {
          sceneJson = serializeAsJSON(elements, appState, files, "local");
        } catch {
          return;
        }
        // Only save if the docId still matches the current document
        if (docId !== loadState.docId) {
          return;
        }
        const payload: SaveScenePayload = {
          docId,
          sceneJson
        };
        sendToNative(sendEnvelope("saveScene", payload));
      }, SAVE_DEBOUNCE_MS);
    },
    [loadState.docId]
  );

  const handleExcalidrawAPI = useCallback(
    (api: ExcalidrawImperativeAPI | null) => {
      excalidrawApi.current = api;
      setIsApiReady(Boolean(api));
    },
    []
  );

  const applyScene = useCallback(
    (docId: string, sceneJson: Record<string, unknown> | null) => {
      const api = excalidrawApi.current;
      if (!api) {
        return;
      }
      isApplyingScene.current = true;
      // Clear any pending save before applying new scene
      if (saveTimeout.current) {
        window.clearTimeout(saveTimeout.current);
        saveTimeout.current = null;
      }
      api.updateScene(normalizeScene(sceneJson));
      if (docId) {
        sendToNative(
          sendEnvelope("didChange", {
            docId,
            dirty: false
          })
        );
      }
      window.setTimeout(() => {
        isApplyingScene.current = false;
      }, 150);
    },
    [normalizeScene]
  );

  const handleBridgeMessage = useCallback(
    async (message: { type: string; payload: unknown }) => {
      if (message.type === "loadScene") {
        const payload = message.payload as LoadScenePayload;
        setSceneLoadKey(value => value + 1);
        setLoadState({
          docId: payload.docId,
          sceneJson: coerceSceneJson(payload.sceneJson),
          readOnly: payload.readOnly
        });
        return;
      }
      if (message.type === "updateDocId") {
        // Update docId without reloading scene (used after file rename)
        const payload = message.payload as { docId: string };
        setLoadState(prev => ({
          ...prev,
          docId: payload.docId
        }));
        return;
      }
      if (message.type === "setAppState") {
        const payload = message.payload as SetAppStatePayload;
        if (payload.theme === "light" || payload.theme === "dark") {
          preferredThemeRef.current = payload.theme;
          setTheme(payload.theme);
        }
        const api = excalidrawApi.current;
        if (!api) {
          return;
        }
        const appStateUpdate = getAppStateUpdate(payload);
        if (!appStateUpdate) {
          return;
        }
        api.updateScene({ appState: appStateUpdate });
      }
      if (message.type === "requestExport") {
        const map = mindMapApi.current;
        if (map || mindMapDocument.current) {
          const payload = message.payload as RequestExportPayload;
          const blob = payload.format === "json"
            ? new Blob([JSON.stringify(mindMapDocument.current?.() ?? map?.getData())], { type: "application/json" })
            : await window.siyeExport?.(payload.format === "svg" ? "svg" : "png");
          if (blob) {
            const bytes = new Uint8Array(await blob.arrayBuffer());
            let binary = "";
            bytes.forEach(byte => { binary += String.fromCharCode(byte); });
            sendToNative(sendEnvelope("exportResult", { format: payload.format, dataBase64: btoa(binary) }));
          }
          return;
        }
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
    [coerceSceneJson]
  );

  useEffect(() => {
    initializeBridge();
    const unsubscribe = addBridgeListener((message) => {
      handleBridgeMessage(message);
    });
    return () => {
      unsubscribe();
    };
  }, [handleBridgeMessage]);

  useEffect(() => {
    let didCancel = false;
    const loadFonts = async () => {
      try {
        if (document.fonts) {
          await Promise.all([
            document.fonts.load("16px Excalifont"),
            document.fonts.load("16px Assistant")
          ]);
          await document.fonts.ready;
        }
      } catch {
        // Fall back to system fonts if custom fonts fail to load.
      }
      if (!didCancel) {
        setFontsReady(true);
      }
    };
    loadFonts();
    return () => {
      didCancel = true;
    };
  }, []);

  // Apply scene when docId changes (new document loaded)
  useEffect(() => {
    if (!isApiReady || !loadState.docId || loadState.docId.toLowerCase().endsWith(".mindmap")) {
      return;
    }
    // Always apply scene when docId changes to ensure content is loaded
    applyScene(loadState.docId, loadState.sceneJson);
    // Reset the ready flag to allow sending ready message for new document
    didSendReady.current = false;
  }, [applyScene, isApiReady, loadState.docId]);

  // Separate effect for sceneJson changes (e.g., from draft restore)
  useEffect(() => {
    if (!isApiReady || !loadState.docId || !loadState.sceneJson) {
      return;
    }
    // Only apply if we haven't just loaded this doc (avoid double apply)
    // This is handled by the separate docId effect above
  }, [isApiReady, loadState.docId, loadState.sceneJson]);

  useEffect(() => {
    if (saveTimeout.current) {
      window.clearTimeout(saveTimeout.current);
      saveTimeout.current = null;
    }
  }, [loadState.docId]);

  useEffect(() => {
    if ((!isApiReady && !mapReady) || didSendReady.current) {
      return;
    }
    didSendReady.current = true;
    sendToNative(sendEnvelope("webReady", { ready: true }));
  }, [isApiReady, mapReady]);

  const initialScene = useMemo(() => {
    return normalizeScene(loadState.sceneJson);
  }, [normalizeScene, loadState.sceneJson]);

  return (
    <div className="app-root">
      {loadState.docId.toLowerCase().endsWith(".mindmap") ? (
        <MindMapEditor
          key={sceneLoadKey}
          docId={loadState.docId}
          data={loadState.sceneJson}
          readOnly={loadState.readOnly}
          theme={theme}
          onDocumentReady={getDocument => { mindMapDocument.current = getDocument; }}
          onReady={instance => {
            mindMapApi.current = instance;
            setMapReady(Boolean(instance));
          }}
        />
      ) : <Excalidraw
        key={loadState.docId || "default"}
        excalidrawAPI={handleExcalidrawAPI}
        initialData={initialScene as never}
        viewModeEnabled={loadState.readOnly}
        UIOptions={{
          canvasActions: {
            changeViewBackgroundColor: false,
            loadScene: false,
            saveAsImage: false,
            export: false,
            saveToActiveFile: false,
            toggleTheme: false
          }
        }}
        onChange={() => {
          if (
            !loadState.docId ||
            loadState.readOnly ||
            isApplyingScene.current
          ) {
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
      />}
      {!loadState.docId.toLowerCase().endsWith(".mindmap") && !fontsReady ? (
        <div className="font-loading-overlay" aria-label="Loading fonts">
          <div className="font-loading-card">Loading fonts…</div>
        </div>
      ) : null}
    </div>
  );
}
