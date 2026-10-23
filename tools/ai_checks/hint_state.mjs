#!/usr/bin/env node
// AI check «Hints against the state» (part of the text check, ai_text_lint.yml). The game shows the hints of
// the first undone main scene whose `requires` hold (story_runner.gd → hint_scene), wherever the player is.
// For every main scene the check lays out what is already done when its hints show (each required flag with
// its journal text and the action that sets it — room, place, item), where the scene's own action happens,
// the journal goal of that moment and the three hints, and asks Claude for two defect classes:
//   • «подсказка про уже сделанное» — a hint instructs an action whose result is already in `requires`
//     (D5, 23.10: M03 requires house_unlocked, its hints 1–2 said «ключ из сумки — на дверь дома»);
//   • «подсказка не ведёт к месту» — the scene becomes current somewhere else, and the first hints only say
//     what to do on the spot, not where it is (M3 gate r29, 23.10: day four, M25's hints about the signals at
//     the windlass while Agata is across the river; the way to the turn was in M24's hints, never shown);
//   plus «подсказки нет» (a scene that waits for the player has no hints) and «подсказка про другое».
//
//   node tools/ai_checks/hint_state.mjs [--base <sha>] [--all] [--print] [--model claude-opus-5-5] [--max-usd 3]
//
// --base: only the scenes whose block (requires, setters, hints…) changed since that commit; nothing changed →
// no API call, no report. Report: Docs/ai_checks/hints_<date>.md. Never edits game/ or data/.

import fs from "node:fs";
import path from "node:path";
import { ROOT, args, log, validBase, readAt, listAt, reportPath, askTool, cell, runLine, Budget } from "./common.mjs";

const json = (ref, rel) => { const t = readAt(ref, rel); if (t === null) return null; try { return JSON.parse(t); } catch (_) { return null; } };
const q = (s, n = 220) => { const t = String(s ?? "").replace(/\s+/g, " ").trim(); return t.length > n ? t.slice(0, n) + "…" : t; };

