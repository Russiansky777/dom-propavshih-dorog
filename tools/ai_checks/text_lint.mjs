#!/usr/bin/env node
// AI check «Text lint»: every line the player reads or hears (data/story/text/ru_*.json, the lines, options,
// hints and goals of data/story/scenes/*.json, item names, journal facts of flags.json, side quests, room
// names) is checked by Claude against the canon (CLAUDE.md, characters.json, Docs/SCENARIO_FINAL.md) and
// for Russian typos / grammar / consistent names and terms / a goal explained only after it is required.
// Main value: catch errors before the voices are recorded.
//
//   node tools/ai_checks/text_lint.mjs [--base <sha>] [--all] [--model claude-opus-5-5] [--max-usd 5]
//
// --base: only the entries that are new or changed since that commit are checked (the whole text is still
// given as context); without a usable base, or with --all — every entry. Nothing changed → no report.
// Report: Docs/ai_checks/text_lint_<date>.md. Never edits game/ or data/.

import fs from "node:fs";
import path from "node:path";
import { ROOT, args, log, validBase, readAt, listAt, canonText, readDoc, reportPath, ask, toolInput, cell, runLine, Budget } from "./common.mjs";


/** Every player-visible Russian string of data/story at a ref ("" = working tree): [{id, who, text}]. */
function collect(ref) {
  const out = [];
  const add = (id, text, who = "") => { if (typeof text === "string" && /[А-Яа-яЁё]/.test(text)) out.push({ id, who, text: text.trim() }); };
  const json = (rel) => { const t = readAt(ref, rel); if (t === null) return null; try { return JSON.parse(t); } catch (_) { return null; } };
  for (const rel of listAt(ref, "data/story/text").filter((f) => /\/ru_[^/]*\.json$/.test(f))) {
    const d = json(rel);
    for (const [k, v] of Object.entries((d && d.texts) || {})) {
      if (typeof v === "string") { add(`${k}`, v); continue; }
      if (!v || typeof v !== "object") continue;
      if (v.line && v.line.text) add(`${k}`, v.line.text, v.line.speaker || "");
      else add(`${k}`, v.text);
      for (const lk of ["label", "prompt", "title"]) if (v[lk]) add(`${k}.${lk}`, v[lk]);
    }
  }
  for (const rel of listAt(ref, "data/story/scenes").filter((f) => f.endsWith(".json"))) {
    const d = json(rel);
    for (const sc of (d && d.scenes) || []) {
      (sc.mandatory_lines || []).forEach((ln, i) => {
        if (ln.context) add(`${sc.id}.${i}.вариант`, ln.context);
        if (ln.prompt) add(`${sc.id}.${i}.вопрос`, ln.prompt);
        for (const o of ln.options || []) { add(`${sc.id}.${i}.${o.id}.вариант`, o.label || ""); add(`${sc.id}.${i}.${o.id}`, o.text || "", ln.speaker || ""); }
        if (ln.text) add(`${sc.id}.${i}`, ln.text, ln.speaker || "");
      });
      (sc.hints || []).forEach((h, i) => add(`${sc.id}.подсказка${i + 1}`, h));
      if (sc.goal) add(`${sc.id}.цель_журнала`, sc.goal);
    }
  }
  const items = json("data/story/items.json");
  for (const it of (items && items.items) || []) add(`предмет.${it.id}`, it.name);
  const flags = json("data/story/flags.json");
  const fl = (flags && flags.flags) || {};
  for (const [k, v] of Array.isArray(fl) ? fl.map((f) => [f.id, f]) : Object.entries(fl)) if (v && v.desc) add(`журнал.${k}`, v.desc);
  const quests = json("data/story/quests.json");
  for (const q of (quests && quests.quests) || []) {
    add(`квест.${q.id}.название`, q.title);
    if (typeof q.text === "string") add(`квест.${q.id}`, q.text);
    (q.steps || []).forEach((s, i) => add(`квест.${q.id}.шаг${i + 1}`, typeof s === "string" ? s : s && s.text));
  }
  const loc = json("data/story/locations.json");
  for (const l of (loc && loc.locations) || []) add(`место.${l.id}`, l.name);
  return out;
}

