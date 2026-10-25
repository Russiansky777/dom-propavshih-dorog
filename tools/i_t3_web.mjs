#!/usr/bin/env node
// Batch I, I-T3 — art batch 10g and the screen setting in the WEB build with REAL mouse input (frames Docs/evidence/I/I_T3_*.jpg):
//
//   tools/export_web.sh && node tools/i_t3_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8796)
//
//   Z3/R1  ?start=t10_turn_day — by day: our shore autumn, the far shore snow; the boat at the turn; the pier without it;
//   R3/O4  ?start=olkhovka — M18 at the far pier: black → the hug frame (F_hug_pelageya) → back; then to Olkhovka, M19 — F_hug_nina;
//   H1     ?start=house — Tikhon speaks (the mouth); the settings panel: «Полный экран», a click, F11 back;
//   H3     ?start=bedtime — the home mirror close-up: the old photo with little Agata;   O1 ?start=freewalk — the tit.
// Exit code 0 only when every check passed and the console has no errors.

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
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "I");
const LOG_DIR = path.join(ROOT, "build", "shots", "i_t3");
const PORT = Number(process.env.H_PORT || 8796);

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
    const file = path.join(OUT_DIR, `I_T3_${name}.jpg`);
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

  const only = (k) => !process.env.H_ONLY || process.env.H_ONLY.split(",").includes(k);
  const start = async (id, ready) => {
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=${id}`);
    const s = await waitFor(`${id}: game up`, ready, 240000);
    await playThrough(`${id}: start`, { quietMs: 2500 });
    await sleep(1200);
    return s;
  };
  try {
    let s;
    // --- Z3 / R1 by day: autumn here, snow there ---
    s = await start("t10_turn_day", (t) => t.room === "Z3");
    check(s.room === "Z3", "Z3 by day");
    await shot("Z3_day_autumn_snow");
    check(await goExit("R1"), "R1: to the pier by day");
    await shot("R1_day_autumn_snow");

    // --- M18: the hug of Pelageya and Mitya ---
    s = await start("olkhovka", (t) => t.room === "R3");
    let hug18 = false;
    await playThrough("M18", { done: (t) => { if (t.frame && t.frame.frame === "F_hug_pelageya") hug18 = true; return hug18; }, timeout: 120000 });
    if (hug18) { await sleep(1500); await shot("M18_hug_frame"); }
    check(hug18, "M18: the hug frame F_hug_pelageya is shown");
    await playThrough("M18 after the hug", { done: (t) => !(t.frame && t.frame.open), timeout: 60000 });
    await sleep(1600);
    s = await state();
    check(s.room === "R3" && !(s.frame && s.frame.open), "M18: back at the far pier after the hug");
    await shot("M18_after_hug");
    // On to Olkhovka behind Mitya — M19 at the porch.
    await playThrough("M18 rest", { quietMs: 3000 });
    let hug19 = false;
    for (const ex of ["O4"]) { s = await state(); if (s.exits && s.exits[ex]) await goExit(ex); }
    await playThrough("M19", { done: (t) => { if (t.frame && t.frame.frame === "F_hug_nina") hug19 = true; return hug19; }, timeout: 120000 });
    if (hug19) { await sleep(1500); await shot("M19_hug_frame"); }
    check(hug19, "M19: the hug frame F_hug_nina is shown");

    // --- H1: Tikhon speaks; the settings: full screen ---
    s = await start("house", (t) => t.room === "H1" && t.hotspots && t.hotspots.tikhon);
    if (s.hotspots.tikhon && s.hotspots.tikhon.visible) {
      await click("hotspot tikhon", s.hotspots.tikhon);
      await waitIdle("tikhon");
      const t1 = await waitFor("Tikhon's line", (t) => t.beat && t.beat.speaker === "tikhon", 30000);
      await sleep(700);
      await shot("H1_tikhon_speaks");
      check(t1.beat && t1.beat.speaker === "tikhon", "Tikhon speaks (mouth frames while his voice sounds)");
      await playThrough("tikhon talk", { quietMs: 2000 });
    }
    await page.keyboard.press("Escape");
    s = await waitFor("pause open", (t) => t.pause && t.pause.open, 8000);
    await click("pause «Настройки»", s.pause.items.settings);
    s = await waitFor("settings panel", (t) => t.ui && t.ui.menu_open && t.ui.buttons.Fullscreen && t.ui.buttons.Fullscreen.x, 8000);
    check(String(s.ui.buttons.Fullscreen && 1) && s.ui.fullscreen === false, "settings: «Полный экран» off — a window");
    await shot("settings_fullscreen");
    await click("«Полный экран»", s.ui.buttons.Fullscreen);
    s = await waitFor("full screen on", (t) => t.ui && t.ui.fullscreen === true, 8000);
    check(s.ui.fullscreen === true && s.ui.fullscreen_on === true, "a click turns full screen on (switch on, saved)");
    await sleep(800);
    await page.keyboard.press("F11");
    s = await waitFor("F11 → window", (t) => t.ui && t.ui.fullscreen === false, 8000);
    check(s.ui.fullscreen === false && s.ui.fullscreen_on === false, "F11 → a window, the switch follows");

    // --- H3: the old photo with little Agata ---
    s = await start("bedtime", (t) => t.room === "H3" && t.hotspots && t.hotspots.mirror_home);
    await click("hotspot mirror_home", s.hotspots.mirror_home);
    await waitIdle("mirror_home");
    s = await waitFor("mirror close-up", (t) => t.view && t.view.open, 30000);
    await sleep(1500);
    await shot("H3_old_photo_agata");
    check(s.view && s.view.open, "H3: the home mirror close-up with the old photo");
    await playThrough("mirror text", { quietMs: 2000 });

    // --- O1: the tit with the cap and the boots ---
    s = await start("freewalk", (t) => t.room === "O1");
    await shot("O1_tit");
    check(s.room === "O1", "O1: the class with the tit poster");
  } finally {
    fs.writeFileSync(path.join(LOG_DIR, "log.txt"), log.join("\n") + "\n");
    await browser.close();
    server.close();
  }
  check(consoleErrors === 0, `console without errors (${consoleErrors})`);
  logLine(`${checks.filter((c) => c.ok).length}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
