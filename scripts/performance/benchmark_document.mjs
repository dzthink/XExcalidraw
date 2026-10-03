// Run from the repository root: node scripts/performance/benchmark_document.mjs
// Synthetic CPU measurements only; these do not measure WKWebView frame times.
import { createRequire } from "node:module";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";

const require = createRequire(resolve("web/canvas-host/package.json"));
const { build } = require("esbuild");
const folder = await mkdtemp(join(tmpdir(), "siye-perf-"));
const results = [];
const percentile = (values, fraction) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * fraction) - 1];
const measure = (run, count = 60) => {
  for (let i = 0; i < 10; i++) run(i);
  const samples = [];
  for (let i = 0; i < count; i++) {
    const start = performance.now(); run(i); samples.push(performance.now() - start);
  }
  return { p50_ms: +percentile(samples, .5).toFixed(3), p95_ms: +percentile(samples, .95).toFixed(3) };
};
try {
  const outfile = join(folder, "document.mjs");
  await build({ entryPoints: [resolve("web/canvas-host/src/mindmap/document.ts")], outfile, bundle: true, platform: "node", format: "esm" });
  const { DocumentStore, newDocument, newNode, findNode, plainContent } = await import(pathToFileURL(outfile));
  for (const nodes of [100, 500, 1000, 5000]) {
    const document = newDocument();
    const queue = [document.nodeData];
    const text = "这是用于性能审计的合成节点正文，包含常规中文编辑内容。".repeat(4);
    for (let i = 1; i < nodes; i++) {
      const node = newNode(text); queue[Math.floor((i - 1) / 8)].children.push(node); queue.push(node);
    }
    const store = new DocumentStore(document), id = queue.at(-1).id;
    let edits = 0;
    const change = group => store.change(doc => { findNode(doc.nodeData, id).content.content[0].content[0].text = text + ++edits; }, group);
    const grouped = measure(() => change("same-node"));
    const separate = measure(() => { store.boundary(); change(null); });
    const local = measure(() => store.changeContent(id, plainContent(text + ++edits)));
    const save = measure(() => JSON.stringify(store.document));
    const topology = node => [node.id, node.expanded, node.children.map(topology)];
    const shape = measure(() => JSON.stringify(topology(store.document.nodeData)));
    const json = JSON.stringify(store.document);
    results.push({ nodes, utf8_bytes: Buffer.byteLength(json), change_grouped: grouped, change_separate: separate, change_node_local: local, stringify_save: save, topology: shape, full_snapshot_200_utf8_MiB: +(Buffer.byteLength(json) * 200 / 1048576).toFixed(1) });
    // Retain a fixture for the native JSON pipeline benchmark, never a user file.
    await writeFile(join(folder, `document-${nodes}.json`), json);
  }
  const output = { runtime: process.version, arch: process.arch, samples: 60, warmup: 10, fixture_directory: folder, results };
  console.log(JSON.stringify(output, null, 2));
  if (process.env.SIYE_PERF_OUTPUT) await writeFile(process.env.SIYE_PERF_OUTPUT, JSON.stringify(output, null, 2) + "\n");
} finally {
  if (!process.env.SIYE_PERF_KEEP_FIXTURES) await rm(folder, { recursive: true, force: true });
}
