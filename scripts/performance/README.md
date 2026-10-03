# Synthetic performance audit

Run from the repository root. The scripts use synthetic documents and temporary output; they never open native user documents. These are diagnostic benchmarks, not fixed CI timing assertions. Keep measurements from the same machine and runtime for before/after comparisons.

## Data and native pipeline

```sh
SIYE_PERF_OUTPUT=/private/tmp/siye-document-perf.json SIYE_PERF_KEEP_FIXTURES=1 node scripts/performance/benchmark_document.mjs
swiftc -O -module-cache-path /private/tmp/siye-perf-module-cache apps/shared/Sources/ExcalidrawShared/Models/ExcalidrawFileEntry.swift apps/shared/Sources/ExcalidrawShared/Models/FileTreeNode.swift apps/shared/Sources/ExcalidrawShared/Stores/ExcalidrawFileIndexStore.swift scripts/performance/benchmark_native.swift -o /private/tmp/siye-native-perf
```

Read `fixture_directory` from the JSON output, then pass that exact path as the third argument:

```sh
/private/tmp/siye-native-perf /private/tmp/siye-native-perf-results /absolute/path/from/fixture_directory
```

The Node output compares legacy whole-document `change` with the production node-local `changeContent`, and includes p50/p95 CPU timing and a serialized-size estimate for 200 full history snapshots. Structural commands still use whole-document history; rich text input uses node-local history. The estimate is not measured heap usage. Native index timing includes local atomic disk writes; document JSON timing excludes WK message transport. Native output is also saved to `native-results.json` in the output directory.

## WebKit editor fixture

Build the separate fixture from `web/canvas-host`:

```sh
cd web/canvas-host
node --input-type=module -e 'import {build} from "vite"; await build({build:{outDir:"/private/tmp/siye-perf-web",emptyOutDir:true,rollupOptions:{input:"tests/performance.html"}}})'
```

Back at the repository root, compile the native runner and serve the built fixture in a separate terminal:

```sh
swiftc -O -module-cache-path /private/tmp/siye-perf-module-cache scripts/performance/benchmark_webkit.swift -o /private/tmp/siye-webkit-perf
python3 -m http.server 18765 --bind 127.0.0.1 --directory /private/tmp/siye-perf-web
```

Run the runner with the test window visible and unobstructed:

```sh
/private/tmp/siye-webkit-perf http://127.0.0.1:18765/tests/performance.html /private/tmp/siye-webkit-results.json
```

The runner creates a standalone WKWebView with nonpersistent storage, records results, and exits. Stop the local HTTP server after testing. The fixture records mount-to-two-rAF time, live editor count, synchronous transaction plus React commit p50/p95, rAF interval p95, and separate map lookup/link rebuilding samples. It intercepts a ProseMirror prototype method solely to capture editor instances for synthetic transactions; application hooks are unchanged. Recheck the fixture after upgrading ProseMirror.

The browser timing has limited resolution and does not measure native IME latency, real screenshot presentation times, iPhone performance, file loading, images, or iCloud. Use Release Instruments and Web Inspector on target devices for final acceptance. The runner may require desktop execution permissions for WebKit processes and the local server.

## Interaction regressions and profiling

The same fixture and native runner also support:

```sh
/private/tmp/siye-webkit-perf 'http://127.0.0.1:18765/tests/performance.html?regression=1' /private/tmp/siye-webkit-regression.json
/private/tmp/siye-webkit-perf 'http://127.0.0.1:18765/tests/performance.html?drawing=1' /private/tmp/siye-drawing-regression.json
/private/tmp/siye-webkit-perf 'http://127.0.0.1:18765/tests/performance.html?profile=1' /private/tmp/siye-webkit-profile.json
```

The regression checks cover the single-editor outline, rich content, undo/redo, input during an in-flight save, view switching, read-only mode, four link layouts, node hit testing, empty-canvas box selection and panning. The drawing checks use the actual Excalidraw integration to draw two shapes, rename during a pending save, and confirm the latest scene under the new document ID. Mouse events are delivered only to the runner's NSWindow; the system pointer is not moved. These checks require the native runner. Snapshots are written beside the JSON results.

Profile mode runs only the 1000-node map with 5 warmups and 395 measured transactions. Use Time Profiler on the runner's own WebContent process; never attach a profiler to unrelated browser processes. The fixture's standalone build includes a dynamically loaded application module for drawing checks, which is loaded only in drawing mode.

The TypeScript project normally checks only `src`. When editing fixtures, explicitly include `tests/performance.tsx` in a temporary TypeScript configuration and typecheck it too. No timing thresholds are used as pass/fail assertions.

Final implementation notes and before/after measurements: [2026-10-02 implementation](../../docs/performance/2026-10-02-implementation.md).
