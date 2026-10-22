#!/usr/bin/env node
// AI check «Visual QA of rooms» (vision): every room whose data or art changed is opened in the web build
// (?ambientprobe hooks: ambientGoto / ambientFlag / ambientWalk — measurement hooks, players never get them),
// framed in key states and shown to Claude with the room's layer list and height references:
//   A_far / A_near — the start state (the room's conditional flags off), Agata at the farthest and nearest
//                    of the room's walk_samples;
//   B             — after the room's scenes (the flags they grant), Agata in the middle;
//   B_space       — the same with Space: the names of all places and actions (text over the art).
// Flags: misaligned / shifted layers, seams, wrong z-order, Agata floating / sinking / wrong scale against
// doors and furniture, text overlapping the art, missing art or placeholders.
//
//   node tools/ai_checks/room_qa.mjs [--rooms H1,O1 | --all] [--url <site>] [--web-dir build/web] [--model ...]
//
// Without --rooms / --all: only rooms whose inputs changed since the last check (Docs/ai_checks/room_qa_state.json:
// data/story/rooms/<R>.json, game/assets/rooms/<R>/, data/story/ambient/<R>.json, data/story/lights/<R>*).
// Report: Docs/ai_checks/room_qa_<date>.md + the frames cited by findings. Never edits game/ or data/.

import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { ROOT, OUT_DIR, args, log, git, reportPath, askTool, cell, runLine, Budget } from "./common.mjs";
import { openGame, serve, sleep } from "./browser.mjs";

const SITE = "https://russiansky777.github.io/dom-propavshih-dorog/";
const STATE = path.join(OUT_DIR, "room_qa_state.json");
const WORK = path.join(ROOT, "build", "ai_checks", "rooms");
const json = (rel) => JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8"));

function roomInputs(room) {
  const paths = [`data/story/rooms/${room}.json`, `game/assets/rooms/${room}`, `data/story/ambient/${room}.json`];
  const lightsDir = path.join(ROOT, "data/story/lights");
  if (fs.existsSync(lightsDir)) for (const f of fs.readdirSync(lightsDir)) if (f.startsWith(`${room}.`) || f.startsWith(`${room}_`)) paths.push(`data/story/lights/${f}`);
  let listing = "";
  try { listing = git("ls-tree", "-r", "HEAD", "--", ...paths); } catch (_) { listing = paths.map((p) => (fs.existsSync(path.join(ROOT, p)) ? `${p}:${fs.statSync(path.join(ROOT, p)).mtimeMs}` : "")).join("\n"); }
  return createHash("sha1").update(listing).digest("hex").slice(0, 16);
}

function roomInfo(room, scenes, locations) {
  const d = json(`data/story/rooms/${room}.json`);
  const ifFlags = new Set(), unlessFlags = new Set();
  for (const l of d.layers || []) { (l.if || []).forEach((f) => ifFlags.add(f)); (l.unless || []).forEach((f) => unlessFlags.add(f)); }
  const grants = new Set();
  for (const sc of scenes) if ((sc.locations || []).includes(room)) for (const f of (sc.grants && sc.grants.flags) || []) grants.add(f);
  const loc = locations.find((l) => l.id === room) || {};
  const samples = (d.walk_samples || []).filter((p) => Array.isArray(p) && p.length >= 2).map((p) => ({ x: p[0], y: p[1], label: p[2] || "" }));
  return { room, name: loc.name || room, d, ifFlags: [...ifFlags], unlessFlags: [...unlessFlags], grants: [...grants], samples };
}

