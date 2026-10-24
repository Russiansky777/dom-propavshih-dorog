#!/usr/bin/env node
// Batch H, T2 — H17 «the bed ends the day» in the WEB build with REAL mouse input (window.probeState):
//
//   tools/export_web.sh && node tools/h_t2_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8791; H_RUNS=D1,D3)
//
//   D1  ?start=bedtime — back from the school into the gallery: Agata says it is night and the bed is in the attic; the
//       living room → the attic → a click on the bed: «пора спать», the night by the stove (N01), morning, «День второй».
//   D3  ?start=bedtime3 — day three with its four deeds done: the attic → the bed → «пора спать», morning of day four (M24).
// Frames: Docs/evidence/H/T2_web_*.jpg. Exit code 0 only when every check passed and the console has no errors.

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
const LOG_DIR = path.join(ROOT, "build", "shots", "h_t2");
const PORT = Number(process.env.H_PORT || 8791);
const RUNS = (process.env.H_RUNS || "D1,D3").split(",");

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
    const file = path.join(OUT_DIR, `T2_web_${name}.jpg`);
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
    if (RUNS.includes("D1")) {
      await page.goto(`http://127.0.0.1:${PORT}/index.html?start=bedtime`);
      let s = await waitFor("D1: game up in the gallery", (t) => t.room === "H3", 240000);
      await page.mouse.click(960, 540);
      const said = await playThrough("D1: the gallery", { quietMs: 2500 });
      check(said.some((l) => l.includes("пора спать")), `D1: Agata says it is time to sleep (${said.join(" / ")})`);
      s = await state();
      check(!s.flags.started_N01, "D1: the night does not start by itself");
      check(await goExit("H1") && await goExit("H4"), "D1: the living room → the attic");
      await page.mouse.move(400, 1000);
      await sleep(500);
      await shot("H17_attic_bed");
      const lines = await useHotspot("bed", { done: (t) => t.flags.done_N01 && !beatKey(t), timeout: 300000 });
      check(lines.length > 0 && lines[0].includes("пора спать"), `D1: the bed — «пора спать» first (${lines[0]})`);
      s = await state();
      check(s.flags.done_N01 && s.room === "H1", `D1: the night by the stove, morning in the living room (${s.room})`);
      await sleep(800);
      await shot("H17_morning_day2");
    }
    if (RUNS.includes("D3")) {
      await page.goto(`http://127.0.0.1:${PORT}/index.html?start=bedtime3`);
      let s = await waitFor("D3: game up in the living room", (t) => t.room === "H1", 240000);
      await page.mouse.click(960, 540);
      await playThrough("D3: start", { quietMs: 2000 });
      check(await goExit("H4"), "D3: up to the attic");
      const lines = await useHotspot("bed", { done: (t) => t.flags.done_M24 && !beatKey(t), timeout: 300000 });
      check(lines.length > 0 && lines[0].includes("пора спать"), `D3: «пора спать» (${lines[0]})`);
      s = await state();
      check(s.flags.done_M24 && s.flags.morning_day4, "D3: morning of day four");
      await shot("H17_morning_day4");
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
  console.log(`h_t2_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
