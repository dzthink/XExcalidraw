import { build } from "esbuild";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
const folder = await mkdtemp(join(tmpdir(), "siye-editor-tests-"));
try {
  const outfile = join(folder, "test.mjs");
  await build({ entryPoints: ["tests/document.test.ts"], outfile, bundle: true, platform: "node", format: "esm" });
  process.exitCode = spawnSync(process.execPath, ["--test", outfile], { stdio: "inherit" }).status ?? 1;
} finally { await rm(folder, { recursive: true, force: true }); }
