# XExcalidraw

This repository contains the initial project scaffold for the Excalidraw Native App (macOS/iOS) and the embedded web canvas host.

## Structure

```
apps/
  ios/            # SwiftUI iOS app (to be implemented)
  macos/          # SwiftUI macOS app (to be implemented)
  shared/         # Shared Swift package (models + bridge types)
web/
  canvas-host/    # React + Excalidraw host app
scripts/
  build_web.sh    # Builds the web host (dist/ output)
docs/
  bridge_protocol.md
  file_format.md
  excalidraw_native_spec_v1.md
```

## Web host development

```bash
cd web/canvas-host
npm install
npm run dev
```

## Build web host for native bundle

```bash
./scripts/build_web.sh
```

## Native app integration notes

- The native apps load `web/canvas-host/dist/index.html` when bundled with the app.
- If the bundle does not contain the web build, the apps fall back to `http://localhost:5173` for development.
