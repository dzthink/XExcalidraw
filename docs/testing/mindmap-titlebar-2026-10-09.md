# macOS mind-map title-bar controls

Mind maps use the same 36 pt native title-bar controls and 18 pt symbols as drawings. One view-toggle icon appears first, followed by text style, table, list, image, code, link, undo, redo, and node operations. Secondary panels open downward below the title bar. Repeated clicks, Escape, outside clicks, and switching views close the panels. Mobile layouts retain their existing toolbar behavior.

Validation:
- Web TypeScript check, 38 web tests, and production build passed.
- macOS application build and 9 macOS package tests passed.
- Updated macOS UI regression target compiled successfully.
- Computer-use verification in Desktop-Outline-QA confirmed the native title-bar row, downward text-style and table panels, Escape and repeated-click dismissal, two-way icon view switching, and native image file picker opening/cancellation.
- The focused automated toolbar regression failed before reaching mind-map assertions: its initial window resize left the window at 1074 pt, with drawing tools in native toolbar overflow, so the expected direct Rectangle button was unavailable. This run is not counted as a UI test pass. Failure artifacts are in the corresponding Xcode result bundle under build/DerivedData/macos/Logs/Test.
