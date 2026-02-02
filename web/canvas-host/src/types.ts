import type { AppState } from "@excalidraw/excalidraw/types";

export type BridgeVersion = "1.0";

export type BridgeEnvelope<TPayload> = {
  version: BridgeVersion;
  type: string;
  payload: TPayload;
};

export type LoadScenePayload = {
  docId: string;
  sceneJson: Record<string, unknown>;
  readOnly: boolean;
};

export type AppStateUpdateKeys =
  | "theme"
  | "viewModeEnabled"
  | "zenModeEnabled"
  | "gridModeEnabled"
  | "gridSize"
  | "gridStep"
  | "showWelcomeScreen";

export type AppStateUpdate = Pick<AppState, AppStateUpdateKeys>;

export type SetAppStatePayload = Partial<AppStateUpdate>;

export type RequestExportPayload = {
  format: "png" | "svg" | "json";
  embedScene: boolean;
};

export type DidChangePayload = {
  docId: string;
  dirty: boolean;
};

export type SaveScenePayload = {
  docId: string;
  sceneJson: Record<string, unknown>;
};

export type RequestAIPayload = {
  docId: string;
  prompt?: string;
};

export type ExportResultPayload = {
  format: "png" | "svg" | "json";
  dataBase64: string;
};

export type NativeToWebMessage =
  | BridgeEnvelope<LoadScenePayload>
  | BridgeEnvelope<SetAppStatePayload>
  | BridgeEnvelope<RequestExportPayload>;

export type WebToNativeMessage =
  | BridgeEnvelope<DidChangePayload>
  | BridgeEnvelope<SaveScenePayload>
  | BridgeEnvelope<RequestAIPayload>
  | BridgeEnvelope<ExportResultPayload>;
