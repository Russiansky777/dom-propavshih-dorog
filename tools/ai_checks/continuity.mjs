#!/usr/bin/env node
// AI check «Whole-game continuity read» (one-off, before the voices are final): the best long-context model reads
// the WHOLE game text in story order — every scene E0–E5 (all episodes of the game, M01…M26 and the epilogue) with
// its mandatory lines and their conditions, the NPC lines and room texts by flag state (rooms in the order the story
// first reaches them), Agata's thoughts and the narrator, item names and examine texts, the side stories Q01–Q10
// (reserve ones marked), the journal goals, facts and hints — plus Docs/SCENARIO_FINAL.md and the canon of CLAUDE.md,
// and reports with exact keys and verbatim quotes:
//   1. continuity — who knows what when, a line contradicting an earlier one, ages / names / time maths;
//   2. character voice — tone breaks per character (Тихон sarcastic and lazy, Павел dry, …) and repeated jokes/lines;
//   3. TTS — stress and pronunciation risks for the voice recording (ё, homographs, names, numbers, abbreviations).
// A goal explained only after it is required is reported under continuity.
//
//   node tools/ai_checks/continuity.mjs [--model claude-fable-5-1] [--effort high] [--max-usd 15]
//        [--passes continuity,voices,tts] [--max-tokens 80000] [--dump build/ai_checks/continuity_corpus.txt] [--dump-only] [--dry]
//
// --dump writes the corpus to a file (--dump-only: and stops, no API); --dry stops after the cost estimate.
// The three passes share one cached prefix (system + corpus): the first call writes the cache, the other two start
// once its stream has begun and read it (≈2.5 % of the input price). Before every call the estimate must fit
// under --max-usd together with what is already spent; otherwise the pass is skipped and the report says so.
// A model the API refuses (400 / not found / overloaded for good) falls back to claude-opus-5-5 once.
// Report: Docs/ai_checks/continuity_<date>.md (+ continuity_<date>.json — the findings for routing).
// Never edits game/ or data/. The key and the workspace ID never reach stdout or the report.

import fs from "node:fs";
import path from "node:path";
import { ROOT, args, log, canonText, readDoc, reportPath, cell, runLine, Budget, redact } from "./common.mjs";
import { callTool, ApiError, PRICES, priceKnown } from "../ai_playtest/claude.mjs";

