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
  sceneJson: Record<string, unknown> | string;
  requestId?: string;
};

export type RequestAIPayload = {
  docId: string;
  prompt?: string;
};

export type AIConfigPayload = {
  enabled: boolean;
};

export type WebReadyPayload = {
  ready: boolean;
};

export type ExportResultPayload = {
  format: "png" | "svg" | "json";
  dataBase64: string;
};

export type UpdateDocIdPayload = {
  docId: string;
};

export type SaveAttachmentPayload = {
  requestId: string;
  docId: string;
  mimeType: string;
  dataBase64: string;
};

export type AttachmentSavedPayload = {
  requestId: string;
  relativePath: string;
};

export type AttachmentSaveFailedPayload = {
  requestId: string;
  error: string;
};

export type NativeToWebMessage =
  | BridgeEnvelope<LoadScenePayload>
  | BridgeEnvelope<UpdateDocIdPayload>
  | BridgeEnvelope<SetAppStatePayload>
  | BridgeEnvelope<RequestExportPayload>
  | BridgeEnvelope<AIConfigPayload>
  | BridgeEnvelope<AttachmentSavedPayload>
  | BridgeEnvelope<AttachmentSaveFailedPayload>;

export type WebToNativeMessage =
  | BridgeEnvelope<Record<string, unknown>>
  | BridgeEnvelope<DidChangePayload>
  | BridgeEnvelope<SaveScenePayload>
  | BridgeEnvelope<RequestAIPayload>
  | BridgeEnvelope<WebReadyPayload>
  | BridgeEnvelope<ExportResultPayload>
  | BridgeEnvelope<SaveAttachmentPayload>
  | BridgeEnvelope<{ cursor: string }>;
