import { exportFreeMind, exportOPML, exportXMind, htmlPage } from "./mindmap/interchange";
import { exportHTML } from "./mindmap/htmlExport";
import type { MapDocument } from "./mindmap/document";
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
  DesktopToolbarActionPayload,
  DesktopToolbarStatePayload,
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
  useEffect(() => {
    const color = theme === "dark" ? "#1e1e1e" : "#ffffff";
    document.documentElement.style.backgroundColor = color;
    document.documentElement.style.colorScheme = theme;
    document.body.style.backgroundColor = color;
  }, [theme]);
  const saveTimeout = useRef<number | null>(null);
  const currentLoad = useRef(loadState);
  currentLoad.current = loadState;
  const loadGeneration = useRef(0);
  const revision = useRef(0);
  const savedRevision = useRef(0);
  const saveFlight = useRef<Promise<boolean> | null>(null);
  const saveRequests = useRef(new Map<string, (okay: boolean) => void>());
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

  const flushExcalidraw = useCallback(async function flush(): Promise<boolean> {
    if (saveTimeout.current !== null) { clearTimeout(saveTimeout.current); saveTimeout.current = null; }
    const state = currentLoad.current;
    if (state.readOnly || savedRevision.current === revision.current) return true;
    if (saveFlight.current) { return await saveFlight.current ? flush() : false; }
    const api = excalidrawApi.current;
    if (!api) return false;
    const atRevision = revision.current, generation = loadGeneration.current, requestId = crypto.randomUUID();
    let sceneJson: string;
    try { sceneJson = serializeAsJSON(api.getSceneElements(), api.getAppState(), api.getFiles(), "local"); }
    catch { return false; }
    const task = new Promise<boolean>(resolve => {
      const timeout = window.setTimeout(() => finish(false), 10000);
      const finish = (okay: boolean) => {
        clearTimeout(timeout); saveRequests.current.delete(requestId);
        if (okay && generation === loadGeneration.current) savedRevision.current = atRevision;
        resolve(okay);
      };
      saveRequests.current.set(requestId, finish);
      const payload: SaveScenePayload = { docId: state.docId, sceneJson, requestId };
      sendToNative(sendEnvelope("saveScene", payload));
    });
    saveFlight.current = task;
    const okay = await task;
    saveFlight.current = null;
    if (!okay || generation !== loadGeneration.current) return false;
    if (revision.current !== atRevision) return flush();
    sendToNative(sendEnvelope("didChange", { docId: currentLoad.current.docId, dirty: false }));
    return true;
  }, []);

  const scheduleSave = useCallback((docId: string) => {
    if (savedRevision.current === revision.current) sendToNative(sendEnvelope("didChange", { docId, dirty: true }));
    revision.current++;
    if (saveTimeout.current !== null) clearTimeout(saveTimeout.current);
    saveTimeout.current = window.setTimeout(() => { void flushExcalidraw(); }, SAVE_DEBOUNCE_MS);
  }, [flushExcalidraw]);

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
      const scene = coerceSceneJson(sceneJson ?? {});
      if (scene.files && typeof scene.files === "object") {
        api.addFiles(Object.values(scene.files) as Parameters<ExcalidrawImperativeAPI["addFiles"]>[0]);
      }
      api.updateScene(normalizeScene(scene));
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
    [normalizeScene, coerceSceneJson]
  );

  const lastToolbarState = useRef("");
  const reportToolbarState = useCallback((appState: ReturnType<ExcalidrawImperativeAPI["getAppState"]>) => {
    if (document.documentElement.dataset.nativeDesktop !== "true" || loadState.docId.toLowerCase().endsWith(".mindmap")) return;
    const formatOpen = appState.openMenu === "shape";
    document.documentElement.dataset.nativeFormatOpen = String(formatOpen);
    const payload: DesktopToolbarStatePayload = {
      docId: loadState.docId,
      kind: "drawing",
      readOnly: loadState.readOnly,
      activeTool: appState.activeTool.type,
      locked: appState.activeTool.locked,
      formatOpen,
      libraryOpen: appState.openSidebar?.name === "default" && appState.openSidebar.tab === "library"
    };
    const signature = JSON.stringify(payload);
    if (lastToolbarState.current === signature) return;
    lastToolbarState.current = signature;
    sendToNative(sendEnvelope("desktopToolbarState", payload));
  }, [loadState.docId, loadState.readOnly]);

  useEffect(() => {
    if (isApiReady && excalidrawApi.current) reportToolbarState(excalidrawApi.current.getAppState());
  }, [isApiReady, reportToolbarState]);

  const handleBridgeMessage = useCallback(
    async (message: { type: string; payload: unknown }) => {
      if (message.type === "saveResult") {
        const result = message.payload as { requestId?: string; success?: boolean };
        if (result.requestId) saveRequests.current.get(result.requestId)?.(result.success === true);
        return;
      }
      if (message.type === "desktopToolbarAction") {
        if (loadState.docId.toLowerCase().endsWith(".mindmap")) return;
        const api = excalidrawApi.current;
        if (!api) return;
        const payload = message.payload as DesktopToolbarActionPayload;
        if (payload.action === "library") {
          api.toggleSidebar({ name: "default", tab: "library" });
          reportToolbarState(api.getAppState());
        } else if (!loadState.readOnly) {
          const activeTool = api.getAppState().activeTool;
          if (payload.action === "format") {
            api.updateScene({ appState: { openMenu: api.getAppState().openMenu === "shape" ? null : "shape" } });
          } else if (payload.action === "lock") {
            api.updateScene({ appState: { activeTool: { ...activeTool, locked: !activeTool.locked } } });
          } else if (payload.action === "tool") {
            const tool = (["hand", "selection", "rectangle", "diamond", "ellipse", "arrow", "line", "freedraw", "text", "image", "eraser", "frame", "embeddable", "laser"] as const).find(type => type === payload.value);
            if (tool) api.setActiveTool({ type: tool, locked: activeTool.locked });
          }
          reportToolbarState(api.getAppState());
          document.querySelector<HTMLElement>(".excalidraw")?.focus({ preventScroll: true });
        }
        return;
      }
      if (message.type === "syncScene") {
        const payload = message.payload as import("./types").SyncScenePayload;
        if (payload.docId !== currentLoad.current.docId || payload.docId.toLowerCase().endsWith(".mindmap")) return;
        if (revision.current !== savedRevision.current || saveFlight.current) return;
        const api = excalidrawApi.current;
        if (!api) return;
        const scene = coerceSceneJson(payload.sceneJson);
        const state = api.getAppState();
        scene.appState = { ...((scene.appState as Record<string, unknown>) ?? {}), scrollX: state.scrollX, scrollY: state.scrollY, zoom: state.zoom, selectedElementIds: state.selectedElementIds };
        applyScene(payload.docId, scene);
        return;
      }
      if (message.type === "loadScene") {
        loadGeneration.current++; revision.current = 0; savedRevision.current = 0;
        // Returning to the same drawing must report its toolbar state again.
        lastToolbarState.current = "";
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
        try {
          const map = mindMapApi.current;
          if (map || mindMapDocument.current) {
            const payload = message.payload as RequestExportPayload;
            const doc = mindMapDocument.current?.() as MapDocument | undefined;
            let blob: Blob | null | undefined;
            if (payload.format === "json" || payload.format === "mindmap") blob = new Blob([JSON.stringify(doc ?? map?.getData())], { type: "application/json" });
            else if (payload.format === "html" && doc) {
              const svg = await window.siyeExport?.("svg");
              if (!svg) throw new Error("无法导出思维导图视图");
              blob = new Blob([await exportHTML(doc, loadState.docId, await svg.text())], { type: "text/html" });
            }
            else if (payload.format === "mm" && doc) blob = new Blob([exportFreeMind(doc)], { type: "application/xml" });
            else if (payload.format === "opml" && doc) blob = new Blob([exportOPML(doc)], { type: "application/xml" });
            else if (payload.format === "xmind" && doc) blob = new Blob([exportXMind(doc).buffer as ArrayBuffer], { type: "application/zip" });
            else if (payload.format === "png" || payload.format === "svg") blob = await window.siyeExport?.(payload.format);
            if (!blob) throw new Error("无法导出此格式");
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
                encodeURIComponent(JSON.stringify({ type: "excalidraw", version: 2, elements, appState, files: api.getFiles() }))
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

          if (payload.format === "svg" || payload.format === "html") {
            const svg = await exportToSvg({
              elements,
              appState,
              files: api.getFiles(),
              embedScene: payload.embedScene
            });
            const svgString = new XMLSerializer().serializeToString(svg);
            const data = btoa(unescape(encodeURIComponent(payload.format === "html" ? htmlPage("画布", svgString) : svgString)));
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
              files: api.getFiles(),
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
        } catch (error) {
          sendToNative(sendEnvelope("exportFailed", { error: error instanceof Error ? error.message : "导出失败" }));
        }
      }
    },
    [coerceSceneJson, loadState.docId, loadState.readOnly, reportToolbarState]
  );

  useEffect(() => {
    const releaseBridge = initializeBridge();
    const unsubscribe = addBridgeListener((message) => {
      handleBridgeMessage(message);
    });
    return () => {
      unsubscribe(); releaseBridge();
      for (const finish of saveRequests.current.values()) finish(false);
      saveRequests.current.clear();
    };
  }, [handleBridgeMessage]);

  useEffect(() => {
    if (loadState.docId.toLowerCase().endsWith(".mindmap")) return;
    window.siyeFlush = flushExcalidraw;
    const leave = () => { void flushExcalidraw(); };
    window.addEventListener("pagehide", leave);
    return () => {
      window.removeEventListener("pagehide", leave);
      if (window.siyeFlush === flushExcalidraw) delete window.siyeFlush;
      if (saveTimeout.current !== null) clearTimeout(saveTimeout.current);
    };
  }, [loadState.docId, flushExcalidraw]);

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

  // Load a new scene once; renaming keeps the live drawing and its pending edits.
  useEffect(() => {
    if (!isApiReady || !loadState.docId || loadState.docId.toLowerCase().endsWith(".mindmap")) {
      return;
    }
    applyScene(loadState.docId, loadState.sceneJson);
    // Reset the ready flag to allow sending ready message for new document
    didSendReady.current = false;
  }, [applyScene, isApiReady, sceneLoadKey]);

  useEffect(() => {
    if (saveTimeout.current) {
      window.clearTimeout(saveTimeout.current);
      saveTimeout.current = null;
    }
  }, [sceneLoadKey]);

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
        key={sceneLoadKey}
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
        onChange={(_elements, appState) => {
          reportToolbarState(appState);
          if (
            !loadState.docId ||
            loadState.readOnly ||
            isApplyingScene.current
          ) {
            return;
          }
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
