#!/usr/bin/env node
// AI playtester: Claude plays the WEB build of «Дом пропавших дорог» like a person — screenshot → the model
// picks one action (click / move / drag / key / wait / zoom / done) → a real mouse or keyboard event in
// headless Chromium → the game settles → the next screenshot.
//
//   node tools/ai_playtest/playtest.mjs --request pipeline/requests/playtest_<name>.json
//        [--out Docs/playtest/<dir>] [--url <site>] [--web-dir build/web] [--dry-run]
//
// Request JSON: mode ("acceptance" | "fresh"), items ("140-154" or [140, …]; acceptance), context_items
// (rows given as reference only), doc (Docs/ACCEPTANCE_*.md; default: the doc that has the first item),
// max_usd (a stop against a looping run, default and ceiling 10), max_steps (default 300 acceptance / 150 fresh),
// max_minutes, url (default the published site), mode "gate" = acceptance then fresh (fresh_max_steps, fresh_note),
// note, model (steps, default claude-haiku-5-5), model_stuck (one step when stuck, default
// claude-sonnet-5-5, "" = off), report_model (default claude-sonnet-5-5), image_width (default 1280),
// max_frames (frames kept in the report, default 24), auto_dialogue (default true).
//
// The key comes from ANTHROPIC_API_KEY (the workflow maps secrets.CLAUDE_API to it). It is never printed;
// stdout carries only step numbers, actions, rooms and costs — no model text (the Actions log is public).
// The budget: every response's usage × the price table (claude.mjs); a step is not sent when it would not
// fit under max_usd together with the reserve kept for the final report.
//
// Window probes: `window.probeReady` / `window.probeState` (main.gd) are used only by the harness — to wait
// for the game to load and to settle after an action, to read the on-screen texts verbatim (the dialogue,
// options, the caption under the pointer, the hint) and to log where the run really got to. The model never
// gets hotspot positions: it finds everything on the frames.
//
// Output (--out, default Docs/playtest/<date>_<mode>_<run>): report.md (Russian), f####.jpg evidence frames
// (only those cited by verdicts / notes + the last one), usage.json (tokens and USD per call), log.json
// (steps, dialogue transcript, game progress — for diagnosing the playtester itself).

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { callClaude, callTool, Budget, ApiError, priceKnown, estimateCost } from "./claude.mjs";
import { parseItems, loadChecklist, checklistText, actTool, systemPrompt, stepText, reportSystem, personaOf } from "./prompts.mjs";
import { docRowIds, normId, byDocOrder } from "./rows.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..", "..");
const SITE = "https://russiansky777.github.io/dom-propavshih-dorog/";
const HARD_MAX_USD = Number(process.env.AI_PLAYTEST_HARD_MAX_USD || 10);   // per-run stop against a looping run (not a budget)
const HARD_MAX_STEPS = 400;
const FRAME_W = 1920, FRAME_H = 1080;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const clampNum = (v, lo, hi, d) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const short = (s, n = 160) => { s = String(s || "").replace(/\s+/g, " ").trim(); return s.length > n ? s.slice(0, n) + "…" : s; };

function args() {
  const a = process.argv.slice(2);
  const o = {};
  for (let i = 0; i < a.length; i++) {
    if (a[i] === "--dry-run") o.dry = true;
    else if (a[i].startsWith("--")) { o[a[i].slice(2)] = a[i + 1]; i++; }
  }
  return o;
}

function serve(dir, port) {
  const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
    ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".txt": "text/plain" };
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Content-Length": st.size,
        "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-store" });
      fs.createReadStream(file).pipe(res);
    });
  });
  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve(server)));
}

function findChromium() {
  try { const p = chromium.executablePath(); if (p && fs.existsSync(p)) return p; } catch (_) {}
  const base = process.env.PLAYWRIGHT_BROWSERS_PATH || "/opt/pw-browsers";
  if (fs.existsSync(base)) {
    for (const d of fs.readdirSync(base)) {
      const cand = path.join(base, d, "chrome-linux", "chrome");
      if (d.startsWith("chromium-") && fs.existsSync(cand)) return cand;
    }
  }
  return undefined;
}

// --- Game state helpers (probe) ------------------------------------------------------------------------

const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.line_id || ""}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
const moving = (s) => !!(s && s.player && (s.player.walking || s.player.acting));
const staging = (s) => !!(s && s.busy && !beatKey(s) && !(s.puzzle && s.puzzle.open) && !(s.view && s.view.open) && !(s.mechanic && s.mechanic.open));
const truthyFlags = (s) => Object.keys((s && s.flags) || {}).filter((k) => s.flags[k]).sort();
function hash(str) { let h = 2166136261; for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); } return (h >>> 0).toString(36); }
/** What counts as progress: room, story flags, the bag, an open close-up and its pieces, the current text. */
function progressSig(s) {
  if (!s) return "";
  const pz = s.puzzle || {};
  return JSON.stringify([s.room, hash(truthyFlags(s).join(",")), (s.inventory || []).join(","), beatKey(s), !!pz.open,
    JSON.stringify(pz.placed || {}), pz.mark, !!pz.solved, !!(s.view && s.view.open), s.view && s.view.id, !!(s.mechanic && s.mechanic.open)]);
}
/** What the player sees change: progress + where Agata stands, the item in hand, panels, the caption, the close-up's drag. */
function screenSig(s) {
  if (!s) return "";
  const pz = s.puzzle || {}, ui = s.ui || {}, eh = ui.exit_hints || {};
  return JSON.stringify([progressSig(s), Math.round(((s.player && s.player.x) || 0) / 8), Math.round(((s.player && s.player.y) || 0) / 8),
    s.selected_item, ui.journal_open, ui.menu_open, ui.map_open, !!(s.pause && s.pause.open), !!(s.title && s.title.open), eh.hint_panel && eh.hint_panel.visible, eh.hover, eh.reveal,
    pz.carry, pz.dragging, pz.errors, pz.leaf, Math.round((pz.beam_dx || 0) / 6), s.last_hint]);
}

// --- Main ---------------------------------------------------------------------------------------------

