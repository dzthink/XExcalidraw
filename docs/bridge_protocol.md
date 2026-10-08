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

### syncScene (macOS)

After a successful save, native sends the committed scene to other windows showing the same file. Payload: `{ docId: string, sceneJson: object | string }`. Receivers update content without saving their old copy first or changing their local viewport. A receiver with unsaved edits or an in-flight save ignores the update; concurrent edits are not merged. Mind maps clear stale undo history when accepting a peer scene.

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

Supported formats: `html`, `png`, `svg`, `json`, `mindmap`, `xmind`, `mm`, `opml`. Native flushes pending edits before requesting export. See [import/export details](import_export.md).
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

The macOS bootstrap sets `document.documentElement.dataset.nativeDesktop = "true"`. Only this host replaces the central web drawing toolbar and view tabs with native title-bar controls. The additional drawing tools remain in the title-bar tools menu; format controls and the Library button keep Excalidraw’s original layout and behavior inside the editor.

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

### exportFailed

Web reports `{ "error": "..." }` when export fails, including missing attachment data. Native displays the error instead of sharing an incomplete file.

### saveAttachment / attachmentSaved / attachmentSaveFailed

For a pasted mind-map image, Web sends `saveAttachment` with `requestId`, the active `.mindmap` `docId`, image `mimeType`, and transient `dataBase64`. Native writes the image to the mounted repository's `attachments/` directory and replies with `attachmentSaved` containing `requestId` and a path relative to the `.mindmap` file. On failure, Native replies with `attachmentSaveFailed` and an error. The saved v2 mind-map scene contains only the relative attachment path in its ProseMirror image node, never the image bytes.

## Save Strategy

- Web: debounce content changes for 2–5 seconds, then send `saveScene`.
- Native: serialize writes to disk (`.excalidraw` only). After write completion, update index and UI state.

### Mind-map v2 save acknowledgement

`saveScene` requests may include `requestId`. Native replies with `saveResult` (`requestId`, `docId`, `success`, optional `error`). The editor awaits acknowledgement before treating a revision as saved. Native awaits the asynchronous `window.siyeFlush()` before switching documents, closing a macOS window or terminating; iOS requests a flush on resigning active. `openLink` carries a `url` restricted to HTTP, HTTPS or mailto. See [mindmap-v2.md](mindmap-v2.md) for the document format.

### iOS mind-map keyboard accessory

For iOS mind-map input, `CanvasWebView.inputAccessoryView` supplies the native capsule toolbar. UIKit owns its position across input methods; no fixed keyboard height is used. A document-start script sets `window.siyeNativeKeyboardAccessory`. Accessory visibility and its actual top edge (converted to CSS coordinates after the WebView safe-area inset) are updated through `siye-native-keyboard`. The page uses these coordinates only to position contextual panels and keep the editing node visible.

`siye-node-toolbar-action` carries a toolbar action label to the current React handlers. iOS suppresses the web formatting strip, including during keyboard transitions. The selection action bar remains visible when no node is being edited. The native image button presents a document picker and emits `siye-node-toolbar-image` with transient `base64`, `name`, and `mime`; the normal `saveAttachment` acknowledgement flow persists the image. Desktop and ordinary browser hosts retain the web toolbar.

### Mobile node interaction

In map view, tapping a non-editing node shows a web floating node-action bar styled like the native keyboard accessory. Editing switches to the native formatting accessory; dismissing the keyboard returns to node selection actions. Long press (350 ms) starts node movement and never opens a context menu. Pointer handling owns this gesture; iOS no longer installs a competing node-menu recognizer. Outline retains its explicit menu buttons and active text editors retain text-selection gestures.
