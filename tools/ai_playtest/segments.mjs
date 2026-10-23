#!/usr/bin/env node
// Segments of a gate (request field "segments"): a start point and the checklist rows it serves —
//   "segments": [{"items": "1-12, 26-29", "url": "?start=olkhovka", "note": "…"},
//                {"items": "13-18", "url": "?start=span", "note": "…"}]          (also "start_save")
// The rows to check are split among them (rows in no segment go to the first one), in the segment's own order;
// a segment without rows is not run. One acceptance run per segment: rows deep in a block are checked from the built-in start point next
// to them, not after replaying the whole block — the M3 gate r29 (23.10) spent 190 steps replaying rows 1–12
// and never reached 13–25.
//
//   node tools/ai_playtest/segments.mjs <request.json> <items>   →  lines «<index>\t<items>»; «-\t<items>» without segments

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { docRowIds, resolveItems } from "./rows.mjs";

/** [{index, items[]}] — index null when the request has no segments. */
export function splitSegments(req, items, ids) {
  const want = resolveItems(items, ids);
  const segs = Array.isArray(req.segments) ? req.segments : [];
  if (!segs.length) return want.length ? [{ index: null, items: want }] : [];
  const own = segs.map((s) => resolveItems(s && s.items, ids));
  const out = segs.map((_, i) => ({ index: i, items: [] }));
  for (const id of want) {
    const i = own.findIndex((list) => list.includes(id));
    out[i >= 0 ? i : 0].items.push(id);
  }
  // In the segment's own order: «8-11, 19-24, 12» — the free day's stories before its evening ends it.
  const at = (i, id) => { const k = own[i].indexOf(id); return k >= 0 ? k : 1e9; };
  for (const s of out) s.items.sort((a, b) => at(s.index, a) - at(s.index, b));
  return out.filter((s) => s.items.length);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [reqFile, items] = process.argv.slice(2);
  const req = JSON.parse(fs.readFileSync(reqFile, "utf8"));
  const spec = String(items || req.items || "").trim();
  // "unpassed" (rows not passed at the last gate) is resolved by playtest.mjs itself: one run.
  if (spec === "unpassed") { process.stdout.write("-\tunpassed\n"); process.exit(0); }
  let ids = null;
  try { ids = req.doc ? docRowIds(fs.readFileSync(String(req.doc), "utf8")) : null; } catch (_) { ids = null; }
  for (const s of splitSegments(req, spec, ids)) process.stdout.write(`${s.index === null ? "-" : s.index}\t${s.items.join(",")}\n`);
}
