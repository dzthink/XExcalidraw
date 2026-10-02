# iOS simulator verification — 2026-10-01

## Coverage

The UI suite opens an isolated fixture repository, loads a blank Excalidraw canvas and a version 2 mind map, checks the native/web ready bridge and visible mind-map root, returns to the file list, opens/closes settings, and opens the system folder picker from onboarding. Screenshots are retained as XCTest attachments.

Fixtures are enabled only in Debug builds through `SIYE_UI_TEST_FIXTURE`. Each launch uses a separate temporary directory, preferences suite, and index file.

## Results

- Web: 7 tests passed; TypeScript check and production build passed.
- Shared Swift package: 10 tests passed.
- iPhone 17 Pro, iOS 26.1: 2 UI tests passed, 0 failures.
- iPhone 16 Pro, iOS 18.4: 2 UI tests passed, 0 failures (with the simulator library-path workaround below).

## Fixes

- Replaced obsolete UI assertions for removed `canvas-status` and `canvas-style-status` elements.
- Added an editor accessibility identifier based on the actual bridge ready state.
- Enabled `DEBUG` compilation and `ONLY_ACTIVE_ARCH` in the Xcode project's Debug configuration. The original simulator build compiled the app for x86_64 while its shared package was available for arm64.

- iOS 18.4 initially aborted before app startup because `libswiftWebKit.dylib` could not be found. The test launcher now adds the runtime Cryptex Swift library directory to `DYLD_FALLBACK_LIBRARY_PATH` when the library exists. This follows the [Apple engineering workaround](https://developer.apple.com/forums/thread/785964). It affects only UI test launches; ordinary iOS 18.4 simulator launches still require the same environment setting.

## Reproduction

```sh
xcodebuild build-for-testing \
  -project apps/_legacy_xcode/ExcalidrawIOS.xcodeproj \
  -scheme ExcalidrawIOSUITests \
  -destination 'platform=iOS Simulator,id=01BCCDBF-FAFC-49BD-B5F6-33574C21BC2E' \
  -configuration Debug -derivedDataPath build/DerivedData/ios

xcodebuild test-without-building \
  -project apps/_legacy_xcode/ExcalidrawIOS.xcodeproj \
  -scheme ExcalidrawIOSUITests \
  -destination 'platform=iOS Simulator,id=01BCCDBF-FAFC-49BD-B5F6-33574C21BC2E' \
  -configuration Debug -derivedDataPath build/DerivedData/ios \
  -parallel-testing-enabled NO
```

## Limits

This is startup/navigation and editor-load coverage. Drawing gestures, edited document persistence, exports, iCloud sync, device signing, and real-device behavior are not verified by these UI tests.

`swift test --package-path apps/ios` on the host fails to link `_ExcalidrawIOS_main`: the executable app entry is guarded by `os(iOS)`, while host SwiftPM tests target macOS. The iOS package's existing unit test is a placeholder. Use the Xcode simulator suite for iOS runtime verification; this host test harness issue remains unresolved.

Result bundles: `build/ios-26-ui.xcresult`, `build/ios-18-verified.xcresult`. Exported iOS 26 screenshots: `build/ios-test-screenshots/`.
