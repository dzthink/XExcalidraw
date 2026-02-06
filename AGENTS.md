# Repository Guidelines

## Project Structure & Module Organization
- `apps/ios`: SwiftUI iOS app package (`Sources/ExcalidrawIOS`, `Tests/ExcalidrawIOSTests`).
- `apps/macos`: SwiftUI macOS app package (`Sources/ExcalidrawMac`, `Tests/ExcalidrawMacTests`).
- `apps/shared`: Shared Swift package for bridge models, indexing, and document logic.
- `web/canvas-host`: React + TypeScript web canvas host embedded in native apps.
- `scripts`: Build/test entrypoints (`build_web.sh`, `build_native.sh`, `test_all.sh`).
- `docs`: Protocol and file format references.
- `apps/_legacy_xcode`: Xcode projects used for current UI test targets.

## Build, Test, and Development Commands
- `cd web/canvas-host && npm install && npm run dev`: Start local web host (Vite).
- `cd web/canvas-host && npm run build`: Produce `web/canvas-host/dist`.
- `./scripts/build_web.sh`: Build web host and copy bundle into native resources when paths are available.
- `./scripts/build_native.sh all`: Build iOS + macOS SwiftPM targets.
- `./scripts/build_native.sh app`: Build runnable app bundles into `build/native`.
- `./scripts/test_all.sh`: Run Swift package tests and legacy Xcode UI tests (macOS + iOS simulator).

## Coding Style & Naming Conventions
- Swift: follow existing style (4-space indentation, `UpperCamelCase` types, `lowerCamelCase` members, one primary type per file).
- TypeScript/React: use strict typings, functional components, and `camelCase` variables; keep bridge payload types in `src/types.ts`.
- File naming: Swift types match filenames (for example `DocumentManager.swift`); React components use `PascalCase` filenames (`App.tsx`).
- Keep comments concise and English-first for shared maintainability.

## Testing Guidelines
- Swift tests use XCTest under each package’s `Tests/` directory.
- Name tests by behavior, e.g. `testOpenUpdatesLastOpenedAt`.
- Run focused tests with `swift test --package-path apps/shared` (or `apps/ios`, `apps/macos`).
- Run full verification before merging via `./scripts/test_all.sh`.

## Commit & Pull Request Guidelines
- Prefer short, imperative commit subjects (`Add ...`, `Fix ...`, `Queue ...`) and keep them scoped to one change.
- Reference issues in PR descriptions and summarize user-visible impact.
- PRs should include:
  - what changed and why,
  - validation steps/commands run,
  - screenshots or recordings for UI updates (iOS, macOS, or web canvas).