async function main() {
  const A = args();
  const reqPath = A.request ? path.resolve(ROOT, A.request) : null;
  const req = reqPath ? JSON.parse(fs.readFileSync(reqPath, "utf8")) : {};
  // "gate" = acceptance then fresh: the workflow runs this script twice with --mode.
  const mode = (A.mode || req.mode) === "acceptance" || (!A.mode && req.mode === "gate") ? "acceptance" : "fresh";
  const dry = !!A.dry || req.dry_run === true;   // dry_run: scripted actions, no API (harness test in CI)
  // Row ids of the checklist ("7", "6а", "И2") — ranges in items / skip_items / context_items take the lettered rows too.
  const docIds = (() => { try { return req.doc ? docRowIds(fs.readFileSync(path.resolve(ROOT, String(req.doc)), "utf8")) : null; } catch (_) { return null; } })();
  const cfg = {
    mode,
    request: reqPath ? path.relative(ROOT, reqPath) : "",
    // --items: the rows of a gate (ai_playtest.yml); "unpassed": rows of the doc not passed at the last gate
    items: String(A.items || req.items || "").trim() === "unpassed" ? unpassedRows(req.doc) : parseItems(A.items || req.items, docIds),
    contextItems: parseItems(req.context_items, docIds),
    // max_usd is a safety stop against a looping run, not a budget (Director 22.10): default and ceiling $10.
    maxUsd: clampNum(mode === "fresh" && req.mode === "gate" ? req.fresh_max_usd ?? req.max_usd : req.max_usd, 0.05, HARD_MAX_USD, HARD_MAX_USD),
    maxSteps: Math.round(clampNum(mode === "fresh" && req.mode === "gate" ? req.fresh_max_steps ?? 150 : req.max_steps, 1, HARD_MAX_STEPS, mode === "acceptance" ? 300 : 150)),
    // up to 330 min: a persona run over the whole game (the job's own limit is 360)
    maxMinutes: clampNum(mode === "fresh" && req.mode === "gate" ? req.fresh_max_minutes ?? 90 : req.max_minutes, 5, 330, mode === "acceptance" ? 120 : 90),
    url: A.url || req.url || SITE,
    note: String((mode === "fresh" && req.mode === "gate" ? req.fresh_note : req.note) || ""),
    // Steps: claude-sonnet-5-5 by default — claude-haiku-5-5 lost track of a finished conversation within 9 steps
    // (acceptance r4, 22.10); the credits are not a constraint (Director 22.10). A stuck step goes one model up.
    model: req.model || "claude-sonnet-5-5",
    modelStuck: req.model_stuck !== undefined ? String(req.model_stuck || "") : ((req.model || "claude-sonnet-5-5") === "claude-haiku-5-5" ? "claude-sonnet-5-5" : "claude-opus-5-5"),
    reportModel: req.report_model || "claude-sonnet-5-5",
    W: Math.round(clampNum(req.image_width, 640, 1920, 1280)),
    maxFrames: Math.round(clampNum(req.max_frames, 4, 40, 24)),
    autoDialogue: req.auto_dialogue !== false,
    // Persona (fresh-mode variant, prompts.mjs PERSONAS): newbie / completionist / impatient / saveload / slow / regression.
    persona: mode === "fresh" ? String(A.persona || req.persona || "") : "",
    // Start point (a block in the middle of the game): {room, spawn, flags[], items[]} via the ?ambientprobe hooks.
    start: (mode === "fresh" && req.mode === "gate" ? req.fresh_start : req.start) || null,
    // Start from a real save (a checkpoint exported by an earlier run, e.g. «День второй»): {file, slot, load}.
    startSave: (mode === "fresh" && req.mode === "gate" ? req.fresh_start_save ?? req.start_save : req.start_save) || null,
  };
  // skip_items: rows of the doc this gate cannot reach from its start (e.g. day-one rows in a day-two doc).
  const skip = parseItems(req.skip_items, docIds);
  if (skip.length) cfg.items = cfg.items.filter((n) => !skip.includes(n));
  // --segment N (run_acceptance.sh): the rows of segment N of the request, from that segment's own start point
  // (segments.mjs: url relative to the request's url, note, start_save / start).
  const segIndex = (mode === "acceptance" || cfg.persona) && A.segment !== undefined && A.segment !== true && Array.isArray(req.segments) ? Number(A.segment) : null;
  const seg = segIndex !== null ? req.segments[segIndex] || null : null;
  if (seg) {
    if (seg.url && !A.url) cfg.url = new URL(String(seg.url), cfg.url).href;
    if (seg.note) cfg.note = [cfg.note, String(seg.note)].filter(Boolean).join(" ");
    if (seg.start_save !== undefined) cfg.startSave = seg.start_save || null;
    if (seg.start !== undefined) cfg.start = seg.start || null;
    // persona segments (regression): own step / cost caps, a goal (flags that end the run as reached), a route
    if (seg.max_steps !== undefined) cfg.maxSteps = Math.round(clampNum(seg.max_steps, 1, HARD_MAX_STEPS, cfg.maxSteps));
    if (seg.max_usd !== undefined) cfg.maxUsd = clampNum(seg.max_usd, 0.05, HARD_MAX_USD, cfg.maxUsd);
    if (seg.max_minutes !== undefined) cfg.maxMinutes = clampNum(seg.max_minutes, 5, 330, cfg.maxMinutes);
    if (seg.goal_flags) cfg.goalFlags = [].concat(seg.goal_flags).map(String);
    if (seg.goal) cfg.goal = String(seg.goal);
    if (seg.route) cfg.route = [].concat(seg.route).map(String);
    cfg.segment = segIndex + 1;
    cfg.segmentId = String(seg.id || segIndex + 1);
  }
  if (!cfg.goalFlags && req.goal_flags) cfg.goalFlags = [].concat(req.goal_flags).map(String);
  if (!cfg.goal && req.goal) cfg.goal = String(req.goal);
  if (!cfg.route && req.route) cfg.route = [].concat(req.route).map(String);
  const P = personaOf(cfg.persona);
  if (cfg.persona && !P) cfg.personaError = `неизвестная роль «${cfg.persona}»`;
  if (P && P.manualDialogue && req.auto_dialogue === undefined) cfg.autoDialogue = false;
  cfg.H = Math.round(cfg.W * FRAME_H / FRAME_W);
  const scale = cfg.W / FRAME_W;
  // Gates of one workflow run go on separate runners with the same run number: the gate's name goes into the
  // folder (…_acceptance_m3_r19), or parallel jobs would commit the same paths (M3 at f3b299c was lost so).
  const gateTag = reqPath && /^playtest_gate_/.test(path.basename(reqPath)) ? `${path.basename(reqPath, ".json").replace(/^playtest_gate_/, "")}_` : "";
  // persona runs of one workflow run go on parallel runners: the request's name keeps their folders apart
  // (persona_completionist.json and persona_completionist_day3.json → completionist_r5, completionist_day3_r5)
  const personaTag = P ? (reqPath && /^persona_/.test(path.basename(reqPath)) ? path.basename(reqPath, ".json").replace(/^persona_/, "") : cfg.persona) : "";
  const runTag = `${gateTag}${personaTag ? `${personaTag}_` : ""}${seg ? (P ? `${cfg.segmentId}_` : `s${segIndex + 1}_`) : ""}${process.env.GITHUB_RUN_NUMBER ? `r${process.env.GITHUB_RUN_NUMBER}` : (dry ? "dry" : "local")}`;
  const date = new Date().toISOString().slice(0, 10);
  // persona runs: Docs/playtest/<date>_persona_<role>[_<segment>]_r<run> (regression: <date>_persona_regression_<segment>_r<run>)
  let outDir = A.out ? path.resolve(ROOT, A.out) : path.join(ROOT, "Docs", "playtest", `${date}_${P ? "persona" : mode}_${runTag}`);
  if (!A.out) { let n = 2; const base = outDir; while (fs.existsSync(outDir)) outDir = `${base}_${n++}`; }
  const workDir = path.join(ROOT, "build", "ai_playtest", path.basename(outDir));
  fs.mkdirSync(path.join(workDir, "frames"), { recursive: true });
  fs.mkdirSync(outDir, { recursive: true });

  const t0 = Date.now();
  const log = (s) => console.log(`[${((Date.now() - t0) / 1000).toFixed(0).padStart(5)} s] ${s}`);
  const apiKey = process.env.ANTHROPIC_API_KEY || "";
  const budget = new Budget(cfg.maxUsd);
  const run = {
    cfg: { ...cfg, actions_run: process.env.GITHUB_RUN_ID ? `${process.env.GITHUB_RUN_NUMBER} (id ${process.env.GITHUB_RUN_ID})` : "" }, version: "", started: new Date().toISOString(), stop: "", steps: [], transcript: [], notes: [],
    verdicts: {}, verdictHistory: [], rooms: [], flagsOrder: [], consoleErrors: [], consoleWarnings: [], frames: [], harness: [],
    anomalies: [], invLog: [],
  };

  // Early refusals (written as a report, so the Director sees why nothing ran).
  for (const m of [cfg.model, cfg.reportModel, cfg.modelStuck].filter(Boolean)) {
    if (!priceKnown(m)) run.stop = `модель ${m} не в таблице цен (claude.mjs) — бюджет нельзя посчитать`;
  }
  if (!dry && !apiKey) run.stop = "нет ключа API (секрет CLAUDE_API → ANTHROPIC_API_KEY)";
  if (cfg.personaError) run.stop = cfg.personaError;
  let checklist = null;
  if (mode === "acceptance") {
    // context_all (default): every other row of the doc as reference — the route through the block to a row deep in it.
    if (req.context_all !== false && cfg.items.length) {
      const full = loadChecklist(ROOT, req.doc, cfg.items, []);
      try {
        const txt = fs.readFileSync(path.resolve(ROOT, full.doc), "utf8");
        const all = docRowIds(txt);
        cfg.contextItems = [...new Set([...cfg.contextItems, ...all.filter((n) => !cfg.items.includes(n))])];
      } catch (_) { /* no doc */ }
    }
    checklist = loadChecklist(ROOT, req.doc, cfg.items, cfg.contextItems);
    if (!checklist.rows.length) run.stop = run.stop || `пункты ${cfg.items.join(", ")} не найдены в Docs/ACCEPTANCE_*.md`;
    run.checklist = { doc: checklist.doc, items: checklist.rows.map((r) => r.num), missing: checklist.missing, context: checklist.context.map((r) => r.num) };
  }
  log(`mode=${mode}${cfg.persona ? ` persona=${cfg.persona}${cfg.segment ? `/${cfg.segmentId}` : ""}` : ""} items=${cfg.items.join(",") || "-"} max_usd=${cfg.maxUsd} max_steps=${cfg.maxSteps} model=${cfg.model} report=${cfg.reportModel} image=${cfg.W}x${cfg.H}${dry ? " DRY-RUN" : ""}`);

  // --- Browser ---
  let server = null, browser = null, page = null, cdp = null;
  let url = cfg.url;
  if (A["web-dir"]) {
    const port = Number(A.port || 8791);
    server = await serve(path.resolve(ROOT, A["web-dir"]), port);
    url = `http://127.0.0.1:${port}/index.html`;
    run.cfg.url = `local:${A["web-dir"]}`;
  }
  const frames = new Map();   // id → {id, file, step, kind, label}
  let frameNo = 0;
  let pointer = { x: 960, y: 600 };

  const state = async () => {
    try { return await page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null)); } catch (_) { return null; }
  };
  // Wait until the probe has been republished at least `ms` after now (hover changes have no signal).
  const freshState = async (ms) => {
    const s0 = await state();
    const tk = s0 && s0.ticks;
    await sleep(ms);
    if (tk === undefined) return;
    const tw = Date.now();
    while (Date.now() - tw < 3000) { const s = await state(); if (!s || s.ticks - tk >= ms) return; await sleep(100); }
  };
  const grab = async (clip = { x: 0, y: 0, width: FRAME_W, height: FRAME_H }, sc = scale, quality = 72) => {
    const r = await cdp.send("Page.captureScreenshot", { format: "jpeg", quality, clip: { ...clip, scale: sc } });
    return Buffer.from(r.data, "base64");
  };
  // Godot web keeps user:// in IndexedDB (Emscripten IDBFS: database "/userfs", store FILE_DATA, key = path).
  const idbSaves = () => page.evaluate(async () => {
    const out = [];
    const names = indexedDB.databases ? (await indexedDB.databases()).map((d) => d.name) : ["/userfs"];
    for (const name of names) {
      const db = await new Promise((res) => { const r = indexedDB.open(name); r.onsuccess = () => res(r.result); r.onerror = () => res(null); });
      if (!db || ![...db.objectStoreNames].includes("FILE_DATA")) { if (db) db.close(); continue; }
      const tx = db.transaction("FILE_DATA", "readonly");
      const st = tx.objectStore("FILE_DATA");
      const keys = await new Promise((res) => { const r = st.getAllKeys(); r.onsuccess = () => res(r.result); });
      for (const k of keys) {
        if (!/\/saves\/[^/]+\.json$/.test(String(k))) continue;
        const v = await new Promise((res) => { const r = st.get(k); r.onsuccess = () => res(r.result); });
        if (v && v.contents) out.push({ db: name, key: String(k), text: new TextDecoder().decode(v.contents) });
      }
      db.close();
    }
    return out;
  });
  // user:// of the web build = /userfs/godot/app_userdata/<config/name> (seen in the exported keys, 23.10).
  const userDir = () => {
    try {
      const pg = fs.readFileSync(path.join(ROOT, "game", "project.godot"), "utf8");
      const custom = /config\/use_custom_user_dir\s*=\s*true/.test(pg) && /config\/custom_user_dir_name\s*=\s*"([^"]+)"/.exec(pg);
      if (custom) return `/userfs/godot/${custom[1]}`;
      const m = /config\/name\s*=\s*"([^"]+)"/.exec(pg);
      return `/userfs/godot/app_userdata/${m ? m[1] : "Dom propavshih dorog"}`;
    } catch (_) { return "/userfs/godot/app_userdata/Dom propavshih dorog"; }
  };
  const idbPutSave = (slot, text) => page.evaluate(async ([slot, text, dir]) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open("/userfs", 21);
      r.onupgradeneeded = () => { const d = r.result; if (!d.objectStoreNames.contains("FILE_DATA")) d.createObjectStore("FILE_DATA").createIndex("timestamp", "timestamp", { unique: false }); };
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    const tx = db.transaction("FILE_DATA", "readwrite");
    const st = tx.objectStore("FILE_DATA");
    const now = new Date();
    const parts = `${dir}/saves`.split("/").filter(Boolean);
    for (let i = 2; i <= parts.length; i++) st.put({ timestamp: now, mode: 16877 }, "/" + parts.slice(0, i).join("/"));
    st.put({ timestamp: now, mode: 33206, contents: new TextEncoder().encode(text) }, `${dir}/saves/${slot}.json`);
    await new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
    db.close();
    return `${dir}/saves/${slot}.json`;
  }, [slot, text, userDir()]);

  const frame = async (step, kind, label = "") => {
    frameNo += 1;
    const id = `f${String(frameNo).padStart(4, "0")}`;
    const file = path.join(workDir, "frames", `${id}.jpg`);
    const buf = await grab();
    fs.writeFileSync(file, buf);
    const f = { id, file, step, kind, label, w: cfg.W, h: cfg.H };
    frames.set(id, f);
    return f;
  };

  // Wait for the game to react to an action and settle: walking / acting over, no staging, state stable.
  const settle = async (before, onStaging, maxMs = 90000) => {
    const ts = Date.now();
    let s = await state();
    if (!s) { await sleep(1500); return { s: null, stagingMs: 0 }; }
    while (Date.now() - ts < 1500) {
      s = await state();
      if (!s || moving(s) || staging(s) || screenSig(s) !== screenSig(before)) break;
      await sleep(100);
    }
    let last = screenSig(s), stable = Date.now(), st0 = 0, stagingMs = 0, shot = false;
    while (Date.now() - ts < maxMs) {
      s = await state();
      if (!s) break;
      const stg = staging(s);
      if (stg) {
        if (!st0) st0 = Date.now();
        if (!shot && onStaging && Date.now() - st0 > 600) { shot = true; await onStaging(); }
      } else if (st0) { stagingMs += Date.now() - st0; st0 = 0; }
      const k = screenSig(s);
      if (k !== last || moving(s) || stg) { last = k; stable = Date.now(); }
      else if (Date.now() - stable > 650) break;
      await sleep(120);
    }
    if (st0) stagingMs += Date.now() - st0;
    return { s, stagingMs };
  };

  const toFrame = (x, y) => ({ x: Math.min(FRAME_W - 1, Math.max(0, x / scale)), y: Math.min(FRAME_H - 1, Math.max(0, y / scale)) });
  // A point outside the frame the model saw (it answered in 1920×1080 window pixels): take it as window pixels.
  const toFrameChecked = (x, y, step) => {
    if (scale < 1 && (x >= cfg.W || y >= cfg.H) && x < FRAME_W && y < FRAME_H) {
      run.harness.push(`step ${step}: point (${Math.round(x)},${Math.round(y)}) outside the ${cfg.W}×${cfg.H} frame — taken as window pixels`);
      return { x, y };
    }
    return toFrame(x, y);
  };
  // A headless screenshot has no mouse pointer: a red ring marks it on every frame (pointer-events: none).
  const showPointer = async (p) => {
    try {
      await page.evaluate(([x, y]) => {
        let el = document.getElementById("__ai_ptr");
        if (!el) {
          el = document.createElement("div");
          el.id = "__ai_ptr";
          el.style.cssText = "position:fixed;width:22px;height:22px;margin:-11px 0 0 -11px;border:3px solid #ff2020;border-radius:50%;box-shadow:0 0 0 2px rgba(255,255,255,.85);pointer-events:none;z-index:2147483647";
          document.body.appendChild(el);
        }
        el.style.left = `${x}px`;
        el.style.top = `${y}px`;
      }, [p.x, p.y]);
    } catch (_) { /* page busy */ }
  };
  const mouseTo = async (p, steps = 6) => { await page.mouse.move(p.x, p.y, { steps }); pointer = p; await showPointer(p); };

  // ---- Mechanics reflexes (agent of mechanics 23.10: probeState.mechanic = {open, type, close, panel}) ----
  // The model decides WHAT to do (it read the game's explanation); the program does the motor part a person does
  // by reflex. The game clock on software WebGL runs ≈0.15× the page clock, so everything is judged from fresh
  // probe states (window.probePause(false) republishes at once), never from fixed real-time delays.
  const fresh = async () => {
    try { return await page.evaluate(() => { try { if (window.probePause) window.probePause(false); } catch (_) {} return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null; }); }
    catch (_) { return null; }
  };
  const panelOf = (s) => (s && s.mechanic && s.mechanic.open && s.mechanic.panel) || null;
  const waitFor = async (pred, ms) => { const t = Date.now(); while (Date.now() - t < ms) { const s = await fresh(); if (s && pred(s)) return s; await sleep(60); } return null; };
  // Wait `sec` GAME seconds (physics frames at 60/s; a GPU-less browser runs the game clock slower than the page clock),
  // at most `capS` real seconds. Returns {game, real} seconds actually waited.
  const waitGame = async (sec, capS) => {
    const t = Date.now();
    const s0 = await state();
    const f0 = s0 && typeof s0.physics_frames === "number" ? s0.physics_frames : null;
    if (f0 === null) { await sleep(Math.min(sec, capS) * 1000); return { game: null, real: (Date.now() - t) / 1000 }; }
    let f = f0;
    while ((f - f0) / 60 < sec && Date.now() - t < capS * 1000) {
      await sleep(250);
      const s1 = await state();
      if (s1 && typeof s1.physics_frames === "number") f = s1.physics_frames;
    }
    return { game: (f - f0) / 60, real: (Date.now() - t) / 1000 };
  };

  // «Точный удар» (F7 brace, H1 shutter latch): Space while timing.in_green and state run; until done / 12 strikes.
  const timingSeries = async (events) => {
    let strikes = 0, last = null;
    const bar = (s) => { const p = panelOf(s); return p && (p.timing || (p.hook && p.hook.timing)) || null; };
    const t0 = Date.now();
    while (strikes < 12 && Date.now() - t0 < 240000) {
      const s = await fresh();
      const t = bar(s);
      if (!t) { if (!strikes) events.push("Полосы «точного удара» на экране нет."); break; }
      last = t;
      if (t.state === "done" || (t.needed && t.hits >= t.needed)) break;
      if (t.state !== "run" || t.paused || !t.in_green) { await sleep(40); continue; }
      const p = panelOf(s);
      const target = (p && (p.strike || p.shutter)) || null;
      if (target && typeof target.x === "number") await page.mouse.click(target.x, target.y); else await page.keyboard.press("Space");
      strikes += 1;
      await waitFor((x) => { const b = bar(x); return !b || b.state !== "run" || b.hits !== t.hits; }, 8000);
      await waitFor((x) => { const b = bar(x); return !b || b.state === "run" || b.state === "done"; }, 20000);
    }
    const b = bar(await fresh()) || last;
    events.push(`Точный удар (рефлекс программы): ударов ${strikes}${b ? `, попаданий подряд ${b.hits} из ${b.needed}, промахов всего ${b.misses}${b.state === "done" ? " — серия пройдена" : ""}` : ""}.`);
  };

  // Hook F8 (H2, stand «ЗМ»): ring once → wait «sway» → double ring while the hook is in the bolt zone → hold the
  // bell until the bar lifts. A stop outside the zone: the hook falls, slips back to «wait» — start again.
  const hookSequence = async (events) => {
    const hk = (s) => { const p = panelOf(s); return p && p.hook ? { p, h: p.hook } : null; };
    let tries = 0, s = await fresh(), c = hk(s);
    if (!c) { events.push("Крюка на экране нет (крупный план зеркала конторы не открыт)."); return; }
    const bell = c.p.strike || (c.p.signals_how && c.p.signals_how.bell) || null;
    if (!bell || typeof bell.x !== "number") { events.push("Не нашла, куда звонить (strike колокола)."); return; }
    while (tries < 5) {
      tries += 1;
      c = hk(await fresh());
      if (!c) break;
      if (c.h.state === "solved") break;
      if (c.h.state === "wait") {
        await page.mouse.click(bell.x, bell.y);
        if (!(await waitFor((x) => { const k = hk(x); return k && k.h.state === "sway"; }, 60000))) { events.push("Крюк не пошёл после первого удара."); break; }
      }
      const inZone = await waitFor((x) => { const k = hk(x); return k && (k.h.in_zone || (k.h.timing && k.h.timing.in_green)) && k.h.state === "sway"; }, 90000);
      if (!inZone) { events.push("Крюк не дошёл до зоны засова."); break; }
      await page.mouse.click(bell.x, bell.y); await sleep(90); await page.mouse.click(bell.x, bell.y);   // «два — стой»
      const st = await waitFor((x) => { const k = hk(x); return k && ["stopped", "falling", "slipping", "wait"].includes(k.h.state); }, 30000);
      const k2 = st && hk(st);
      if (!k2 || k2.h.state !== "stopped") {
        events.push("Крюк остановился мимо засова и сорвался — заново.");
        await waitFor((x) => { const k = hk(x); return k && k.h.state === "wait"; }, 60000);
        continue;
      }
      await page.mouse.move(bell.x, bell.y);
      await page.mouse.down();                                                                          // «долгий — подымай»
      const lifted = await waitFor((x) => { const k = hk(x); return k && ["lift_bar", "solved"].includes(k.h.state); }, 60000);
      await page.mouse.up();
      if (lifted) { await waitFor((x) => { const k = hk(x); return !k || k.h.state === "solved"; }, 30000); break; }
    }
    const e = hk(await fresh());
    events.push(`Крюк звоном (рефлекс программы): попыток ${tries}; состояние ${e ? e.h.state : "окно закрыто"}${e ? `, промахов ${e.h.misses}` : ""}.`);
  };

  // Crossing F12 (R2): one click is queued during a pull, the rest are dropped — click rope once while not pulling,
  // wait for pulls to go up, until pulls_total; then the room changes to R3.
  const crossingPulls = async (events) => {
    const cp = (s) => { const p = panelOf(s); return p && typeof p.pulls === "number" && p.pulls_total ? p : null; };
    let c = cp(await fresh()), clicks = 0;
    if (!c) { events.push("Каната переправы на экране нет."); return; }
    const t0 = Date.now();
    while (c && c.pulls < c.pulls_total && Date.now() - t0 < 300000) {
      if (c.pulling) { c = cp(await waitFor((x) => { const k = cp(x); return !k || !k.pulling; }, 30000)); continue; }
      const at = c.rope && typeof c.rope.x === "number" ? c.rope : c.center;
      const before = c.pulls;
      await page.mouse.click(at.x, at.y);
      clicks += 1;
      c = cp(await waitFor((x) => { const k = cp(x); return !k || k.pulls > before; }, 30000));
    }
    const s = await waitFor((x) => !cp(x) || x.room === "R3", 60000);
    events.push(`Переправа (рефлекс программы): щелчков ${clicks}; ${s && s.room === "R3" ? "лодка дошла — R3" : c ? `потянуто ${c.pulls} из ${c.pulls_total}` : "окно закрылось"}.`);
  };

  // Knot F6: grab the rope end, trace the shown contour (current stroke, then the next ones) without releasing.
  const knotTrace = async (events) => {
    const kp = (s) => { const p = panelOf(s); return p && p.knot_path && p.knot_path.open ? p.knot_path : null; };
    let k = kp(await fresh());
    if (!k) { events.push("Узла на экране нет."); return; }
    for (let attempt = 0; attempt < 3 && k && k.state !== "done"; attempt++) {
      const pts = [...(k.next || []), ...((k.strokes || []).slice((k.loops_done || 0) + 1).flat())].filter((q) => q && typeof q.x === "number");
      if (!k.end || !pts.length) { events.push("Контур узла не читается."); return; }
      const dense = [];
      let prev = { x: k.end.x, y: k.end.y };
      for (const q of pts) {
        const d = Math.hypot(q.x - prev.x, q.y - prev.y), n = Math.max(1, Math.ceil(d / 60));
        for (let i = 1; i <= n; i++) dense.push({ x: prev.x + (q.x - prev.x) * i / n, y: prev.y + (q.y - prev.y) * i / n });
        prev = q;
      }
      await page.mouse.move(k.end.x, k.end.y, { steps: 3 });
      await page.mouse.down();
      await sleep(150);
      for (const q of dense) { await page.mouse.move(q.x, q.y, { steps: 2 }); await sleep(25); }
      await sleep(200);
      await page.mouse.up();
      await sleep(600);
      k = kp(await fresh());
    }
    events.push(`Узел (рефлекс программы): ${k ? `петель ${k.loops_done} из ${k.loops_total}, состояние ${k.state}` : "окно узла закрылось — узел завязан"}.`);
  };

  // Lines and narration in a row: read verbatim, frame each, real click on the text box. Options stop here.
  const runDialogue = async (step, events, extra) => {
    let n = 0;
    while (n < 80) {
      let s = await state();
      if (!s) return;
      if (staging(s) || moving(s)) {
        const r = await settle(s, async () => {
          const f = await frame(step, "staging", "затемнение / постановка");
          extra.push(f);
        });
        if (r.stagingMs > 300) events.push(`Затемнение / постановка сцены ~${(r.stagingMs / 1000).toFixed(1)} с${extra.length ? ` (кадр ${extra[extra.length - 1].id})` : ""}`);
        s = r.s;
        if (!s) return;
      }
      const b = s.beat || {};
      if (!b.type) { if (n) events.push(`Текст закончился: показано реплик и текстов — ${n}, окно текста закрыто. Можно действовать дальше.`); return; }
      if (b.type === "options") return;
      if (!cfg.autoDialogue) {
        // Manual dialogue (impatient persona): the line stays on screen; record it once, the player decides.
        const k = beatKey(s);
        if (k && !manualSeen.has(k)) {
          manualSeen.add(k);
          const f = await frame(step, "line", short(b.text, 60));
          const who = b.type === "line" ? (b.speaker_name || b.speaker || "?") : "Текст";
          events.push(`На экране реплика (сама не пролистывается): ${who}: «${String(b.text || "")}» [${f.id}]`);
          run.transcript.push({ step, frame: f.id, room: s.room, who, text: String(b.text || "") });
          extra.push(f);
        }
        return;
      }
      const f = await frame(step, "line", short(b.text, 60));
      const who = b.type === "line" ? (b.speaker_name || b.speaker || "?") : "Текст";
      const text = String(b.text || "");
      events.push(`${who}: «${text}» [${f.id}]`);
      run.transcript.push({ step, frame: f.id, room: s.room, who, text });
      if (n === 0 || extra.filter((e) => e.kind === "line").length < 2) extra.push(f);
      else extra.splice(extra.findLastIndex((e) => e.kind === "line"), 1, f);   // keep the first and the latest line
      const key = beatKey(s);
      if (P && P.lineDelay) await waitGame(P.lineDelay, 20);   // slow persona: reading time before the click
      const at = s.ui && s.ui.dialogue_click ? s.ui.dialogue_click : { x: 960, y: 900 };
      let advanced = false;
      for (let attempt = 0; attempt < 2 && !advanced; attempt++) {
        await page.mouse.move(at.x, at.y, { steps: 2 });
        await page.mouse.click(at.x, at.y);
        const tw = Date.now();
        while (Date.now() - tw < 12000) {
          const t = await state();
          if (!t || beatKey(t) !== key) { advanced = true; break; }
          await sleep(120);
        }
      }
      if (!advanced) {
        events.push("Окно текста не перелистнулось щелчком (два щелчка).");
        run.harness.push(`step ${step}: dialogue box did not advance`);
        return;
      }
      n += 1;
    }
  };

  // Captions seen under the pointer, per room, at the pointer's place in the model's frame — what a player
  // remembers after hovering («Вдоль берега» was at the left edge). M3 gate r29 (23.10): the model saw «Вдоль
  // берега» at (30,647), decided to go there and clicked (93,332) — the street exit; the turn was never reached.
  const seenLabels = {};
  const rememberHover = (s) => {
    const label = s && s.ui && s.ui.exit_hints && s.ui.exit_hints.hover;
    if (!label || !pointer || !s.room) return;
    const m = seenLabels[s.room] || (seenLabels[s.room] = new Map());
    m.delete(label);
    m.set(label, [Math.round(pointer.x * scale), Math.round(pointer.y * scale)]);
    if (m.size > 16) m.delete(m.keys().next().value);
  };
  const placesOf = (room) => [...((room && seenLabels[room]) || new Map()).entries()].map(([l, [x, y]]) => `«${l}» — (${x},${y})`);

  // Events of one step from the states before / after (what a player would notice), plus the dialogue.
  const describe = (before, after, events) => {
    if (!after) { events.push("Состояние игры не читается (зонд недоступен) — смотри на кадр."); return; }
    if (before && after.room !== before.room) events.push("Место сменилось (другая комната / локация).");
    const bi = (before && before.inventory) || [], ai = after.inventory || [];
    if (before && ai.length !== bi.length) events.push(`В сумке стало предметов: ${ai.length} (было ${bi.length}).`);
    else if (before && ai.join() !== bi.join()) events.push("Содержимое сумки изменилось.");
    if (before && after.selected_item !== before.selected_item) events.push(after.selected_item ? "Предмет взят в руку (иконка у курсора)." : "Предмета в руке больше нет.");
    const eh = (after.ui && after.ui.exit_hints) || {};
    if (eh.hover) { events.push(`Подпись под курсором: «${eh.hover}»`); rememberHover(after); }
    if (eh.hint_panel && eh.hint_panel.visible) events.push(`Открыта подсказка: «${short(eh.hint_panel.title, 80)}» — «${short(eh.hint_panel.text, 400)}»`);
    if (after.last_hint && (!before || after.last_hint !== before.last_hint)) events.push(`Строка подсказки внизу: «${short(after.last_hint, 300)}»`);
    const b = after.beat || {};
    if (b.type === "options") {
      const opts = (b.options || []).map((o, i) => `${i + 1}) «${o.label || o.id}»`).join("  ");
      events.push(`На экране выбор${b.prompt ? ` «${b.prompt}»` : ""}: ${opts} — щёлкни по строке варианта.`);
    }
    if (after.ui && after.ui.journal_open) events.push("Открыт журнал.");
    if (after.ui && after.ui.menu_open) events.push("Открыто меню.");
    if (after.pause && after.pause.open && !(before && before.pause && before.pause.open)) events.push("Открылось меню паузы (игра стоит; «Продолжить» или Escape — назад).");
    if (after.title && after.title.open && !(before && before.title && before.title.open)) events.push("Открылось главное меню.");
    if (after.puzzle && after.puzzle.open && !(before && before.puzzle && before.puzzle.open)) events.push("Открылся крупный план.");
    if (after.view && after.view.open && !(before && before.view && before.view.open)) events.push("Открылся крупный план (просмотр).");
  };

  // Model "brain" for --dry-run: a scripted path resolved against the probe (harness test without the API):
  // looks, a conversation, hover on the bag, the journal, exits, the key on the door, the H1 trio with its option.
  const dryPlan = [
    { move: "tamara" }, { rapid: "tamara" }, { key: "Space" }, { hot: "letters" }, { hot: "tamara" }, { pocketMove: "key_house" },
    { button: "JournalButton" }, { button: "CloseJournal" }, { zoom: true }, { exit: "Z4" }, { exit: "Z2" },
    { pocket: "key_house" }, { exit: "H1" }, { exit: "H1" }, { hot: "shutter" }, { hot: "stove" }, { hot: "scarf" },
    { option: true }, { wait: 2 }, { done: true },
  ];
  const dryAct = async (s) => {
    s = s || {};
    const img = (p) => ({ x: p.x * scale, y: p.y * scale });
    let a = null;
    while (!a && dryPlan.length) {
      const it = dryPlan.shift();
      const H = s.hotspots || {}, E = s.exits || {}, U = s.ui || {};
      if (it.rapid && P && P.rapid && H[it.rapid]) a = { action: "rapid", path: [[H[it.rapid].x * scale, H[it.rapid].y * scale], [960 * scale, 900 * scale], [H[it.rapid].x * scale, H[it.rapid].y * scale]] };
      else if (it.move && H[it.move]) a = { action: "move", ...img(H[it.move]) };
      else if (it.key) a = { action: "key", key: it.key };
      else if (it.hot && H[it.hot] && H[it.hot].visible) a = { action: "click", ...img(H[it.hot]) };
      else if (it.pocketMove && U.inventory && U.inventory[it.pocketMove]) a = { action: "move", ...img(U.inventory[it.pocketMove]) };
      else if (it.pocket && U.inventory && U.inventory[it.pocket]) a = { action: "click", ...img(U.inventory[it.pocket]) };
      else if (it.button && U.buttons && U.buttons[it.button]) a = { action: "click", ...img(U.buttons[it.button]) };
      else if (it.exit && E[it.exit]) a = { action: "click", ...img(E[it.exit]) };
      else if (it.option && U.options && Object.keys(U.options).length) a = { action: "click", ...img(Object.values(U.options)[0]) };
      else if (it.zoom) a = { action: "zoom", region: [420 * scale * 1.5, 0, 860 * scale * 1.5, 50 * scale * 1.5] };
      else if (it.wait) a = { action: "wait", seconds: it.wait };
      else if (it.done) a = { action: "done" };
    }
    a = a || { action: "done" };
    return { input: { observe: "dry", thought: `dry ${a.action}`, ...a, memory: "", notes: [], verdicts: [] },
      usage: { input_tokens: 0, output_tokens: 0 } };   // dry run: nothing is billed
  };

  // --- The loop ---
  let lastState = null;
  let memory = "";
  const history = [];
  let noScreenChange = 0, noProgress = 0, invalidRow = 0, refusals = 0;
  let lastClick = null, sameClick = 0, rejectedDone = 0;
  const seenTexts = new Set();
  const manualSeen = new Set();
  let pendingZoom = null;
  const reportReserve = Math.min(cfg.maxUsd * 0.25, estimateCost(cfg.reportModel, { textChars: 120000, images: Array(cfg.maxFrames).fill({ w: cfg.W, h: cfg.H }), maxOut: 9000 }));
  run.reportReserve = Number(reportReserve.toFixed(4));
  let events = [], extra = [];
  const routeTxt = P && P.route ? routeText(cfg.route) : "";
  const sys = run.stop ? "" : systemPrompt(mode, { W: cfg.W, H: cfg.H, checklist: checklist ? checklistText(checklist) : "", note: cfg.note,
    persona: cfg.persona, route: routeTxt, goal: cfg.goal || "",
    start: cfg.start ? String(cfg.start.label || "предыдущая часть игры уже пройдена, о ней ты знаешь только то, что увидишь")
      : cfg.startSave ? `загружено сохранение${saveTitle(cfg.startSave) ? ` «${saveTitle(cfg.startSave)}»` : ""} — всё, что было до него, уже пройдено (о прошлом ты знаешь только то, что увидишь в игре и журнале)`
      : startPointLabel(url) });
  const tool = actTool(mode, cfg.W, cfg.H, cfg.persona);
  const pendingItems = () => (checklist ? checklist.rows.map((r) => r.num).filter((n) => !run.verdicts[n]) : []);
  const trackProgress = (s, step) => {
    if (!s) return;
    if (run.rooms[run.rooms.length - 1] !== s.room) run.rooms.push(s.room);
    const seen = new Set(run.flagsOrder.map((f) => f.flag));
    for (const f of truthyFlags(s)) if (!seen.has(f)) run.flagsOrder.push({ flag: f, step });
  };
  // Objective anomalies from the game state (all persona runs): duplicated items, items / flags that disappear,
  // a one-time scene line shown again, the game busy for long. The report model weighs them against the actions
  // (a load of an older slot legitimately rolls the state back and replays scenes).
  const onceLines = mandatoryLines();
  const lineSeen = new Map();
  const anomaly = (step, kind, text) => { if (run.anomalies.length < 200) run.anomalies.push({ step, kind, text: short(text, 300) }); };
  const checkAnomalies = (before, after, step, desc) => {
    if (!after) return;
    const inv = after.inventory || [];
    const dup = inv.filter((x, i) => inv.indexOf(x) !== i);
    if (dup.length) anomaly(step, "дубль предмета", `в сумке дважды: ${[...new Set(dup)].join(", ")} (после «${desc}»)`);
    if (before) {
      const bi = before.inventory || [];
      const gone = bi.filter((x) => !inv.includes(x)), came = inv.filter((x) => !bi.includes(x));
      if (gone.length || came.length) run.invLog.push({ step, room: after.room, desc: short(desc, 80), plus: came, minus: gone });
      const bf = truthyFlags(before), af = new Set(truthyFlags(after));
      const lost = bf.filter((f) => !af.has(f));
      if (lost.length) anomaly(step, "флаги сброшены", `${lost.length}: ${lost.slice(0, 12).join(", ")}${lost.length > 12 ? " …" : ""} (после «${desc}»; комната ${before.room}→${after.room})`);
      if (before.goal && after.goal && before.goal !== after.goal && lost.length) anomaly(step, "цель журнала откатилась", `«${short(before.goal, 90)}» → «${short(after.goal, 90)}»`);
    }
    for (const t of run.transcript.filter((x) => x.step === step)) {
      const id = onceLines.get(normText(t.text));
      if (!id) continue;
      const first = lineSeen.get(id);
      if (first === undefined) lineSeen.set(id, step);
      else if (first !== step) { anomaly(step, "разовая реплика повторилась", `${id} «${short(t.text, 80)}» — впервые на шаге ${first}, снова на шаге ${step} (после «${desc}»)`); lineSeen.set(id, step); }
    }
  };

  try {
    if (!run.stop) {
      browser = await chromium.launch({ headless: true, executablePath: findChromium(),
        args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
          "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
      const context = await browser.newContext({ viewport: { width: FRAME_W, height: FRAME_H }, deviceScaleFactor: 1 });
      page = await context.newPage();
      page.setDefaultTimeout(180000);
      page.on("console", (m) => {
        if (m.type() !== "error") return;
        const t = m.text();
        if (/^WARNING: /.test(t) || /^at: push_warning/.test(t)) { if (!/^at: /.test(t) && run.consoleWarnings.length < 40) run.consoleWarnings.push(short(t, 300)); }
        else if (run.consoleErrors.length < 30) run.consoleErrors.push(short(t, 300));
      });
      page.on("pageerror", (e) => { if (run.consoleErrors.length < 30) run.consoleErrors.push(`pageerror: ${short(e.message, 300)}`); });
      cdp = await context.newCDPSession(page);
      try {
        const vr = await page.request.get(new URL("version.txt", url.endsWith("/") || url.endsWith(".html") ? url : url + "/").toString(), { timeout: 30000 });
        if (vr.ok()) run.version = (await vr.text()).trim().slice(0, 80);
      } catch (_) { /* no version.txt locally */ }
      if (cfg.startSave) {
        // Same origin first (IndexedDB is per origin), the save in place, then the game reads it at start-up.
        try {
          const sf = path.resolve(ROOT, String(cfg.startSave.file || cfg.startSave));
          const text = fs.readFileSync(sf, "utf8");
          const slot = String(cfg.startSave.slot || path.basename(sf, ".json"));
          await page.goto(new URL("version.txt", url.endsWith("/") || url.endsWith(".html") ? url : url + "/").toString(), { waitUntil: "load", timeout: 60000 }).catch(() => {});
          await idbPutSave(slot, text);
          run.consoleErrors.length = 0;   // the helper page's favicon 404 is not the game's
          run.startSave = { file: path.relative(ROOT, sf), slot, title: (JSON.parse(text).title || "") };
          log(`save ${run.startSave.file} → slot ${slot}`);
        } catch (e) { run.harness.push(`start_save failed: ${short(e && e.message, 160)}`); }
      }
      log(`open ${run.cfg.url} (build ${run.version || "?"})${cfg.start ? ` from ${cfg.start.room || "?"}` : ""}`);
      await page.goto(cfg.start ? url + (url.includes("?") ? "&" : "?") + "ambientprobe" : url, { waitUntil: "load", timeout: 180000 });
      try {
        await page.waitForFunction(() => window.probeReady === true, null, { timeout: 300000 });
        run.probe = true;
      } catch (_) {
        run.probe = false;
        run.harness.push("window.probeReady did not appear in 300 s: settling by time only");
        await sleep(20000);
      }
      await sleep(2500);
      if (cfg.start) {
        // A block in the middle of the game: story flags, the bag (needs window.ambientItem), the room.
        try {
          await page.waitForFunction(() => window.ambientProbeReady === true, null, { timeout: 60000 });
          for (const f of cfg.start.flags || []) await page.evaluate((x) => window.ambientFlag(x, true), String(f));
          const items = cfg.start.items || [];
          if (items.length) {
            const can = await page.evaluate(() => typeof window.ambientItem === "function");
            if (can) for (const it of items) await page.evaluate((x) => window.ambientItem(x), String(it));
            else run.harness.push(`start: items ${items.join(", ")} not given — the build has no window.ambientItem hook`);
          }
          if (cfg.start.room) await page.evaluate(([r, sp]) => window.ambientGoto(r, sp), [String(cfg.start.room), String(cfg.start.spawn || "default")]);
          await sleep(1500);
          run.startNote = `старт с ${cfg.start.room || "?"}: флагов ${(cfg.start.flags || []).length}, предметов ${(cfg.start.items || []).length}`;
        } catch (e) { run.harness.push(`start point failed: ${short(e && e.message, 160)}`); }
      }
      if (run.startSave && cfg.startSave.load !== false) {
        // Like a player: «Меню» → the pause's «Загрузить» → the slot's «Загрузить» (real clicks on the probe's centres).
        try {
          let s0 = await state();
          const mb = s0 && s0.ui && s0.ui.buttons && s0.ui.buttons.MenuButton;
          if (mb) { await page.mouse.click(mb.x, mb.y); await sleep(900); }
          s0 = await state();
          const pl = s0 && s0.pause && s0.pause.open && s0.pause.items && s0.pause.items.load;
          if (pl) { await page.mouse.click(pl.x, pl.y); await sleep(900); }
          s0 = await state();
          const lb = s0 && s0.ui && s0.ui.buttons && s0.ui.buttons[`Load${run.startSave.slot}`];
          if (!lb) throw new Error(`no Load${run.startSave.slot} in the menu (${Object.keys((s0 && s0.ui && s0.ui.buttons) || {}).join(",")})`);
          await page.mouse.click(lb.x, lb.y);
          await sleep(2500);
          const s1 = await state();
          if (s1 && s1.ui && s1.ui.menu_open && s1.ui.buttons.CloseMenu) { await page.mouse.click(s1.ui.buttons.CloseMenu.x, s1.ui.buttons.CloseMenu.y); await sleep(600); }
          run.startNote = `загружено сохранение «${run.startSave.title || run.startSave.slot}» (${run.startSave.file}) через «Меню → Загрузить»; комната ${(await state() || {}).room || "?"}`;
        } catch (e) { run.harness.push(`start_save load: ${short(e && e.message, 200)}`); }
      }
      lastState = await state();
      trackProgress(lastState, 0);
      await mouseTo(pointer, 1);
      // Something already on screen at the start (an opening text): read it like any other dialogue.
      await runDialogue(0, events, extra);
      const st = await state();
      describe(lastState, st, events);
      lastState = st;
      log(`game loaded: room=${st && st.room} probe=${run.probe}`);
    }

    for (let step = 1; !run.stop && step <= cfg.maxSteps; step++) {
      if ((Date.now() - t0) / 60000 > cfg.maxMinutes) { run.stop = `время: ${cfg.maxMinutes} мин`; break; }
      // Which model: the cheap one; the stronger one for a single step when the run is stuck.
      const stuck = noScreenChange >= 3 || noProgress >= 10;
      const stepEst = (m) => Math.max(estimateCost(m, { textChars: 9000, images: [{ w: cfg.W, h: cfg.H }, { w: cfg.W, h: cfg.H }, { w: cfg.W, h: cfg.H }], maxOut: 700 }),
        budget.recentStepCost(m) * 1.3);
      let model = cfg.model;
      if (stuck && cfg.modelStuck && step % 2 === 0 && budget.fits(stepEst(cfg.modelStuck), reportReserve)) model = cfg.modelStuck;
      const est = stepEst(model);
      if (!budget.fits(est, reportReserve)) {
        run.stop = `бюджет: потрачено $${budget.spent.toFixed(3)} из $${cfg.maxUsd}, ещё шаг (~$${est.toFixed(4)}) и отчёт (резерв $${reportReserve.toFixed(2)}) не помещаются`;
        break;
      }

      // The frame the model sees now (+ a zoom crop if asked, + frames from the dialogue that just played).
      const cur = await frame(step, "step", "");
      const images = [];
      const labels = [];
      for (const f of extra.slice(-3)) { images.push(f); labels.push(`${f.id} — ${f.kind === "staging" ? "во время затемнения" : "реплика по ходу"}`); }
      let zoomBuf = null;
      if (pendingZoom) {
        const [x0, y0, x1, y1] = pendingZoom;
        const a = toFrame(Math.min(x0, x1), Math.min(y0, y1)), b = toFrame(Math.max(x0, x1), Math.max(y0, y1));
        const w = Math.max(40, b.x - a.x), h = Math.max(30, b.y - a.y);
        const sc = Math.min(cfg.W / w, cfg.H / h, 3);
        zoomBuf = { buf: await grab({ x: a.x, y: a.y, width: Math.min(w, FRAME_W - a.x), height: Math.min(h, FRAME_H - a.y) }, sc, 80), w: Math.round(w * sc), h: Math.round(h * sc) };
        fs.writeFileSync(path.join(workDir, "frames", `zoom_${step}.jpg`), zoomBuf.buf);
        labels.push(`увеличенный фрагмент (${pendingZoom.map(Math.round).join(", ")}) текущего кадра — координаты для действий бери по полному кадру`);
        pendingZoom = null;
      }
      labels.push(`${cur.id} — ТЕКУЩИЙ кадр ${cfg.W}×${cfg.H}`);

      const warnings = [];
      if (noScreenChange >= 2) warnings.push(`Последние ${noScreenChange} действия ничего не изменили на экране. Попробуй другое место или другой способ.`);
      if (sameClick >= 2) warnings.push("Ты щёлкаешь в одну и ту же точку — она не реагирует. Наведи курсор (move) рядом, чтобы найти подпись, или ищи в другом месте.");
      if (noProgress >= 12) warnings.push(mode === "acceptance"
        ? `${noProgress} шагов без продвижения. Если текущий пункт не даётся — дай «не дошёл» с объяснением и переходи к следующему, или возьми игровую «Подсказку».`
        : `${noProgress} шагов без продвижения истории. Подумай, что ещё не пробовала; можно взять игровую «Подсказку» (и отметить это).`);
      const left = cfg.maxSteps - step;
      if (left <= 5 || budget.left() - reportReserve < est * 6) warnings.push(mode === "acceptance"
        ? "Шаги или бюджет почти кончились: дай вердикты по всему, что успела увидеть."
        : "Шаги или бюджет почти кончились: запиши главные впечатления в notes.");

      const recent = run.transcript.filter((t) => t.step < step).slice(-14).map((t) => `#${t.step} ${t.who}: «${short(t.text, 220)}»`);
      const text = stepText({ step, maxSteps: cfg.maxSteps, spent: budget.spent, maxUsd: cfg.maxUsd, memory,
        verdicts: Object.values(run.verdicts), pending: pendingItems(), history: history.slice(-12), recent, events, warnings, imageLabels: labels,
        places: placesOf(lastState && lastState.room) });
      const content = [];
      for (const f of extra.slice(-3)) {
        content.push({ type: "text", text: `${f.id}${f.kind === "staging" ? " (затемнение)" : " (реплика)"}:` });
        content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: fs.readFileSync(f.file).toString("base64") } });
      }
      if (zoomBuf) {
        content.push({ type: "text", text: "Увеличенный фрагмент:" });
        content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: zoomBuf.buf.toString("base64") } });
      }
      content.push({ type: "text", text: `${cur.id} (текущий кадр):` });
      content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: fs.readFileSync(cur.file).toString("base64") } });
      content.push({ type: "text", text });

      // Ask the model.
      let input = null, usd = 0;
      try {
        let resp;
        if (dry) resp = await dryAct(lastState);
        else {
          // The system prompt and the tool are the same every step: cached (tools → system prefix).
          const r = await callTool(apiKey, { model, max_tokens: 6000, system: [{ type: "text", text: sys, cache_control: { type: "ephemeral" } }],
            tools: [tool], output_config: { effort: "low" }, messages: [{ role: "user", content }] }, "act", { log });
          resp = r.resp;
          resp.input = r.input;
        }
        usd = budget.add(dry ? cfg.model : model, resp.usage, `step${step}`);
        input = resp.input;
        if (!dry && resp.stop_reason === "refusal") { refusals += 1; run.harness.push(`step ${step}: refusal`); }
      } catch (e) {
        if (e instanceof ApiError && e.status === 400 && model !== cfg.model && !/workspace|credit|billing|balance/i.test(e.message)) {
          // The stronger model of a stuck step refused the request: no more escalation, the run goes on.
          run.harness.push(`step ${step}: ${model} — ${short(e.message, 200)}; escalation off`);
          cfg.modelStuck = "";
          continue;
        }
        if (e instanceof ApiError) {
          run.stop = `API: ${e.status === 401 ? "ключ не принят (401)"
            : e.type === "workspace" ? e.message.replace(/^HTTP \d+ workspace: /, "")
            : e.status === 404 && /workspace/i.test(e.message) ? "рабочее пространство не найдено или у владельца ключа нет к нему доступа (проверьте CLAUDE_WORKSPACE)"
            : /anthropic-workspace-id header must be a valid/i.test(e.message) ? "CLAUDE_WORKSPACE — не ID пространства (нужен вида wrkspc_…)"
            : /credit|billing|balance/i.test(e.message) ? "на счёте API нет средств"
            : `ошибка ${e.status} ${e.type}`}`;
          run.harness.push(`step ${step}: ${short(e.message, 200)}`);
          break;
        }
        throw e;
      }
      if (!input || !input.action) {
        invalidRow += 1;
        events = ["Прошлый ответ не содержал действия — сделай одно действие инструментом act."];
        extra = [];
        if (invalidRow >= 3 || refusals >= 3) { run.stop = "модель три раза подряд не дала действия"; break; }
        continue;
      }
      invalidRow = 0;

      // Memory, notes, verdicts.
      if (input.memory && String(input.memory).trim()) memory = short(input.memory, 900);
      const validFrames = (arr) => (Array.isArray(arr) ? arr.map(String).filter((id) => frames.has(id)) : []);
      for (const n of Array.isArray(input.notes) ? input.notes : []) {
        if (!n || !n.text) continue;
        const fr = validFrames(n.frames);
        run.notes.push({ step, kind: String(n.kind || "впечатление"), text: short(n.text, 600), frames: fr.length ? fr : [cur.id] });
      }
      if (mode === "acceptance") {
        for (const v of Array.isArray(input.verdicts) ? input.verdicts : []) {
          const num = normId(v && v.item);
          if (!checklist.rows.some((r) => r.num === num)) continue;
          const fr = validFrames(v.frames);
          const rec = { item: num, status: String(v.status || ""), seen: short(v.seen, 900), frames: fr.length ? fr : [cur.id], step };
          run.verdicts[num] = rec;
          run.verdictHistory.push(rec);
        }
      }

      // Execute.
      const before = await state();
      const act = String(input.action);
      let desc = act;
      const x = Number(input.x), y = Number(input.y);
      const hasXY = Number.isFinite(x) && Number.isFinite(y);
      const stepRec = { step, model, room: before && before.room, frame: cur.id, action: act, observe: short(input.observe, 300), thought: short(input.thought, 300), usd: Number(usd.toFixed(5)) };
      events = [];
      extra = [];
      if (["click", "right_click", "double_click", "hold", "move", "drag"].includes(act) && !hasXY) {
        events.push(`Действие ${act} не выполнено: нет координат x, y.`);
      } else if (act === "click" || act === "right_click" || act === "double_click") {
        const p = toFrameChecked(x, y, step);
        await mouseTo(p, 5);
        await sleep(120);
        if (act === "double_click") { await page.mouse.click(p.x, p.y); await sleep(140); await page.mouse.click(p.x, p.y); }
        else {
          const times = act === "click" ? Math.round(clampNum(input.times, 1, 12, 1)) : 1;   // e.g. pulls on the crossing rope
          for (let i = 0; i < times; i++) { await page.mouse.click(p.x, p.y, { button: act === "right_click" ? "right" : "left" }); if (times > 1) await sleep(1200); }
          if (times > 1) stepRec.times = times;
        }
        desc = `${act === "click" ? "щелчок" : act === "right_click" ? "правый щелчок" : "двойной щелчок"} (${Math.round(x)},${Math.round(y)})`;
        stepRec.at = { x: Math.round(p.x), y: Math.round(p.y) };
        if (lastClick && Math.hypot(lastClick.x - p.x, lastClick.y - p.y) < 20) sameClick += 1; else sameClick = 0;
        lastClick = p;
      } else if (act === "hold") {
        const p = toFrameChecked(x, y, step);
        const sec = clampNum(input.seconds, 0.3, 5, 1);
        await mouseTo(p, 5);
        await sleep(100);
        await page.mouse.down();
        await sleep(sec * 1000);
        await page.mouse.up();
        desc = `держала кнопку ${sec} с в (${Math.round(x)},${Math.round(y)})`;
        stepRec.at = { x: Math.round(p.x), y: Math.round(p.y) };
        stepRec.hold = sec;
      } else if (act === "move") {
        const p = toFrameChecked(x, y, step);
        await mouseTo({ x: p.x - 25, y: p.y - 8 }, 2);
        await mouseTo(p, 5);
        await freshState(700);
        desc = `навела курсор (${Math.round(x)},${Math.round(y)})`;
        stepRec.at = { x: Math.round(p.x), y: Math.round(p.y) };
      } else if (act === "drag") {
        const p = toFrameChecked(x, y, step), q = toFrameChecked(Number(input.x2), Number(input.y2), step);
        if (!Number.isFinite(q.x) || !Number.isFinite(q.y)) events.push("drag не выполнен: нет x2, y2.");
        else {
          await mouseTo(p, 4);
          await page.mouse.down();
          await sleep(150);
          await page.mouse.move(q.x, q.y, { steps: 16 });
          pointer = q;
          await showPointer(q);
          await sleep(150);
          await page.mouse.up();
          desc = `перетащила (${Math.round(x)},${Math.round(y)}) → (${Math.round(input.x2)},${Math.round(input.y2)})`;
          stepRec.at = { x: Math.round(p.x), y: Math.round(p.y), x2: Math.round(q.x), y2: Math.round(q.y) };
        }
      } else if (act === "drag_path") {
        const pts = (Array.isArray(input.path) ? input.path : []).filter((q) => Array.isArray(q) && q.length >= 2 && q.every(Number.isFinite)).slice(0, 40)
          .map((q) => toFrameChecked(Number(q[0]), Number(q[1]), step));
        if (pts.length < 2) events.push("drag_path не выполнен: нужно хотя бы 2 точки path.");
        else {
          await mouseTo(pts[0], 4);
          await page.mouse.down();
          await sleep(120);
          for (const q of pts.slice(1)) { await page.mouse.move(q.x, q.y, { steps: 8 }); await sleep(30); }
          pointer = pts[pts.length - 1];
          await showPointer(pointer);
          await sleep(120);
          await page.mouse.up();
          desc = `протянула по ${pts.length} точкам`;
          stepRec.path = pts.map((q) => [Math.round(q.x), Math.round(q.y)]);
        }
      } else if (act === "key") {
        let k = String(input.key || "").trim();
        const map = { " ": "Space", "пробел": "Space", "space": "Space", "esc": "Escape", "escape": "Escape", "enter": "Enter", "tab": "Tab" };
        k = map[k.toLowerCase()] || k;
        const ok = /^(Space|Enter|Escape|Tab|F([1-9]|10)|Arrow(Left|Right|Up|Down)|[0-9]|[a-zA-Z])$/.test(k);
        if (!ok) events.push(`Клавиша «${short(k, 20)}» не разрешена в плейтесте.`);
        else {
          await page.keyboard.press(k);
          desc = `клавиша ${k}`;
          stepRec.key = k;
        }
      } else if (act === "timing") {
        await timingSeries(events);
        desc = "точный удар (серия)";
      } else if (act === "hook") {
        await hookSequence(events);
        desc = "крюк звоном";
      } else if (act === "crossing") {
        await crossingPulls(events);
        desc = "переправа: тянуть канат";
      } else if (act === "knot") {
        await knotTrace(events);
        desc = "узел по контуру";
      } else if (act === "rapid" && P && P.rapid) {
        // A burst without settling: the next click lands while Agata walks, a line types, an animation plays.
        const pts = (Array.isArray(input.path) ? input.path : []).filter((q) => Array.isArray(q) && q.length >= 2 && q.every(Number.isFinite)).slice(0, 12)
          .map((q) => toFrameChecked(Number(q[0]), Number(q[1]), step));
        if (!pts.length) events.push("rapid не выполнен: нужна хотя бы 1 точка path.");
        else {
          for (const q of pts) { await page.mouse.move(q.x, q.y, { steps: 1 }); await page.mouse.click(q.x, q.y); await sleep(120); }
          pointer = pts[pts.length - 1];
          await showPointer(pointer);
          desc = `быстрая очередь ${pts.length} щелчков`;
          stepRec.path = pts.map((q) => [Math.round(q.x), Math.round(q.y)]);
        }
      } else if (act === "wait" && P && P.gameWait) {
        const sec = clampNum(input.seconds, 1, 60, 5);
        const w = await waitGame(sec, 300);
        desc = w.game === null ? `ждала ${Math.round(w.real)} с` : `ждала ${w.game.toFixed(1)} игровых с (${Math.round(w.real)} с по часам)`;
        stepRec.wait = w;
      } else if (act === "wait") {
        const sec = clampNum(input.seconds, 1, 20, 3);
        await sleep(sec * 1000);
        desc = `ждала ${sec} с`;
      } else if (act === "zoom") {
        const r = Array.isArray(input.region) && input.region.length === 4 ? input.region.map(Number) : null;
        if (r && r.every(Number.isFinite)) { pendingZoom = r; desc = `увеличила (${r.map(Math.round).join(",")})`; }
        else events.push("zoom не выполнен: нужен region [x0,y0,x1,y1].");
      } else if (act === "done" && mode === "acceptance" && pendingItems().length + Object.values(run.verdicts).filter((v) => v.status === "не дошёл").length > 0
          && step < cfg.maxSteps * 0.8 && noProgress < 30 && rejectedDone < 3) {
        // Too early: rows deep in the block need the story played up to them (gate r12 gave up after 24 steps).
        rejectedDone += 1;
        events.push("Завершать рано: есть пункты без проверки или «не дошёл», а шаги ещё есть. Пройди сюжет до этих пунктов (смотри справку — порядок дня), бери игровую «Подсказку», если не ясно, куда идти.");
        desc = "попытка завершить (отклонена)";
      } else if (act === "done") {
        run.stop = `модель завершила прогон (done): ${short(input.thought, 200)}`;
      } else {
        events.push(`Неизвестное действие ${act}.`);
      }
      stepRec.desc = desc;

      // Settle, read the dialogue, describe what happened.
      let after = before;
      if (act !== "done" && act !== "zoom") {
        if (act === "key" && stepRec.key === "Space") { await sleep(250); after = await state(); }   // the reveal lasts ~1.5 s: frame it now
        else {
          const r = await settle(before, async () => { extra.push(await frame(step, "staging", "затемнение / постановка")); });
          if (r.stagingMs > 300) events.push(`Затемнение / постановка сцены ~${(r.stagingMs / 1000).toFixed(1)} с.`);
          if (P && r.stagingMs > 85000) anomaly(step, "игра занята долго", `затемнение / постановка не кончилась за ${Math.round(r.stagingMs / 1000)} с (после «${desc}», комната ${(r.s && r.s.room) || "?"})`);
          for (let i = 0; i < 3; i++) {
            const n0 = run.transcript.length;
            await runDialogue(step, events, extra);
            const r2 = await settle(await state(), async () => { extra.push(await frame(step, "staging", "затемнение / постановка")); });
            if (r2.stagingMs > 300) events.push(`Затемнение / постановка сцены ~${(r2.stagingMs / 1000).toFixed(1)} с.`);
            const t = await state();
            if (run.transcript.length === n0 && !(t && t.beat && (t.beat.type === "line" || t.beat.type === "narration"))) break;
          }
          if (pointer) { await page.mouse.move(pointer.x, pointer.y, { steps: 2 }); await showPointer(pointer); }
          await freshState(700);   // the caption under the pointer reaches the probe on its 0.4 s refresh
          after = await state();
        }
        describe(before, after, events);
      }
      // Change counters.
      if (act !== "zoom" && act !== "done") {
        if (screenSig(after) === screenSig(before) && events.filter((e) => !e.startsWith("Подпись под курсором")).length === 0) noScreenChange += 1;
        else noScreenChange = 0;
        // Progress: the room / flags / bag / close-up changed, or a text never seen before was shown.
        const newTexts = run.transcript.filter((t) => t.step === step && !seenTexts.has(t.text));
        for (const t of run.transcript.filter((t) => t.step === step)) seenTexts.add(t.text);
        if (progressSig(after) === progressSig(before) && !newTexts.length) noProgress += 1;
        else noProgress = 0;
        if (noScreenChange === 0) sameClick = Math.min(sameClick, 0);
      }
      if (noScreenChange && act !== "move") events.push("Видимых изменений нет.");
      trackProgress(after, step);
      if (P) checkAnomalies(before, after, step, desc);
      lastState = after;
      stepRec.room_after = after && after.room;
      if (after) { stepRec.inv = (after.inventory || []).join(","); stepRec.flags = truthyFlags(after).length; }
      stepRec.events = events.map((e) => short(e, 400));
      run.steps.push(stepRec);
      const lines = run.transcript.filter((t) => t.step === step);
      const other = events.filter((e) => !/^Видимых/.test(e) && !/» \[f\d+\]$/.test(e) && !/^Текст закончился/.test(e));
      const said = lines.length ? `реплик ${lines.length}: «${short(lines[0].text, 70)}»${lines.length > 1 ? ` … «${short(lines[lines.length - 1].text, 70)}»` : ""}; ` : "";
      history.push(`#${step} ${desc}${input.thought ? ` — «${short(input.thought, 110)}»` : ""} → ${said}${short(other.slice(0, 3).join(" | "), 200) || (said ? "" : "без изменений")}`);
      log(`step ${String(step).padStart(3)}/${cfg.maxSteps} [${(before && before.room) || "?"}→${(after && after.room) || "?"}] ${act}${stepRec.at ? ` (${stepRec.at.x},${stepRec.at.y})` : ""}${model !== cfg.model ? ` model=${model}` : ""} +$${usd.toFixed(4)} = $${budget.spent.toFixed(4)}`);
      if (cfg.goalFlags && cfg.goalFlags.length && after && cfg.goalFlags.every((f) => after.flags && after.flags[f])) {
        run.goalReached = step;
        run.stop = `цель отрезка достигнута на шаге ${step} (${cfg.goalFlags.join(", ")})`;
        break;
      }
      if (noProgress >= (mode === "acceptance" ? 40 : 45)) { run.stop = `застряла: ${noProgress} шагов без продвижения`; break; }
    }
    if (!run.stop) run.stop = `потолок шагов: ${cfg.maxSteps}`;
  } catch (e) {
    run.stop = run.stop || `сбой плейтеста: ${short(e && e.message, 200)}`;
    run.harness.push(`exception: ${short(e && e.stack, 800)}`);
    log(`exception: ${short(e && e.message, 200)}`);
  }

  // Last frame and the true end state.
  let lastFrame = null;
  try { if (page && cdp) lastFrame = await frame(run.steps.length + 1, "final", "последний кадр"); } catch (_) {}
  const endState = page ? await state() : null;
  // Saves of this run (checkpoints like «День второй») — a later gate can start from them (start_save).
  try {
    if (page) {
      const saves = await idbSaves();
      if (saves.length) {
        fs.mkdirSync(path.join(outDir, "saves"), { recursive: true });
        run.saves = [];
        for (const sv of saves.slice(0, 8)) {
          const slot = path.basename(sv.key, ".json");
          fs.writeFileSync(path.join(outDir, "saves", `${slot}.json`), sv.text);
          let title = ""; try { title = JSON.parse(sv.text).title || ""; } catch (_) {}
          run.saves.push({ slot, title, key: sv.key });
          // A checkpoint the game wrote itself («День второй», day3 …) replaces the shared start save of later gates.
          if (title && /^day\d+$/.test(slot) && !dry && !P && !(run.startSave && run.startSave.slot === slot)) {
            fs.mkdirSync(path.join(ROOT, "Docs", "playtest", "saves"), { recursive: true });
            fs.writeFileSync(path.join(ROOT, "Docs", "playtest", "saves", `${slot}.json`), sv.text);
            run.harness.push(`checkpoint ${slot} «${title}» → Docs/playtest/saves/${slot}.json (start of later gates)`);
          }
        }
      }
    }
  } catch (e) { run.harness.push(`saves export: ${short(e && e.message, 160)}`); }
  run.end = endState ? { room: endState.room, inventory: endState.inventory, goal: endState.goal, flags: truthyFlags(endState).length } : null;
  run.endFlags = endState ? truthyFlags(endState) : [];
  run.blocked = blockedScenes(run.endFlags, run.rooms);
  if (P) run.coverage = coverage(run.endFlags, run.rooms, run.transcript);
  if (cfg.goalFlags) run.goal = { flags: cfg.goalFlags, reached: cfg.goalFlags.every((f) => run.endFlags.includes(f)), step: run.goalReached || null };
  if (mode === "acceptance") {
    for (const r of checklist ? checklist.rows : []) {
      if (!run.verdicts[r.num]) run.verdicts[r.num] = { item: r.num, status: "не дошёл", seen: `вердикта нет: прогон остановлен (${run.stop})`, frames: [], step: null, auto: true };
    }
  }
  log(`stop: ${run.stop}`);

  // --- Frames for the report: failures first, then bugs / stuck notes, then passes, then the last frame.
  const chosen = [];
  const pick = (id) => { if (id && frames.has(id) && !chosen.includes(id) && chosen.length < cfg.maxFrames) chosen.push(id); };
  const vs = Object.values(run.verdicts).sort(vSort(checklist));
  for (const v of vs) if (v.status !== "прошёл") v.frames.slice(0, 3).forEach(pick);
  for (const n of run.notes) if (["баг", "застряла", "непонятно"].includes(n.kind)) n.frames.slice(0, 2).forEach(pick);
  for (const v of vs) if (v.status === "прошёл") v.frames.slice(0, 1).forEach(pick);
  if (lastFrame) pick(lastFrame.id);
  for (const n of run.notes) n.frames.slice(0, 1).forEach(pick);
  chosen.sort();
  for (const id of chosen) fs.copyFileSync(frames.get(id).file, path.join(outDir, `${id}.jpg`));
  run.frames = chosen.map((id) => { const f = frames.get(id); return { id, step: f.step, kind: f.kind, label: f.label }; });

  // --- Final report: a stronger model checks the verdicts against the transcript and frames.
  let body = "";
  const reportInput = buildReportInput(run, cfg, checklist);
  let reportImages = chosen.slice(0, 20);
  const estOf = (imgs) => estimateCost(cfg.reportModel, { textChars: reportInput.length, images: imgs.map(() => ({ w: cfg.W, h: cfg.H })), maxOut: 9000 });
  while (reportImages.length && !budget.fits(estOf(reportImages), 0)) reportImages = reportImages.slice(0, Math.floor(reportImages.length / 2));
  const estReport = estOf(reportImages);
  if (!dry && apiKey && (run.steps.length || run.transcript.length) && budget.fits(estReport, 0)) {
    try {
      const content = [];
      for (const id of reportImages) {
        content.push({ type: "text", text: `Кадр ${id}:` });
        content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: fs.readFileSync(frames.get(id).file).toString("base64") } });
      }
      content.push({ type: "text", text: reportInput });
      const base = { model: cfg.reportModel, max_tokens: 16000, system: reportSystem(mode, cfg.persona), messages: [{ role: "user", content }] };
      let resp;
      const long = { log, timeoutMs: 300000, attempts: 3, stream: true };   // the report with thinking: streamed
      try { resp = await callClaude(apiKey, { ...base, output_config: { effort: "medium" } }, long); }
      catch (e) { if (e instanceof ApiError && e.status === 400) resp = await callClaude(apiKey, base, long); else throw e; }
      budget.add(cfg.reportModel, resp.usage, "report");
      body = (resp.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();
      log(`report: ${cfg.reportModel} +$${budget.calls[budget.calls.length - 1].usd.toFixed(4)}`);
    } catch (e) {
      run.harness.push(`report model: ${short(e && e.message, 200)}`);
      body = "";
    }
  } else if (!dry && apiKey && (run.steps.length || run.transcript.length)) {
    run.harness.push(`report model skipped: estimate $${estReport.toFixed(3)} does not fit (left $${budget.left().toFixed(3)})`);
  }

  const md = renderReport(run, cfg, checklist, body, budget, Math.round((Date.now() - t0) / 60000));
  fs.writeFileSync(path.join(outDir, "report.md"), md);
  fs.writeFileSync(path.join(outDir, "usage.json"), JSON.stringify({ ...budget.toJSON(), report_reserve_usd: run.reportReserve, stop: run.stop }, null, 1));
  fs.writeFileSync(path.join(outDir, "log.json"), JSON.stringify({
    cfg: run.cfg, version: run.version, started: run.started, stop: run.stop, probe: run.probe, end: run.end, start_save: run.startSave, saves: run.saves,
    rooms: run.rooms, flags_order: run.flagsOrder, blocked_scenes: run.blocked, harness: run.harness, console_errors: run.consoleErrors, console_warnings: run.consoleWarnings,
    persona: cfg.persona || undefined, segment: cfg.segmentId || undefined, goal: run.goal, anomalies: run.anomalies, inventory_log: run.invLog, coverage: run.coverage, end_flags: run.endFlags,
    checklist: run.checklist, verdict_history: run.verdictHistory, notes: run.notes, frames: run.frames,
    steps: run.steps, transcript: run.transcript,
  }, null, 1));
  log(`report: ${path.relative(ROOT, outDir)}/report.md; spent $${budget.spent.toFixed(4)} of $${cfg.maxUsd}`);
  try { if (browser) await browser.close(); } catch (_) {}
  if (server) server.close();
  // Summary line for the workflow's commit message.
  const sum = mode === "acceptance"
    ? Object.values(run.verdicts).reduce((a, v) => { a[v.status] = (a[v.status] || 0) + 1; return a; }, {})
    : run.goal ? { [run.goal.reached ? "цель достигнута" : "цель НЕ достигнута"]: run.goal.flags.join("+"), шагов: run.steps.length }
    : { шагов: run.steps.length, ...(P ? { аномалий: run.anomalies.length } : {}) };
  fs.writeFileSync(path.join(ROOT, "build", "ai_playtest", "last_out.txt"), path.relative(ROOT, outDir));
  fs.writeFileSync(path.join(workDir, "summary.txt"), `${path.basename(outDir)}: ${Object.entries(sum).map(([k, v]) => `${k} ${v}`).join(", ")}; $${budget.spent.toFixed(2)}`);
  process.exit(0);
}

