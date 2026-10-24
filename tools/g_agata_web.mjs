#!/usr/bin/env node
// Batch G, Agata's motion (G1, G53) in the WEB build with REAL mouse input (window.probeState):
//
//   tools/export_web.sh && node tools/g_agata_web.mjs      (G_WEB_DIR — another build dir; G_PORT, default 8793)
//
//   A  (G1) ?start=day2 — the morning in H1: a real click on the shelf sockets (action_anim «reach», since rev 9 «take
//      at the waist»): Agata walks there, plays «reach» once — the frame at the key frame is the evidence (her hand
//      forward at the waist, no swing) — and on the key frame the Q04 question opens; option A → the shelf by the stove.
//   B  (G53) ?start=epilogue — M26 to the last frame: the dinner, Agata SEATED at the table between Ilya and Varvara
//      (layer «agata» — the sit sheet, under the drawn family).
//   C  (G10) ?start=house — the shutter, then a real click on the wet kerchief: pick at the bench → walk to the hanger
//      (the bench bare, the kerchief in her hands) → reach at the left hook → the kerchief on the hook (flag once).
//   D  (G56) ?start=wedges — H2, Agata walks to the front edge (depth scale ≈ 3): the frame and a 1:1 crop of her.
//      G_RUNS=C,D for these two.
// Frames: Docs/evidence/G/G1_take_shelf.jpg, G53_dinner_seated.jpg, G10_carry_walk.jpg, G10_carry_hook.jpg,
// G56_H2_close.jpg, G56_H2_close_crop.png; C also G10_pick_bench.jpg (T5c: the squat at its key frame). G_OUT — another
// folder for the frames (T5c: G_OUT=Docs/evidence/agata_v4). Exit code 0 only when every step reached its
// state and the console has no errors (Godot warnings are listed, not counted). Log: build/shots/g_agata/.

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
  ({ chromium } = createRequire(process.env.PLAYWRIGHT_FROM || path.join(ROOT, "package.json"))("playwright"));
}
const WEB_DIR = process.env.G_WEB_DIR ? path.resolve(ROOT, process.env.G_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = process.env.G_OUT ? path.resolve(ROOT, process.env.G_OUT) : path.join(ROOT, "Docs", "evidence", "G");
const LOG_DIR = path.join(ROOT, "build", "shots", "g_agata");
const PORT = Number(process.env.G_PORT || 8793);
const RUNS = (process.env.G_RUNS || "A,B").split(",");

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
  let page = null;
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = 60000, every = 150) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(every);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)} frame=${JSON.stringify(s?.frame?.frame)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `${name}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 85, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.speaker || ""}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  /** Clicks through beats (options from `choices` in order) until `done(state)` or `quietMs` without a beat. */
  const playThrough = async (label, { choices = [], done = null, quietMs = 4000, timeout = 240000, onBeat = null } = {}) => {
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
      quietSince = Date.now();
      if (onBeat) await onBeat(s);
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
      while (Date.now() - t1 < 10000) {
        const t = await state();
        if (beatKey(t) !== key) break;
        await sleep(120);
      }
      quietSince = Date.now();
    }
    check(false, `${label}: did not finish in ${timeout} ms`);
    return lines;
  };
  const open = async (start) => {
    if (page) await page.close();
    page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
    page.on("console", (m) => {
      const t = m.text();
      if (m.type() === "error") {
        if (/^WARNING: /.test(t) || /at: push_warning/.test(t)) consoleWarnings.push(t);
        else consoleErrors += 1;
      }
      logLine(`console.${m.type()}: ${t}`);
    });
    page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });
    logLine(`=== ?start=${start}`);
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=${start}`, { waitUntil: "load", timeout: 60000 });
    await page.waitForSelector("#canvas", { timeout: 30000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 180000 });
    await sleep(1500);
  };

  try {
    // ---- A (G1): «reach» = take at the waist, at the shelf sockets in H1.
    if (RUNS.includes("A")) {
      await open("day2");
      await playThrough("day two opening", { quietMs: 3000, timeout: 120000 });
      let s = await state();
      check(s.room === "H1", `?start=day2 → H1 (${s.room})`);
      const h = s.hotspots.shelf;
      check(h && h.visible, `the shelf sockets are a hotspot (${JSON.stringify(h)})`);
      const fires0 = s.actor.action_fires;
      // The action lasts 1.25 s of game time and swiftshader draws a few frames a second: the game runs at 1/10
      // speed for the walk and the action (window.probePause(false, k) — the existing probe hook; the click is real),
      // each read asks for a fresh state, and at the key frame the tree is frozen for the screenshot.
      const fresh = () => page.evaluate(() => { if (window.probePause) window.probePause(false); return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null; });
      // First walk to the sockets' stand point (data/story/rooms/H1.json → shelf.stand) by a click on the floor, at
      // full speed; then 1/10 speed and the real click on the sockets: only the turn and the action remain.
      await click("floor at the sockets' stand point", { x: 700, y: 800 });
      await waitFor("walked to the stand point", (t) => !t.player.walking && Math.hypot(t.player.x - 700, t.player.y - 800) < 12, 120000);
      await page.evaluate(() => window.probePause && window.probePause(false, 0.1));
      await click("hotspot shelf (sockets)", h);
      const seen = new Set();
      let keyShot = false;
      let started = false;
      const t0 = Date.now();
      while (Date.now() - t0 < 600000) {
        s = await fresh();
        const anim = String(s.actor.anim || "");
        if (anim.startsWith("reach_")) { started = true; seen.add(s.actor.frame); } else if (started) break;
        if (started && !keyShot && s.actor.frame >= 10 && s.actor.frame <= 14) {
          await page.evaluate(() => window.probePause(true));
          await shot("G1_take_shelf");
          logLine(`key frame shot: ${anim} frame ${s.actor.frame} (action «${s.actor.action}»)`);
          await page.evaluate(() => window.probePause(false, 0.1));
          keyShot = true;
        }
        await sleep(30);
      }
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0));
      check(started, "the reach action played at the shelf");
      check(keyShot, `the frame at the key moment of «reach» captured (frames seen: ${[...seen].sort((a, b) => a - b).join(",")})`);
      s = await waitFor("after the action Agata idles", (t) => String(t.actor.anim || "").startsWith("idle_") && !t.player.acting, 30000);
      check(s.actor.action_fires - fires0 === 1, `the action fired its effect once (${s.actor.action_fires - fires0})`);
      await waitFor("Q04 question after the action", (t) => beatKey(t) !== "", 20000);
      const q04 = await playThrough("Q04", { choices: ["A"], done: (t) => t.flags.done_Q04, timeout: 900000 });
      s = await state();
      check(s.flags.done_Q04 && s.flags.q04_corner_stove, `Q04 → the shelf by the stove (${q04.length} beats)`);
    }

    // ---- B (G53): the dinner, Agata seated.
    if (RUNS.includes("B")) {
      await open("epilogue");
      let shotDone = false;
      await playThrough("M26", { done: (t) => t.frame && t.frame.open && t.frame.frame === "EP_dinner" && shotDone, timeout: 1500000, onBeat: async (b) => {
        if (!shotDone && b.frame && b.frame.open && b.frame.frame === "EP_dinner") {
          await sleep(1200);
          await shot("G53_dinner_seated");
          shotDone = true;
        }
      } });
      const s = await state();
      const ly = (s.frame && s.frame.layers) || {};
      check(s.frame && s.frame.frame === "EP_dinner", `the dinner frame is on (${s.frame && s.frame.frame})`);
      check(ly.agata === true && ly.family === true, `the dinner: Agata's layer and the drawn family shown (${JSON.stringify(ly)})`);
      check(shotDone, "the dinner frame captured");
    }
    // ---- C (G10): the kerchief carried to the hook.
    if (RUNS.includes("C")) {
      await open("house");
      await playThrough("house opening", { quietMs: 3000, timeout: 120000 });
      let s = await state();
      check(s.room === "H1", `?start=house → H1 (${s.room})`);
      await click("hotspot shutter", s.hotspots.shutter);
      await waitFor("the shutter open", (t) => t.flags.h1_shutter_open && !t.player.acting && !t.player.walking, 180000);
      await playThrough("after the shutter", { quietMs: 3000, timeout: 120000 });
      s = await state();
      const fires0 = s.actor.action_fires;
      const fresh = () => page.evaluate(() => { if (window.probePause) window.probePause(false); return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null; });
      // T5c: the pick itself at the key frame (the lowest point of the squat) — the game at 1/5 speed until it is captured
      await page.evaluate(() => window.probePause && window.probePause(false, 0.2));
      await click("hotspot scarf (the wet kerchief on the bench)", s.hotspots.scarf);
      const stages = [];
      let pickShot = false;
      let walkShot = false;
      let hookShot = false;
      const t0 = Date.now();
      while (Date.now() - t0 < 600000) {
        s = await fresh();
        const st = String(s.actor.carry || "");
        if (st && stages[stages.length - 1] !== st) { stages.push(st); logLine(`carry stage ${st}`); }
        if (!pickShot && String(s.actor.anim || "").startsWith("pick_") && s.actor.frame >= 20 && s.actor.frame <= 26) {
          await page.evaluate(() => window.probePause(true));
          await shot("G10_pick_bench");
          logLine(`pick shot: ${s.actor.anim} frame ${s.actor.frame}`);
          await page.evaluate(() => window.probePause(false, 1.0));
          pickShot = true;
        }
        if (st === "walk" && !walkShot && Math.abs(s.player.x - 1215) < 260) {
          await page.evaluate(() => window.probePause(true));
          await shot("G10_carry_walk");
          await page.evaluate(() => window.probePause(false));
          walkShot = true;
        }
        if (s.flags.h1_scarf_removed && !hookShot) {
          await page.evaluate(() => window.probePause(true));
          await shot("G10_carry_hook");
          logLine(`flag at ${s.actor.anim} frame ${s.actor.frame}, Agata at (${Math.round(s.player.x)}, ${Math.round(s.player.y)})`);
          await page.evaluate(() => window.probePause(false));
          hookShot = true;
        }
        if (hookShot && !st) break;
        await sleep(40);
      }
      check(stages.join(",") === "pick,walk,place", `pick → walk → place (${stages.join(",")})`);
      check(pickShot && walkShot && hookShot, "the pick, the carry and the hook captured");
      s = await state();
      check(s.flags.h1_scarf_removed && s.actor.action_fires - fires0 === 1, `the kerchief on the hook, the effect once (${s.actor.action_fires - fires0})`);
      await playThrough("after the kerchief", { quietMs: 3000, timeout: 300000 });
    }

    // ---- D (G56): Agata close in H2 (the largest depth scale).
    if (RUNS.includes("D")) {
      await open("wedges");
      await playThrough("wedges opening", { quietMs: 3000, timeout: 120000 });
      await click("floor at the front edge of H2", { x: 900, y: 1000 });
      let s = await waitFor("walked to the front", (t) => !t.player.walking && !t.player.acting, 120000);
      await sleep(1500);
      await shot("G56_H2_close");
      const x = Math.round(s.player.x), y = Math.round(s.player.y);
      const h = Math.round(339 * (s.actor.scale || 3));
      const clip = { x: Math.max(0, x - Math.round(h * 0.35)), y: Math.max(0, y - h - 20), width: Math.round(h * 0.7), height: Math.min(1080 - Math.max(0, y - h - 20), h + 40) };
      await page.screenshot({ path: path.join(OUT_DIR, "G56_H2_close_crop.png"), clip, timeout: 180000 });
      logLine(`Agata at (${x}, ${y}), depth scale ${s.actor.scale}, sprite scale (×k) ${s.actor.sprite_scale}; crop ${JSON.stringify(clip)}`);
      check(s.room === "H2" && s.actor.scale > 2.0, `H2 close to the viewer (scale ${s.actor.scale})`);
    }
  } catch (e) {
    check(false, `exception: ${e && e.stack ? e.stack : e}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors} (Godot warnings, not errors: ${consoleWarnings.filter((w) => w.startsWith("WARNING")).length})`);
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures, warnings: consoleWarnings }, null, 1));
    await browser.close();
    server.close();
  }
  const ok = checks.filter((c) => c.ok).length;
  console.log(`g_agata_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