const SYSTEM = `Ты — художник-постановщик и QA 2D point-and-click игры «Дом пропавших дорог» (кадр 1920×1080, нарисованный фон и слои-предметы поверх, героиня Агата — 3D-модель, отрендеренная в спрайт, ростом 1,66 м). Тебе показывают одну комнату в нескольких состояниях. Ищи то, что заметит игрок:
- слои: предмет сдвинут относительно фона, двойной контур, шов, ореол или обрезанный край, предмет висит в воздухе или «плавает» над поверхностью, слой другого масштаба или стиля, чем фон;
- порядок по глубине: Агата нарисована перед предметом, за которым должна стоять (или наоборот), её режет край слоя;
- Агата парит над полом или проваливается в него, тень не под ногами, ноги на стене;
- масштаб Агаты не сходится с дверьми и мебелью (ориентиры роста даны ниже: дверь, лавка…), вдали и вблизи;
- текст поверх арта: подписи наезжают друг на друга, на лица, на важные места, нечитаемы, вылезают за кадр;
- нет арта: цветной прямоугольник, шахматка, текст-заглушка, пустая область, явная временная фигура.
Не придирайся к художественному стилю и свету, если он не ломает картинку. Каждая находка — кадр (A_far, A_near, B, B_space), где на кадре (словами и примерными координатами в пикселях 1920×1080), что не так. Важность: «критично» — бросается в глаза сразу; «важно» — заметно при внимательном взгляде; «мелочь» — видно только при разглядывании. Если всё чисто — пустой список. Ответ — только вызовом инструмента report.`;

const tool = {
  name: "report",
  description: "Итог осмотра комнаты.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string" },
      findings: {
        type: "array",
        items: {
          type: "object",
          properties: {
            shot: { type: "string", enum: ["A_far", "A_near", "B", "B_space"] },
            where: { type: "string" },
            area: { type: "string", enum: ["слои/швы", "порядок по глубине", "Агата парит/тонет", "масштаб", "текст поверх арта", "нет арта/заглушка", "другое"] },
            problem: { type: "string" },
            severity: { type: "string", enum: ["критично", "важно", "мелочь"] },
          },
          required: ["shot", "where", "area", "problem", "severity"],
        },
      },
    },
    required: ["summary", "findings"],
  },
};

