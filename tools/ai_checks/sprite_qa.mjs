#!/usr/bin/env node
// AI check «Sprite QA» (vision): the 8-direction sprite sheets of each character (assets/characters/<name>/)
// are laid out as contact sheets (tools/ai_checks/sprite_sheets.py) and Claude looks for what a player would
// notice: feet (boots splayed, toes through the floor or the other foot, a planted foot jumping between frames),
// hands or the bag through the body, texture smears and holes, wrong facing, cropped frames; then the scale of
// all characters relative to each other (lineup at their heights). The numeric feet-angle check is separate.
//
//   node tools/ai_checks/sprite_qa.mjs [--chars agata,pavel | --all] [--model claude-opus-5-5] [--max-usd 6]
//
// Without --chars / --all: only the characters whose sprite files changed since the last check
// (Docs/ai_checks/sprite_qa_state.json). Nothing changed → no API call, no report.
// Report: Docs/ai_checks/sprite_qa_<date>.md + the contact sheets cited by findings in sprite_qa_<date>/.

import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { ROOT, OUT_DIR, args, log, git, reportPath, askTool, cell, runLine, canonText, Budget } from "./common.mjs";

const CHARS = path.join(ROOT, "assets", "characters");
const STATE = path.join(OUT_DIR, "sprite_qa_state.json");
const WORK = path.join(ROOT, "build", "ai_checks", "sprites");

/** Characters that have sprite sheets, with a hash of their top-level sprite files (rt3d/ and the like excluded). */
function characters() {
  const out = {};
  for (const name of fs.readdirSync(CHARS).sort()) {
    const meta = path.join(CHARS, name, "sprites.json");
    if (!fs.existsSync(meta)) continue;
    let sheets = 0;
    try { const m = JSON.parse(fs.readFileSync(meta, "utf8")); sheets = Object.keys(m.actions || {}).length; } catch (_) {}
    if (!sheets) continue;
    let listing = "";
    try { listing = git("ls-tree", "HEAD", "--", `assets/characters/${name}/`).split("\n").filter((l) => / blob /.test(l)).join("\n"); }
    catch (_) { listing = fs.readdirSync(path.join(CHARS, name)).map((f) => { const p = path.join(CHARS, name, f); return fs.statSync(p).isFile() ? `${f}:${fs.statSync(p).size}:${fs.statSync(p).mtimeMs}` : ""; }).join("\n"); }
    out[name] = createHash("sha1").update(listing).digest("hex").slice(0, 16);
  }
  return out;
}

const castId = (dir) => dir.replace(/_mirror$/, "").replace(/_v\d+[a-z]?$/, "");

function castInfo() {
  try {
    const ch = JSON.parse(fs.readFileSync(path.join(ROOT, "data/story/characters.json"), "utf8")).characters || [];
    return Object.fromEntries(ch.map((c) => [c.id, c]));
  } catch (_) { return {}; }
}

const img = (file) => ({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: fs.readFileSync(file).toString("base64") } });

const findingSchema = {
  type: "object",
  properties: {
    character: { type: "string", description: "папка персонажа, напр. agata, tamara_v3" },
    image: { type: "string", description: "имя листа без .jpg, на котором видно, напр. agata_walk_feet" },
    action: { type: "string" },
    where: { type: "string", description: "направления и кадры, напр. «d3, f4–f6»" },
    area: { type: "string", enum: ["стопы", "руки/сумка", "текстура", "направление", "обрезка кадра", "масштаб", "другое"] },
    problem: { type: "string", description: "что видно, конкретно" },
    severity: { type: "string", enum: ["критично", "важно", "мелочь"] },
  },
  required: ["character", "image", "where", "area", "problem", "severity"],
};
const tool = {
  name: "report",
  description: "Итог осмотра: сводка и находки.",
  input_schema: { type: "object", properties: { summary: { type: "string" }, findings: { type: "array", items: findingSchema } }, required: ["summary", "findings"] },
};

