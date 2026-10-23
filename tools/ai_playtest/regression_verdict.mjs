#!/usr/bin/env node
// Verdict of a change-driven full-game regression (ai-regression.yml): reads the segment runs of one workflow run
// (Docs/playtest/<date>_persona_regression_<segment>_r<run>/log.json, usage.json, report.md), writes
//   Docs/playtest/regression_<date>.md — one-line verdict, a table per segment, the confirmed defects of each report;
//   Docs/playtest/regression_state.json — the deploy this regression checked (the next scheduled run skips the API
//   until a newer successful deploy changes game/ or data/);
//   build/ai_playtest/regression_summary.txt — the line for the commit message.
//
//   node tools/ai_playtest/regression_verdict.mjs --run <run number> --sha <deployed sha> [--request Docs/playtest/requests/regression.json]
//   node tools/ai_playtest/regression_verdict.mjs --check --sha <deployed sha>   (prints "run" or "skip: <why>"; no files)

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const PT = path.join(ROOT, "Docs", "playtest");
const STATE = path.join(PT, "regression_state.json");
const args = () => { const a = process.argv.slice(2), o = {}; for (let i = 0; i < a.length; i++) if (a[i].startsWith("--")) { const v = a[i + 1]; if (v === undefined || v.startsWith("--")) o[a[i].slice(2)] = true; else { o[a[i].slice(2)] = v; i++; } } return o; };
const A = args();
const reqRel = String(A.request || "Docs/playtest/requests/regression.json");
const req = JSON.parse(fs.readFileSync(path.join(ROOT, reqRel), "utf8"));
const state = (() => { try { return JSON.parse(fs.readFileSync(STATE, "utf8")); } catch (_) { return {}; } })();
const sha = String(A.sha || "");

if (A.check) {
  // Change-driven: run only for a successful deploy newer than the last regression that changed the game itself.
  const segs = req.segments || [];
  const sum = segs.reduce((a, s) => a + Number(s.max_usd || 0), 0);
  if (sum > Number(req.max_usd_total || 8) + 0.01) { console.log(`skip: сумма max_usd отрезков $${sum.toFixed(2)} больше потолка $${req.max_usd_total}`); process.exit(0); }
  if (!sha) { console.log("skip: нет успешной публикации"); process.exit(0); }
  if (state.last_sha && state.last_sha === sha) { console.log(`skip: сборка ${sha.slice(0, 7)} уже проверена регрессией ${state.date || ""}`); process.exit(0); }
  if (state.last_sha) {
    let changed = null;
    try {
      execFileSync("git", ["cat-file", "-e", `${state.last_sha}^{commit}`], { cwd: ROOT });
      changed = execFileSync("git", ["diff", "--name-only", state.last_sha, sha, "--", "game", "data"], { cwd: ROOT, encoding: "utf8" }).trim();
    } catch (_) { changed = null; }
    if (changed === "") { console.log(`skip: с ${state.last_sha.slice(0, 7)} до ${sha.slice(0, 7)} game/ и data/ не менялись`); process.exit(0); }
  }
  console.log("run");
  process.exit(0);
}

