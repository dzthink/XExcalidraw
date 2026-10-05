# Bridge Protocol (v1.0)

All Web ↔ Native interactions must flow through the versioned Bridge envelope. Excalidraw remains a black-box canvas engine; the Native host owns files, directories, iCloud, and AI.

## Envelope

```ts
interface BridgeEnvelope {
  version: "1.0"
  type: string
  payload: any
}
```

## Native → Web

### loadScene
```json
{
  "version": "1.0",
  "type": "loadScene",
  "payload": {
    "docId": "uuid",
    "sceneJson": { "elements": [], "appState": {} },
    "readOnly": false
  }
}
```

### setAppState
```json
{
  "version": "1.0",
  "type": "setAppState",
  "payload": {
    "theme": "dark"
  }
}
```

### requestExport
```json
{
  "version": "1.0",
  "type": "requestExport",
  "payload": {
    "format": "png",
    "embedScene": true
  }
}
```

## Web → Native

### desktopToolbarState (macOS)

The web editor reports the current document and toolbar selection. The native host ignores reports for another `docId`. Drawing reports are sent only when the tool, lock, document, or read-only state changes.

```ts
{
  docId: string;
  kind: "drawing" | "mindmap";
  readOnly: boolean;
  activeTool?: string;
  locked?: boolean;
  viewMode?: "outline" | "map";
}
```

The macOS bootstrap sets `document.documentElement.dataset.nativeDesktop = "true"`. Only this host replaces the web drawing toolbar and view tabs with native title-bar controls.

### desktopToolbarAction (Native → Web, macOS)

```ts
{
  action: "tool" | "lock" | "library" | "view";
  value?: string;
}
```

`tool` selects a supported Excalidraw tool; `lock` toggles tool locking; `library` toggles the default sidebar's library tab. `view` accepts `outline` or `map` and flushes pending mind-map edits before switching. Drawing mutations are ignored in read-only documents. Drawing commands return keyboard focus to the canvas so existing shortcuts remain usable.

### didChange
```json
{
  "version": "1.0",
  "type": "didChange",
  "payload": {
    "docId": "uuid",
    "dirty": true
  }
}
```

### saveScene
```json
{
  "version": "1.0",
  "type": "saveScene",
  "payload": {
    "docId": "uuid",
    "sceneJson": { "elements": [], "appState": {} }
  }
}
```

### exportResult
```json
{
  "version": "1.0",
  "type": "exportResult",
  "payload": {
    "format": "png",
    "dataBase64": "..."
  }
}
```

### saveAttachment / attachmentSaved / attachmentSaveFailed

For a pasted mind-map image, Web sends `saveAttachment` with `requestId`, the active `.mindmap` `docId`, image `mimeType`, and transient `dataBase64`. Native writes the image to the mounted repository's `attachments/` directory and replies with `attachmentSaved` containing `requestId` and a path relative to the `.mindmap` file. On failure, Native replies with `attachmentSaveFailed` and an error. The saved v2 mind-map scene contains only the relative attachment path in its ProseMirror image node, never the image bytes.

## Save Strategy

- Web: debounce content changes for 2–5 seconds, then send `saveScene`.
- Native: serialize writes to disk (`.excalidraw` only). After write completion, update index and UI state.

### Mind-map v2 save acknowledgement

`saveScene` requests may include `requestId`. Native replies with `saveResult` (`requestId`, `docId`, `success`, optional `error`). The editor awaits acknowledgement before treating a revision as saved. Native awaits the asynchronous `window.siyeFlush()` before switching documents, closing a macOS window or terminating; iOS requests a flush on resigning active. `openLink` carries a `url` restricted to HTTP, HTTPS or mailto. See [mindmap-v2.md](mindmap-v2.md) for the document format.

### iOS mind-map keyboard accessory

For iOS mind-map input, `CanvasWebView.inputAccessoryView` supplies the native capsule toolbar. UIKit owns its position across input methods; no fixed keyboard height is used. A document-start script sets `window.siyeNativeKeyboardAccessory`. Accessory visibility and its actual top edge (converted to CSS coordinates after the WebView safe-area inset) are updated through `siye-native-keyboard`. The page uses these coordinates only to position contextual panels and keep the editing node visible.

`siye-node-toolbar-action` carries a toolbar action label to the current React handlers. iOS always suppresses the old web action strip, including during keyboard transitions. The native image button presents a document picker and emits `siye-node-toolbar-image` with transient `base64`, `name`, and `mime`; the normal `saveAttachment` acknowledgement flow persists the image. Desktop and ordinary browser hosts retain the web toolbar.
