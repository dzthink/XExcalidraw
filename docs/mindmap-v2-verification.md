# Mind-map v2 verification — 2026-10-01

## Automated checks

- Web TypeScript type check: passed.
- Web editor/document tests: 7 passed (batch movement and cycle prevention, indent/outdent, shared history and cursor, format validation, selected text formatting, table commands, safe links and attachments).
- Shared Swift package: 8 passed, including new-document JSON and attachment storage/resolution.
- macOS Swift package: 9 passed.
- Web production build: passed.
- macOS and iOS app bundle builds: passed.
- `git diff --check`: passed.

## UI checks

Verified using the isolated development fixture and installed macOS app:

- Outline Enter adds a paragraph within the current node on desktop and mobile. Desktop Shift+Enter creates a sibling and focuses its editor (a focused root gets a child). Mobile adds nodes through the node menu, including when using a hardware keyboard. Tab changes hierarchy, and focus breadcrumbs retain the canonical document root.
- Outline node menus close when their trigger is clicked again, when clicking outside, or when pressing Escape.
- The same rich text and plain-text quoted notes appear in both views. Clicking a map note enters the inline editor; Shift+Enter switches fields.
- Toolbar formatting retains the text selection. Table insertion appends when no text range is selected and can be undone from the other view.
- Links can be inserted and edited without duplicating their original text.
- Layout and palette settings survive reload; map transforms restore and fit-to-window includes image nodes.
- Save failure retains input and prevents an unsaved switch; retry succeeds. Read-only editors have `contenteditable=false`.
- A PNG was selected through the native open panel, saved as a local attachment, resized, and reopened successfully.
- Input immediately before quitting and closing the macOS window was present after reopening.
- The 390×844 layout and dark mode were inspected in the browser fixture.

The iOS build environment has no available simulator runtime. iOS native UI, real touch gestures, and physical Chinese IME input have not been verified on a device. Native UI drag operations were not exhaustively tested; movement and hierarchy invariants are covered by the document tests.

## Captures and delivery

[Native outline capture](screenshots/mindmap-v2-outline.png).

[Native mind-map capture](screenshots/mindmap-v2-map.png).

The final app bundle is in `build/native/macos/Siye.app`; the iOS bundle is in `build/native/ios/Siye.app`. The final macOS build was installed at `/Applications/Siye.app`, reopened successfully, and left open on the test document for user testing.

## Native interaction regression fix

- Restore MindElixir's pointer/wheel handlers by disabling its `overflowHidden` option; apply clipping with CSS instead. In 5.15.1 that constructor option skips registration of the native interaction handlers.
- Enable MindElixir's native layout and zoom toolbars. Move the view toggle to the top center; persist native direction changes, including left layout.
- Update the React portal anchor only when it changes. Remove portals before native layout/fold commands replace their parent DOM, and require the portal anchor to match the edited node.
- Cache rendered node HTML, avoid linking on selection-only renders, and avoid React redraws and repeated native dirty messages during wheel/pan events.
- Browser regression: switching edited nodes, typing, native layout changes, and switching views completed without a blank page. A test-only control dispatched 100 Command-wheel events in 3 ms; scale changed and node DOM stayed intact. This is a small fixture event-handler measurement, not a large-document benchmark or physical mouse test.
- Installed macOS regression: node single click, double-click editing, and selecting another node while editing completed without a blank page. Typecheck, 7 Web tests, Web build and macOS build passed. Final app installed and opened at `/Applications/Siye.app`.

[Native controls fix capture](screenshots/mindmap-native-controls-fix.png).

## Excalidraw cloud-file opening regression

File reads on the main thread could stall on iCloud download; a direct read observed a filesystem timeout. The switch handshake also reopened the target synchronously. macOS now flushes the previous editor first, reads in the background, accepts only the latest requested result, and activates/delivers it once. The shared reader does not mutate the active document while waiting. The generic macOS/iOS switch handshake no longer synchronously rereads the target. macOS shows a nonblocking reading indicator and an error on failure.

Shared tests: 9 passed, including background-read completion on the main queue without activating or rewriting the source file. macOS and iOS app builds passed. Native macOS checks opened 2026-work, selected 2026, switched to the mind map and returned to Excalidraw, with the app responsive. The final macOS build was installed and left open on 2026-work. Native iOS UI remains unverified.
