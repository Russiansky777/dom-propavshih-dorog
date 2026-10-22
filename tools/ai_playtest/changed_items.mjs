#!/usr/bin/env node
// Rows of an acceptance doc to check at a gate: new or changed table rows (rows of «Критично…» sections first).
//
//   node tools/ai_playtest/changed_items.mjs <doc> <base-sha>              rows changed since a commit
//   node tools/ai_playtest/changed_items.mjs <doc> --state <dir>           rows changed since the last gate run
//   node tools/ai_playtest/changed_items.mjs <doc> --state <dir> --record <sha> --ref <sha>   remember the rows
//                                                                           of the doc at <sha> as gated
//
// The state (Docs/playtest/gates_state/<ACCEPTANCE_M>.json) keeps a hash of every row the last gate saw and the
// deployed commit it ran on. A gate runs on the commit that was just deployed (build-and-publish succeeded),
// so a checklist change that is not deployed yet is simply not in the doc read here — the gate waits for the
// next successful deploy.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";

const a = process.argv.slice(2);
const doc = a[0];
const opt = (k) => { const i = a.indexOf(k); return i >= 0 ? a[i + 1] : undefined; };
const statePath = opt("--state");
const record = opt("--record");
const base = !statePath ? a[1] : undefined;

const read = (ref) => {
  if (!ref) return fs.existsSync(doc) ? fs.readFileSync(doc, "utf8") : "";
  try { return execFileSync("git", ["show", `${ref}:${doc}`], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }); } catch (_) { return ""; }
};
const h = (s) => createHash("sha1").update(s).digest("hex").slice(0, 12);
function rows(text) {
  const out = new Map();
  let section = "";
  for (const line of text.split("\n")) {
    if (/^##\s/.test(line)) section = line.replace(/^##\s+/, "");
    const m = /^\|\s*(\d+)\s*\|/.exec(line);
    if (m) out.set(Number(m[1]), { hash: h(line.trim()), critical: /критично/i.test(section) });
  }
  return out;
}

// --ref <sha>: read the checklist at that commit (the deployed one), not from the working tree.
const now = rows(read(opt("--ref") || ""));
if (statePath) {
  // --state <dir>: one file per checklist (<dir>/ACCEPTANCE_M2.json) — parallel gates never touch the same file.
  const file = `${statePath.replace(/\/$/, "")}/${doc.split("/").pop().replace(/\.md$/, "")}.json`;
  const state = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
  if (record) {
    fs.mkdirSync(statePath, { recursive: true });
    fs.writeFileSync(file, JSON.stringify({ doc, sha: record, at: new Date().toISOString(), rows: Object.fromEntries([...now.entries()].map(([n, r]) => [n, r.hash])) }, null, 1) + "\n");
    process.exit(0);
  }
  const seen = state.rows || {};
  const changed = [...now.entries()].filter(([n, r]) => seen[n] !== r.hash);
  changed.sort((x, y) => (y[1].critical - x[1].critical));
  process.stdout.write(changed.map(([n]) => n).join(","));
} else {
  const before = base && !/^0+$/.test(base) ? rows(read(base)) : new Map();
  const changed = [...now.entries()].filter(([n, r]) => !before.has(n) || before.get(n).hash !== r.hash);
  changed.sort((x, y) => (y[1].critical - x[1].critical));
  process.stdout.write(changed.map(([n]) => n).join(","));
}