async function main() {
  const A = args();
  const model = A.model || "claude-opus-5-5";
  const budget = new Budget(Math.min(10, Number(A["max-usd"] || 8)));
  const index = json("data/story/rooms/_index.json");
  const all = (index.in_scope || []).filter((r) => fs.existsSync(path.join(ROOT, `data/story/rooms/${r}.json`)));
  const hashes = Object.fromEntries(all.map((r) => [r, roomInputs(r)]));
  const state = fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, "utf8")) : {};
  let targets, scope;
  if (A.all) { targets = all; scope = "все комнаты"; }
  else if (A.rooms && A.rooms !== true) { targets = String(A.rooms).split(",").map((s) => s.trim()).filter((r) => all.includes(r)); scope = `по запросу: ${targets.join(", ")}`; }
  else { targets = all.filter((r) => state[r] !== hashes[r]); scope = "комнаты, чьи данные или арт изменились"; }
  log(`rooms: ${all.length}; to check: ${targets.join(", ") || "none"} (${scope})`);
  if (!targets.length) { log("nothing changed — no report"); return; }

  const scenes = [];
  for (const f of fs.readdirSync(path.join(ROOT, "data/story/scenes"))) if (f.endsWith(".json")) scenes.push(...(json(`data/story/scenes/${f}`).scenes || []));
  const locations = (json("data/story/locations.json").locations || []);
  const ref = index.agata_ref || {};

  let server = null, url = A.url || SITE;
  if (A["web-dir"]) { server = await serve(path.resolve(ROOT, A["web-dir"]), 8792); url = "http://127.0.0.1:8792/index.html"; }
  let version = "";
  try { const r = await fetch(new URL("version.txt", url.endsWith("/") ? url : url.replace(/[^/]*$/, "")).toString()); if (r.ok) version = (await r.text()).trim(); } catch (_) {}
  fs.rmSync(WORK, { recursive: true, force: true });
  fs.mkdirSync(WORK, { recursive: true });
  const g = await openGame(url + (url.includes("?") ? "&" : "?") + "ambientprobe", { log });
  await g.page.waitForFunction(() => window.ambientProbeReady === true, null, { timeout: 60000 });
  const call = (fn, ...a) => g.page.evaluate(([f, x]) => window[f](...x), [fn, a]);
  const park = () => g.page.mouse.move(330, 38);   // over the room title: no hotspot, no caption

  const results = [];
  const errors = [];
  for (const room of targets) {
    const info = roomInfo(room, scenes, locations);
    const shots = {};
    const notes = [];
    const byY = [...info.samples].sort((a, b) => a.y - b.y);
    const far = byY[0], near = byY[byY.length - 1], mid = byY[Math.floor(byY.length / 2)];
    try {
      const goto = async (spawn = "default") => {
        for (let i = 0; i < 3; i++) {
          await call("ambientGoto", room, spawn);
          await sleep(800);
          const t = await g.dismissTexts();
          if (t.length) notes.push(`при входе показан текст: ${t.slice(0, 3).join(" / ")}`);
          const s = await g.settle();
          if (s && s.room === room) return true;
          notes.push(`после входа игра перевела в ${s && s.room}`);
        }
        return false;
      };
      const walk = async (p) => { await call("ambientWalk", p.x, p.y); await sleep(600); await g.settle(40000); await g.dismissTexts(); };
      // A: the start state.
      for (const f of new Set([...info.ifFlags, ...info.unlessFlags, ...info.grants])) await call("ambientFlag", f, false);
      if (!(await goto())) throw new Error("не удалось войти в комнату");
      await park();
      if (far) await walk(far);
      fs.writeFileSync(shots.A_far = path.join(WORK, `${room}_A_far.jpg`), await g.grab());
      if (near && near !== far) { await walk(near); fs.writeFileSync(shots.A_near = path.join(WORK, `${room}_A_near.jpg`), await g.grab()); }
      // B: after the room's scenes.
      for (const f of info.grants) await call("ambientFlag", f, true);
      await goto();
      await park();
      if (mid) await walk(mid);
      fs.writeFileSync(shots.B = path.join(WORK, `${room}_B.jpg`), await g.grab());
      await g.page.keyboard.press("Space");
      await sleep(300);
      fs.writeFileSync(shots.B_space = path.join(WORK, `${room}_B_space.jpg`), await g.grab());
      await sleep(1500);
      log(`${room}: ${Object.keys(shots).length} frames`);
    } catch (e) {
      errors.push(`${room}: ${String(e.message || e).slice(0, 200)}`);
      continue;
    }
    const layers = (info.d.layers || []).map((l) => `- ${l.id}: z ${l.z ?? "—"}${l.occluder ? ", перекрывает Агату" : ""}${l.if ? `, виден при ${l.if.join("+")}` : ""}${l.unless ? `, скрыт при ${l.unless.join("/")}` : ""}${l.scale ? `, масштаб ${l.scale}` : ""}`);
    const refs = (info.d.height_refs || []).map((h) => `- ${h.what}: настоящая высота ${h.m} м, на фоне ${h.px} px при линии земли y ${h.y}`);
    const content = [];
    const labels = { A_far: `начальное состояние (флаги комнаты сброшены), Агата в дальней точке ${far ? `(${far.x}, ${far.y})` : ""}`,
      A_near: `начальное состояние, Агата в ближней точке ${near ? `(${near.x}, ${near.y})` : ""}`,
      B: `после сцен комнаты (флаги ${info.grants.join(", ") || "—"}), Агата в средней точке ${mid ? `(${mid.x}, ${mid.y})` : ""}`,
      B_space: "то же, нажат Пробел: подписи всех мест и действий" };
    for (const [k, f] of Object.entries(shots)) { content.push({ type: "text", text: `Кадр ${k}: ${labels[k]}` }); content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: fs.readFileSync(f).toString("base64") } }); }
    content.push({ type: "text", text: `Комната ${room} — «${info.name}». ${String(info.d._art || "").slice(0, 600)}\nСлои:\n${layers.join("\n") || "—"}\nОриентиры роста:\n${refs.join("\n") || "—"}\nАгата: ${ref.height_m || 1.66} м. ${notes.length ? `Заметки съёмки: ${notes.join("; ")}` : ""}\nОсмотри кадры и ответь вызовом report.` });
    try {
      const r = await askTool(budget, `room:${room}`, { model, max_tokens: 16000, system: SYSTEM, tools: [tool], output_config: { effort: "medium" }, messages: [{ role: "user", content }] }, "report");
      if (r) results.push({ room, name: info.name, shots, summary: r.summary || "", findings: (r.findings || []).map((f) => ({ ...f, room })) });
      else errors.push(`${room}: нет ответа инструментом`);
      log(`${room}: ${r ? (r.findings || []).length : "?"} findings, total $${budget.spent.toFixed(3)}`);
    } catch (e) { errors.push(`${room}: ${String(e.message || e).slice(0, 200)}`); }
  }
  const consoleErrors = g.consoleErrors.slice();
  await g.close();
  if (server) server.close();

  // Report.
  const file = reportPath("room_qa");
  const dir = file.replace(/\.md$/, "");
  const all_f = results.flatMap((r) => r.findings);
  const order = { "критично": 0, "важно": 1, "мелочь": 2 };
  all_f.sort((a, b) => (order[a.severity] ?? 3) - (order[b.severity] ?? 3) || a.room.localeCompare(b.room));
  const cited = [];
  for (const f of all_f) { const k = `${f.room}_${f.shot}`; if (!cited.includes(k) && cited.length < 16) cited.push(k); }
  if (cited.length) fs.mkdirSync(dir, { recursive: true });
  for (const k of cited) { const src = path.join(WORK, `${k}.jpg`); if (fs.existsSync(src)) fs.copyFileSync(src, path.join(dir, `${k}.jpg`)); }
  const link = (k) => (cited.includes(k) && fs.existsSync(path.join(dir, `${k}.jpg`)) ? `[${k}](${path.basename(dir)}/${k}.jpg)` : k);
  const L = [];
  L.push(`# ИИ-осмотр комнат — ${new Date().toISOString().slice(0, 10)}`);
  L.push("");
  L.push(`- Что проверено: ${scope} — ${results.map((r) => r.room).join(", ") || "—"}; сборка \`${version || "?"}\` (${A["web-dir"] ? `локально: ${A["web-dir"]}` : url}).`);
  L.push(`- Кадры: начальное состояние с Агатой вдали и вблизи, состояние после сцен комнаты, подписи по Пробелу. Модель \`${model}\`; ${runLine()}; стоимость **$${budget.spent.toFixed(3)}**.`);
  L.push(`- Правок в game/ и data/ проверка не делает; находки разводит координатор.`);
  L.push("");
  if (errors.length) { L.push(`**Не проверено:** ${errors.join("; ")}`); L.push(""); }
  if (consoleErrors.length) { L.push(`Ошибки консоли браузера при съёмке: ${consoleErrors.slice(0, 5).map((e) => cell(e)).join(" | ")}`); L.push(""); }
  L.push("## Итог");
  L.push("");
  for (const r of results) L.push(`- **${r.room} — ${r.name}**: ${cell(r.summary)}`);
  L.push("");
  L.push(`## Находки (${all_f.length})`);
  L.push("");
  if (!results.length) L.push("Проверка не выполнена (см. выше).");
  else if (!all_f.length) L.push("Замечаний нет.");
  else {
    L.push("| Важность | Комната | Кадр | Где | Что | Тип |");
    L.push("| --- | --- | --- | --- | --- | --- |");
    for (const f of all_f) L.push(`| ${cell(f.severity)} | ${f.room} | ${link(`${f.room}_${f.shot}`)} | ${cell(f.where)} | ${cell(f.problem)} | ${cell(f.area)} |`);
  }
  L.push("");
  fs.writeFileSync(file, L.join("\n") + "\n");
  for (const r of results) state[r.room] = hashes[r.room];
  fs.writeFileSync(STATE, JSON.stringify(state, null, 1) + "\n");
  fs.mkdirSync(path.join(ROOT, "build", "ai_checks"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "build", "ai_checks", "summary.txt"), `комнаты ${results.map((r) => r.room).join(", ")}: ${all_f.length} находок (${all_f.filter((f) => f.severity === "критично").length} критичных); $${budget.spent.toFixed(2)}`);
  log(`report ${path.relative(ROOT, file)}: ${all_f.length} findings, $${budget.spent.toFixed(3)}`);
}

main().catch((e) => { console.error(`fatal: ${String(e && e.message).slice(0, 300)}`); process.exit(1); });