const jf = (rel) => { try { return JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8")); } catch (_) { return null; } };

// --- The corpus -------------------------------------------------------------------------------------------------

const SPEAK = { agata: "Агата", tamara: "Тамара", pelageya: "Пелагея", tikhon: "Тихон", nina: "Нина", ilya: "Илья",
  ulyana: "Ульяна", mitya: "Митя", pavel: "Павел", narrator: "Закадровый голос", varvara: "Варвара", manager: "Фёдор Лукич",
  fedor: "Фёдор Лукич", fyodor: "Фёдор Лукич", aksinya: "Аксинья" };
const who = (s) => SPEAK[s] || s || "";

// Keys of room data that are geometry, art, sound or layout — never text the player reads.
const DROP = new Set(["walkable", "walkable_holes", "walkable_interior", "walkable_exterior", "no_walk_samples", "walk_samples",
  "depth", "depth_exterior", "height_refs", "rect", "polygon", "effects", "offset", "scale", "pivot", "modulate", "spin",
  "rotation_deg", "background", "props", "image", "images", "occluder", "z", "cue", "cue_dir", "cue_at", "lights", "stand",
  "color", "draw", "pick_priority", "action_anim", "art", "art_source", "clearance", "nearest_checks", "spawns", "spawn",
  "layers", "sounds", "sound", "synth_sound", "files", "canvas", "feet", "shadow", "horizon", "floor_foreshortening",
  "region", "open_region", "view", "timing_rect", "timing", "bar", "patch", "glass_quad", "glass_polygon", "reflection",
  "poses", "room_art", "anchor", "positions", "marks_pos", "hint_pos", "status_pos", "schedule_pos", "legend_pos", "text_rect",
  "bbox", "size", "tint", "compose", "frame", "font", "font_size", "align", "fade", "zoom_from", "stage", "stage_note",
  "door_hinges", "door_leaf", "hinge_pos", "beam", "light", "lantern_box", "ring", "skoba_box", "knot_path", "strokes",
  "wedges", "water", "levels", "gauge_rect", "clock_face", "pendulum", "hand_min", "hand_hour", "flame", "watch_dial",
  "loupe", "gallery", "row", "border", "haze", "waviness", "resolution", "tray", "handle", "drag", "slots", "pieces",
  "winter_view", "snow", "breath", "opening", "hit", "pos", "edge", "crop", "paper", "board", "sheet", "blocks", "porch"]);

/** Every text of data/story/text/ru_*.json: key → {text, speaker, tags, voice_text, draft, file}. */
function loadTexts() {
  const T = new Map();
  const files = fs.readdirSync(path.join(ROOT, "data/story/text")).filter((f) => /^ru_.*\.json$/.test(f));
  const order = ["ru_E0_E1.json", "ru_E2_E3.json", "ru_E4_E5.json", "ru_bag.json", "ru_mechanics.json", "ru_exits.json", "ru_map.json", "ru_world.json"];
  files.sort((a, b) => ((order.indexOf(a) + 1) || 99) - ((order.indexOf(b) + 1) || 99) || a.localeCompare(b));
  for (const f of files) {
    const d = jf(`data/story/text/${f}`);
    for (const [k, v] of Object.entries((d && d.texts) || {})) {
      if (typeof v === "string") { T.set(k, { text: v, file: f }); continue; }
      if (!v || typeof v !== "object") continue;
      const e = { text: v.text || "", file: f, tags: v.tags || null, voice_text: v.voice_text || "", draft: !!v.draft };
      if (v.line && v.line.text) { e.text = v.line.text; e.speaker = v.line.speaker || ""; e.tags = v.line.tags || e.tags; e.voice_text = v.line.voice_text || e.voice_text; }
      for (const lk of ["label", "prompt", "title"]) if (v[lk]) e[lk] = v[lk];
      T.set(k, e);
    }
  }
  return T;
}

export function buildCorpus() {
  const T = loadTexts();
  const chars = (jf("data/story/characters.json") || {}).characters || [];
  const charName = Object.fromEntries(chars.map((c) => [c.id, c.name]));
  for (const c of chars) if (!SPEAK[c.id]) SPEAK[c.id] = c.name;
  const used = new Set();
  const keys = new Set();   // every id the report may cite
  const tags = (t) => (t && t.length ? ` (${t.join(", ")})` : "");
  const tref = (ref) => {
    const key = String(ref).replace(/^@/, "");
    if (/^char\./.test(key)) return `«${charName[key.slice(5)] || key.slice(5)}»`;
    const t = T.get(key);
    used.add(key);
    keys.add(key);
    if (!t) return `⟨${key}: текста нет⟩`;
    return `${t.speaker ? `${who(t.speaker)}: ` : ""}«${t.text}»${tags(t.tags)}${t.voice_text ? ` [для озвучки: ${t.voice_text}]` : ""}${t.draft ? " (черновик)" : ""} ⟨${key}⟩`;
  };
  const val = (v) => (typeof v === "string" && v.startsWith("@") ? tref(v) : String(v));
  const isNumArr = (v) => Array.isArray(v) && v.every((x) => typeof x === "number" || (Array.isArray(x) && isNumArr(x)) || x === null);
  const isFile = (s) => /^res:\/\/|\.(png|jpg|ogg|wav|glb|svg|webp)$|^#[0-9a-f]{3,8}$/i.test(s);   // files and colours

  /** Generic room / puzzle renderer: conditions and texts only, @refs resolved, geometry and art dropped. */
  const render = (o, ind, out) => {
    const pad = "  ".repeat(ind);
    if (Array.isArray(o)) {
      for (const x of o) {
        if (x && typeof x === "object" && !Array.isArray(x)) {
          const sub = [];
          render(x, ind + 1, sub);
          if (sub.length) { out.push(`${pad}-${sub[0].slice(pad.length + 1)}`); out.push(...sub.slice(1)); }
        } else if (typeof x === "string" && !isFile(x)) out.push(`${pad}- ${val(x)}`);
      }
      return;
    }
    for (const [k, v] of Object.entries(o)) {
      if (k.startsWith("_") || DROP.has(k) || v === null || v === undefined) continue;
      if (typeof v === "number" || typeof v === "boolean") { if (k === "exclusive" && v) out.push(`${pad}${k}: да`); continue; }
      if (typeof v === "string") { if (!isFile(v) && v.trim()) out.push(`${pad}${k}: ${val(v)}`); continue; }
      if (isNumArr(v)) continue;
      if (Array.isArray(v) && v.every((x) => typeof x === "string")) {
        const s = v.filter((x) => !isFile(x));
        if (!s.length) continue;
        if (s.some((x) => x.startsWith("@"))) { out.push(`${pad}${k}:`); for (const x of s) out.push(`${pad}  - ${val(x)}`); }
        else out.push(`${pad}${k}: ${s.join(", ")}`);
        continue;
      }
      const sub = [];
      render(v, ind + 1, sub);
      if (sub.length) { out.push(`${pad}${k}:`); out.push(...sub); }
    }
  };
  const cond = (x) => {
    const p = [];
    if (x.if) p.push(`если: ${[].concat(x.if).join(" + ")}`);
    if (x.if_any) p.push(`если хоть один: ${[].concat(x.if_any).join(" / ")}`);
    if (x.unless) p.push(`кроме: ${[].concat(x.unless).join(" / ")}`);
    return p.length ? ` {${p.join("; ")}}` : "";
  };
  const flagsOf = (r) => [...((r && r.flags) || []), ...((r && r.items) || []).map((i) => `предмет ${i}`)].join(", ") || "—";

  const L = [];
  // 1. Scenes in story order.
  const sceneFiles = fs.readdirSync(path.join(ROOT, "data/story/scenes")).filter((f) => /^E\d+\.json$/.test(f))
    .sort((a, b) => Number(a.slice(1, -5)) - Number(b.slice(1, -5)));
  const roomOrder = [];
  L.push("############ ЧАСТЬ 1. ОСНОВНОЙ СЮЖЕТ — СЦЕНЫ ПО ПОРЯДКУ (data/story/scenes/E*.json)");
  L.push("Формат: == <id сцены> «название» [тип]; места; требует (флаги/предметы); даёт. Строки: [<сцена>.<номер>] Кто (теги подачи): «реплика» {условие показа}. Выбор: [<сцена>.<номер>.<вариант>]. «цель журнала» — что журнал пишет в «Что дальше» ПОСЛЕ этой сцены; «подсказки» — кнопка «Подсказка», пока сцена текущая. «Ремарка» — описание для разработчиков, игрок его не видит.");
  for (const f of sceneFiles) {
    const d = jf(`data/story/scenes/${f}`) || {};
    L.push(`\n=================== ${f.replace(".json", "")}: «${d.title || ""}»${d.premise ? ` — ${d.premise}` : ""}`);
    for (const sc of d.scenes || []) {
      for (const r of sc.locations || []) if (!roomOrder.includes(r)) roomOrder.push(r);
      L.push(`\n== ${sc.id} «${sc.title || ""}» [${sc.type || ""}]; места: ${(sc.locations || []).join(", ") || "—"}; требует: ${flagsOf(sc.requires)}; даёт: ${flagsOf(sc.grants)}${sc.consumes ? `; тратит: ${flagsOf(sc.consumes)}` : ""}`);
      if (sc.actions && sc.actions.length) L.push(`   Ремарка (действия игрока): ${sc.actions.join(" / ")}`);
      if (sc.summary) L.push(`   Ремарка: ${sc.summary}`);
      if (sc.facts_revealed && sc.facts_revealed.length) L.push(`   Ремарка (что игрок узнаёт): ${sc.facts_revealed.join(" / ")}`);
      for (const k of ["puzzle", "mechanics", "end_frame", "checkpoint"]) {
        if (!sc[k]) continue;
        const sub = [];
        if (typeof sc[k] === "string") sub.push(`      ${val(sc[k])}`); else render(sc[k], 3, sub);
        if (sub.length) { L.push(`   ${k}:`); L.push(...sub); }
      }
      (sc.mandatory_lines || []).forEach((ln, i) => {
        const id = `${sc.id}.${i}`;
        keys.add(id);
        if (ln.options) {
          L.push(`   [${id}] ВЫБОР${ln.prompt ? ` «${ln.prompt}»` : ""}${ln.speaker ? ` (отвечает ${who(ln.speaker)})` : ""}${cond(ln)}:`);
          for (const o of ln.options) {
            keys.add(`${id}.${o.id}`);
            L.push(`      [${id}.${o.id}] вариант «${o.label || ""}»${o.text ? ` → ${who(ln.speaker)}: «${o.text}»` : ""}${o.voice_text ? ` [для озвучки: ${o.voice_text}]` : ""}${o.sets ? ` (ставит ${o.sets})` : ""}`);
          }
          return;
        }
        L.push(`   [${id}] ${who(ln.speaker)}${tags(ln.tags)}: «${ln.text || ""}»${ln.voice_text ? ` [для озвучки: ${ln.voice_text}]` : ""}${cond(ln)}`);
      });
      if (sc.goal) { keys.add(`${sc.id}.цель_журнала`); L.push(`   [${sc.id}.цель_журнала] «${sc.goal}»`); }
      (sc.hints || []).forEach((h, i) => { keys.add(`${sc.id}.подсказка${i + 1}`); L.push(`   [${sc.id}.подсказка${i + 1}] «${h}»`); });
      if (sc.proposed_change) L.push(`   Ремарка (предложенная правка, не в игре): ${typeof sc.proposed_change === "string" ? sc.proposed_change : JSON.stringify(sc.proposed_change)}`);
    }
  }

  // 2. Rooms in the order the story first reaches them, then the rest (epilogue frames, mirror views).
  const roomFiles = fs.readdirSync(path.join(ROOT, "data/story/rooms")).filter((f) => /^[A-Z].*\.json$/.test(f)).map((f) => f.slice(0, -5));
  const rooms = [...roomOrder.filter((r) => roomFiles.includes(r)), ...roomFiles.filter((r) => !roomOrder.includes(r)).sort()];
  const locs = Object.fromEntries((((jf("data/story/locations.json") || {}).locations) || []).map((l) => [l.id, l.name]));
  L.push("\n\n############ ЧАСТЬ 2. КОМНАТЫ: ЧТО ИГРОК ЧИТАЕТ И СЛЫШИТ ПРИ НАВЕДЕНИИ, ОСМОТРЕ, ДЕЙСТВИИ, РАЗГОВОРЕ (data/story/rooms/*.json)");
  L.push("Порядок — как сюжет впервые приводит в комнату. label — подпись при наведении; look — осмотр; use — действие; talk.scene — разговор запускает сцену из части 1; choice — вопросы игрока (requires — когда доступны), options — варианты и ответы; states — другой текст/подпись при флагах (if); visible_if / hidden_if — когда хотспот есть; item_use — предмет из сумки на этот объект; exits — выходы (closed_text — почему закрыт). Каждый текст — «…» ⟨ключ⟩; ключ — это id для находок.");
  for (const r of rooms) {
    const d = jf(`data/story/rooms/${r}.json`);
    if (!d) continue;
    const sub = [];
    render({ title: d.title, hotspots: d.hotspots, exits: d.exits, on_enter: d.on_enter, complete_when: d.complete_when, puzzle: d.puzzle }, 1, sub);
    if (!sub.length) continue;
    L.push(`\n=== Комната ${r}${locs[r] ? ` «${locs[r]}»` : ""}`);
    L.push(...sub);
  }

  // 3. Items: name, examine, wrong target.
  L.push("\n\n############ ЧАСТЬ 3. ПРЕДМЕТЫ (data/story/items.json): название, «Рассмотреть», реакция «не туда»");
  for (const it of ((jf("data/story/items.json") || {}).items) || []) {
    keys.add(`предмет.${it.id}`);
    const p = [`[предмет.${it.id}] «${it.name || ""}»${it.inventory === false ? " (не в сумке)" : ""}; откуда: ${it.source_location || "—"}/${it.source_scene || "—"}; ремарка: ${it.use || ""}`];
    const sub = [];
    render({ examine: it.examine, wrong_target: it.wrong_target, texts: it.texts }, 2, sub);
    L.push(p[0]);
    L.push(...sub);
  }

  // 4. Side stories.
  const qd = jf("data/story/quests.json") || {};
  L.push(`\n\n############ ЧАСТЬ 4. НЕОБЯЗАТЕЛЬНЫЕ ИСТОРИИ (data/story/quests.json). Доступны после requires и до флага ${qd.closes_on || "?"}. Резервные (reserve) — в игре пока нет запусков в комнатах; Директор 23.10: Q02 и Q06 включаются, Q05 и Q10 — нет.`);
  for (const q of qd.quests || []) {
    L.push(`\n== ${q.id} «${q.title || ""}»${q.reserve ? " (резерв)" : ""}; места: ${(q.locations || []).join(", ")}; требует: ${flagsOf(q.requires)}`);
    (q.steps || []).forEach((s, i) => { keys.add(`квест.${q.id}.шаг${i + 1}`); L.push(`   [квест.${q.id}.шаг${i + 1}] ${typeof s === "string" ? s : (s && s.text) || ""}`); });
    (q.lines || []).forEach((ln, i) => { keys.add(`квест.${q.id}.реплика${i + 1}`); L.push(`   [квест.${q.id}.реплика${i + 1}] ${who(ln.speaker)}${tags(ln.tags)}: «${ln.text || ""}»${ln.voice_text ? ` [для озвучки: ${ln.voice_text}]` : ""}${cond(ln)}`); });
    if (q.choice) for (const o of q.choice.options || []) L.push(`   выбор ${q.choice.id}.${o.id} (ставит ${o.sets}): след в эпилоге — ${o.epilogue || "—"}`);
    if (q.if_skipped) L.push(`   если пропустить: ${q.if_skipped}`);
  }

  // 5. The journal: facts (flag descriptions) and achievements.
  const fl = (jf("data/story/flags.json") || {}).flags || {};
  L.push("\n\n############ ЧАСТЬ 5. ЖУРНАЛ «ЧТО Я ЗНАЮ» (data/story/flags.json): запись появляется, когда флаг поставлен (сцена или комната, что его ставит — части 1–2)");
  for (const [k, v] of Array.isArray(fl) ? fl.map((f) => [f.id, f]) : Object.entries(fl)) {
    if (!v || !v.desc) continue;
    keys.add(`журнал.${k}`);
    L.push(`[журнал.${k}] «${v.desc}»`);
  }
  const ach = (jf("data/story/achievements.json") || {}).achievements || [];
  if (ach.length) {
    L.push("\nЭкран конца «Что осталось от твоих выборов» (data/story/achievements.json):");
    for (const a of ach) { const sub = []; render(a, 1, sub); L.push(...sub); }
  }

  // 6. Every other text: interface, close-ups, mechanics, bag, map — by file.
  L.push("\n\n############ ЧАСТЬ 6. ОСТАЛЬНЫЕ ТЕКСТЫ (интерфейс, крупные планы, механики, сумка, карта, общие реакции; data/story/text/ru_*.json), по файлам");
  let curFile = "";
  for (const [k, t] of T) {
    if (used.has(k)) continue;
    if (t.file !== curFile) { curFile = t.file; L.push(`\n--- ${curFile}`); }
    keys.add(k);
    L.push(`${t.speaker ? `${who(t.speaker)}: ` : ""}«${t.text}»${tags(t.tags)}${t.voice_text ? ` [для озвучки: ${t.voice_text}]` : ""} ⟨${k}⟩`);
  }
  return { text: L.join("\n"), keys, textCount: T.size };
}

// --- The passes ---------------------------------------------------------------------------------------------------

const PASSES = {
  continuity: {
    title: "Непрерывность, канон, порядок целей",
    cats: ["кто что знает", "противоречие раньше сказанному", "канон: возраст/имя/время", "цель после требования", "другое"],
    ask: `ЗАДАНИЕ (проход 1 — НЕПРЕРЫВНОСТЬ). Прочитай игру по порядку, как игрок, который проходит всё, и отслеживай, что каждый персонаж и игрок знает в каждый момент. Найди:
1. «кто что знает» — персонаж (или Агата в мыслях, или журнал) называет факт, имя, место или предмет, которого он к этому моменту знать не может: о нём ещё не сказали, его ещё не нашли, это знает только другой берег (помни: до каната дороги нет, Ольховка и Заречье не слышат друг друга, зеркало показывает только вид, не звук). Реплика, которую можно увидеть ДО события, о котором она говорит (по условиям requires / if / visible_if), — тоже сюда.
2. «противоречие раньше сказанному» — поздняя строка противоречит ранней (сколько лет прошло, кто где был в день паводка, что сломано, чья вещь, кто кого как зовёт, что уже починено), или две строки одного момента говорят разное; журнал «что я знаю» противоречит репликам.
3. «канон: возраст/имя/время» — возраст, родство, имя, разница в годах, счёт времени 20:1 (снаружи год, внутри двадцать; Митя был 17, стал 37; Ульяне 8 — родилась внутри после разрыва), «Дарья» — против канона и сценария. Считай: «двадцать лет» внутри, «год» снаружи, Евдокия умерла за два местных (заречных) года до событий.
4. «цель после требования» — игра требует действие (закрытый выход, предмет, механика, условие сцены), а объясняет, зачем и что делать, позже — или не объясняет вовсе; подсказка или цель журнала называет то, что игрок ещё не видел.
Не ищи опечатки и пунктуацию (это делает другая проверка). Не предлагай литературную переделку. Каждая находка — с ключами ВСЕХ строк, которые сталкиваются (поздняя первой), дословными цитатами и объяснением по порядку сюжета.`,
  },
  voices: {
    title: "Голоса персонажей и повторы",
    cats: ["тон персонажа", "повтор", "другое"],
    ask: `ЗАДАНИЕ (проход 2 — ГОЛОСА И ПОВТОРЫ). Прочитай все реплики каждого персонажа подряд (по ключам), сверяя с его характером ниже и в сценарии. Найди:
1. «тон персонажа» — реплика выпадает из характера: Тихон — печной зверёк-смотритель с кошачьими повадками, ворчливый, ленивый, любит поесть, саркастичный; не подсказчик (не объясняет игроку, что делать), не милый питомец, не сюсюкает. Павел — сухой, деловой, короткие фразы, чувство прячет. Нина — учительская точность, спокойствие, двадцать лет усталости без жалобы, не сентиментальничает. Агата — наблюдательная, любопытная, упрямая, собранная, тихая самоирония; ей 18 — не взрослая начальница и не ребёнок. Илья — старше сестры на 14 лет, вырос внутри (ему было 12, стало 32), отец Ульяны. Ульяна — 8 лет, говорит как ребёнок восьми лет, не как взрослая и не как малыш. Митя — 37, вырос на посту у фонаря. Пелагея — мать Мити, лодочница, твёрдая. Тамара — почтальонша, Дунина подруга, тёплая и практичная. Закадровый голос — нейтральный рассказчик осмотров, без шуток от первого лица. Время и место: русская деревня, начало XX века — современные слова, канцелярит и англицизмы («окей», «проблема», «ресурс», «локация», «функционал»…) — выпадение. Отмечай также реплику, отданную не тому персонажу (по смыслу её должен говорить другой).
2. «повтор» — одна и та же шутка, формула, образ или фраза звучит больше одного раза в местах, где игрок услышит оба (особенно повторные реакции, осмотры одинаковых вещей, одни и те же слова у разных героев); дословные дубли строк с разными ключами; одно и то же слово-паразит у персонажа, которое заметно надоест. Укажи все ключи повтора. Повтор, который явно задуман как рефрен (закон мира «Вещи помнят место…», «Дорогу держат с двух концов», сигналы «Пускай/Стой/Подымай»), — не дефект, если звучит к месту.
Каждая находка — ключи, дословные цитаты, кто говорит, что не так и готовая замена (того же смысла и длины).`,
  },
  tts: {
    title: "Риски озвучки (ударение и произношение)",
    cats: ["озвучка: ударение", "озвучка: произношение", "озвучка: подача"],
    ask: `ЗАДАНИЕ (проход 3 — ОЗВУЧКА). Все реплики, мысли Агаты, осмотры и строки закадрового голоса будут один раз записаны синтезом речи ElevenLabs (модель eleven_v4, русский). У неё нет SSML и словаря ударений: ударение она угадывает сама; заглавные буквы читает как эмфазу; паузы — по пунктуации (многоточие, тире); аудиотеги в квадратных скобках ([sighs], [whispers]…) работают только в поле «для озвучки» (voice_text) — экранный текст при этом не меняется. Найди строки, где синтез с заметной вероятностью ошибётся:
1. «озвучка: ударение» — омографы и слова с плавающим ударением, где смысл зависит от ударения (замок/замок, мука, стоит, плачу, уже/уже́, кругом, дорога/дорогá, полки, крюки, пары, сорок, ворот/ворот…); «е» вместо «ё», где без ё чтение двоится или звучит неправильно (все/всё, небо/нёбо, слезы, береста, издали…); имена и названия с неочевидным ударением (Евдокия, Пелагея, Ольховка, Заречье, Аксинья, Фёдор Лукич, Варвара, Ульяна, Нина, Митя, Тихон, Дуня…) — где синтез вероятно ударит не туда, и диалектные или старые слова (стопор, уключина, ворот, ставня, засов, лежанка, горница, сени, коромысло…).
2. «озвучка: произношение» — цифры и числа (читать словами), даты, сокращения, инициалы, знаки (№, %, «–»), латиница, кавычки внутри реплики, которые синтез прочтёт как часть речи, ремарки в тексте реплики.
3. «озвучка: подача» — строка слишком длинная для одной подачи (> ~250 знаков), где лучше разбить; междометия, которые синтез прочтёт по буквам («Хм», «Мм», «Тс-с», «Ш-ш»); строка из одного слова, которая без тега прозвучит не тем чувством; противоречие тегов подачи и смысла (тег sarcastic у нежной фразы).
Не отмечай слова, где синтез почти наверняка не ошибётся. Для каждой находки — ключ, дословная цитата, проблемное слово, как прочтёт синтез и как надо, и готовое исправление: лучше всего — текст для поля voice_text (с ё, с переставленным словом, числом словами или знаком ударения «́» после ударной гласной), а если ошибка и на экране (е вместо ё, где смысл двоится) — исправление текста.`,
  },
};

const tool = {
  name: "report",
  description: "Итог прохода: краткая сводка и список находок с точными ключами и дословными цитатами.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "3–6 фраз: общее состояние по теме прохода и главное." },
      findings: {
        type: "array",
        items: {
          type: "object",
          properties: {
            category: { type: "string", description: "категория из списка задания" },
            keys: { type: "array", items: { type: "string" }, description: "ключи строк ровно как во входе (⟨ключ⟩ или [ключ]); первой — строка, которую править" },
            quotes: { type: "array", items: { type: "string" }, description: "дословные фрагменты этих строк, в том же порядке" },
            character: { type: "string", description: "кто говорит (для тона и озвучки), иначе пусто" },
            problem: { type: "string", description: "что не так, коротко и конкретно" },
            evidence: { type: "string", description: "на чём основано: какая ранняя строка, факт сценария или канона, условие показа" },
            fix: { type: "string", description: "готовое исправление: новый текст строки или текст для поля voice_text" },
            severity: { type: "string", enum: ["критично", "важно", "мелочь"] },
          },
          required: ["category", "keys", "quotes", "problem", "evidence", "fix", "severity"],
        },
      },
    },
    required: ["summary", "findings"],
  },
};