const SYSTEM = `Ты — технический художник 2D-игры «Дом пропавших дорог». Персонажи — 3D-модели (Meshy), отрендеренные в Blender в спрайты: 8 направлений (d0 — анфас, дальше камера идёт вокруг персонажа по часовой стрелке, d4 — спина), кадры анимаций. В игре фигура стоит на полу комнаты рядом с дверьми и мебелью; ходьба нарисована на месте, вперёд её двигает игра.
Ищи то, что заметит игрок:
- стопы: носки неестественно врозь или внутрь, носок или каблук проходит сквозь другую ногу или подол, опорная стопа рывком меняет положение между соседними кадрами, нога выворачивается;
- руки, пальцы или сумка проходят сквозь тело, юбку, сумку; рука ломается в локте;
- текстура: размазанные или растянутые пятна, дыры, чужой цвет, швы, мусор;
- направление: в столбце dN фигура смотрит не туда, порядок направлений сбит, два соседних столбца одинаковые;
- фигура обрезана краем кадра, резкий скачок позы или размера между кадрами;
- лицо или одежда явно не соответствуют возрасту и роли персонажа.
Не придирайся к стилю и не повторяй одну проблему на каждом кадре — укажи диапазон. Важность: «критично» — сразу бросается в глаза в игре; «важно» — заметно при внимательном взгляде; «мелочь» — видно только на листе. Если всё чисто — пустой список. Ответ — только вызовом инструмента report.
Возраст и родство сверяй с каноном ниже (снаружи прошёл год, внутри двадцать: кто жил внутри, постарел на двадцать лет — так Пелагее 40, а её сыну Мите 37; это не ошибка).

${canonText()}`;