/** Everything the blocks need, read at a ref ("" = working tree). */
function load(ref) {
  const texts = {};
  for (const rel of listAt(ref, "data/story/text").filter((f) => /\/ru_[^/]*\.json$/.test(f))) {
    const d = json(ref, rel);
    for (const [k, v] of Object.entries((d && d.texts) || {})) {
      texts[k] = typeof v === "string" ? v : v && v.line && v.line.text ? v.line.text : v && typeof v.text === "string" ? v.text : "";
    }
  }
  const T = (s) => { if (Array.isArray(s)) return s.map(T).join(" / "); const t = String(s ?? ""); return t.startsWith("@") ? texts[t.slice(1)] ?? t : t; };
  const loc = json(ref, "data/story/locations.json") || {};
  const roomName = {};
  for (const l of loc.locations || []) roomName[l.id] = l.name;
  const R = (id) => (roomName[id] ? `${id} «${roomName[id]}»` : id);
  const itemName = {};
  for (const it of (json(ref, "data/story/items.json") || {}).items || []) itemName[it.id] = it.name;
  const I = (id) => (itemName[id] ? `«${itemName[id]}»` : id);
  const fl = (json(ref, "data/story/flags.json") || {}).flags || {};
  const flagDesc = {};
  for (const [k, v] of Array.isArray(fl) ? fl.map((f) => [f.id, f]) : Object.entries(fl)) flagDesc[k] = (v && v.desc) || "";

  const scenes = [];
  for (const rel of listAt(ref, "data/story/scenes").filter((f) => f.endsWith(".json"))) {
    for (const sc of (json(ref, rel) || {}).scenes || []) scenes.push(sc);
  }
  const byId = Object.fromEntries(scenes.map((s) => [s.id, s]));

  // Who sets a flag / gives an item / starts a scene: rooms (hotspots, exits, item uses, close-ups) and scenes.
  const setters = {}, givers = {}, triggers = {};
  const push = (m, k, v) => { (m[k] || (m[k] = [])).push(v); };
  const how = (via) => {
    const i = via.lastIndexOf("item_use");
    if (i >= 0 && via[i + 1]) return `предмет ${I(via[i + 1])} на это место`;
    if (via.includes("events")) return `в крупном плане (${via[via.indexOf("events") + 1] || "событие"})`;
    if (via.includes("mechanic")) return "в крупном плане";
    if (via.includes("options")) return "выбор ответа";
    if (via.includes("talk")) return "разговор";
    if (via.includes("look")) return "осмотр";
    if (via.includes("on_enter")) return "при входе";
    if (via.includes("use")) return "щелчок";
    return via.filter((k) => !/^\d+$/.test(k)).slice(-1)[0] || "";
  };
  const walk = (node, room, spot, via) => {
    if (Array.isArray(node)) { node.forEach((x, i) => walk(x, room, spot, [...via, String(i)])); return; }
    if (!node || typeof node !== "object") return;
    let sp = spot;
    if (typeof node.id === "string" && (node.label || node.kind)) sp = T(node.label) || node.id;
    else if (typeof node.to === "string" && node.label) sp = `выход «${T(node.label)}»`;
    const where = { rooms: [room], text: `${R(room)} → «${sp || "комната"}»${how(via) ? `, ${how(via)}` : ""}` };
    for (const f of Array.isArray(node.sets) ? node.sets : []) push(setters, f, where);
    for (const it of Array.isArray(node.gives) ? node.gives : []) push(givers, it, where);
    if (typeof node.scene === "string") push(triggers, node.scene, where);
    for (const [k, v] of Object.entries(node)) if (k !== "sets" && k !== "gives" && !k.startsWith("_")) walk(v, room, sp, [...via, k]);
  };
  for (const rel of listAt(ref, "data/story/rooms").filter((f) => f.endsWith(".json") && !/\/_/.test(f))) {
    const d = json(ref, rel);
    if (d) walk(d, d.id || path.basename(rel, ".json"), "", []);
  }
  for (const sc of scenes) {
    const tag = `сцена ${sc.id} «${sc.title || ""}»${(sc.locations || []).length ? ` (${sc.locations.map(R).join(", ")})` : ""}`;
    const at = { rooms: sc.locations || [], text: tag };
    for (const f of (sc.grants && sc.grants.flags) || []) push(setters, f, at);
    for (const it of (sc.grants && sc.grants.items) || []) push(givers, it, at);
    for (const st of sc.stage || []) for (const f of st.sets || []) push(setters, f, { ...at, text: `${tag}, по ходу` });
  }
  const texts_ = (list, n) => [...new Set((list || []).map((w) => w.text))].slice(0, n).join("; ");
  // Where the scene's own action is, and where the player stands when it becomes the hint scene (the rooms
  // where its requirements get done). Disjoint → the first hint has to say where to go (class 2).
  const actionRooms = (sc) => new Set([...(sc.locations || []), ...(triggers[sc.id] || []).flatMap((w) => w.rooms)]);
  const playerRooms = (sc) => {
    const out = new Set();
    for (const f of (sc.requires && sc.requires.flags) || []) {
      const m = /^done_(.+)$/.exec(f);
      if (m && byId[m[1]]) for (const r of actionRooms(byId[m[1]])) out.add(r);
      else for (const w of setters[f] || []) for (const r of w.rooms) out.add(r);
    }
    for (const it of (sc.requires && sc.requires.items) || []) for (const w of givers[it] || []) for (const r of w.rooms) out.add(r);
    return out;
  };

  // One block per main scene, in game order.
  const blocks = [];
  for (const sc of scenes.filter((s) => s.type === "main")) {
    const L = [];
    L.push(`[${sc.id}] «${sc.title || ""}» — место действия: ${(sc.locations || []).map(R).join(", ") || "—"}`);
    const tr = triggers[sc.id] || [];
    if (tr.length) L.push(`  Действие сцены запускается: ${texts_(tr, 6)}`);
    if (sc.puzzle && sc.puzzle.solution) L.push(`  Решение: ${q(sc.puzzle.solution, 260)}`);
    const req = sc.requires || {};
    const rf = req.flags || [], ri = req.items || [];
    L.push("  Подсказки этой сцены показываются, когда УЖЕ выполнено:");
    if (!rf.length && !ri.length) L.push("    (ничего — с начала игры)");
    for (const f of rf) {
      const m = /^done_(.+)$/.exec(f);
      if (m && byId[m[1]]) {
        const p = byId[m[1]];
        L.push(`    - ${f}: сцена ${p.id} «${p.title || ""}» пройдена (место: ${(p.locations || []).map(R).join(", ") || "—"}; её цель в журнале: «${q(p.goal, 200)}»)`);
      } else {
        L.push(`    - ${f}${flagDesc[f] ? `: «${q(flagDesc[f], 200)}»` : ""} — ставится (это действие УЖЕ сделано): ${texts_(setters[f], 4) || "?"}`);
      }
    }
    for (const it of ri) L.push(`    - в сумке ${I(it)} — даёт: ${texts_(givers[it], 3) || "?"}`);
    const S = actionRooms(sc), P = playerRooms(sc);
    if (P.size && S.size && ![...P].some((r) => S.has(r))) {
      L.push(`  ⚠ Сцена становится текущей НЕ там, где её действие: игрок в этот момент — ${[...P].map(R).join(", ")}; действие — ${[...S].map(R).join(", ")}. Подсказка 1 должна назвать, куда идти.`);
    }
    L.push(`  Цель этой сцены (в журнале после неё): «${q(sc.goal, 240)}»`);
    const hints = Array.isArray(sc.hints) ? sc.hints : sc.hint ? [sc.hint] : [];
    if (hints.length) hints.forEach((h, i) => L.push(`  Подсказка ${i + 1}: «${T(h)}»`));
    else L.push("  Подсказок нет — игра покажет общие («Осмотрись…»)");
    blocks.push({ id: sc.id, text: L.join("\n") });
  }
  return blocks;
}