function systemText() {
  const chars = ((jf("data/story/characters.json") || {}).characters || [])
    .map((c) => `- ${c.name} (${c.id}): ${c.voice && c.voice.direction ? c.voice.direction : ""}`).join("\n");
  return `Ты — старший редактор сюжета и диалогов русской компьютерной игры «Дом пропавших дорог» (2D point-and-click). Тебе дают ВЕСЬ текст игры в порядке сюжета — то, что игрок прочитает и услышит, с условиями показа, — принятый сценарий и канон. Голоса скоро запишут один раз, поэтому каждая найденная сейчас ошибка дешевле, чем после записи.
Правила:
- Опирайся только на данные ниже. Каждая находка — с точными ключами (как во входе: ⟨H1.stove.look⟩ → H1.stove.look; [M02.3] → M02.3) и ДОСЛОВНЫМИ цитатами; без ключа и цитаты находку не пиши.
- Учитывай условия показа: строка с {если: …} или в states / choice.requires видна только при этих флагах; requires сцены — когда сцена может начаться. Не называй противоречием две строки взаимоисключающих веток (разные варианты выбора, if/кроме).
- Ремарки и пометки «для разработчиков» игрок не видит — по ним можно понять замысел, но находка должна быть в видимом тексте.
- «(резерв)» — истории пока без запусков в игре: проверяй их тексты так же, но помечай это в problem.
- Не переписывай стиль и литературу — только настоящие ошибки по теме прохода. Важность: «критично» — ломает канон, смысл или запись голоса; «важно» — игрок заметит или синтез прочтёт неверно; «мелочь» — шероховатость.
- Ответ — только вызовом инструмента report.

ХАРАКТЕРЫ ДЛЯ ОЗВУЧКИ (data/story/characters.json):
${chars}

${canonText()}

СЦЕНАРИЙ (Docs/SCENARIO_FINAL.md, принят 22.10 — истина для фактов):
${readDoc("Docs/SCENARIO_FINAL.md", 200000)}`;
}

