#!/usr/bin/env node
// Item numbers of an acceptance doc whose table rows are new or changed since a commit — the input of a gate
// run fired by a hand-off. Rows of sections titled «Критично…» come first, then the rest in doc order.
//
//   node tools/ai_playtest/changed_items.mjs Docs/ACCEPTANCE_M2.md <base-sha>    → "21,22,1,2" (or empty)

import { execFileSync } from "node:child_process";
import fs from "node:fs";

const [doc, base] = process.argv.slice(2);
const read = (ref) => {
  if (!ref) return fs.existsSync(doc) ? fs.readFileSync(doc, "utf8") : "";
  try { return execFileSync("git", ["show", `${ref}:${doc}`], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }); } catch (_) { return ""; }
};
function rows(text) {
  const out = new Map();
  let section = "";
  for (const line of text.split("\n")) {
    if (/^##\s/.test(line)) section = line.replace(/^##\s+/, "");
    const m = /^\|\s*(\d+)\s*\|/.exec(line);
    if (m) out.set(Number(m[1]), { line: line.trim(), critical: /критично/i.test(section) });
  }
  return out;
}
const now = rows(read(""));
const before = base && !/^0+$/.test(base) ? rows(read(base)) : new Map();
const changed = [...now.entries()].filter(([n, r]) => !before.has(n) || before.get(n).line !== r.line);
changed.sort((a, b) => (b[1].critical - a[1].critical));
process.stdout.write(changed.map(([n]) => n).join(","));
