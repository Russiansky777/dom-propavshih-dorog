#!/usr/bin/env node
// AI check «Story logic review per block»: when a block's Docs/ACCEPTANCE_<M>.md appears or changes, Claude
// reads the block (the changed sections of that doc, or the whole doc when it is new) and the game's story
// data (scenes, rooms without geometry, items, flags, quests, locations, the texts the player sees) against
// Docs/SCENARIO_FINAL.md and the canon, and flags: steps a player can't infer; required items that can be
// missed, lost or given twice; goals required before they are explained; dead ends; contradictions with canon.
//
//   node tools/ai_checks/story_logic.mjs --doc Docs/ACCEPTANCE_M2.md [--base <sha>] [--model claude-opus-5-5]
//   node tools/ai_checks/story_logic.mjs --changed --base <sha>     (every ACCEPTANCE_*.md changed since base)
//
// Report: Docs/ai_checks/story_logic_<date>.md. Never edits game/ or data/.

import fs from "node:fs";
import path from "node:path";
import { ROOT, args, log, git, validBase, readAt, canonText, readDoc, reportPath, askTool, cell, runLine, Budget } from "./common.mjs";

const GEOMETRY = new Set(["walkable", "walkable_holes", "no_walk_samples", "walk_samples", "depth", "height_refs", "rect", "polygon",
  "effects", "offset", "scale", "pivot", "modulate", "spin", "rotation_deg", "background", "props", "image", "occluder", "z", "cue", "cue_dir", "lights"]);
