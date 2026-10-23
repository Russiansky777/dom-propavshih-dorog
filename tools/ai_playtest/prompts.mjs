// Prompts of the AI playtester: the checklist from Docs/ACCEPTANCE_*.md, the system prompts of both modes,
// the `act` tool (one action per step), the per-step message and the final report prompt. Russian, because
// the game, the checklist and the report are Russian.

import fs from "node:fs";
import path from "node:path";

/** "140-154" | [140, "141-143"] | 140 → [140, 141, …]. */
export function parseItems(v) {
  const out = [];
  const add = (x) => {
    const s = String(x).trim();
    const m = /^(\d+)\s*[-–]\s*(\d+)$/.exec(s);
    if (m) { for (let i = Number(m[1]); i <= Number(m[2]); i++) out.push(i); }
    else if (/^\d+$/.test(s)) out.push(Number(s));
  };
  if (Array.isArray(v)) v.forEach((x) => String(x).split(",").forEach(add));
  else if (v !== undefined && v !== null) String(v).split(",").forEach(add);
  return [...new Set(out)];
}

function cells(line) {
  const parts = line.split("|").map((c) => c.trim());
  return parts.slice(1, parts.length - 1);
}

/** Rows "| N | Что сделать | Как должно работать | Ок? |" of one acceptance doc, with their section prose. */
function readDoc(file) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  const rows = new Map();
  const sections = [];
  let cur = { title: "", prose: [] };
  sections.push(cur);
  let controls = "";
  for (const line of lines) {
    if (/^##\s/.test(line)) { cur = { title: line.replace(/^##\s+/, "").trim(), prose: [] }; sections.push(cur); continue; }
    if (/^Управление\b/.test(line.trim()) && !controls) controls = line.trim();
    const m = /^\|\s*(\d+)\s*\|/.exec(line);
    if (m) {
      const c = cells(line);
      rows.set(Number(m[1]), { num: Number(m[1]), what: c[1] || "", expect: c[2] || "", section: cur });
      continue;
    }
    if (/^\|/.test(line)) continue;     // table header / separator
    if (line.trim()) cur.prose.push(line.trim());
  }
  return { rows, controls, title: (lines.find((l) => /^#\s/.test(l)) || "").replace(/^#\s+/, "") };
}

/** The checklist for the requested items: rows, their section prose, the controls paragraph. */
export function loadChecklist(root, docRel, items, contextItems = []) {
  let files = [];
  if (docRel) files = [path.resolve(root, docRel)];
  else {
    const dir = path.join(root, "Docs");
    files = fs.readdirSync(dir).filter((f) => /^ACCEPTANCE_.*\.md$/.test(f)).sort().reverse().map((f) => path.join(dir, f));
  }
  for (const f of files) {
    if (!fs.existsSync(f)) continue;
    const d = readDoc(f);
    if (!items.length || !d.rows.has(items[0])) continue;
    const found = items.filter((n) => d.rows.has(n)).map((n) => d.rows.get(n));
    const missing = items.filter((n) => !d.rows.has(n));
    const ctx = contextItems.filter((n) => d.rows.has(n) && !items.includes(n)).map((n) => d.rows.get(n));
    const secs = [];
    for (const r of found) if (!secs.includes(r.section)) secs.push(r.section);
    return { doc: path.relative(root, f), title: d.title, controls: d.controls, rows: found, missing, context: ctx, sections: secs };
  }
  return { doc: docRel || "", title: "", controls: "", rows: [], missing: items, context: [], sections: [] };
}

const clip = (s, n) => (s.length > n ? s.slice(0, n) + "…" : s);

// Section prose without the developers' notes (autotests, evidence paths) — the tester does not need them.
const proseOf = (s) => s.prose.filter((l) => !/^(Проверено до передачи|Кадры игры)/.test(l)).join("\n");

export function checklistText(cl) {
  const out = [];
  out.push(`Документ: ${cl.doc} — ${cl.title}`);
  if (cl.controls) out.push(`\n${cl.controls}`);
  for (const s of cl.sections) {
    out.push(`\n## ${s.title}`);
    if (s.prose.length) out.push(clip(proseOf(s), 3500));
  }
  out.push("\nПУНКТЫ ДЛЯ ПРОВЕРКИ (по порядку):");
  for (const r of cl.rows) out.push(`\n[${r.num}] Что сделать: ${r.what}\n      Как должно работать: ${r.expect}`);
  if (cl.context.length) {
    out.push("\nСПРАВКА (остальные пункты чеклиста — порядок блока и как что делается; их НЕ проверять и вердикты по ним не давать, но проходить сюжет через них можно и нужно, чтобы дойти до своих пунктов):");
    const ctxSecs = [];
    for (const r of cl.context) if (!cl.sections.includes(r.section) && !ctxSecs.includes(r.section)) ctxSecs.push(r.section);
    for (const s of ctxSecs) out.push(`(${s.title}) ${clip(proseOf(s), 1500)}`);
    for (const r of cl.context) out.push(`\n[справка ${r.num}] ${r.what}\n      → ${r.expect}`);
  }
  return out.join("\n");
}

// --- The one tool of a step -------------------------------------------------------------------------

export function actTool(mode, W, H) {
  const props = {
    observe: { type: "string", description: "Что видно на кадре сейчас — 1–2 коротких фразы." },
    thought: { type: "string", description: "Коротко, вслух: что делаю и зачем (1–2 фразы)." },
    action: {
      type: "string",
      enum: ["click", "right_click", "double_click", "hold", "move", "drag", "drag_path", "timing", "hook", "knot", "key", "wait", "zoom", "done"],
      description: "click — левый щелчок в (x,y); right_click — правый; double_click — двойной, два щелчка подряд быстро (например, рассмотреть предмет в сумке или «два удара»); hold — нажать левую кнопку в (x,y) и держать seconds секунд (0.3–5), потом отпустить («долгий» звон, долгое нажатие); move — навести курсор (покажет подпись); drag — нажать в (x,y), тянуть до (x2,y2), отпустить; drag_path — нажать в первой точке path и вести мышь через все точки по порядку, отпустить в последней (протянуть по контуру); timing — «точный удар»: когда на экране полоса с бегунком (красный — зелёный — красный: скоба, ставня), программа бьёт, когда бегунок в зелёной зоне (как рефлекс игрока), до конца серии; hook — «крюк звоном» в крупном плане зеркала конторы: программа звонит раз (пустить крюк), два — когда крюк над засовом (стой), долгий — поднять засов; knot — «узел»: программа берёт конец каната и протягивает его по показанному контуру петель; key — нажать клавишу key; wait — подождать seconds; zoom — следующий шаг покажет увеличенный фрагмент region; done — закончить прогон.",
    },
    times: { type: "integer", description: "Для click: сколько раз подряд щёлкнуть (1–12, по умолчанию 1), например тянуть канат переправы." },
    x: { type: "number", description: `X в пикселях этого кадра (0…${W - 1}).` },
    y: { type: "number", description: `Y в пикселях этого кадра (0…${H - 1}).` },
    x2: { type: "number", description: "Для drag: куда тянуть, X." },
    y2: { type: "number", description: "Для drag: куда тянуть, Y." },
    key: { type: "string", description: "Для key: Space, Enter, Escape, Tab, F5, F9, ArrowLeft, ArrowRight, цифра или буква." },
    seconds: { type: "number", description: "Для wait: 1–20 секунд; для hold: сколько держать кнопку, 0.3–5 (по умолчанию 1)." },
    region: { type: "array", items: { type: "number" }, description: "Для zoom: [x0, y0, x1, y1] в пикселях этого кадра." },
    path: { type: "array", items: { type: "array", items: { type: "number" } }, description: "Для drag_path: точки [[x, y], …] в пикселях этого кадра, от 2 до 40." },
    memory: { type: "string", description: "Твоя память между шагами (старых кадров ты не видишь): где ты, что уже сделано, что дальше. До 800 символов. Пиши, когда что-то важное изменилось; пусто — оставить прежнюю." },
    notes: {
      type: "array",
      description: mode === "fresh"
        ? "Заметки игрока, только когда есть что сказать: непонятно (не ясно, что делать или зачем), застряла, баг (что-то выглядит сломанным), подсказка (пришлось взять подсказку), впечатление."
        : "Заметки по ходу, только когда есть что сказать: баг, непонятно, техника (проблема самого плейтеста: не попадаю, кадр не тот).",
      items: {
        type: "object",
        properties: {
          kind: { type: "string", enum: ["непонятно", "застряла", "баг", "подсказка", "впечатление", "техника"] },
          text: { type: "string" },
          frames: { type: "array", items: { type: "string" }, description: "Номера кадров-доказательств, напр. [\"f0012\"]." },
        },
        required: ["kind", "text"],
      },
    },
  };
  const required = ["observe", "thought", "action"];
  if (mode === "acceptance") {
    props.verdicts = {
      type: "array",
      description: "Вердикт по пункту чеклиста, как только пункт проверен (или его точно не проверить). Можно уточнить позже — засчитывается последний.",
      items: {
        type: "object",
        properties: {
          item: { type: "integer" },
          status: { type: "string", enum: ["прошёл", "не прошёл", "частично", "не дошёл", "не проверяемо"] },
          seen: { type: "string", description: "Что именно увидела: цитаты текста, что на экране. Для «не прошёл»/«частично» — что отличается от ожидаемого." },
          frames: { type: "array", items: { type: "string" }, description: "Кадры-доказательства, напр. [\"f0012\", \"f0013\"]." },
        },
        required: ["item", "status", "seen"],
      },
    };
  }
  return {
    name: "act",
    description: "Одно действие в игре и твои пометки. Вызывается ровно один раз за шаг.",
    input_schema: { type: "object", properties: props, required },
  };
}

// --- System prompts ---------------------------------------------------------------------------------

function harnessRules(W, H) {
  return `КАК ТЫ ИГРАЕШЬ
- Каждый шаг ты получаешь свежий кадр игры ${W}×${H} (уменьшенная копия окна 1920×1080) и делаешь ОДНО действие инструментом act. Координаты — в пикселях присланного кадра, (0,0) — левый верхний угол.
- После действия программа ждёт, пока героиня дойдёт и игра успокоится, и только потом снимает новый кадр.
- Реплики и тексты, которые идут подряд, программа пролистывает сама (настоящими щелчками по окну текста) и присылает тебе их дословно вместе с номерами кадров. Если на экране выбор вариантов — его делаешь ты: щёлкни по строке нужного варианта.
- Красный кружок на кадре — где сейчас курсор мыши (его рисует программа; в самой игре его нет).
- «Подпись под курсором» — то, что игра показывает при наведении; чтобы прочитать подпись, используй move.
- Ты не слышишь звук. Старых кадров не видишь — веди память в поле memory: после каждого важного события коротко записывай, что уже сделано и проверено и что дальше (не «разговор идёт», а «разговор с Тамарой окончен, в сумке 3 предмета»).
- timing, hook и knot — это руки игрока, а не подсказка: выбирай их, только когда игра на экране объяснила, что нужно сделать; если не объяснила — отметь «непонятно».
- Когда в событиях написано «Текст закончился» — разговор или осмотр завершён; повторный щелчок по тому же месту повторит его, а не продолжит.
- Каждый кадр имеет номер вида f0012; им подтверждай вердикты и заметки.
- Если щелчок ничего не изменил — не повторяй его в ту же точку: сдвинься, наведи курсор (move), чтобы найти подпись, или попробуй другое.
- Не перезагружай страницу и не закрывай вкладку.`;
}

export function systemPrompt(mode, { W, H, checklist, note, start }) {
  const begin = start ? `Игра запущена в чистом браузере с середины: ${start}.` : "Игра уже запущена в чистом браузере — это новая игра с самого начала.";
  if (mode === "acceptance") {
    return `Ты — тестировщик компьютерной игры «Дом пропавших дорог» (2D point-and-click на русском, героиня Агата). Ты проходишь приёмочный чеклист настоящими щелчками мыши и честно сообщаешь, что видишь. ${begin}

${harnessRules(W, H)}
- Пробел на ~1,5 секунды показывает подписи всех мест и действий в комнате (кадр снимается сразу после нажатия) — используй, когда ищешь, куда щёлкнуть.
- Сумка (предметы) — вверху; щелчок по предмету берёт его «в руку», затем щелчок по цели применяет; правый щелчок — вернуть предмет в сумку.

КАК ПРОВЕРЯТЬ
- Проходи пункты по порядку. Чтобы дойти до пункта, делай всё, что нужно по сюжету (разговоры, предметы, загадки), даже если это не написано в пункте.
- Выполняй ВСЁ, что упомянуто в пункте — и в «Что сделать», и в «Как должно работать» (если там названы действия или предметы, например «Мешок/тетради — …», сделай и это), и только потом ставь «прошёл». Пропущенное действие может заблокировать следующие пункты.
- Если игра не продвигается (переход ничего не запускает, цель не меняется) — сначала проверь, всё ли сделано в текущей комнате по пунктам, затем возьми игровую «Подсказку» (кнопка вверху справа) и следуй ей; отметь это в notes.
- Как только пункт проверен, сразу дай вердикт в verdicts: прошёл / не прошёл / частично / не дошёл / не проверяемо. В seen — что именно увидела (дословные цитаты ключевых фраз), для «не прошёл» и «частично» — чем отличается от ожидаемого. В frames — номера кадров.
- Сверяй смысл и ключевые фразы, выделенные в пункте; мелкие расхождения в пунктуации — не провал. Звук ты не слышишь: проверь всё остальное, а про звук напиши «звук не проверяем».
- Если застряла на пункте больше ~12 шагов — дай «не дошёл» с объяснением и, если можно, переходи к следующему.
- Когда по всем пунктам есть вердикты — action=done.

ЧЕКЛИСТ
${checklist}
${note ? `\nЗАМЕЧАНИЕ К ПРОГОНУ: ${note}` : ""}`;
  }
  return `Ты — игрок, который впервые запустил компьютерную игру «Дом пропавших дорог» (2D point-and-click на русском). Ты ничего не знаешь о сюжете и о том, что надо делать: только то, что видишь на экране. Обычно в таких играх щёлкают мышью по предметам и людям, наводят курсор, чтобы увидеть подписи. ${begin}

${harnessRules(W, H)}

ТВОЯ ЗАДАЧА
- Пройти как можно дальше за отведённые шаги, играя как обычный внимательный новичок.
- Думай вслух коротко (thought). Отмечай в notes: «непонятно» — когда не ясно, что делать или зачем; «застряла» — когда несколько попыток не двигают историю; «баг» — что выглядит сломанным (обрезанный текст, объект не реагирует, героиня застряла, странная графика, противоречие в тексте); «подсказка» — если пришлось взять игровую подсказку; «впечатление» — что зацепило или раздражает. Не пиши заметку на каждом шаге — только по делу.
- Подсказкой игры пользуйся, только если застряла, как обычный игрок.
- action=done — только если игра закончилась или ты окончательно застряла и всё перепробовала.
${note ? `\nЗАМЕЧАНИЕ К ПРОГОНУ: ${note}` : ""}`;
}

// --- The per-step user message ------------------------------------------------------------------------

export function stepText(ctx) {
  const L = [];
  L.push(`Шаг ${ctx.step} из ${ctx.maxSteps}. Потрачено $${ctx.spent.toFixed(3)} из $${ctx.maxUsd.toFixed(2)}.`);
  if (ctx.memory) L.push(`\nТВОЯ ПАМЯТЬ: ${ctx.memory}`);
  if (ctx.verdicts && ctx.verdicts.length) {
    L.push(`\nВЕРДИКТЫ, ЧТО ТЫ УЖЕ ДАЛА: ${ctx.verdicts.map((v) => `${v.item} — ${v.status}`).join("; ")}`);
    if (ctx.pending && ctx.pending.length) L.push(`Ещё без вердикта: ${ctx.pending.join(", ")}`);
  } else if (ctx.pending && ctx.pending.length) {
    L.push(`\nПункты без вердикта: ${ctx.pending.join(", ")}`);
  }
  if (ctx.history.length) {
    L.push("\nПОСЛЕДНИЕ ДЕЙСТВИЯ:");
    for (const h of ctx.history) L.push(h);
  }
  if (ctx.recent && ctx.recent.length) {
    L.push("\nРЕПЛИКИ И ТЕКСТЫ ПРОШЛЫХ ШАГОВ (дословно, последние):");
    for (const r of ctx.recent) L.push(r);
  }
  L.push("\nЧТО ПРОИЗОШЛО ПОСЛЕ ПОСЛЕДНЕГО ДЕЙСТВИЯ:");
  if (ctx.events.length) for (const e of ctx.events) L.push(`- ${e}`);
  else L.push("- (первый кадр)");
  if (ctx.warnings.length) {
    L.push("\nВНИМАНИЕ:");
    for (const w of ctx.warnings) L.push(`- ${w}`);
  }
  L.push(`\nКадры ниже: ${ctx.imageLabels.join("; ")}. Сделай одно действие инструментом act.`);
  return L.join("\n");
}

// --- The final report ---------------------------------------------------------------------------------

export function reportSystem(mode) {
  return `Ты пишешь отчёт ИИ-плейтеста игры «Дом пропавших дорог» для Директора проекта (он не читает код) и для разработчиков. Пиши по-русски, коротко и по фактам, Markdown без заголовка первого уровня (заголовок добавит программа). Не выдумывай: опирайся только на журнал шагов, дословные реплики, заметки, вердикты и приложенные кадры. Объективный журнал игры (комнаты, флаги) — служебные данные, их игрок не видел; используй их, чтобы проверить, куда реально дошёл прогон, и не цитируй имена флагов Директору без нужды.
Ссылайся на кадры только из списка доступных, в виде [f0012](f0012.jpg).
Заявления шаговой модели о багах и непонятностях проверяй по кадрам и дословным текстам: шаговая модель ошибается в том, куда указывает (красный кружок на кадре — где был курсор). Что кадр не подтверждает — не выдавай за дефект игры, а отнеси в «Плейтестер» с пометкой «не подтверждено». Предупреждения Godot (WARNING) — не ошибки игры для игрока.
${mode === "acceptance"
    ? `Структура:
## Итог
2–3 строки: сколько пунктов прошло / не прошло / не дошло, главное.
## Пункты
Таблица | № | Вердикт | Что видела | Кадры |. Вердикт — прошёл / не прошёл / частично / не дошёл / не проверяемо. Проверь вердикты шаговой модели по репликам и кадрам; если не согласен — поставь свой вердикт и допиши «(исправлено при проверке: …)».
## Что не так
По пунктам, что отличается от ожидаемого — так, чтобы разработчик понял, что чинить.
## Плейтестер
Где вердикт может быть неверен из-за техники (не попала, не дождалась, не прочла) — честно.`
    : `Структура:
## Итог
2–3 строки: докуда дошла, сколько шагов, главное впечатление.
## Путь
Коротко по порядку: где была, что сделала.
## Где было непонятно
Самые важные места (до 7), по каждому: что видел игрок, почему непонятно, что могло бы помочь. С кадрами.
## Где застряла
## Похоже на баг
## Впечатления
## Плейтестер
Где проблема могла быть в самом плейтесте (промахи, ожидание, чтение), а не в игре.`}`;
}
