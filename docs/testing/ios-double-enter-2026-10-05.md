# iOS double Return — 2026-10-05

In editable outline and map node paragraphs, a single Return inserts a paragraph break. A second Return within 450 ms restores the content and cursor from before that break, creates a sibling, and focuses its editor. The document root uses the existing add-child behavior. Nested lists, quotes, tables, code blocks, selected text, composition, and modified Return retain existing editing behavior. Input, cursor movement, pointer interaction, or blur cancels a pending pair.

The shortcut uses ProseMirror's existing iOS Return handling, including its native DOM-change and delayed key-event paths. It does not intercept or cancel the native keyboard's initial keydown event.

Validation:

- Web type checking and all 25 unit tests passed. New tests cover content/cursor restoration, slow Return, intervening typing, nested blocks, code, and selected text.
- Production web build passed.
- `./scripts/build_native.sh ios-app` compiled the Swift targets and packaged the current web bundle. Asset compilation reported unavailable simulator services/runtimes in the sandbox despite the script returning success.
- iPhone 17 / iOS 26.6.2: `testMindMapQuickDoubleReturnCreatesSibling` passed in both outline and map mode using the native software keyboard. Single Return retained text in the original node; rapid double Return created a child at the root and a sibling from that child. Both node texts, the two-node structure, keyboard visibility, and persistence after reopening were verified.
- Result bundle: `build/iphone-gestures-verified-2026-10-05.xcresult`. Screenshots: `docs/screenshots/iphone-gestures-2026-10-05/outline-double-enter.png` and `map-double-enter.png`.
- The initial device test queried static text only; WebKit exposes non-editing nodes as text fields. Querying their accessible values resolved that test failure without changing the interaction implementation. Chinese composition behavior was not exercised by this test.
