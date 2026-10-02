# Final iOS UI adjustments — 2026-10-02

- The repository name is no longer used as the file browser's navigation title. This removes the visible XExcalidraw heading for that mounted folder and uses a compact navigation bar.
- Double-clicking a mind-map topic starts editing at ProseMirror's valid end selection, even when a previous cursor position is remembered. Other cursor restoration paths remain available.

Validation:

- TypeScript check, production build, and 8 web tests passed.
- All 3 simulator UI tests passed: `build/ios-final-small-fixes.xcresult`.
- iPhone toolbar/UI test passed in outline and map modes: `build/iphone-final-small-fixes.xcresult`.
- The UI test verifies the repository name is absent from the navigation heading. Immediately after double-clicking the map topic, typing a period produces `中心主题.`; undo and redo also preserve the expected content.
- The final app was installed and launched on the connected iPhone without test fixture environment variables.
