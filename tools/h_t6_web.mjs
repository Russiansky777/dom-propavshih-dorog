#!/usr/bin/env node
// Batch H, T6 — «every day ends with sleep» and the change-of-day card in the WEB build with REAL mouse input
// (window.probeState):
//
//   tools/export_web.sh && node tools/h_t6_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8792; H_RUNS=D1,D2,D3)
//
//   D1  ?start=bedtime — back from the school: «лягу у печи»; the attic bed is Dunya's («Дунина… Лягу у печи — там
//       теплее», no sleep); the lezhanka by the stove: «пора спать», the night, «День второй» on black, the morning.
//   D2  ?start=bedtime2 — after the talk with Ilya, night in mum's room: the bed → «пора спать», «День третий», morning.
//   D3  ?start=bedtime3 — day three, four deeds done: the bed at mum's → «День четвёртый», morning of day four.
//   Each card is seen once; reloading the checkpoint save does not show it again (D1).
// Frames: Docs/evidence/H/T6_web_*.jpg. Exit code 0 only when every check passed and the console has no errors.

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
const LOG_DIR = path.join(ROOT, "build", "shots", "h_t6");
const PORT = Number(process.env.H_PORT || 8792);
const RUNS = (process.env.H_RUNS || "D1,D2,D3").split(",");

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
    const file = path.join(OUT_DIR, `T6_web_${name}.jpg`);
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

  /** Plays through beats until `done`, watching the day card; returns {lines, cards} (cards — texts seen on screen). */
  const sleepAt = async (label, id, done) => {
    const cards = [];
    let shotCard = false;
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `${label}: hotspot ${id} visible in ${s.room}`); return { lines: [], cards }; }
    await click(`${label}: ${id}`, h);
    await waitIdle(label);
    const lines = [];
    const t0 = Date.now();
    while (Date.now() - t0 < 300000) {
      const t = await state();
      const dc = t.day_card || {};
      if (dc.text && cards[cards.length - 1] !== dc.text) cards.push(dc.text);
      if (dc.phase === "hold" && !shotCard) { shotCard = true; await shot(`${label}_card`); }
      if (done(t) && !beatKey(t) && !dc.phase) break;
      const key = beatKey(t);
      if (key && !(t.ui && t.ui.options && Object.keys(t.ui.options).length)) {
        lines.push(`${t.beat.speaker || "·"}: ${t.beat.text || ""}`);
        await click(`${label}: continue`, t.ui.dialogue_click || { x: 960, y: 780 });
        const t1 = Date.now();
        while (Date.now() - t1 < 15000) { const u = await state(); if (beatKey(u) !== key) break; await sleep(120); }
      } else {
        await sleep(100);
      }
    }
    return { lines, cards };
  };

  try {
    if (RUNS.includes("D1")) {
      await page.goto(`http://127.0.0.1:${PORT}/index.html?start=bedtime`);
      let s = await waitFor("D1: game up in the gallery", (t) => t.room === "H3", 240000);
      await page.mouse.click(960, 300);   // the first click unlocks the sound; the line waits for it in the browser
      s = await waitFor("D1: Agata's line in the gallery", (t) => t.beat && /пора спать/i.test(t.beat.text || ""), 60000);
      check(s.beat && /у печи/.test(s.beat.text || ""), `D1: «пора спать — лягу у печи» (${s.beat && s.beat.text})`);
      await playThrough("D1: the gallery", { quietMs: 2500 });
      check(await goExit("H1") && await goExit("H4"), "D1: the living room → the attic");
      let lines = await useHotspot("bed", { quietMs: 2500 });
      check(lines.length > 0 && /Дунина… Лягу у печи — там теплее/.test(lines[0]), `D1: the attic bed — «Дунина… Лягу у печи — там теплее» (${lines[0]})`);
      s = await state();
      check(!s.flags.started_N01, "D1: no sleep in the attic");
      check(await goExit("H1"), "D1: down to the living room");
      await page.mouse.move(400, 1000);
      await sleep(400);
      await shot("D1_lezhanka_night");
      const r = await sleepAt("D1", "lezhanka", (t) => t.flags.done_N01);
      check(r.lines.length > 0 && /пора спать/.test(r.lines[0]), `D1: the lezhanka — «пора спать» first (${r.lines[0]})`);
      check(JSON.stringify(r.cards) === JSON.stringify(["День второй"]), `D1: the card «День второй» once (${JSON.stringify(r.cards)})`);
      s = await state();
      check(s.flags.done_N01 && s.room === "H1" && s.time && s.time.day === 2, `D1: morning of day two by the stove (${s.room}, day ${s.time && s.time.day})`);
      await shot("D1_morning_day2");
      // Load the checkpoint «День второй»: the card does not come again.
      const ok = await page.evaluate(() => window.probeLoad ? window.probeLoad("cp_day2") : null);
      await sleep(3000);
      const seen = [];
      for (let i = 0; i < 20; i++) { const t = await state(); if (t.day_card && t.day_card.phase) seen.push(t.day_card.text); await sleep(150); }
      if (ok !== null) check(seen.length === 0, `D1: after loading «День второй» no card (${JSON.stringify(seen)})`);
      else logLine("D1: no window.probeLoad in this build — the load check is in test_batch_h_t6.gd");
    }
    if (RUNS.includes("D2")) {
      await page.goto(`http://127.0.0.1:${PORT}/index.html?start=bedtime2`);
      let s = await waitFor("D2: game up in mum's room", (t) => t.room === "O3", 240000);
      await page.mouse.click(1500, 300);
      await playThrough("D2: start", { quietMs: 2000 });
      s = await state();
      check(s.flags.done_M20 && !s.flags.morning_day3, "D2: after the talk with Ilya it is still night");
      const r = await sleepAt("D2", "bed", (t) => t.flags.done_N02);
      check(r.lines.length > 0 && /Поздно/.test(r.lines[0]), `D2: the bed — «пора спать» first (${r.lines[0]})`);
      check(JSON.stringify(r.cards) === JSON.stringify(["День третий"]), `D2: the card «День третий» once (${JSON.stringify(r.cards)})`);
      s = await state();
      check(s.flags.morning_day3 && s.room === "O3", "D2: morning of day three in mum's room");
      await shot("D2_morning_day3");
    }
    if (RUNS.includes("D3")) {
      await page.goto(`http://127.0.0.1:${PORT}/index.html?start=bedtime3`);
      let s = await waitFor("D3: game up in mum's room", (t) => t.room === "O3", 240000);
      await page.mouse.click(1500, 300);
      await playThrough("D3: start", { quietMs: 2000 });
      const r = await sleepAt("D3", "bed", (t) => t.flags.done_M24);
      check(r.lines.length > 0 && /пора спать/i.test(r.lines[0]), `D3: «пора спать» (${r.lines[0]})`);
      check(JSON.stringify(r.cards) === JSON.stringify(["День четвёртый"]), `D3: the card «День четвёртый» once (${JSON.stringify(r.cards)})`);
      s = await state();
      check(s.flags.done_M24 && s.flags.morning_day4, "D3: morning of day four");
      await shot("D3_morning_day4");
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
  console.log(`h_t6_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