function strip(o) {
  if (Array.isArray(o)) return o.map(strip);
  if (o && typeof o === "object") {
    const r = {};
    for (const [k, v] of Object.entries(o)) if (!k.startsWith("_") && !GEOMETRY.has(k)) r[k] = strip(v);
    return r;
  }
  return o;
}
const jfile = (rel) => { try { return JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8")); } catch (_) { return null; } };

/** The story data, compact: scenes, rooms (hotspots, exits, layers' conditions), items, flags, quests, locations, texts. */
function storyData() {
  const L = [];
  for (const f of fs.readdirSync(path.join(ROOT, "data/story/scenes")).sort()) if (f.endsWith(".json")) L.push(`### scenes/${f}\n${JSON.stringify(strip(jfile(`data/story/scenes/${f}`)))}`);
  for (const f of fs.readdirSync(path.join(ROOT, "data/story/rooms")).sort()) if (/^[A-Z].*\.json$/.test(f)) L.push(`### rooms/${f}\n${JSON.stringify(strip(jfile(`data/story/rooms/${f}`)))}`);
  for (const f of ["items.json", "flags.json", "quests.json", "locations.json"]) L.push(`### ${f}\n${JSON.stringify(strip(jfile(`data/story/${f}`)))}`);
  const texts = {};
  for (const f of fs.readdirSync(path.join(ROOT, "data/story/text")).sort()) {
    if (!/^ru_.*\.json$/.test(f)) continue;
    for (const [k, v] of Object.entries((jfile(`data/story/text/${f}`) || {}).texts || {})) texts[k] = typeof v === "string" ? v : (v.line ? `${v.line.speaker}: ${v.line.text}` : v.text);
  }
  L.push(`### тексты (ключ @… → что видит игрок)\n${Object.entries(texts).map(([k, v]) => `${k} = ${v}`).join("\n")}`);
  return L.join("\n\n");
}

/** Sections of an acceptance doc touched since `base` (whole doc when new or no base). */
function blockOf(docRel, base) {
  const now = readAt("", docRel);
  if (now === null) return null;
  const before = base ? readAt(base, docRel) : null;
  const lines = now.split("\n");
  const sections = [];
  let cur = { title: "(начало)", start: 0, lines: [] };
  lines.forEach((l, i) => { if (/^##\s/.test(l)) { sections.push(cur); cur = { title: l.replace(/^##\s+/, ""), start: i, lines: [] }; } cur.lines.push(l); });
  sections.push(cur);
  if (before === null) return { scope: "весь документ (новый или ручной запуск)", text: now };
  const old = new Set(before.split("\n"));
  const touched = sections.filter((s) => s.lines.some((l) => l.trim() && !old.has(l)));
  if (!touched.length) return { scope: "без изменений", text: "" };
  return { scope: `изменённые разделы: ${touched.map((s) => `«${s.title}»`).join(", ")}`, text: [lines[0], ...touched.map((s) => s.lines.join("\n"))].join("\n\n") };
}

const tool = {
  name: "report",
  description: "Итог разбора логики блока.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "3–5 фраз: проходим ли блок без догадок, главное." },
      findings: {
        type: "array",
        items: {
          type: "object",
          properties: {
            kind: { type: "string", enum: ["игроку не вывести", "предмет: пропустить/потерять/дважды", "цель не объяснена до требования", "тупик", "противоречие канону/сценарию", "расхождение данных и чеклиста", "другое"] },
            where: { type: "string", description: "сцена / комната / хотспот / флаг / предмет (id из данных) и пункт чеклиста, если есть" },
            problem: { type: "string", description: "что не так, с точки зрения игрока" },
            evidence: { type: "string", description: "на чём основано: что именно сказано в данных, сценарии или чеклисте" },
            fix: { type: "string", description: "что поменять (данные/текст/порядок), коротко" },
            severity: { type: "string", enum: ["критично", "важно", "мелочь"] },
          },
          required: ["kind", "where", "problem", "evidence", "fix", "severity"],
        },
      },
    },
    required: ["summary", "findings"],
  },
};

async function main() {
  const A = args();
  const model = A.model || "claude-opus-5-5";
  const budget = new Budget(Math.min(10, Number(A["max-usd"] || 6)));
  const base = validBase(A.base || "");
  let docs = [];
  if (A.doc && A.doc !== true) docs = [String(A.doc)];
  else if (A.changed && base) docs = git("diff", "--name-only", "--diff-filter=AM", base, "HEAD", "--", "Docs/ACCEPTANCE_*.md").split("\n").filter(Boolean);
  if (!docs.length) { log("no acceptance doc to review"); return; }
  const data = storyData();
  const scenario = readDoc("Docs/SCENARIO_FINAL.md", 150000);
  for (const doc of docs) {
    const block = blockOf(doc, A.doc ? "" : base);
    if (!block || !block.text.trim()) { log(`${doc}: nothing changed`); continue; }
    log(`${doc}: ${block.scope}; data ${data.length} chars, model ${model}`);
    const system = `Ты — гейм-дизайнер и редактор логики квестов 2D point-and-click игры «Дом пропавших дорог». Тебе дают блок игры (раздел приёмочного чеклиста — что сейчас собрано и как должно работать), все данные сюжета игры (сцены с условиями requires/grants/consumes, комнаты с хотспотами и выходами и их условиями, предметы, флаги и записи журнала, побочные квесты, тексты, которые видит игрок) и принятый сценарий. Проверь блок глазами игрока, который ничего не знает заранее:
1. Можно ли вывести каждый шаг из того, что игра показала и сказала к этому моменту (осмотры, реплики, подсказки, журнал)? Где игроку придётся угадывать — «игроку не вывести».
2. Обязательные предметы: где выдаются, где тратятся; можно ли их пропустить, потерять, получить дважды, потратить не туда; не выдаётся ли предмет до того, как он понятен.
3. Цель объяснена до того, как её требуют (правило проекта: «любая цель объяснена до требования её выполнить»).
4. Тупики: состояние, из которого блок не пройти (условия выходов и сцен, взаимоисключающие флаги, повтор одноразового события после загрузки).
5. Противоречия канону и сценарию; расхождения между данными и тем, что обещает чеклист.
Опирайся только на данные; в evidence приводи конкретные id и дословные фрагменты. Не пересказывай то, что работает. Важность: «критично» — блок не пройти или канон нарушен; «важно» — игрок застрянет или запутается; «мелочь» — шероховатость. Ответ — только вызовом инструмента report.

${canonText()}

СЦЕНАРИЙ (Docs/SCENARIO_FINAL.md, принят 22.10):
${scenario}`;
    const user = `БЛОК НА ПРОВЕРКУ — ${doc} (${block.scope}):\n${block.text.slice(0, 40000)}\n\nДАННЫЕ СЮЖЕТА ИГРЫ (data/story, без геометрии и служебных заметок):\n${data}\n\nОтветь вызовом инструмента report.`;
    let r = null, err = "";
    try {
      r = await askTool(budget, `logic:${path.basename(doc)}`, { model, max_tokens: 32000, system, tools: [tool], thinking: { type: "adaptive" }, output_config: { effort: "high" },
        messages: [{ role: "user", content: user }] }, "report");
      if (!r) err = "модель не вернула отчёт инструментом";
    } catch (e) { err = String(e.message || e); }
    const findings = ((r && r.findings) || []);
    const order = { "критично": 0, "важно": 1, "мелочь": 2 };
    findings.sort((a, b) => (order[a.severity] ?? 3) - (order[b.severity] ?? 3));
    const L = [];
    L.push(`# ИИ-разбор логики блока — ${path.basename(doc, ".md")} — ${new Date().toISOString().slice(0, 10)}`);
    L.push("");
    L.push(`- Блок: \`${doc}\` — ${block.scope}.`);
    L.push(`- Против чего: данные data/story (сцены, комнаты, предметы, флаги, квесты, тексты), Docs/SCENARIO_FINAL.md, канон CLAUDE.md.`);
    L.push(`- Модель: \`${model}\`; ${runLine()}; стоимость **$${budget.spent.toFixed(3)}**. Правок в game/ и data/ нет; находки разводит координатор.`);
    L.push("");
    if (err) { L.push(`**Разбор не выполнен:** ${err}`); L.push(""); }
    if (r) {
      L.push("## Итог"); L.push(""); L.push(r.summary || ""); L.push("");
      L.push(`## Находки (${findings.length})`); L.push("");
      if (!findings.length) L.push("Замечаний нет.");
      for (const [i, f] of findings.entries()) {
        L.push(`### ${i + 1}. ${cell(f.severity)} — ${cell(f.kind)}: ${cell(f.where)}`);
        L.push("");
        L.push(`- **Что не так:** ${cell(f.problem)}`);
        L.push(`- **Основание:** ${cell(f.evidence)}`);
        L.push(`- **Что поменять:** ${cell(f.fix)}`);
        L.push("");
      }
    }
    const file = reportPath(`story_logic_${path.basename(doc, ".md").replace(/^ACCEPTANCE_/, "")}`);
    fs.writeFileSync(file, L.join("\n") + "\n");
    fs.mkdirSync(path.join(ROOT, "build", "ai_checks"), { recursive: true });
    fs.writeFileSync(path.join(ROOT, "build", "ai_checks", "summary.txt"), `логика ${path.basename(doc, ".md")}: ${findings.length} находок (${findings.filter((f) => f.severity === "критично").length} критичных); $${budget.spent.toFixed(2)}`);
    log(`report ${path.relative(ROOT, file)}: ${findings.length} findings, $${budget.spent.toFixed(3)}`);
  }
}

main().catch((e) => { console.error(`fatal: ${String(e && e.message).slice(0, 300)}`); process.exit(1); });