/**
 * Diagnostics for the report: main scenes of the rooms the run visited that did not complete, with the
 * flags their `requires` still miss and the scene that grants each (data/story/scenes of this checkout).
 * Tells «the game is broken» from «a step was skipped» (acceptance r6: the night did not start because M06
 * — two of three class traces — was never done, so M07 and M08 waited).
 */
function blockedScenes(flags, rooms) {
  const have = new Set(flags);
  const scenes = [];
  try {
    const dir = path.join(ROOT, "data", "story", "scenes");
    for (const f of fs.readdirSync(dir).sort()) {
      if (!f.endsWith(".json")) continue;
      const d = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
      const ep = Number(d.episode ?? (/E(\d+)/.exec(f) || [])[1] ?? 0);
      for (const sc of d.scenes || []) scenes.push({ ...sc, _ep: ep });
    }
  } catch (_) { return []; }
  // Only the episodes the run reached: up to the last episode with a completed scene.
  const maxEp = Math.max(0, ...scenes.filter((sc) => have.has(`done_${sc.id}`)).map((sc) => sc._ep));
  const grantedBy = {};
  for (const sc of scenes) for (const fl of (sc.grants && sc.grants.flags) || []) (grantedBy[fl] ||= []).push(sc);
  const visited = new Set(rooms);
  const out = [];
  for (const sc of scenes) {
    if (have.has(`done_${sc.id}`) || sc.type !== "main" || sc._ep > maxEp) continue;
    const req = (sc.requires && sc.requires.flags) || [];
    const touched = (sc.locations || []).some((r) => visited.has(r)) || req.some((r) => have.has(r));
    if (!touched) continue;
    const missing = req.filter((r) => !have.has(r));
    const partly = req.length && missing.length < req.length;
    if (!missing.length && !(sc.locations || []).some((r) => visited.has(r))) continue;
    if (missing.length && !partly && !(sc.locations || []).some((r) => visited.has(r))) continue;
    out.push(`${sc.id} «${sc.title || ""}» (${(sc.locations || []).join(", ")}): ${missing.length
      ? `не хватает ${missing.map((m) => `${m}${grantedBy[m] ? ` ← ${grantedBy[m].map((g) => `${g.id} «${g.title || ""}»`).join(" / ")}` : ""}`).join("; ")}`
      : "условия выполнены, но сцена не завершена (её действие не сделано)"}`);
  }
  return out.slice(0, 25);
}


