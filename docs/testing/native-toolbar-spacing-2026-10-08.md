# macOS drawing toolbar spacing

Updated from main at `dc965f7`.

Drawing controls now have a 36 × 36 pt hit area, 18 pt symbols, and 6 pt spacing. The expanded row keeps its ideal width instead of squeezing buttons. SwiftUI `ViewThatFits` supplies a native Drawing tools menu when space is limited, including when macOS moves the toolbar item into its overflow menu.

Validation:
- Production web build and macOS app build passed.
- macOS package tests: 9 passed.
- Final macOS UI test target compiled successfully. UI test execution could not start because XCTest timed out enabling system automation mode; no UI test pass is claimed.
- Verified the built app through computer use with isolated test documents: expanded tools at approximately 1280 pt window width, a click near the Diamond button's edge, native overflow at approximately 900 pt, readable Drawing tools submenu with all tools, Rectangle selection from that submenu, and switching back to the mind map view picker.
- Updated the existing UI regression to check larger button dimensions and tool access through the system overflow menu.

Screenshots and the overflow accessibility snapshot are in `docs/screenshots/native-toolbar-spacing-2026-10-08/`.