const run = String(A.run || "");
const dirs = fs.readdirSync(PT).filter((d) => new RegExp(`_persona_regression_.+_r${run}(_\\d+)?$`).test(d) && fs.statSync(path.join(PT, d)).isDirectory());
const rows = [];
const defects = [];
let spent = 0, version = "";
for (const [i, seg] of (req.segments || []).entries()) {
  const id = String(seg.id || i + 1);
  const dir = dirs.filter((d) => new RegExp(`_persona_regression_${id}_r${run}(_\\d+)?$`).test(d)).sort().pop();
  if (!dir) { rows.push({ id, goal: seg.goal || "", status: "сбой", note: "прогона нет (раннер упал или не запускался — см. Docs/playtest/failures/)" }); continue; }
  let log = {}, usage = {}, report = "";
  try { log = JSON.parse(fs.readFileSync(path.join(PT, dir, "log.json"), "utf8")); } catch (_) {}
  try { usage = JSON.parse(fs.readFileSync(path.join(PT, dir, "usage.json"), "utf8")); } catch (_) {}
  try { report = fs.readFileSync(path.join(PT, dir, "report.md"), "utf8"); } catch (_) {}
  spent += Number(usage.spent_usd || 0);
  version = version || log.version || "";
  const reached = log.goal ? !!log.goal.reached : false;
  const steps = (log.steps || []).length;
  // The "## Дефекты" section of the report (the report model keeps only confirmed ones there).
  const m = /\n## Дефекты\s*\n([\s\S]*?)(?=\n## |\n---\n|$)/.exec(report);
  const body = m ? m[1].trim() : "";
  const n = (body.match(/^### /gm) || []).length;
  if (n) defects.push({ id, dir, body: body.replace(/\]\((f\d+\.jpg)\)/g, `](${dir}/$1)`) });
  rows.push({ id, dir, goal: seg.goal || "", status: reached ? "дошла" : "не дошла", steps, usd: Number(usage.spent_usd || 0), n,
    note: reached ? `шаг ${log.goal.step || steps}` : String(log.stop || "").slice(0, 160), anomalies: (log.anomalies || []).length });
}
const ok = rows.filter((r) => r.status === "дошла").length;
const nDef = rows.reduce((a, r) => a + (r.n || 0), 0);
const date = new Date().toISOString().slice(0, 10);
const verdict = `Регрессия ${date}, сборка ${(version || sha).slice(0, 7)}: ${ok === rows.length && !nDef ? "игра проходится целиком" : ok === rows.length ? "игра проходится целиком, есть дефекты" : "НЕ проходится целиком"} — отрезков дошло ${ok} из ${rows.length}, подтверждённых дефектов ${nDef}; $${spent.toFixed(2)}`;
const L = [];
L.push(`# Регрессия всей игры — ${date}`);
L.push("");
L.push(`**${verdict}**`);
L.push("");
L.push(`- Сборка: \`${version || "?"}\` (опубликованный коммит ${sha.slice(0, 7)}); запуск Actions ${run}; запрос \`${reqRel}\`. Отрезки шли параллельно, каждый — со своей точки старта по маршруту из data/story; прогон отрезка кончается, когда цель достигнута.`);
L.push(`- Стоимость: **$${spent.toFixed(2)}** (потолок $${req.max_usd_total || 8}: сумма max_usd отрезков).`);
L.push("");
L.push("| Отрезок | Цель | Итог | Шагов | Аномалий | Дефектов | $ | Отчёт |");
L.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
for (const r of rows) L.push(`| ${r.id} | ${r.goal} | ${r.status}${r.note ? ` (${r.note.replace(/\|/g, "/")})` : ""} | ${r.steps ?? "—"} | ${r.anomalies ?? "—"} | ${r.n ?? "—"} | ${r.usd !== undefined ? r.usd.toFixed(2) : "—"} | ${r.dir ? `[${r.dir}](${r.dir}/report.md)` : "—"} |`);
L.push("");
if (defects.length) {
  L.push("## Дефекты (подтверждённые, из отчётов отрезков)");
  L.push("");
  for (const d of defects) { L.push(`### Отрезок ${d.id} — [${d.dir}](${d.dir}/report.md)`); L.push(""); L.push(d.body.replace(/^### /gm, "#### ")); L.push(""); }
} else L.push("Подтверждённых дефектов нет.");
L.push("");
L.push("Отрезок «не дошла» — это не обязательно дефект игры: причину смотреть в отчёте отрезка (раздел «Маршрут» и «Плейтестер»).");
let file = path.join(PT, `regression_${date}.md`);
for (let k = 2; fs.existsSync(file); k++) file = path.join(PT, `regression_${date}_${k}.md`);
fs.writeFileSync(file, L.join("\n") + "\n");
fs.writeFileSync(STATE, JSON.stringify({ last_sha: sha, last_run: run, date, verdict, report: path.relative(ROOT, file) }, null, 1) + "\n");
fs.mkdirSync(path.join(ROOT, "build", "ai_playtest"), { recursive: true });
fs.writeFileSync(path.join(ROOT, "build", "ai_playtest", "regression_summary.txt"), verdict);
console.log(verdict);
