# Node editing regression checks — 2026-10-02

Scope: iOS long-press node actions, unified quote formatting, and continuing text after tables/code in outline and map views.

- TypeScript check and 14 web unit tests pass (quote wrap/unquote, legacy-note migration, block continuation, code exit, shared undo/redo).
- Shared Swift package: 10 tests pass.
- macOS Swift package: 9 tests pass. Corrected the outdated `ExcalidrawMac` import in `FileTreeViewTests` to `XExcalidrawMac`.
- iOS simulator build-for-testing passes. The existing canvas/document opening, toolbar/quote interaction, and onboarding tests passed in the first suite run.
- macOS Xcode build-for-testing passes after adding the existing FileTreeView source to its legacy project. macOS UI tests cannot initialize automation mode (system timeout); no desktop UI pass is claimed.
- Running the iOS Swift package tests on macOS fails to link `_ExcalidrawIOS_main`, because its app entry is iOS-only. The actual iOS simulator build is verified instead.

Interaction checks exposed a continuation button hidden behind the native keyboard accessory. It now appears in an overlay above the reported keyboard edge. Continuation checks require that cell text remains unchanged and new text lands outside the table.

iOS recognizes node long presses natively and sends hit-test coordinates to the editor, avoiding competing system text-selection gestures. Browser touch behavior remains available outside the native host. Testing also found release-click suppression persisting into the next menu tap; resetting it at the start of each touch lets menu commands execute.

Results: `build/ios-node-editing-20261002.xcresult` (initial suite), `build/ios-block-menu-20261002-r9.xcresult` (latest focused interaction run), and `build/macos-node-editing-20261002.xcresult` (automation initialization failure).

The final focused iOS UI test passed (70.261 seconds). In both outline and map views it enters a table cell, continues with paragraph text while preserving the cell, creates a code block and continues after it, opens the long-press menu, adds and edits a child, and deletes the child through its long-press menu. Screenshots are in `docs/screenshots/node-editing-2026-10-02/`.
