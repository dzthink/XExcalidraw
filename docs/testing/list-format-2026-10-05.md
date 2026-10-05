# List formatting regression — 2026-10-05

Changes: remove dash lists; add saved task completion; render markers on empty items; move list indent/outdent to the text formatting menu. Existing dash documents render as bullet lists.

Validation:
- `cd web/canvas-host && npm run typecheck && npm test && npm run build`: passed; 27 tests.
- `tests/lists.html` in native macOS WKWebView: passed empty bullet/number/task markers, checkbox completion, Return creating an unfinished task, list/format menu placement, indent/outdent, and serialized HTML round trip.
- Screenshot: `docs/screenshots/list-format-2026-10-05/siye-regression-lists.png`; includes empty rows and an ordered list starting at 3.
- iPhone 17 simulator, iOS 26.1: `testMindMapListStylesAboveKeyboard` passed in outline and map modes (`build/ios-list-format-verified-2026-10-05.xcresult`, task test in that initial bundle used an incorrect caret-placement step).
- `testMindMapTaskListsSaveCompletionAndEmptyItems` passed in outline and map modes after correcting the interaction sequence (`build/ios-task-lists-verified-2026-10-05.xcresult`). It creates an empty child, converts it to a task, toggles completion, types and presses Return, verifies the empty next checkbox is unfinished, and reopens the document to verify saved completion.
- Native testing found that ProseMirror's `splitListItem` applies its item attributes only when splitting at paragraph end. `splitUnfinishedListItem` now resets completion on the new item when splitting inside existing text too, with a dedicated unit regression test.
- Simulator screenshots: `docs/screenshots/ios-list-format-2026-10-05/`.
- The current signed Debug app, including the split fix, was installed successfully on the connected iPhone 17 using `devicectl`. Its bundled web entry matches the web build verified in the simulator.

Reproduce WebKit validation: start Vite on port 18766, compile `scripts/performance/benchmark_webkit.swift`, then run that harness with `http://127.0.0.1:18766/tests/lists.html` and an output JSON path.

Normal device launch was attempted after installation; CoreDevice reported the iPhone was locked. Installation succeeded. Unlock the device and open Siye to use the update.
