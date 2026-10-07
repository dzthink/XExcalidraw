# Node drag and mobile actions — native verification

Date: 2026-10-06

Mobile More dismissal follow-up: added a transparent menu-dismiss layer so tapping outside More closes only the secondary menu, without clearing the selected node or collapsing the primary action bar into the exit-only state. Explicit Cancel Selection retains its existing behavior. Menu state also resets when selection is cleared. Desktop/mobile browser regression, web type check, 33 unit tests, and production build passed. The extended physical iPhone test passed (1 test, 0 failures), checking outside taps on blank canvas and the node while focused, retained Edit/Child/Cancel controls, and continued exit/edit/drag/persistence behavior. Results: `/private/tmp/siye-more-dismiss-ios-20261006.xcresult`.

- [Complete action bar after dismissing More](../screenshots/node-drag-native-2026-10-06/mobile-more-dismiss.png)

Final interaction update: desktop and mobile action bars now replace Enter This Node with Return to Full Map whenever the document is focused. Desktop context-menu entry and exit use the same document state, including the menu's visible options. Removed the separate Return to Parent / Return to Full Map controls from the editor canvas. After deselection, the action bar keeps an exit-only control so focus cannot trap the user. This supersedes the earlier focus-navigation layout below.

Verification: web type check, 33 unit tests, production build, browser regression at desktop and 390 × 844, and both focused native UI tests passed. Desktop testing includes right-click entry followed by toolbar exit and restoration of Enter This Node. iPhone testing checks the single exit action and exit after deselection. Updated both `/Applications/Siye.app` and the physical iPhone, launched normally, and checked the installed desktop app's existing focused document displays the correct action without canvas navigation.

Latest result bundles:

- `/private/tmp/siye-focus-toolbar-macos-20261006.xcresult` — 1 test, 0 failures.
- `/private/tmp/siye-focus-toolbar-ios-20261006.xcresult` — 1 test, 0 failures.

Latest screenshots:

- [Desktop synchronized action bar](../screenshots/node-drag-native-2026-10-06/desktop-focus-toolbar-synced.png)
- [iPhone synchronized action bar](../screenshots/node-drag-native-2026-10-06/iphone-focus-toolbar-synced.png)
- [iPhone exit after deselection](../screenshots/node-drag-native-2026-10-06/iphone-focus-toolbar-deselected.png)
- [Mobile browser regression](../screenshots/node-drag-native-2026-10-06/mobile-focus-toolbar-regression.png)

Follow-up: removed Increase/Decrease Indentation from the mobile selected-node action bar. Repeated the 33 web tests, type check, production build, and the physical iPhone UI test; all passed. The UI test now explicitly asserts that both actions are absent from More. Updated device-test results: `/private/tmp/siye-node-no-indent-20261006.xcresult` (1 test, 0 failures).

Focus-exit follow-up: the original Return to Parent path passed on the physical iPhone, but the mobile More panel lacked an exit. Added Return to Full Map to that panel and persistent navigation, retained Return to Parent for nested focus, and separated navigation from map/view controls with larger touch targets. The extended physical-device test passed (1 test, 0 failures), covering navigation after deselection, nested focus/return, toolbar exit, editing, dragging, and persistence. Web type check, 33 unit tests, build, and desktop/mobile browser regression passed. Installed and normally launched the verified iPhone build. Results: `/private/tmp/siye-focus-final-20261006.xcresult`.

- [iPhone exit in node actions](../screenshots/node-drag-native-2026-10-06/iphone-focus-exit.png)
- [iPhone navigation without selection](../screenshots/node-drag-native-2026-10-06/iphone-focus-navigation.png)
- [Mobile browser regression](../screenshots/node-drag-native-2026-10-06/mobile-focus-regression.png)

## Installation

- macOS: built the SwiftPM desktop app and installed it at `/Applications/Siye.app`. Launched the installed app and confirmed existing documents load and both map/outline views work. Restored the original selected document after validation.
- iOS: built and signed the device app, installed it on the connected iPhone 17, and ran XCTest on the physical device. After testing, reinstalled the same build and launched `com.excalidraw.ios` normally, without fixture environment variables.

## Results

| Check | Result |
| --- | --- |
| Web TypeScript check, 33 unit tests, production build | Passed |
| Browser pointer regression fixture, desktop and 390 × 844 viewport | Passed |
| macOS native `testNodeDragReparentsSubtreeAndPersists` | Passed: 1 test, 0 failures |
| iPhone native `testMobileNodeSelectionAndLongPressReparent` | Passed: 1 test, 0 failures |
| `git diff --check` | Passed |

The desktop test uses a mouse drag to move a node under another parent, checks that its child moves with it, and reopens the document to verify persistence. The installed desktop app also received a launch/document-loading smoke check; the automated UI test uses the legacy Xcode test target built from the same application sources and web bundle.

The physical iPhone test verifies tap selection and the floating node action bar, the More actions, entering editing and dismissing the keyboard, long-press dragging, subtree ownership, and persistence after reopening. Browser regression checks additionally cover dashed parent previews, stationary holds, swipe panning, cancellation, undo, and multitouch interruption.

Native tests use an isolated seeded document through the existing debug UI-test fixture, with `SIYE_UI_TEST_NODE_DRAG=1`. Normal app launches do not seed this fixture. This was focused feature verification; the complete `scripts/test_all.sh` suite was not run.

## Evidence

- [Desktop subtree after moving](../screenshots/node-drag-native-2026-10-06/desktop-subtree.png)
- [iPhone floating node actions](../screenshots/node-drag-native-2026-10-06/iphone-node-actions.png)
- [iPhone subtree after moving](../screenshots/node-drag-native-2026-10-06/iphone-subtree.png)
- [iPhone persisted subtree after reopening](../screenshots/node-drag-native-2026-10-06/iphone-persistence.png)

Local XCTest result bundles:

- `/private/tmp/siye-node-macos-final-20261006.xcresult`
- `/private/tmp/siye-node-iphone-final-20261006.xcresult`

Build/test logs:

- `/private/tmp/siye-node-install-web.log`
- `/private/tmp/siye-node-macos-build.log`
- `/private/tmp/siye-node-macos-test.log`
- `/private/tmp/siye-node-iphone-test.log`
