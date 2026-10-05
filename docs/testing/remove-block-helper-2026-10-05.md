# Remove block continuation helper — 2026-10-05

Removed the floating “在块后继续输入” button, its React state, portal, touch listener and CSS. Existing Enter handlers, keyboard commands and trailing paragraphs remain intact.

Validation:
- Web typecheck, 27 unit tests and production build passed.
- iPhone 17 / iOS 26.1 simulator task-list test passed in both views, including absence of the removed button, empty item creation and saved task completion (`build/ios-no-block-helper-2026-10-05.xcresult`).
- Outline table-cell input, clicking the trailing paragraph and two-Enter code exit passed in the focused block test's runs; screenshot is retained from `build/ios-block-input-no-helper-2026-10-05.xcresult`.
- Map table continuation could not be verified with the coordinate-based native test: the transformed wide node and keyboard accessory caused taps to miss the empty paragraph. The full legacy block/menu test also failed at its unrelated node-menu step. These failures are retained in the result bundles; neither workflow is reported as passing.
- The focused outline continuation test passed (`build/ios-outline-blocks-no-helper-2026-10-05.xcresult`). The existing full block/menu test remains available separately.

The signed app was installed successfully on the connected iPhone 17. Normal launch was attempted, but CoreDevice reported the phone was locked. Unlock and open Siye. Screenshots are in `docs/screenshots/no-block-helper-2026-10-05/`.