// --- Persona helpers: the route of a segment, one-time lines, coverage ------------------------------------------------

function storyScenes() {
  const out = [];
  try {
    const dir = path.join(ROOT, "data", "story", "scenes");
    const files = fs.readdirSync(dir).filter((f) => /^E\d+\.json$/.test(f)).sort((a, b) => Number(a.slice(1, -5)) - Number(b.slice(1, -5)));
    for (const f of files) for (const sc of (JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")).scenes || [])) out.push(sc);
  } catch (_) { /* no data */ }
  return out;
}
let TEXTS = null;
function texts() {
  if (TEXTS) return TEXTS;
  TEXTS = new Map();
  try {
    const dir = path.join(ROOT, "data", "story", "text");
    for (const f of fs.readdirSync(dir).filter((x) => /^ru_.*\.json$/.test(x))) {
      for (const [k, v] of Object.entries(JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")).texts || {})) {
        TEXTS.set(k, typeof v === "string" ? v : (v && v.line && v.line.text) || (v && v.text) || "");
      }
    }
  } catch (_) { /* no data */ }
  return TEXTS;
}
const tx = (ref) => (typeof ref === "string" && ref.startsWith("@") ? texts().get(ref.slice(1)) || "" : String(ref || ""));
const normText = (t) => String(t || "").replace(/[«»"„“”]/g, "").replace(/\s+/g, " ").trim().toLowerCase();

/** The walkthrough of a segment: main scenes from route[0] to route[1] (inclusive) — where, what to do, the game's hints. */
function routeText(route) {
  if (!route || !route.length) return "";
  const sc = storyScenes().filter((x) => x.type === "main");
  const a = sc.findIndex((x) => x.id === route[0]);
  const b = route[1] ? sc.findIndex((x) => x.id === route[1]) : a;
  if (a < 0 || b < a) return "";
  const loc = {};
  try { for (const l of JSON.parse(fs.readFileSync(path.join(ROOT, "data", "story", "locations.json"), "utf8")).locations || []) loc[l.id] = l.name; } catch (_) {}
  return sc.slice(a, b + 1).map((x, i) => `${i + 1}. «${x.title || x.id}» — где: ${(x.locations || []).map((r) => loc[r] || r).join(", ")}. ${(x.actions || []).join("; ")}${(x.hints || []).length ? ` Подсказки игры: ${x.hints.join(" / ")}.` : ""}`).join("\n");
}

/** Text of every mandatory scene line → its id (M03.4): they play once, a second showing is a replay. */
function mandatoryLines() {
  const m = new Map();
  for (const sc of storyScenes()) (sc.mandatory_lines || []).forEach((ln, i) => {
    if (ln.text && ln.text.length >= 12) m.set(normText(ln.text), `${sc.id}.${i}`);
    for (const [k, t] of (ln.then || []).entries()) if (t.text && t.text.length >= 12) m.set(normText(t.text), `${sc.id}.${i}.then${k}`);
  });
  return m;
}

/** Coverage for persona reports: side stories (data/story/quests.json), choice flags, examined places per visited room. */
function coverage(endFlags, rooms, transcript) {
  const have = new Set(endFlags);
  const seenTxt = new Set(transcript.map((t) => normText(t.text)));
  const out = { quests: [], choices: [], rooms: [] };
  try {
    const q = JSON.parse(fs.readFileSync(path.join(ROOT, "data", "story", "quests.json"), "utf8"));
    for (const x of q.quests || []) {
      const opts = ((x.choice && x.choice.options) || []);
      const ch = opts.find((o) => have.has(o.sets));
      const started = [...have].some((f) => f.toLowerCase().startsWith(`${x.id.toLowerCase()}_`));
      out.quests.push({ id: x.id, title: x.title || "", reserve: !!x.reserve, done: have.has(`done_${x.id}`), started: started || !!ch, choice: ch ? ch.id : "" });
    }
  } catch (_) {}
  const choiceRe = /^(v0\d|q\d\d)_|_answer_|^board_|^mitten_/;
  out.choices = [...have].filter((f) => choiceRe.test(f)).sort();
  for (const r of [...new Set(rooms)]) {
    try {
      const d = JSON.parse(fs.readFileSync(path.join(ROOT, "data", "story", "rooms", `${r}.json`), "utf8"));
      let total = 0, seen = 0;
      const unseen = [];
      for (const h of d.hotspots || []) {
        const look = tx(h.look);
        if (!look) continue;
        total += 1;
        if (seenTxt.has(normText(look))) seen += 1; else unseen.push(tx(h.label) || h.id);
      }
      if (total) out.rooms.push({ room: r, total, seen, unseen });
    } catch (_) {}
  }
  return out;
}

/** Verdicts in the checklist's order (row ids are strings: "6", "6а", "7"). */
const vSort = (cl) => { const c = byDocOrder(cl ? cl.rows.map((r) => r.num) : []); return (a, b) => c(a.item, b.item); };

/** Rows of a checklist whose last gate verdict is not «прошёл» (Docs/playtest/gates_state/ACCEPTANCE_<M>.json). */
function unpassedRows(docRel) {
  try {
    const st = JSON.parse(fs.readFileSync(path.join(ROOT, "Docs", "playtest", "gates_state", `${path.basename(String(docRel), ".md")}.json`), "utf8"));
    const txt = fs.readFileSync(path.resolve(ROOT, String(docRel)), "utf8");
    const all = docRowIds(txt);
    return all.filter((n) => (st.verdicts || {})[n] !== "прошёл");
  } catch (_) { return []; }
}

/** A built-in start point in the URL (?start=<id>, data/story/start_points.json) as a sentence for the prompt, or "". */
function startPointLabel(u) {
  const m = /[?&]start=([\w-]+)/.exec(String(u || ""));
  if (!m) return "";
  let title = "";
  try { title = ((JSON.parse(fs.readFileSync(path.join(ROOT, "data", "story", "start_points.json"), "utf8")).points || []).find((p) => p.id === m[1]) || {}).title || ""; } catch (_) {}
  return `встроенная точка старта ?start=${m[1]}${title ? ` («${title}»)` : ""} — всё, что было до неё, уже пройдено (о прошлом ты знаешь только то, что увидишь в игре и журнале)`;
}

function saveTitle(ss) {
  try { return JSON.parse(fs.readFileSync(path.resolve(ROOT, String(ss.file || ss)), "utf8")).title || ""; } catch (_) { return ""; }
}

function buildReportInput(run, cfg, checklist) {
  const L = [];
  const P = personaOf(cfg.persona);
  L.push(`РЕЖИМ: ${cfg.mode === "acceptance" ? "приёмка по чеклисту" : P ? `роль «${P.title}» — ${P.goal}` : "свежий взгляд новичка"}${cfg.segmentId ? `, отрезок ${cfg.segmentId}` : ""}. Сборка: ${run.version || "?"} (${run.cfg.url}).`);
  if (run.startNote) L.push(`Начало: ${run.startNote}`);
  if (run.goal) L.push(`Цель отрезка: ${cfg.goal || run.goal.flags.join(", ")} — ${run.goal.reached ? `ДОСТИГНУТА${run.goal.step ? ` на шаге ${run.goal.step}` : ""}` : "НЕ достигнута"}.`);
  L.push(`Остановка: ${run.stop}. Шагов: ${run.steps.length} из ${cfg.maxSteps}.`);
  if (process.env.SITE_NOTE) L.push(`ВНИМАНИЕ: ${process.env.SITE_NOTE}. Если пункт описывает правку, которой в этой сборке ещё нет, — так и напиши («сборка старше правки»), не выдавай за дефект.`);
  if (cfg.note) L.push(`Замечание к прогону: ${cfg.note}`);
  if (checklist) L.push(`\nЧЕКЛИСТ:\n${checklistText(checklist)}`);
  if (cfg.mode === "acceptance") {
    L.push("\nВЕРДИКТЫ ШАГОВОЙ МОДЕЛИ (последний по пункту):");
    for (const v of Object.values(run.verdicts).sort(vSort(checklist))) L.push(`[${v.item}] ${v.status} (шаг ${v.step ?? "—"}; кадры ${v.frames.join(", ") || "—"}): ${v.seen}`);
    const changed = run.verdictHistory.filter((v, i, arr) => arr.findLastIndex((w) => w.item === v.item) !== i);
    if (changed.length) { L.push("Ранние версии вердиктов:"); for (const v of changed) L.push(`[${v.item}] шаг ${v.step}: ${v.status} — ${short(v.seen, 200)}`); }
  }
  L.push("\nЗАМЕТКИ ПО ХОДУ:");
  for (const n of run.notes) L.push(`шаг ${n.step} [${n.kind}] ${n.text} (кадры ${n.frames.join(", ")})`);
  if (!run.notes.length) L.push("(нет)");
  L.push("\nРЕПЛИКИ И ТЕКСТЫ ИГРЫ (дословно, по порядку):");
  for (const t of run.transcript) L.push(`шаг ${t.step} [${t.room}] ${t.who}: «${t.text}» (${t.frame})`);
  L.push("\nЖУРНАЛ ШАГОВ:");
  for (const s of run.steps) L.push(`#${s.step} [${s.room}${s.room_after && s.room_after !== s.room ? "→" + s.room_after : ""}] ${s.desc}${s.model !== cfg.model ? ` (${s.model})` : ""} | видит: ${short(s.observe, 160)} | думает: ${short(s.thought, 160)} | итог: ${short((s.events || []).filter((e) => !/«.*» \[f\d+\]$/.test(e)).join(" ; "), 220)}`);
  L.push("\nОБЪЕКТИВНЫЙ ЖУРНАЛ ИГРЫ (игроку не виден):");
  L.push(`Комнаты по порядку: ${run.rooms.join(" → ") || "—"}`);
  L.push(`Флаги сюжета по порядку появления: ${run.flagsOrder.map((f) => `${f.flag}@${f.step}`).join(", ") || "—"}`);
  if (run.end) L.push(`Конец: комната ${run.end.room}, сумка [${(run.end.inventory || []).join(", ")}], цель журнала: «${short(run.end.goal, 200)}»`);
  if (run.blocked && run.blocked.length) {
    L.push("Незавершённые сцены посещённых мест и чего им не хватает (по данным data/story; «A ← B» — флаг A даёт сцена B). Используй, чтобы отличить дефект игры от пропущенного игроком шага:");
    for (const b of run.blocked) L.push(`- ${b}`);
  }
  if (P) {
    L.push(`Объективные аномалии (посчитала программа по состоянию игры): ${run.anomalies.length ? "" : "нет"}`);
    for (const a of run.anomalies.slice(0, 60)) L.push(`- шаг ${a.step} [${a.kind}] ${a.text}`);
    if (run.invLog.length) L.push(`Сумка по шагам (+ получено, − ушло): ${run.invLog.slice(0, 80).map((x) => `#${x.step} [${x.room}] ${x.plus.map((i) => "+" + i).join(" ")}${x.minus.map((i) => " −" + i).join("")} («${x.desc}»)`).join("; ")}`);
    if (run.coverage) {
      const c = run.coverage;
      L.push("ПОКРЫТИЕ (по данным игры и дословным текстам прогона):");
      L.push(`- Необязательные истории: ${c.quests.map((q) => `${q.id} «${q.title}»${q.reserve ? " (резерв)" : ""}: ${q.done ? "закончена" : q.started ? "начата" : "нет"}${q.choice ? `, выбор ${q.choice}` : ""}`).join("; ")}`);
      L.push(`- Выборы (флаги вариантов): ${c.choices.join(", ") || "—"}`);
      for (const r of c.rooms) L.push(`- ${r.room}: осмотрено ${r.seen} из ${r.total}${r.unseen.length ? `; не осмотрено: ${r.unseen.slice(0, 14).join(", ")}${r.unseen.length > 14 ? " …" : ""}` : ""}`);
    }
  }
  if (run.harness.length) L.push(`Технические события плейтеста: ${run.harness.map((h) => short(h, 200)).join(" | ")}`);
  if (run.consoleErrors.length) L.push(`Ошибки консоли браузера: ${run.consoleErrors.slice(0, 8).join(" | ")}`);
  if (run.consoleWarnings.length) L.push(`Предупреждения игры (Godot WARNING, не ошибки): ${[...new Set(run.consoleWarnings)].slice(0, 12).join(" | ")}`);
  L.push(`\nДОСТУПНЫЕ КАДРЫ (лежат рядом с отчётом): ${run.frames.map((f) => `${f.id} (шаг ${f.step}, ${f.kind}${f.label ? ": " + short(f.label, 40) : ""})`).join("; ") || "нет"}`);
  return L.join("\n");
}

function renderReport(run, cfg, checklist, body, budget, minutes) {
  const L = [];
  const P = personaOf(cfg.persona);
  const title = cfg.mode === "acceptance" ? `ИИ-плейтест: приёмка, пункты ${checklist && checklist.rows.length ? `${checklist.rows[0].num}–${checklist.rows[checklist.rows.length - 1].num}` : cfg.items.join(", ")}`
    : P ? `ИИ-плейтест в роли: ${P.title}${cfg.segmentId ? ` — отрезок ${cfg.segmentId}` : ""}` : "ИИ-плейтест: свежий взгляд новичка";
  const link = (id) => (run.frames.some((f) => f.id === id) ? `[${id}](${id}.jpg)` : id);
  L.push(`# ${title} — ${run.started.slice(0, 10)}`);
  L.push("");
  L.push(`- Сборка: \`${run.version || "?"}\` — ${run.cfg.url}${process.env.SITE_NOTE ? `. **Внимание:** ${process.env.SITE_NOTE} — правки этого пуша в проверке могут отсутствовать` : ""}`);
  L.push(`- Запрос: \`${cfg.request || "—"}\`${cfg.note ? ` — ${cfg.note}` : ""}${run.cfg.actions_run ? `; запуск Actions ${run.cfg.actions_run}` : ""}`);
  L.push(`- Модели: шаги — \`${cfg.model}\`${cfg.modelStuck ? `, когда застряла — \`${cfg.modelStuck}\`` : ""}; отчёт — \`${cfg.reportModel}\`. Кадр модели ${cfg.W}×${cfg.H} JPEG (окно игры 1920×1080).`);
  if (run.startNote) L.push(`- Начало: ${run.startNote}${cfg.start ? " (хуки ?ambientprobe)" : ""}`);
  if (run.saves && run.saves.length) L.push(`- Сохранения прогона (для start_save следующих ворот): ${run.saves.map((sv) => `saves/${sv.slot}.json${sv.title ? ` «${sv.title}»` : ""}`).join(", ")}`);
  L.push(`- Шагов: ${run.steps.length} из ${cfg.maxSteps}; время ${minutes} мин. Остановка: ${run.stop}`);
  L.push(`- Стоимость прогона: **$${budget.spent.toFixed(3)}** (по usage ответов API, подробно — usage.json; предохранитель от зацикливания — $${cfg.maxUsd})`);
  L.push(`- Где оказалась по факту: ${run.rooms.join(" → ") || "—"}${run.end ? `; конец — ${run.end.room}` : ""}`);
  if (run.goal) L.push(`- Цель отрезка (${run.goal.flags.join(", ")}): **${run.goal.reached ? `достигнута${run.goal.step ? ` на шаге ${run.goal.step}` : ""}` : "не достигнута"}**`);
  if (P) L.push(`- Объективные аномалии по состоянию игры: ${run.anomalies.length}${run.anomalies.length ? ` (${[...new Set(run.anomalies.map((a) => a.kind))].join(", ")}; log.json → anomalies)` : ""}`);
  if (run.consoleErrors.length) L.push(`- Ошибки консоли браузера: ${run.consoleErrors.length} (log.json)`);
  if (run.consoleWarnings.length) L.push(`- Предупреждения игры (Godot WARNING): ${run.consoleWarnings.length} (log.json)`);
  L.push("");
  if (body) L.push(body);
  else L.push("_Итоговый отчёт сильной модели не составлен (нет бюджета, ключа или ответа) — ниже сырые данные прогона._");
  L.push("");
  L.push("---");
  L.push("");
  if (cfg.mode === "acceptance") {
    L.push("## Приложение: вердикты шаговой модели (сырые)");
    L.push("");
    L.push("| № | Вердикт | Что видела | Кадры |");
    L.push("| --- | --- | --- | --- |");
    for (const v of Object.values(run.verdicts).sort(vSort(checklist))) {
      L.push(`| ${v.item} | ${v.status} | ${String(v.seen).replace(/\|/g, "/").replace(/\n/g, " ")} | ${v.frames.map(link).join(", ") || "—"} |`);
    }
    L.push("");
  }
  if (run.anomalies && run.anomalies.length) {
    L.push("## Приложение: объективные аномалии (по состоянию игры)");
    L.push("");
    for (const a of run.anomalies.slice(0, 60)) L.push(`- шаг ${a.step}, ${a.kind}: ${a.text}`);
    L.push("");
  }
  if (run.notes.length) {
    L.push("## Приложение: заметки по ходу");
    L.push("");
    for (const n of run.notes) L.push(`- шаг ${n.step}, ${n.kind}: ${n.text.replace(/\n/g, " ")} (${n.frames.map(link).join(", ")})`);
    L.push("");
  }
  if (run.harness.length) {
    L.push("## Приложение: техника плейтеста");
    L.push("");
    for (const h of run.harness.slice(0, 20)) L.push(`- ${String(h).replace(/\n/g, " ")}`);
    L.push("");
  }
  L.push(`Полный журнал шагов и дословные реплики — log.json; токены и стоимость каждого вызова — usage.json.`);
  return L.join("\n") + "\n";
}

main().catch((e) => { console.error(`fatal: ${e && e.message}`); process.exit(1); });