const SPEAKERS = { agata: "Агата", tamara: "Тамара", pelageya: "Пелагея", tikhon: "Тихон", nina: "Нина", ilya: "Илья",
  ulyana: "Ульяна", mitya: "Митя", pavel: "Павел", narrator: "голос за кадром" };
const fmt = (e) => `[${e.id}]${e.who ? ` ${SPEAKERS[e.who] || e.who}:` : ""} ${e.text}`;

async function main() {
  const A = args();
  const base = A.all ? "" : validBase(A.base || "");
  const model = A.model || "claude-opus-5-5";
  const budget = new Budget(Math.min(10, Number(A["max-usd"] || 5)));
  const now = collect("");
  let check = now;
  let scope = "весь текст";
  if (base) {
    const before = new Map(collect(base).map((e) => [`${e.id}|${e.who}`, e.text]));
    check = now.filter((e) => before.get(`${e.id}|${e.who}`) !== e.text);
    scope = `новое и изменённое с ${base.slice(0, 7)}`;
  }
  log(`entries: ${now.length}, to check: ${check.length} (${scope}), model ${model}`);
  if (!check.length) { log("nothing changed — no report"); return; }

  const tool = {
    name: "report",
    description: "Итог проверки: краткая сводка и список находок.",
    input_schema: {
      type: "object",
      properties: {
        summary: { type: "string", description: "2–4 фразы: общее состояние текста, главное." },
        findings: {
          type: "array",
          items: {
            type: "object",
            properties: {
              id: { type: "string", description: "id строки в квадратных скобках, как во входе" },
              quote: { type: "string", description: "дословный фрагмент с ошибкой" },
              problem: { type: "string", description: "что не так, коротко" },
              fix: { type: "string", description: "как исправить (готовый вариант фрагмента)" },
              category: { type: "string", enum: ["канон", "опечатка", "грамматика", "пунктуация", "имя/термин", "цель позже требования", "логика", "другое"] },
              severity: { type: "string", enum: ["критично", "важно", "мелочь"] },
            },
            required: ["id", "quote", "problem", "fix", "category", "severity"],
          },
        },
      },
      required: ["summary", "findings"],
    },
  };
  const system = `Ты — редактор-корректор русского текста компьютерной игры «Дом пропавших дорог» (2D point-and-click). Тексты ниже — то, что игрок читает и слышит: реплики (их озвучат один раз, поэтому ошибка дорогая), осмотры, варианты ответов, подсказки, цели и записи журнала, названия предметов и мест.
Найди только настоящие ошибки — не переписывай стиль и литературу (это дело владельца текста):
1. КАНОН: возраст, родство, имена, факты мира — против канона и сценария ниже. Имя «Дарья» не используется никогда. Тихон — печной зверёк-смотритель, ворчливый, ленивый, саркастичный, не подсказчик и не питомец. Эха в конторе мельницы нет (снято 22.10). Евдокию близкие зовут Дуня/Дуня-тётя — это не ошибка.
2. Русский язык: опечатки, грамматика, согласование, пунктуация (в том числе тире и кавычки «» в прямой речи), ё там, где без неё смысл двоится.
3. Единообразие имён и терминов (одна и та же вещь называется по-разному без причины; разные написания имени).
4. Цель объясняется позже, чем её требуют (если это видно по текстам), явные логические противоречия между строками.
Каждая находка — одна строка входа (id), дословная цитата, что не так, готовое исправление, категория и важность: «критично» — противоречит канону или искажает смысл; «важно» — ошибка, заметная игроку или в озвучке; «мелочь» — пунктуация и шероховатости. Если ошибок нет — пустой список. Ответ — только вызовом инструмента report.

${canonText()}

СЦЕНАРИЙ (Docs/SCENARIO_FINAL.md, принят 22.10 — истина для фактов):
${readDoc("Docs/SCENARIO_FINAL.md", 120000)}`;
  const user = `${base ? `ПРОВЕРИТЬ (новые и изменённые строки, ${check.length}):\n${check.map(fmt).join("\n")}\n\nВЕСЬ ТЕКСТ ИГРЫ (контекст, находки — только по строкам из списка «проверить», кроме прямого противоречия с ними):\n${now.map(fmt).join("\n")}`
    : `ПРОВЕРИТЬ ВЕСЬ ТЕКСТ ИГРЫ (${check.length} строк):\n${check.map(fmt).join("\n")}`}`;

  let input = null, err = "";
  try {
    const body = { model, max_tokens: 32000, system, tools: [tool], tool_choice: { type: "auto" }, thinking: { type: "adaptive" }, output_config: { effort: "high" },
      messages: [{ role: "user", content: user + "\n\nОтветь вызовом инструмента report." }] };
    let resp;
    try { resp = await ask(budget, "lint", body); }
    catch (e) { if (/HTTP 400/.test(String(e.message))) { const { thinking, output_config, ...b } = body; resp = await ask(budget, "lint", { ...b, tool_choice: { type: "tool", name: "report" } }); } else throw e; }
    input = toolInput(resp, "report");
    if (!input) {
      const { thinking, output_config, ...b } = body;
      resp = await ask(budget, "lint-forced", { ...b, tool_choice: { type: "tool", name: "report" } });
      input = toolInput(resp, "report");
    }
  } catch (e) { err = String(e.message || e); }

  const known = new Set(now.map((e) => e.id));
  const findings = ((input && input.findings) || []).filter((f) => f && f.id);
  const order = { "критично": 0, "важно": 1, "мелочь": 2 };
  findings.sort((a, b) => (order[a.severity] ?? 3) - (order[b.severity] ?? 3));
  const L = [];
  L.push(`# ИИ-проверка текста — ${new Date().toISOString().slice(0, 10)}`);
  L.push("");
  L.push(`- Что проверено: ${scope} — ${check.length} строк из ${now.length} (реплики, осмотры, варианты, подсказки, цели и журнал, предметы, места).`);
  L.push(`- Против чего: канон CLAUDE.md, data/story/characters.json, Docs/SCENARIO_FINAL.md; русский язык; единообразие.`);
  L.push(`- Модель: \`${model}\`; ${runLine()}; стоимость **$${budget.spent.toFixed(3)}**.`);
  L.push(`- Правок в game/ и data/ проверка не делает; находки разводит координатор.`);
  L.push("");
  if (err) L.push(`**Проверка не выполнена:** ${err}\n`);
  if (input && input.summary) { L.push("## Итог"); L.push(""); L.push(input.summary); L.push(""); }
  if (input) {
    L.push(`## Находки (${findings.length})`);
    L.push("");
    if (!findings.length) L.push("Ошибок не найдено.");
    else {
      L.push("| Важность | Где | Цитата | Что не так | Исправление | Тип |");
      L.push("| --- | --- | --- | --- | --- | --- |");
      for (const f of findings) L.push(`| ${cell(f.severity)} | \`${cell(f.id)}\`${known.has(f.id) ? "" : " (?)"} | ${cell(f.quote)} | ${cell(f.problem)} | ${cell(f.fix)} | ${cell(f.category)} |`);
    }
    L.push("");
  }
  L.push("Где искать строку: id вида `H1.stove.look` — ключ в data/story/text/ru_*.json; `M03.2` — сцена M03, реплика №2 (с нуля) в data/story/scenes/E*.json; `журнал.<флаг>` — data/story/flags.json; `предмет.<id>` — items.json; `место.<id>` — locations.json.");
  const file = reportPath("text_lint");
  fs.writeFileSync(file, L.join("\n") + "\n");
  log(`report ${path.relative(ROOT, file)}: ${findings.length} findings, $${budget.spent.toFixed(3)}${err ? " (error)" : ""}`);
  fs.mkdirSync(path.join(ROOT, "build", "ai_checks"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "build", "ai_checks", "summary.txt"), `текст: ${findings.length} находок (${findings.filter((f) => f.severity === "критично").length} критичных); $${budget.spent.toFixed(2)}`);
}

main().catch((e) => { console.error(`fatal: ${String(e && e.message).slice(0, 200)}`); process.exit(1); });
