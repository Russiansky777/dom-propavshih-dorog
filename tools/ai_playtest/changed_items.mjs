#!/usr/bin/env node
// Rows of an acceptance doc to check at a gate (Director 23.10: only what the published build changed —
// no re-runs of passed items unless the build changed them):
//   • rows whose text is new or changed since the last gate (Docs/playtest/gates_state/ACCEPTANCE_<M>.json);
//   • plus the later rows of the same section that did NOT pass at the last gate — a checklist is a walk
//     through the story, so a change early in it reaches the steps after it (the D1 fix changed row 149, the
//     night by the stove is row 153);
//   • rows of «Критично…» sections first, doc order inside.
//
//   node tools/ai_playtest/changed_items.mjs <doc> <base-sha>                           rows changed since a commit
//   node tools/ai_playtest/changed_items.mjs <doc> --state <dir> [--ref <sha>]           rows to check at a gate
//   node tools/ai_playtest/changed_items.mjs <doc> --state <dir> --record <sha> --ref <sha> [--verdicts a/log.json,b/log.json]
//        remember the rows of the doc at <sha> as gated, with the gate's verdicts (log.json of each acceptance run)
//
// --config <playtest_gate_*.json>: its "recheck": {"items": "13-25", "run": 1, "why": "…"} — rows to check once
// more at the next gate although the checklist did not change them (the coordinator asks after a fix in data:
// M3 gate r29 never reached 13–25, D6 fixed in f9f57fe). One-shot: the state remembers the run it was done for.
//
// --ref reads the checklist at that commit (the deployed one), not from the working tree: a checklist change
// that is not deployed yet is not seen, so the gate waits for the next successful deploy.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import { rowIdOf, normId, resolveItems } from "./rows.mjs";

const a = process.argv.slice(2);
const doc = a[0];
const opt = (k) => { const i = a.indexOf(k); return i >= 0 ? a[i + 1] : undefined; };
const statePath = opt("--state");
const cfgPath = opt("--config");
const gateCfg = (() => { try { return cfgPath ? JSON.parse(fs.readFileSync(cfgPath, "utf8")) : {}; } catch (_) { return {}; } })();
const recheck = gateCfg.recheck && gateCfg.recheck.items ? { items: gateCfg.recheck.items, run: String(gateCfg.recheck.run ?? 1) } : null;
const record = opt("--record");
const base = !statePath ? a[1] : undefined;

const read = (ref) => {
  if (!ref) return fs.existsSync(doc) ? fs.readFileSync(doc, "utf8") : "";
  try { return execFileSync("git", ["show", `${ref}:${doc}`], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }); } catch (_) { return ""; }
};
const h = (s) => createHash("sha1").update(s).digest("hex").slice(0, 12);
function rows(text) {
  const out = new Map();
  let section = "", order = 0;
  for (const line of text.split("\n")) {
    if (/^##\s/.test(line)) section = line.replace(/^##\s+/, "");
    const id = rowIdOf(line);    // "7", "6а", "И2" — lettered rows count too (23.10)
    if (id) out.set(id, { hash: h(line.trim()), critical: /критично/i.test(section), section, order: order++ });
  }
  return out;
}
const sortRows = (list) => list.sort((x, y) => (y[1].critical - x[1].critical) || (x[1].order - y[1].order));

const now = rows(read(opt("--ref") || ""));
if (statePath) {
  // One file per checklist (<dir>/ACCEPTANCE_M2.json): parallel gates never touch the same file.
  const file = `${statePath.replace(/\/$/, "")}/${doc.split("/").pop().replace(/\.md$/, "")}.json`;
  const state = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
  if (record) {
    const verdicts = { ...(state.verdicts || {}) };
    // --verdicts a/log.json[,b/log.json …]: one acceptance run per segment of the gate (run_acceptance.sh).
    const vfs = String(opt("--verdicts") || "").split(",").map((f) => f.trim()).filter((f) => f && fs.existsSync(f));
    for (const vf of vfs) {
      const log = JSON.parse(fs.readFileSync(vf, "utf8"));
      const last = {};
      for (const v of log.verdict_history || []) last[normId(v.item)] = v.status;
      // The report's table (the stronger model re-checked the step model) wins over the raw verdicts.
      const rep = vf.replace(/log\.json$/, "report.md");
      if (fs.existsSync(rep)) {
        const md = fs.readFileSync(rep, "utf8");
        const sec = (/## Пункты\n([\s\S]*?)(\n## |$)/.exec(md) || [])[1] || "";
        const ids = [...now.keys()];
        for (const line of sec.split("\n")) {
          const m = /^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|/.exec(line);
          if (!m) continue;
          const st = ["не прошёл", "не дошёл", "не проверяемо", "частично", "прошёл"].find((x) => m[2].toLowerCase().startsWith(x));
          if (!st) continue;
          // One row («6а») or a span the report folded («13–20»: every row inside it, lettered ones too).
          for (const id of /[-–—]/.test(m[1]) ? resolveItems(m[1], ids) : [normId(m[1])]) if (now.has(id)) last[id] = st;
        }
      }
      for (const n of ((log.checklist && log.checklist.items) || []).map(normId)) verdicts[n] = last[n] || "не дошёл";
    }
    fs.mkdirSync(statePath, { recursive: true });
    const recheck_run = recheck ? recheck.run : state.recheck_run;
    fs.writeFileSync(file, JSON.stringify({ doc, sha: record, at: new Date().toISOString(),
      rows: Object.fromEntries([...now.entries()].map(([n, r]) => [n, r.hash])), verdicts, ...(recheck_run ? { recheck_run } : {}) }, null, 1) + "\n");
    process.exit(0);
  }
  const seen = state.rows || {};
  const verdicts = state.verdicts || {};
  const changed = [...now.entries()].filter(([n, r]) => seen[n] !== r.hash);
  const pick = new Map(changed);
  for (const [, r] of changed) {
    for (const [m, q] of now.entries()) if (q.section === r.section && q.order > r.order && verdicts[m] !== "прошёл") pick.set(m, q);
  }
  if (recheck && state.recheck_run !== recheck.run) {
    for (const id of resolveItems(recheck.items, [...now.keys()])) if (now.has(id)) pick.set(id, now.get(id));
  }
  process.stdout.write(sortRows([...pick.entries()]).map(([n]) => n).join(","));
} else {
  const before = base && !/^0+$/.test(base) ? rows(read(base)) : new Map();
  const changed = [...now.entries()].filter(([n, r]) => !before.has(n) || before.get(n).hash !== r.hash);
  process.stdout.write(sortRows(changed).map(([n]) => n).join(","));
}
