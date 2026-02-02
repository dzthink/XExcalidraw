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

## Save Strategy

- Web: debounce content changes for 2–5 seconds, then send `saveScene`.
- Native: serialize writes to disk (`.excalidraw` only). After write completion, update index and UI state.
