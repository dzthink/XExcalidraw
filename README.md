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

- Add a Run Script build phase in the iOS/macOS targets that invokes `./scripts/build_web.sh` so the latest web build is copied into the app bundle resources.
- The build script copies the `dist/` contents into the bundle resources root, so `Bundle.main.url(forResource: "index", withExtension: "html")` resolves on both platforms.
- If the bundle does not contain the web build, the apps fall back to `http://localhost:5173` for development.
