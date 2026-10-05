# iOS left-edge back gesture — 2026-10-05

The editor recognizes a one-finger right swipe starting at the left screen edge. Completion requires at least 70 points of horizontal travel, or 24 points with a rightward velocity of at least 500 points/second. Vertical and cancelled gestures do not return.

The gesture uses the same save-before-return action as the toolbar button. Repeated requests while saving are ignored. Failed saves keep the editor open with the existing error message. The web view reserves a transparent 20-point strip at its left edge so canvas touch handling cannot suppress navigation. Normal navigation stack pages retain their system back gesture.

Validation:

- Simulator build-for-testing passed.
- `testEditorLeftEdgeSwipeReturnsAndSaves` passed on iPhone 17 / iOS 26.1 with zero failures. It checks outline return with the keyboard visible, reopens to verify saved text, and checks return from mind map and Excalidraw canvas.
- Result bundle: `build/ios-edge-back-verified-2026-10-05.xcresult`.
- Screenshot: `docs/screenshots/ios-edge-back-2026-10-05.png`.
- iPhone 17 / iOS 26.6.2: `testEditorLeftEdgeSwipeReturnsAndSaves` passed on the physical device, including outline return while the keyboard was open, persistence after reopening, mind map return, and canvas return.
- Device result bundle: `build/iphone-gestures-verified-2026-10-05.xcresult` (two focused tests, zero failures, including double Return). Screenshot: `docs/screenshots/iphone-gestures-2026-10-05/edge-back.png`.
- The signed latest app was installed with `devicectl` and relaunched without the test fixture after verification. Test documents and preferences used isolated temporary locations.
- `git diff --check` passed.
