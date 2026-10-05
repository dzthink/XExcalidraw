# Editing long press and outline keyboard reveal — 2026-10-05

Node long press is governed by view mode and editing state. Outline never starts a node-menu long press; its left-hand menu buttons remain available. In map mode, the editing node ID is excluded even when the gesture lands on the node border, and non-editing nodes retain their menu. State transitions cancel pending timers, and timer callbacks recheck current state.

Web sends `nodeInteractionState` to iOS. The native recognizer is enabled only in editable map mode with no active editing node, regardless of software keyboard visibility. While a map node is editing, web touch handling can still open a different non-editing node's menu. Editable DOM checks remain secondary protections for form controls, rather than the rule deciding node interaction.

Outline keyboard reveal uses the focused ProseMirror selection coordinates and scrolls only the outline container. It follows the reported native accessory top or visual viewport bottom, reserves space for the visible web toolbar, and runs after layout. Adding an entry while the keyboard is already visible also triggers this path through focus tracking.

Validation:

- `npm run typecheck`, `npm test` (22 tests), and `npm run build` passed.
- iOS simulator application build passed.
- Chromium at 390 × 844: synthetic touch long press and native long-press events in both views kept editor focus, opened no node menu, and did not prevent the text context-menu default action. A non-editable map node still opened its menu and entered editing.
- A long outline with the add button near the bottom scrolled the new editor above a simulated native keyboard/accessory top at 440 CSS pixels. The editor bottom was 426.5 pixels. This checks layout and event behavior; it does not emulate a system text-selection menu or real input method.
- Screenshot: `docs/screenshots/outline-add-keyboard-2026-10-05.png`. The shaded keyboard region is an explicit test overlay.
- The existing iOS toolbar UI test now long presses editable text in both views and verifies that the node menu does not open and the keyboard remains attached.
- Targeted simulator UI run: `testMindMapToolbarAboveKeyboard` failed before opening the editor because the fixture's `Test Mind Map` was absent (line 198). The new native long-press assertions were not reached. Result bundle: `build/input-fixes-2026-10-05.xcresult`; native gesture behavior still needs a successful fixture/device run.

Follow-up state checks: outline non-editing nodes ignore web and native long press; the map editing node border also ignores both paths. The state-policy unit test covers outline, map, editing/non-editing nodes, missing node IDs, and read-only mode.

## iPhone 17 validation follow-up

The device is wired, paired, and running iOS 26.6.2. The latest signed app was installed with `devicectl`. The targeted test opens All Documents before choosing the fixture, resolving the earlier failure to locate the fixture on the browser home page.

The first device run confirmed outline system text selection and ten successive added entries above the native accessory. Its map-menu lookup incorrectly queried Buttons instead of MenuItems; the recorded accessibility hierarchy confirmed that the node menu was present. That query was corrected.

The next run confirmed the non-editing map node menu and double-tap entry into editing, but the system text-action assertion failed. The map library sets prefixed WebKit text selection to `none`; the editing node and rich-text descendants now explicitly restore `-webkit-user-select: text` and native touch callouts. Editor pointer/touch events stop propagation into the map drag/tap handlers while leaving native default behavior intact. This complements the view/editing-state menu policy.

Web type checking, all 22 unit tests, and the production build passed after that correction. A final device test is queued and waiting for the phone to be unlocked again; its result must be checked before claiming full native text-selection verification. Intermediate result bundles: `build/iphone-input-states-2026-10-05.xcresult`, `build/iphone-input-states-verified-2026-10-05.xcresult`. Pending final bundle: `build/iphone-input-selection-final-2026-10-05.xcresult`. Captured outline screenshots are in `docs/screenshots/input-interactions-2026-10-05/`.

The final combined run again passed outline selection and all ten outline additions, but map system text actions were still absent after the first WebKit CSS correction. The editing state now additionally restores `touch-action: auto` and text selection on the map-container/map-canvas ancestors; non-editing node bodies retain disabled text selection. A separate `testMindMapEditingTextSelection` invokes the same map checks without repeating the outline loop. Its device run (`build/iphone-map-selection-2026-10-05.xcresult`) is waiting for another unlock; the new ancestor correction is not yet verified on device. Type checking and all 22 web tests pass.
