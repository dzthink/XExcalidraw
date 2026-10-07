# Layout-aware drag and sibling sorting — iPhone verification

Date: 2026-10-07. Device: connected physical iPhone 17, iOS 26.6.2.

Built and signed the current Debug iOS app with the existing development team, installed it with `devicectl`, and ran focused XCTest UI tests on the physical device. The installed bundle's web entry and JavaScript asset match the verified production web build.

- `testLayoutDragSiblingOrderAndParentPersistence`: passed, 1 test, 0 failures. Covers right, left, down and two-sided layouts. A real long-press drag changes B1/B2/B3 to B1/B3/B2; reopening preserves that order. A second drag into the B1/C lane attaches B3 to B1. Folding B1 hides the whole moved subtree while other root branches remain visible, including after reopening. The opposite branch in the two-sided layout remains on its original side.
- `testMobileNodeSelectionAndLongPressReparent`: passed, 1 test, 0 failures. Covers selection actions, focus entry/exit, editing and keyboard dismissal, long-press reparenting, descendant preservation and persistence.

The first four-layout run reached successful right-layout sorting and reparenting but failed at an outline assertion that queried rich-editor content as static text. Corrected it to assert the count of visible node-selection controls; the complete four-layout rerun passed. The older gesture test's drop point now passes the downward alignment band, consistent with the new layout inference.

Tests seed temporary documents only when explicit debug launch environment flags are present. After verification, the signed app was reinstalled and launched normally as `com.excalidraw.ios`, without test fixture flags. No full native test suite was run.

Result bundles and logs:

- `/private/tmp/siye-layout-iphone-final-20261007.xcresult`: passing four-layout regression.
- `/private/tmp/siye-layout-iphone-20261007.xcresult`: passing existing mobile regression and initial outline assertion failure.
- `/private/tmp/siye-layout-iphone-build.log`
- `/private/tmp/siye-layout-iphone-final-test.log`
- `/private/tmp/siye-layout-iphone-install-final.log`

Screenshots:

- [Right sibling order](../screenshots/layout-drag-iphone-2026-10-07/right-sibling-order.png)
- [Left sibling order](../screenshots/layout-drag-iphone-2026-10-07/left-sibling-order.png)
- [Down sibling order](../screenshots/layout-drag-iphone-2026-10-07/down-sibling-order.png)
- [Two-sided sibling order](../screenshots/layout-drag-iphone-2026-10-07/side-sibling-order.png)
- [Right layout reparenting](../screenshots/layout-drag-iphone-2026-10-07/right-reparent.png)
- [Two-sided saved subtree](../screenshots/layout-drag-iphone-2026-10-07/side-persistence.png)