// --- Main ---------------------------------------------------------------------------------------------------------

const FALLBACK = "claude-opus-5-5";

async function main() {
  const A = args();
  const corpus = buildCorpus();
  if (A.dump) {
    const f = path.resolve(ROOT, A.dump === true ? "build/ai_checks/continuity_corpus.txt" : String(A.dump));
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, corpus.text);
    log(`corpus ${path.relative(ROOT, f)}: ${corpus.text.length} chars, ${corpus.keys.size} keys, ${corpus.textCount} texts`);
    if (A["dump-only"]) return;
  }
  let model = String(A.model || "claude-fable-5-1");
  const effort = String(A.effort || "high");
  const maxUsd = Math.min(20, Number(A["max-usd"] || 15));
  const passes = String(A.passes || "continuity,voices,tts").split(",").map((s) => s.trim()).filter((p) => PASSES[p]);
  const budget = new Budget(maxUsd);
  const system = systemText();
  const sysChars = system.length, corpusChars = corpus.text.length;
  if (!priceKnown(model)) { log(`model ${model} has no price in claude.mjs — refused`); process.exit(1); }
  const maxTokens = Math.round(Number(A["max-tokens"] || 80000));
  const estPass = (m, cached) => {
    // Input: system + corpus once (cache write 1.25×) or as a cache read (≈2.5 %); output up to maxTokens is the ceiling,
    // the expected answer (thinking + findings) is ~25k tokens.
    const inTok = Math.ceil((sysChars + corpusChars) / 2.5);
    const p = PRICES[m];
    const inUsd = inTok * (cached ? p.cr : p.cw) / 1e6;
    return { expected: inUsd + 25000 * p.out / 1e6, ceiling: inUsd + maxTokens * p.out / 1e6, inTok };
  };
  const e0 = estPass(model, false);
  log(`corpus ${corpusChars} chars + system ${sysChars} chars ≈ ${e0.inTok} tokens; model ${model}, effort ${effort}; passes ${passes.join(",")}; ` +
    `estimate first pass ~$${e0.expected.toFixed(2)} (ceiling $${e0.ceiling.toFixed(2)}), cached passes ~$${estPass(model, true).expected.toFixed(2)}; max $${maxUsd}`);
  if (A.dry) return;

  const results = {};
  const errors = {};
  const content = [{ type: "text", text: `ВЕСЬ ТЕКСТ ИГРЫ В ПОРЯДКЕ СЮЖЕТА:\n\n${corpus.text}`, cache_control: { type: "ephemeral" } }];
  const body = (m, p) => {
    const b = { model: m, max_tokens: maxTokens, system: [{ type: "text", text: system }], tools: [tool], output_config: { effort },
      messages: [{ role: "user", content: [...content, { type: "text", text: `${PASSES[p].ask}\n\nКатегории этого прохода: ${PASSES[p].cats.join(", ")}.\nОтветь вызовом инструмента report.` }] }] };
    if (m !== "claude-fable-5-1") b.thinking = { type: "adaptive" };   // Fable 5.1: adaptive thinking is always on, no field
    return b;
  };
  const apiKey = process.env.ANTHROPIC_API_KEY || "";
  if (!apiKey) { log("нет ключа API (секрет CLAUDE_API → ANTHROPIC_API_KEY)"); process.exit(1); }

  const runPass = async (p, onStart, cached) => {
    let m = model;
    for (let attempt = 0; attempt < 2; attempt++) {
      const est = estPass(m, cached);
      if (!budget.fits(est.expected)) { errors[p] = `пропущен: оценка $${est.expected.toFixed(2)} не помещается (потрачено $${budget.spent.toFixed(2)} из $${maxUsd})`; onStart && onStart(); return; }
      try {
        const t0 = Date.now();
        const { resp, input } = await callTool(apiKey, body(m, p), "report", { log, timeoutMs: 600000, attempts: 3, stream: true, onStart });
        budget.add(m, resp.usage, `pass:${p}`);
        const u = resp.usage || {};
        log(`pass ${p}: ${m}, ${Math.round((Date.now() - t0) / 1000)} s, in ${u.input_tokens || 0} + cache w ${u.cache_creation_input_tokens || 0} / r ${u.cache_read_input_tokens || 0}, out ${u.output_tokens || 0}, stop ${resp.stop_reason}; $${budget.spent.toFixed(3)} total`);
        if (input) { results[p] = { ...input, model: m }; return; }
        if (attempt === 0 && resp.stop_reason !== "max_tokens") { log(`pass ${p}: no report tool call (stop ${resp.stop_reason}), retry`); cached = true; continue; }
        errors[p] = `модель не вернула отчёт инструментом (stop_reason ${resp.stop_reason})`;
        return;
      } catch (e) {
        const msg = redact(String((e && e.message) || e)).slice(0, 300);
        const st = e instanceof ApiError ? e.status : 0;
        if (m !== FALLBACK && (st === 400 || st === 404 || st === 403 || st === 529 || st === 0) && !/credit|billing|balance|workspace/i.test(msg)) {
          log(`pass ${p}: ${m} failed (${msg.slice(0, 120)}), fallback ${FALLBACK}`);
          if (p === passes[0]) model = FALLBACK;   // the cached prefix belongs to one model: the rest follow
          m = FALLBACK;
          cached = false;
          continue;
        }
        errors[p] = `API: ${msg}`;
        onStart && onStart();
        return;
      }
    }
  };

  // First pass writes the cache; the others start once its stream has begun (cache is readable from then on).
  let started;
  const startedP = new Promise((r) => { started = r; });
  const fallbackTimer = setTimeout(() => started(), 300000);
  const first = runPass(passes[0], () => started(), false);
  await Promise.race([startedP, first]);
  clearTimeout(fallbackTimer);
  await new Promise((r) => setTimeout(r, 5000));
  await Promise.all([first, ...passes.slice(1).map((p) => runPass(p, null, true))]);

  // --- Report ---
  const order = { "критично": 0, "важно": 1, "мелочь": 2 };
  const known = corpus.keys;
  const norm = (k) => String(k || "").replace(/^[⟨[]|[⟩\]]$/g, "").trim();
  const L = [];
  const date = new Date().toISOString().slice(0, 10);
  L.push(`# ИИ-чтение всей игры на непрерывность — ${date}`);
  L.push("");
  L.push(`- Что прочитано: весь текст игры в порядке сюжета — сцены E0–E5 (M01…M26, эпилог) с обязательными репликами и условиями, комнаты (реплики NPC и тексты по флагам, мысли Агаты, осмотры, выходы), предметы, необязательные истории Q01–Q10, журнал (цели, факты, подсказки), интерфейс и крупные планы — ${corpus.textCount} текстов, ${corpusChars} знаков; плюс Docs/SCENARIO_FINAL.md и канон CLAUDE.md, characters.json.`);
  L.push(`- Модель: \`${[...new Set(Object.values(results).map((r) => r.model))].join("`, `") || model}\`, усилие ${effort}; ${runLine()}; стоимость **$${budget.spent.toFixed(3)}** (по usage ответов; потолок $${maxUsd}).`);
  L.push(`- Проходы: ${passes.map((p) => `${PASSES[p].title}${results[p] ? ` — ${(results[p].findings || []).length} находок` : ` — ${errors[p] || "нет ответа"}`}`).join("; ")}.`);
  L.push("- Правок в game/ и data/ проверка не делает; находки разводит координатор. Ключ `(?)` — модель назвала ключ, которого нет во входе (проверить вручную).");
  L.push("");
  const all = [];
  for (const p of passes) {
    const r = results[p];
    L.push(`## ${PASSES[p].title}`);
    L.push("");
    if (!r) { L.push(`**Не выполнено:** ${errors[p] || "нет ответа"}`); L.push(""); continue; }
    if (r.summary) { L.push(r.summary); L.push(""); }
    const fs_ = (r.findings || []).filter((f) => f && (f.keys || []).length).sort((a, b) => (order[a.severity] ?? 3) - (order[b.severity] ?? 3));
    if (!fs_.length) { L.push("Находок нет."); L.push(""); continue; }
    L.push("| # | Важность | Тип | Ключи | Цитаты | Кто | Что не так | Основание | Исправление |");
    L.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    fs_.forEach((f, i) => {
      const ks = (f.keys || []).map((k) => `\`${cell(norm(k))}\`${known.has(norm(k)) ? "" : " (?)"}`).join(", ");
      const qs = (f.quotes || []).map((q) => `«${cell(q)}»`).join(" / ");
      L.push(`| ${p[0].toUpperCase()}${i + 1} | ${cell(f.severity)} | ${cell(f.category)} | ${ks} | ${qs} | ${cell(f.character || "")} | ${cell(f.problem)} | ${cell(f.evidence)} | ${cell(f.fix)} |`);
      all.push({ id: `${p[0].toUpperCase()}${i + 1}`, pass: p, ...f, keys: (f.keys || []).map(norm), unknown_keys: (f.keys || []).map(norm).filter((k) => !known.has(k)) });
    });
    L.push("");
  }
  L.push("## Где искать строку");
  L.push("");
  L.push("- `H1.stove.look`, `Z1.tamara.after` — ключ в `data/story/text/ru_*.json` (поле `line` — реплика с именем; `voice_text` — текст для озвучки, экран не меняет).");
  L.push("- `M03.2` — сцена M03, реплика №2 (с нуля) в `data/story/scenes/E*.json`; `M13.4.A` — вариант A выбора в реплике 4; `M03.цель_журнала`, `M03.подсказка1` — поля `goal`, `hints`. Запись голоса — `<сцена>_<номер>` в манифесте озвучки.");
  L.push("- `квест.Q04.реплика4`, `квест.Q04.шаг2` — `data/story/quests.json` (с единицы); `журнал.<флаг>` — `flags.json`; `предмет.<id>` — `items.json`.");
  const file = reportPath("continuity");
  fs.writeFileSync(file, L.join("\n") + "\n");
  fs.writeFileSync(file.replace(/\.md$/, ".json"), JSON.stringify({ date, model, effort, spent_usd: Number(budget.spent.toFixed(4)), usage: budget.toJSON().by_model,
    summaries: Object.fromEntries(Object.entries(results).map(([p, r]) => [p, r.summary || ""])), errors, findings: all }, null, 1));
  const crit = all.filter((f) => f.severity === "критично").length;
  fs.mkdirSync(path.join(ROOT, "build", "ai_checks"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "build", "ai_checks", "summary.txt"), `непрерывность: ${all.length} находок (${crit} критичных); $${budget.spent.toFixed(2)}`);
  log(`report ${path.relative(ROOT, file)}: ${all.length} findings (${crit} critical), $${budget.spent.toFixed(3)}${Object.keys(errors).length ? ` (errors: ${Object.keys(errors).join(",")})` : ""}`);
  if (!Object.keys(results).length) process.exit(1);
}

main().catch((e) => { console.error(`fatal: ${redact(String(e && e.message)).slice(0, 300)}`); process.exit(1); });
