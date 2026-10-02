# Mind map editor v2

New `.mindmap` documents use `format: "siye-mindmap"` and `version: 2`. Legacy documents are rejected without conversion or automatic writes.

Each node stores a stable `id`, ProseMirror `content` JSON, legacy plain-text `note` (merged into a rich-text blockquote on opening), `expanded`, and ordered `children`. Rendering HTML is generated from the schema and is never the persistence source. The schema permits paragraphs, blockquotes, H1–H3, bold, italic, strike, lists, tables, images, inline/block code and safe links. Images contain attachment paths and display width; bytes remain in the repository attachment store.

`settings` stores layout (`side`, `right`, `down`), palette (`gray`, `blue`, `green`), and note display (`all`, `first`). `views` stores mode, selected node IDs, focus node, outline scroll, and the map transform. Focus never replaces the document root.

`DocumentStore` owns content and structure history for both views. Text input groups by node/field, focus changes end a group, and structure/toolbar commands form separate steps. MindElixir handles positioning, connectors and exports. Its internal undo and built-in editor are disabled.

## Native protocol

- Web sends `saveScene` with `docId`, `requestId`, and JSON string `sceneJson` after 500ms idle.
- Native replies `saveResult` with `requestId`, `docId`, `success`, and optional `error`. Web only marks the acknowledged revision saved. A failed or timed-out save keeps the current document and offers retry.
- Native awaits `window.siyeFlush()` before replacing the loaded document, closing the macOS window, or terminating the application. A failed flush cancels the operation. iOS requests the same flush when resigning active under a background task.
- `saveAttachment` must succeed before inserting the relative image reference. Images support PNG/JPEG/GIF/WebP up to 10MB. The existing native resolver validates attachment paths against the mounted repository.
- `openLink` accepts only HTTP, HTTPS and mailto URLs. Native opens these through the system.

## Verification

Run `npm run typecheck` and `npm test` in `web/canvas-host`. The standalone `tests/editor.html` development page uses a local fixture and mocked save acknowledgements, with controls for read-only, theme and save failures. It does not access native documents and is excluded from the production entry point.

Run `swift test --package-path apps/shared`, `swift test --package-path apps/macos`, and the native bundle build scripts. Manual verification should include IME input, selection retention in toolbar panels, notes, content insertion, structural undo across views, drag and multi-selection, attachment success/failure, save retry, and immediate close/reopen after typing.

Quote formatting lives in the text-style menu on iOS and desktop. Typing `> ` at the start of an empty paragraph creates a quote. Quotes are edited inside node content; there is no separate note editor. Legacy notes are appended as quote paragraphs without truncation, and the compatibility `note` field is cleared on the next save.

Rich editors keep a trailing paragraph after tables, code, quotes, lists, and images so text can continue in the same node. Use the block continuation button or Cmd/Ctrl+Enter to move into a paragraph immediately after the selected block. At the end of a code block, a second Enter on an empty line exits to normal text. Appended paragraphs participate in the same shared history change.