async function main() {
  const A = args();
  const model = A.model || "claude-opus-5-5";
  const budget = new Budget(Math.min(10, Number(A["max-usd"] || 6)));
  const all = characters();
  const state = fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, "utf8")) : {};
  let targets;
  let scope;
  if (A.all) { targets = Object.keys(all); scope = "все персонажи"; }
  else if (A.chars && A.chars !== true) { targets = String(A.chars).split(",").map((s) => s.trim()).filter((c) => all[c]); scope = `по запросу: ${targets.join(", ")}`; }
  else { targets = Object.keys(all).filter((c) => state[c] !== all[c]); scope = "изменившиеся с прошлой проверки"; }
  log(`characters with sheets: ${Object.keys(all).join(", ")}; to check: ${targets.join(", ") || "none"} (${scope})`);
  if (!targets.length) { log("nothing changed — no report"); return; }

  fs.rmSync(WORK, { recursive: true, force: true });
  fs.mkdirSync(WORK, { recursive: true });
  const manifest = JSON.parse(execFileSync("python3", [path.join(ROOT, "tools/ai_checks/sprite_sheets.py"), "--out", WORK, "--chars", targets.join(","), "--lineup"],
    { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }));
  const cast = castInfo();
  const findings = [];
  const summaries = [];
  const errors = [];
  const checked = [];
  const stem = (f) => path.basename(f, ".jpg");

  for (const name of targets) {
    const items = manifest.filter((m) => m.name === name);
    if (!items.length) continue;
    const meta = JSON.parse(fs.readFileSync(path.join(CHARS, name, "sprites.json"), "utf8"));
    const c = cast[castId(name)] || {};
    const content = [];
    for (const it of items) { content.push({ type: "text", text: `Лист ${stem(it.file)}: ${it.caption}` }); content.push(img(it.file)); }
    content.push({ type: "text", text: `Персонаж: ${name}${c.name ? ` — ${c.name}${c.age ? `, ${c.age} лет` : ""}; ${String(c.role || "").slice(0, 300)}` : ""}. Рост модели ${meta.character_height_m || "?"} м, кадр ${meta.frame_w}×${meta.frame_h}. Действия: ${Object.entries(meta.actions || {}).map(([k, v]) => `${k} (${v.frames} кадров, ${v.fps} к/с, клип ${v.clip || "?"})`).join("; ")}.${meta.qa_note ? `\nОсобенность этих листов: ${meta.qa_note}` : ""}\nОсмотри листы и ответь вызовом report (character = «${name}»).` });
    try {
      const r = await askTool(budget, `sprite:${name}`, { model, max_tokens: 16000, system: SYSTEM, tools: [tool], output_config: { effort: "medium" }, messages: [{ role: "user", content }] }, "report");
      if (r) {
        summaries.push({ name, text: r.summary || "" });
        for (const f of r.findings || []) findings.push({ ...f, character: name });
        checked.push(name);
      } else errors.push(`${name}: нет ответа инструментом`);
      log(`${name}: ${(r && r.findings || []).length} findings, total $${budget.spent.toFixed(3)}`);
    } catch (e) { errors.push(`${name}: ${String(e.message || e).slice(0, 200)}`); }
  }

  // Scale of everyone relative to each other.
  const lu = manifest.find((m) => m.kind === "lineup");
  let lineupSummary = "";
  if (lu && checked.length) {
    const rows = Object.keys(all).map((n) => {
      const meta = JSON.parse(fs.readFileSync(path.join(CHARS, n, "sprites.json"), "utf8"));
      const c = cast[castId(n)] || {};
      return `- ${n}: ${c.name || "?"}${c.age ? `, ${c.age} лет` : ""}, рост модели ${meta.character_height_m} м; ${String(c.role || "").slice(0, 120)}`;
    });
    try {
      const r = await askTool(budget, "sprite:lineup", { model, max_tokens: 12000, system: SYSTEM, tools: [tool], output_config: { effort: "medium" },
        messages: [{ role: "user", content: [{ type: "text", text: `Лист lineup: ${lu.caption}` }, img(lu.file), { type: "text", text: `Персонажи:\n${rows.join("\n")}\nОцени только масштаб и пропорции относительно друг друга и возраста (area = «масштаб», image = «lineup»): кто слишком высок или низок для своего возраста и роли, у кого голова или руки непропорциональны, у кого фигура в линейке выглядит иначе, чем другие (поза, наклон, «парит» над полом). Версии одного персонажа (tamara и tamara_v3) сравни между собой.` }] }] }, "report");
      if (r) { lineupSummary = r.summary || ""; for (const f of r.findings || []) findings.push({ ...f, image: "lineup", area: f.area || "масштаб" }); }
    } catch (e) { errors.push(`lineup: ${String(e.message || e).slice(0, 200)}`); }
  }

  // Report + the sheets cited by findings.
  const file = reportPath("sprite_qa");
  const shotsDir = file.replace(/\.md$/, "");
  const order = { "критично": 0, "важно": 1, "мелочь": 2 };
  findings.sort((a, b) => (order[a.severity] ?? 3) - (order[b.severity] ?? 3) || String(a.character).localeCompare(String(b.character)));
  const cited = [...new Set(findings.map((f) => String(f.image || "").replace(/\.jpg$/, "")))].filter((s) => manifest.some((m) => stem(m.file) === s)).slice(0, 18);
  if (cited.length) fs.mkdirSync(shotsDir, { recursive: true });
  for (const s of cited) fs.copyFileSync(path.join(WORK, `${s}.jpg`), path.join(shotsDir, `${s}.jpg`));
  const rel = path.basename(shotsDir);
  const link = (s) => (cited.includes(s) ? `[${s}](${rel}/${s}.jpg)` : s);
  const L = [];
  L.push(`# ИИ-проверка спрайтов — ${new Date().toISOString().slice(0, 10)}`);
  L.push("");
  L.push(`- Что проверено: ${scope} — ${checked.join(", ") || "—"}; листы всех действий в 8 направлениях, низ фигуры ×2 (ходьба, стойка), опорные виды, линейка всех персонажей по росту.`);
  L.push(`- Модель: \`${model}\`; ${runLine()}; стоимость **$${budget.spent.toFixed(3)}**. Числовая проверка углов стоп — отдельно (другой агент); здесь — глазами.`);
  L.push(`- Правок в assets/ и game/ проверка не делает; находки разводит координатор.`);
  L.push("");
  if (errors.length) { L.push(`**Не проверено:** ${errors.join("; ")}`); L.push(""); }
  L.push("## Итог");
  L.push("");
  for (const s of summaries) L.push(`- **${s.name}**: ${cell(s.text)}`);
  if (lineupSummary) L.push(`- **Линейка (масштаб)**: ${cell(lineupSummary)}`);
  L.push("");
  L.push(`## Находки (${findings.length})`);
  L.push("");
  if (!checked.length) L.push("Проверка не выполнена (см. выше).");
  else if (!findings.length) L.push("Замечаний нет.");
  else {
    L.push("| Важность | Персонаж | Лист | Где | Что | Тип |");
    L.push("| --- | --- | --- | --- | --- | --- |");
    for (const f of findings) L.push(`| ${cell(f.severity)} | ${cell(f.character)} | ${link(String(f.image || "").replace(/\.jpg$/, ""))} | ${cell(f.where)} | ${cell(f.problem)} | ${cell(f.area)} |`);
  }
  L.push("");
  L.push("Как читать лист: столбцы d0…d7 — направления (d0 анфас, дальше по часовой стрелке, d4 — спина), строки f — номера кадров в листе действия `assets/characters/<персонаж>/<действие>.png`.");
  fs.writeFileSync(file, L.join("\n") + "\n");
  // Remember what was checked (only the characters that got an answer).
  for (const n of checked) state[n] = all[n];
  fs.writeFileSync(STATE, JSON.stringify(state, null, 1) + "\n");
  fs.mkdirSync(path.join(ROOT, "build", "ai_checks"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "build", "ai_checks", "summary.txt"), `спрайты ${checked.join(", ")}: ${findings.length} находок (${findings.filter((f) => f.severity === "критично").length} критичных); $${budget.spent.toFixed(2)}`);
  log(`report ${path.relative(ROOT, file)}: ${findings.length} findings, $${budget.spent.toFixed(3)}`);
}

main().catch((e) => { console.error(`fatal: ${String(e && e.message).slice(0, 300)}`); process.exit(1); });
