#!/usr/bin/env node
// Armed persona runs (ai-personas.yml): the five persona playtests of the whole game run ONCE, by themselves, on the
// first successful deploy (build-and-publish) whose commit has the awaited content live — e.g. side stories Q02 and
// Q06 wired into the rooms — or after a deadline, whichever comes first. Then their defects are merged into one file.
//
//   node tools/ai_playtest/persona_arm.mjs check --sha <deployed sha>   → stdout: JSON array of request files ([] = not now);
//                                                                         the reason goes to stderr. No API.
//   node tools/ai_playtest/persona_arm.mjs start --sha <sha> --run <workflow run number>   → state: started (no second start)
//   node tools/ai_playtest/persona_arm.mjs merge --run <workflow run number> [--sha <sha>]  → Docs/playtest/defects_personas_<date>.md
//
// Arm: Docs/playtest/requests/personas_armed.json {requests: [...], when: {quests_live: ["Q02", "Q06"]}, deadline, run, hold?}.
// `hold` (a reason string) pauses the arm regardless of the deadline — remove it to let the next publish start the runs.
// A quest is live at a commit when quests.json no longer marks it reserve, or a room of data/story/rooms mentions it
// (its id or its q0N_ flags). State: Docs/playtest/personas_state.json {arm_run, started_run, sha, …} — one run per arm.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const PT = path.join(ROOT, "Docs", "playtest");
const ARM = path.join(PT, "requests", "personas_armed.json");
const STATE = path.join(PT, "personas_state.json");
const cmd = process.argv[2] || "";
const A = (() => { const a = process.argv.slice(3), o = {}; for (let i = 0; i < a.length; i++) if (a[i].startsWith("--")) { o[a[i].slice(2)] = a[i + 1]; i++; } return o; })();
const readJson = (f, d = {}) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch (_) { return d; } };
const git = (...a) => execFileSync("git", a, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
const arm = readJson(ARM, null);
const state = readJson(STATE);
const sha = String(A.sha || "");

function questLive(id, at) {
  try {
    const q = (JSON.parse(git("show", `${at}:data/story/quests.json`)).quests || []).find((x) => x.id === id);
    if (q && q.reserve !== true) return true;
  } catch (_) { /* no file */ }
  try { return git("grep", "-l", "-E", `"${id}"|${id.toLowerCase()}_`, at, "--", "data/story/rooms").trim() !== ""; } catch (_) { return false; }
}

if (cmd === "check") {
  const out = (files, why) => { process.stderr.write(`${why}\n`); console.log(JSON.stringify(files)); process.exit(0); };
  if (!arm || !Array.isArray(arm.requests) || !arm.requests.length) out([], "нет взведённых прогонов (personas_armed.json)");
  if (String(state.arm_run ?? "") === String(arm.run)) out([], `взвод run ${arm.run} уже запущен (${state.started_run ? `прогон Actions ${state.started_run}` : ""}, сборка ${String(state.sha || "").slice(0, 7)})`);
  if (!sha) out([], "нет успешной публикации");
  if (arm.hold) out([], `взвод на паузе: ${arm.hold}`);
  const need = ((arm.when && arm.when.quests_live) || []);
  const missing = need.filter((q) => !questLive(q, sha));
  const late = arm.deadline && Date.now() > Date.parse(arm.deadline);
  if (missing.length && !late) out([], `сборка ${sha.slice(0, 7)}: ещё не в игре ${missing.join(", ")} — ждём (крайний срок ${arm.deadline || "—"})`);
  const files = arm.requests.filter((f) => fs.existsSync(path.join(ROOT, f)));
  out(files, `сборка ${sha.slice(0, 7)}: ${missing.length ? `крайний срок ${arm.deadline} прошёл (не в игре: ${missing.join(", ")})` : `в игре ${need.join(", ") || "всё нужное"}`} — запуск ${files.length} прогонов`);
}

if (cmd === "start") {
  fs.writeFileSync(STATE, JSON.stringify({ arm_run: arm ? arm.run : null, started_run: A.run || "", sha, started_at: new Date().toISOString(), requests: arm ? arm.requests : [] }, null, 1) + "\n");
  console.log(`state: arm ${arm && arm.run} started (run ${A.run}, ${sha.slice(0, 7)})`);
}

if (cmd === "merge") {
  const run = String(A.run || "");
  const dirs = fs.readdirSync(PT).filter((d) => new RegExp(`_persona_(?!regression)[a-z_0-9]+_r${run}(_\\d+)?$`).test(d) && fs.statSync(path.join(PT, d)).isDirectory()).sort();
  const date = new Date().toISOString().slice(0, 10);
  const rows = [], blocks = [];
  let spent = 0, nDef = 0, version = "";
  for (const d of dirs) {
    const log = readJson(path.join(PT, d, "log.json"));
    const usage = readJson(path.join(PT, d, "usage.json"));
    let report = "";
    try { report = "\n" + fs.readFileSync(path.join(PT, d, "report.md"), "utf8"); } catch (_) {}
    version = version || log.version || "";
    spent += Number(usage.spent_usd || 0);
    const sect = (name) => { const m = new RegExp(`\\n## ${name}[^\\n]*\\n([\\s\\S]*?)(?=\\n## |\\n---\\n|$)`).exec(report); return m ? m[1].trim().replace(/\]\((f\d+\.jpg)\)/g, `](${d}/$1)`) : ""; };
    const defects = sect("Дефекты");
    const n = (defects.match(/^### /gm) || []).length;
    nDef += n;
    const role = (/_persona_(.+)_r\d+/.exec(d) || [])[1] || d;
    const start = (log.start_save && `сохранение «${log.start_save.title || log.start_save.slot}»`) || (/[?&]start=([\w-]+)/.exec((log.cfg && log.cfg.url) || "") || [])[1] || "новая игра";
    rows.push(`| ${role} | ${String(start).replace(/\|/g, "/")} | ${(log.steps || []).length} | ${String(log.stop || "").replace(/\|/g, "/").slice(0, 90)} | ${(log.anomalies || []).length} | ${n} | ${Number(usage.spent_usd || 0).toFixed(2)} | [отчёт](${d}/report.md) |`);
    const extra = [sect("Итог"), role.startsWith("newbie") ? sect("Где новичок застрял") : "", role.startsWith("completionist") ? sect("Покрытие") : ""].filter(Boolean);
    blocks.push(`## ${role} — [${d}](${d}/report.md)\n\n${extra.map((x) => x.replace(/^### /gm, "#### ")).join("\n\n")}\n\n### Дефекты\n\n${defects ? defects.replace(/^### /gm, "#### ") : "Подтверждённых дефектов нет."}\n`);
  }
  const L = [];
  L.push(`# Дефекты ИИ-плейтеста в ролях — ${date}`);
  L.push("");
  L.push(`Пять ролей по всей игре (новичок без помощи; собиратель всего — дни 1–2 и свободный день; нетерпеливый; сохраняет-загружает; медленный игрок), сборка \`${version || sha.slice(0, 7) || "?"}\`, запуск Actions ${run}. Каждый дефект ниже отчёт роли подтвердил кадрами, дословными репликами или объективными аномалиями по состоянию игры (сумка, флаги, повтор разовых реплик — \`log.json → anomalies\`) и записал как «комната — действие — ожидалось — получилось — как воспроизвести». Сводка собрана программой (\`tools/ai_playtest/persona_arm.mjs merge\`); перед разводкой агентам — проверить дубли между ролями. Правок в game/ и data/ плейтест не делает.`);
  L.push("");
  L.push(`**Итого:** подтверждённых дефектов ${nDef}; стоимость всех прогонов **$${spent.toFixed(2)}**.`);
  L.push("");
  L.push("| Роль | Старт | Шагов | Остановка | Аномалий | Дефектов | $ | Отчёт |");
  L.push("| --- | --- | --- | --- | --- | --- | --- | --- |");
  L.push(...rows);
  L.push("");
  L.push(...blocks);
  let file = path.join(PT, `defects_personas_${date}.md`);
  for (let k = 2; fs.existsSync(file); k++) file = path.join(PT, `defects_personas_${date}_${k}.md`);
  fs.writeFileSync(file, L.join("\n") + "\n");
  if (fs.existsSync(STATE)) { const st = readJson(STATE); fs.writeFileSync(STATE, JSON.stringify({ ...st, merged: path.relative(ROOT, file), finished_at: new Date().toISOString(), spent_usd: Number(spent.toFixed(2)), defects: nDef }, null, 1) + "\n"); }
  fs.mkdirSync(path.join(ROOT, "build", "ai_playtest"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "build", "ai_playtest", "personas_summary.txt"), `роли: ${dirs.length} прогонов, дефектов ${nDef}; $${spent.toFixed(2)}`);
  console.log(`${path.relative(ROOT, file)}: ${dirs.length} runs, ${nDef} defects, $${spent.toFixed(2)}`);
}

if (!["check", "start", "merge"].includes(cmd)) { console.error("usage: persona_arm.mjs check|start|merge …"); process.exit(2); }
