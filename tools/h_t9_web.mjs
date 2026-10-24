#!/usr/bin/env node
// Batch H, T8 — the boat at the turn and the house after Pelageya, in the WEB build with REAL mouse input:
//
//   tools/export_web.sh && node tools/h_t8_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8795)
//
//   D1  ?start=pier_first — a click on the house door before the pier: Agata «Записи подождут. Сперва к причалу…»,
//       the door stays shut; down to the pier, the talk with Pelageya (M02); back — the door now names the key.
//   B1  ?start=boat_turn — the turn: the boat by the plate, Pelageya by it, «В лодку» shown; the pier without the boat;
//       back to the turn, a click on Pelageya: the empty boat slides off along the rope (frame mid-way) and comes back
//       with the ribbon; «В лодку» at the plate → into the boat (the crossing begins).
// Frames: Docs/evidence/H/T9_web_*.jpg. Exit code 0 only when every check passed and the console has no errors.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch (_) {
  // A worktree without node_modules: PLAYWRIGHT_FROM=<a package.json next to node_modules/playwright>.
  ({ chromium } = createRequire(process.env.PLAYWRIGHT_FROM || path.join(ROOT, "package.json"))("playwright"));
}
const WEB_DIR = process.env.H_WEB_DIR ? path.resolve(ROOT, process.env.H_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "H");
const LOG_DIR = path.join(ROOT, "build", "shots", "h_t9");
const PORT = Number(process.env.H_PORT || 8795);

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".ico": "image/x-icon",
};