async function main() {
  const A = args();
  const base = A.all ? "" : validBase(A.base || "");
  // claude-sonnet-5-5 at medium effort (first run, 23.10, $0.04) missed M25 and listed «не дефект» as findings.
  const model = A.model || "claude-opus-5-5";
  const budget = new Budget(Math.min(10, Number(A["max-usd"] || 3)));
  const now = load("");
  let check = now, scope = "все основные сцены";
  if (base) {
    const before = new Map(load(base).map((b) => [b.id, b.text]));
    check = now.filter((b) => before.get(b.id) !== b.text);
    scope = `сцены, у которых с ${base.slice(0, 7)} изменились условия, подсказки или то, что их ставит`;
  }
  log(`main scenes: ${now.length}, to check: ${check.length} (${scope}), model ${model}`);
  fs.mkdirSync(path.join(ROOT, "build", "ai_checks"), { recursive: true });
  if (!check.length) { log("nothing changed — no report"); return; }
  if (A.print) { console.log(check.map((b) => b.text).join("\n\n")); return; }   // the blocks only, no API

  const tool = {
    name: "report",
    description: "Итог: сводка и находки по подсказкам.",
    input_schema: {
      type: "object",
      properties: {
        summary: { type: "string", description: "2–3 фразы: общее состояние подсказок, главное. Только то, что есть в findings." },
        place_checks: {
          type: "array",
          description: "По КАЖДОЙ сцене с пометкой ⚠: называет ли подсказка 1 место, куда идти (комнату или узнаваемый ориентир), или путь туда.",
          items: {
            type: "object",
            properties: {
              scene: { type: "string" },
              names_place: { type: "boolean" },
              note: { type: "string", description: "коротко: какое место названо или чего не хватает" },
            },
            required: ["scene", "names_place", "note"],
          },
        },
        findings: {
          type: "array",
          items: {
            type: "object",
            properties: {
              scene: { type: "string", description: "id сцены, как во входе (M03)" },
              hint: { type: "integer", description: "номер подсказки 1–3; 0 — если подсказок нет" },
              quote: { type: "string", description: "дословно подсказка (или «нет подсказок»)" },
              class: { type: "string", enum: ["подсказка про уже сделанное", "подсказка не ведёт к месту", "подсказки нет", "подсказка про другое"] },
              why: { type: "string", description: "почему: какое условие из «уже выполнено» это делает (флаг и что он значит) или где игрок в этот момент" },
              fix: { type: "string", description: "готовый вариант подсказки (или что сделать)" },
              severity: { type: "string", enum: ["важно", "мелочь"] },
            },
            required: ["scene", "hint", "quote", "class", "why", "fix", "severity"],
          },
        },
      },
      required: ["summary", "place_checks", "findings"],
    },
  };
  const system = `Ты проверяешь подсказки point-and-click игры «Дом пропавших дорог». Кнопка «Подсказка» показывает подсказки (по одной, 1 → 2 → 3) первой непройденной основной сцены, у которой выполнены все условия requires, — где бы игрок ни стоял. Поэтому всё, что перечислено в «уже выполнено», на момент показа подсказок УЖЕ сделано, а игрок может быть в любой комнате — обычно там, где выполнил последнее из условий.
Для каждой сцены входа найди только настоящие дефекты этих классов:
1. «подсказка про уже сделанное» — подсказка велит сделать то, результат чего уже есть в «уже выполнено» (или прямо вытекает из него). Пример (дефект D5): сцена в избе требует house_unlocked («ключ открыл дверь дома»), а подсказки 1–2 — «Тётин дом — на улице; ключ от него в сумке», «Ключ из сумки — на дверь дома». Игрок уже в доме и идёт снова к двери.
2. «подсказка не ведёт к месту» — сцены с пометкой ⚠: сцена становится текущей не там, где её действие (программа посчитала это по данным). Если подсказка 1 говорит только, что делать на месте, и не называет, куда идти, — дефект. Пример: утро четвёртого дня, Агата в Ольховке за рекой, а подсказки сцены у поворота — только про сигналы «Пускай/Стой/Подымай» у ворота. Если подсказка 1 называет место (комнату, дом, мельницу, причал или узнаваемый ориентир, как в цели журнала) — не дефект. По каждой сцене с ⚠ дай запись в place_checks.
3. «подсказки нет» — у сцены нет подсказок, а она ждёт действия игрока (не начинается и не идёт сама).
4. «подсказка про другое» — подсказка явно о задаче другой сцены (уже пройденной или ещё не открытой).
В findings — только дефекты: если, разобравшись, видишь, что всё в порядке, — не включай. Не придирайся к стилю и литературе, не повторяй одну находку на несколько подсказок одной сцены — укажи первую. Важность: «важно» — подсказка уводит игрока не туда или оставляет без пути; «мелочь» — неточность, с которой игрок всё же справится. Если дефектов нет — пустой список. Ответ — только вызовом инструмента report.`;
  const user = `ОСНОВНЫЕ СЦЕНЫ ДЛЯ ПРОВЕРКИ (${check.length} из ${now.length}, в порядке игры):\n\n${check.map((b) => b.text).join("\n\n")}\n\nОтветь вызовом инструмента report.`;

  let input = null, err = "";
  try {
    input = await askTool(budget, "hints", { model, max_tokens: 16000, system, tools: [tool], thinking: { type: "adaptive" }, output_config: { effort: "medium" },
      messages: [{ role: "user", content: user }] }, "report");
    if (!input) err = "модель не вернула отчёт инструментом";
  } catch (e) { err = String(e.message || e); }

  const known = new Set(now.map((b) => b.id));
  const findings = ((input && input.findings) || []).filter((f) => f && f.scene && !/^\s*(без изменений|не дефект|оставить как есть)/i.test(String(f.fix || "")));
  // A ⚠ scene judged «does not name the place» but missing from findings — added from place_checks.
  for (const c of (input && input.place_checks) || []) {
    if (c && c.scene && c.names_place === false && !findings.some((f) => f.scene === c.scene && f.class === "подсказка не ведёт к месту")) {
      findings.push({ scene: c.scene, hint: 1, quote: "", class: "подсказка не ведёт к месту", why: c.note || "", fix: "первая подсказка — куда идти", severity: "важно" });
    }
  }
  const sev = { "важно": 0, "мелочь": 1 };
  const order = new Map(now.map((b, i) => [b.id, i]));
  findings.sort((a, b) => (sev[a.severity] ?? 2) - (sev[b.severity] ?? 2) || (order.get(a.scene) ?? 999) - (order.get(b.scene) ?? 999));
  const L = [];
  L.push(`# ИИ-проверка подсказок против состояния — ${new Date().toISOString().slice(0, 10)}`);
  L.push("");
  L.push(`- Что проверено: ${scope} — ${check.length} из ${now.length} (data/story/scenes: requires, hints, goal; data/story/rooms — что ставит условия).`);
  L.push("- Правило игры: «Подсказка» показывает подсказки первой непройденной основной сцены, у которой выполнены requires (story_runner.gd → hint_scene), — где бы игрок ни был.");
  L.push("- Классы дефектов: **подсказка про уже сделанное** (велит сделать то, что уже есть в requires; D5 — M03 «ключ на дверь» при house_unlocked), **подсказка не ведёт к месту** (сцена становится текущей в другом месте, а подсказки — только про действие на месте; M25 в день четвёртый), **подсказки нет**, **подсказка про другое**.");
  L.push(`- Модель: \`${model}\`; ${runLine()}; стоимость **$${budget.spent.toFixed(3)}**. Правок в game/ и data/ нет; находки разводит координатор.`);
  L.push("");
  if (err) L.push(`**Проверка не выполнена:** ${err}\n`);
  if (input && input.summary) { L.push("## Итог"); L.push(""); L.push(input.summary); L.push(""); }
  const pc = (input && input.place_checks) || [];
  if (pc.length) {
    L.push(`Сцены, которые становятся текущими не там, где их действие (⚠, по данным): ${pc.length}; подсказка 1 называет место — ${pc.filter((c) => c.names_place).length}: ${pc.map((c) => `\`${cell(c.scene)}\` ${c.names_place ? "да" : "**нет**"}`).join(", ")}.`);
    L.push("");
  }
  if (input) {
    L.push(`## Находки (${findings.length})`);
    L.push("");
    if (!findings.length) L.push("Дефектов не найдено.");
    else {
      L.push("| Важность | Сцена | № | Подсказка | Класс | Почему | Как поправить |");
      L.push("| --- | --- | --- | --- | --- | --- | --- |");
      for (const f of findings) L.push(`| ${cell(f.severity)} | \`${cell(f.scene)}\`${known.has(f.scene) ? "" : " (?)"} | ${f.hint || "—"} | ${cell(f.quote)} | ${cell(f.class)} | ${cell(f.why)} | ${cell(f.fix)} |`);
    }
    L.push("");
  }
  L.push("Где поправить: `data/story/scenes/E*.json` → сцена → `hints` (три строки, от общего к точному; первая — куда идти, если сцена начинается не там, где игрок).");
  const file = reportPath("hints");
  fs.writeFileSync(file, L.join("\n") + "\n");
  const imp = findings.filter((f) => f.severity === "важно").length;
  log(`report ${path.relative(ROOT, file)}: ${findings.length} findings (${imp} important), $${budget.spent.toFixed(3)}${err ? " (error)" : ""}`);
  fs.writeFileSync(path.join(ROOT, "build", "ai_checks", "summary_hints.txt"), `подсказки: ${findings.length} находок (${imp} важных); $${budget.spent.toFixed(2)}`);
}

main().catch((e) => { console.error(`fatal: ${String(e && e.message).slice(0, 200)}`); process.exit(1); });