function serve(dir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, {
        "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Content-Length": st.size,
        "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-store",
      });
      fs.createReadStream(file).pipe(res);
    });
  });
  return new Promise((resolve) => server.listen(PORT, "127.0.0.1", () => resolve(server)));
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

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}. Run tools/export_web.sh first.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });
  const log = [];
  const logLine = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const failures = [];
  const checks = [];
  const check = (ok, msg) => { checks.push({ ok: !!ok, msg }); logLine(`${ok ? "OK  " : "FAIL"} ${msg}`); if (!ok) failures.push(msg); };
  let consoleErrors = 0;
  const consoleWarnings = [];
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.setDefaultTimeout(180000);
  page.on("console", (m) => {
    const t = m.text();
    if (m.type() === "error") {
      if (/^WARNING: /.test(t) || /at: push_warning/.test(t)) consoleWarnings.push(t);
      else consoleErrors += 1;
    }
    if (m.type() === "error" || m.type() === "warning") logLine(`console.${m.type()}: ${t}`);
  });
  page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });

  // A fresh probe on every read (probePause(false) with no time scale publishes at once and changes nothing).
  const state = () => page.evaluate(() => {
    if (window.probePause) window.probePause(false);
    return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null;
  });
  const waitFor = async (label, pred, timeout = 90000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(150);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)} mechanic=${JSON.stringify(s?.mechanic)?.slice(0, 300)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `T9_web_${name}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 82, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 3 });
    await sleep(80);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.speaker || ""}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  /** Clicks through beats (options from `choices` in order) until `done(state)` or `quietMs` without a beat. */
  const playThrough = async (label, { choices = [], done = null, quietMs = 3500, timeout = 240000 } = {}) => {
    const lines = [];
    const t0 = Date.now();
    let quietSince = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (done && s && done(s)) return lines;
      const key = beatKey(s);
      if (!key) {
        if (!done && Date.now() - quietSince > quietMs) return lines;
        await sleep(150);
        continue;
      }
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        let pick = choices.length ? choices.shift() : ids[0];
        if (!ids.includes(pick)) pick = ids[0];
        lines.push(`options:${pick}`);
        await click(`${label}: option ${pick}`, s.ui.options[pick]);
      } else {
        lines.push(`${s.beat.speaker || "·"}: ${s.beat.text || ""}`);
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 780 });
      }
      const t1 = Date.now();
      while (Date.now() - t1 < 15000) {
        const t = await state();
        if (beatKey(t) !== key) break;
        await sleep(120);
      }
      quietSince = Date.now();
    }
    check(false, `${label}: did not finish in ${timeout} ms`);
    return lines;
  };
  const waitIdle = async (label) => {
    await sleep(400);
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 90000);
  };
  const useHotspot = async (id, opts = {}) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `hotspot ${id} visible in ${s.room}`); return []; }
    await click(`hotspot ${id}`, h);
    await waitIdle(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "" || (t.mechanic && t.mechanic.open) || (t.view && t.view.open), 30000);
    return playThrough(`hotspot ${id}`, opts);
  };
  const goExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { check(false, `exit ${target} in ${s.room}`); return false; }
    await click(`exit → ${target}`, e);
    await waitIdle(`exit → ${target}`);
    await waitFor(`room == ${target}`, (t) => t.room === target, 60000);
    await sleep(800);
    await playThrough(`enter ${target}`, { quietMs: 1500 });
    return (await state()).room === target;
  };
  const closeMechanic = async (label) => {
    const s = await state();
    if (s.mechanic && s.mechanic.open && s.mechanic.close) {
      await click(`${label}: «Закрыть»`, s.mechanic.close);
      await waitFor(`${label}: close-up put away`, (t) => !(t.mechanic && t.mechanic.open), 60000);
    }
  };
  /** Real drag: press at the first point, move along in small steps, let go (or not). */
  const drag = async (label, pts, release = true) => {
    logLine(`drag ${label}: ${pts.length} points`);
    await page.mouse.move(pts[0].x, pts[0].y, { steps: 2 });
    await sleep(120);
    await page.mouse.down();
    for (let j = 1; j < pts.length; j++) {
      const a = pts[j - 1], b = pts[j];
      const n = Math.max(1, Math.round(Math.hypot(b.x - a.x, b.y - a.y) / 16));
      for (let k = 1; k <= n; k++) await page.mouse.move(a.x + (b.x - a.x) * k / n, a.y + (b.y - a.y) * k / n);
    }
    await sleep(150);
    if (release) await page.mouse.up();
    await sleep(300);
  };
  const slow = async (k) => { await page.evaluate((x) => window.probePause(false, x), k); };

  try {
    let s;
    const lineOf = (t) => (t && t.beat ? `${t.beat.speaker || ""}: ${t.beat.text || ""}` : "");
    const route = async (label, rooms) => { for (const r of rooms) check(await goExit(r), `${label}: → ${r}`); };
    if (!process.env.H_ONLY || process.env.H_ONLY === "W1") {
    // --- W1: R36 — after the knot the yard does not loop; Agata herself waits for the crossing ---
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=lights`);
    s = await waitFor("W1: game up at the pier", (t) => t.room === "R1" && t.exits && t.exits.Z2, 240000);
    await playThrough("W1: start", { quietMs: 2500 });
    await route("W1", ["Z2", "H1", "H3", "O1", "O2"]);
    s = await state();
    check(s.room === "O2" && s.exits.O4 && !s.exits.O4.open, "W1: the yard, the gate to the village not open yet");
    await click("exit → O4 (gate)", s.exits.O4);
    await waitIdle("gate");
    s = await waitFor("W1: Agata at the gate", (t) => t.beat && t.beat.type, 30000);
    check(/сперва к причалу/.test(s.beat.text || "") && s.beat.speaker === "agata", `W1: «${s.beat.text}» (${s.beat.speaker})`);
    await shot("W1_gate_after_knot");
    await playThrough("W1: line", { quietMs: 1500 });
    s = await state();
    check(s.room === "O2" && !/кругами/.test(lineOf(s)), "W1: no loop — still in the yard");
    }

    if (!process.env.H_ONLY || process.env.H_ONLY === "W2") {
    // --- W2: letters first (Nina comes and goes), then Dunya's house; day three — Pelageya at the turn, short crossing ---
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=freewalk`);
    s = await waitFor("W2: game up in the class", (t) => t.room === "O1" && t.exits && t.exits.O2, 240000);
    await playThrough("W2: start", { quietMs: 2500 });
    await route("W2", ["O2", "O4"]);
    s = await state();
    check(!(s.hotspots.nina && s.hotspots.nina.visible), "W2: before the letters Nina is not on the street");
    await click("hotspot tamara", s.hotspots.tamara);
    await waitIdle("tamara");
    await waitFor("W2: M23a starts", (t) => t.beat && t.beat.type, 60000);
    s = await waitFor("W2: Nina came to the letters", (t) => t.hotspots && t.hotspots.nina && t.hotspots.nina.visible && t.beat && t.beat.type, 30000);
    check(s.hotspots.nina && s.hotspots.nina.visible, "W2: Nina on the street while Tamara reads the addresses");
    await shot("W2_letters_nina_here");
    const m23a = await playThrough("W2: M23a", { quietMs: 8000 });
    check(m23a.some((l) => /Нина вернулась/.test(l)) && m23a.some((l) => /к Дуне в дом/.test(l)), `W2: Nina comes and goes back (${m23a.length} beats)`);
    s = await state();
    check(!(s.hotspots.nina && s.hotspots.nina.visible), "W2: after the letters Nina is gone from the street");
    await route("W2", ["O2", "O1", "H3", "H1"]);
    await playThrough("W2: M23c", { quietMs: 12000 });
    s = await state();
    check(s.hotspots.nina && s.hotspots.nina.visible, "W2: Nina in her sister's house");
    await shot("W2_nina_in_house");
    await route("W2", ["Z2", "R1"]);
    s = await state();
    check(!(s.hotspots.pelageya && s.hotspots.pelageya.visible), "W2: day three — no Pelageya at her pier");
    await shot("W2_pier_day3");
    await route("W2", ["Z3"]);
    s = await state();
    check(s.hotspots.pelageya && s.hotspots.pelageya.visible, "W2: Pelageya by the boat at the turn");
    await click("hotspot pelageya", s.hotspots.pelageya);
    await waitIdle("pelageya");
    s = await waitFor("W2: Pelageya speaks", (t) => t.beat && t.beat.type, 30000);
    check(/перевезу/.test(s.beat.text || ""), `W2: Pelageya «${s.beat.text}»`);
    await shot("W2_pelageya_at_turn");
    await playThrough("W2: Pelageya", { quietMs: 1500 });
    s = await state();
    await click("exit → R2 (into the boat)", s.exits.R2);
    await waitIdle("into the boat");
    s = await waitFor("W2: the crossing opens", (t) => t.mechanic && t.mechanic.open, 60000);
    await sleep(1200);
    await shot("W2_crossing_auto");
    const t0 = Date.now();
    s = await waitFor("W2: across by itself", (t) => t.room === "R3", 60000);
    check(s.room === "R3", `W2: at the far pier without a single pull (${Math.round((Date.now() - t0) / 1000)} s)`);
    await playThrough("W2: R3", { quietMs: 1500 });
    s = await state();
    await click("exit → R2 (back)", s.exits.R2);
    await waitIdle("back into the boat");
    s = await waitFor("W2: the crossing back opens", (t) => t.mechanic && t.mechanic.open, 60000);
    await sleep(800);
    await click("W2: one click — to the shore", { x: 960, y: 640 });
    s = await waitFor("W2: at the turn after one click", (t) => t.room === "Z3", 30000);
    check(s.room === "Z3", "W2: back at the turn");
    await shot("W2_back_at_turn");
    }

    if (!process.env.H_ONLY || process.env.H_ONLY === "W3") {
    // --- W3: Dunya's house first, then the letters ---
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=freewalk`);
    s = await waitFor("W3: game up in the class", (t) => t.room === "O1" && t.exits && t.exits.H3, 240000);
    await playThrough("W3: start", { quietMs: 2500 });
    await route("W3", ["H3", "H1"]);
    await playThrough("W3: M23c", { quietMs: 12000 });
    s = await state();
    check(s.hotspots.nina && s.hotspots.nina.visible, "W3: Nina in her sister's house first");
    await route("W3", ["H3", "O1", "O2", "O4"]);
    s = await state();
    await click("hotspot tamara", s.hotspots.tamara);
    await waitIdle("tamara");
    s = await waitFor("W3: Nina came to the letters", (t) => t.hotspots && t.hotspots.nina && t.hotspots.nina.visible && t.beat && t.beat.type, 60000);
    check(s.hotspots.nina && s.hotspots.nina.visible, "W3: Nina on the street for the letters (after her sister's house)");
    await shot("W3_letters_after_house");
    const m23a = await playThrough("W3: M23a", { quietMs: 8000 });
    check(m23a.some((l) => /к Дуне в дом/.test(l)), "W3: Nina goes back to Dunya's house");
    await route("W3", ["O2", "O1", "H3", "H1"]);
    s = await state();
    check(s.hotspots.nina && s.hotspots.nina.visible, "W3: Nina in her sister's house again");
    }
  } catch (e) {
    check(false, `exception: ${e.message}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors} (Godot warnings, not errors: ${consoleWarnings.length})`);
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures, warnings: consoleWarnings }, null, 1));
    await browser.close();
    server.close();
  }
  const ok = checks.filter((c) => c.ok).length;
  console.log(`h_t9_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
