#!/usr/bin/env node
// M1 walkthrough of the web build with REAL canvas clicks: Z1 → … → M08 → back to H3.
//
//   node tools/screenshots.mjs            (after tools/export_web.sh)
//
// Serves build/web on localhost, opens it in headless Chromium (software WebGL), waits for
// `window.probeReady`, then follows the bot's solution path. Click targets come from
// `window.probeState` (published by main.gd: hotspot/exit centres, UI buttons, dialogue options,
// inventory slots, puzzle pieces) so the script never hard-codes pixel positions. One screenshot
// per room plus the puzzle close-up, the dialogue box, journal and menu go to build/shots/m1/.
// build/shots/m1/console.log holds every console message / page error. Exit code 0 only when every
// step reached its expected game state.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.SHOTS_WEB_DIR ? path.resolve(ROOT, process.env.SHOTS_WEB_DIR) : path.join(ROOT, "build", "web");
const SHOTS_DIR = path.join(ROOT, "build", "shots", "m1");
const PORT = Number(process.env.SHOTS_PORT || 8765);
const GL_MODE = process.env.SHOTS_GL || "angle";
const MODE = process.env.SHOTS_MODE || "full";   // "full" = M01→M08 walkthrough, "h1" = real-art H1 frames, "stride" = 100 ms frame series, "h3" = up to M05: mirror + door close-ups by mouse → Docs/evidence/M1/H3_v2_*.png
const STRIDE_DIR = path.join(SHOTS_DIR, "stride");
const STEP_TIMEOUT_MS = 40000;

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript",
  ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png",
  ".json": "application/json", ".css": "text/css", ".ico": "image/x-icon",
};

function serve(dir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, {
        "Content-Type": MIME[path.extname(file)] || "application/octet-stream",
        "Content-Length": st.size,
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "require-corp",
        "Cache-Control": "no-store",
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
      if (!d.startsWith("chromium-")) continue;
      const cand = path.join(base, d, "chrome-linux", "chrome");
      if (fs.existsSync(cand)) return cand;
    }
  }
  return undefined;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) {
    console.error(`No web build at ${WEB_DIR}. Run tools/export_web.sh first.`);
    process.exit(2);
  }
  fs.mkdirSync(SHOTS_DIR, { recursive: true });
  if (MODE === "full") {
    for (const f of fs.readdirSync(SHOTS_DIR)) {
      if (/^\d\d_/.test(f) || /^real_/.test(f) || f === "console.log") fs.rmSync(path.join(SHOTS_DIR, f), { force: true });
    }
  }
  const consoleLog = [];
  const logLine = (s) => { const line = `[${new Date().toISOString()}] ${s}`; consoleLog.push(line); console.log(line); };

  const server = await serve(WEB_DIR);
  const url = `http://127.0.0.1:${PORT}/index.html`;
  const glArgs = GL_MODE === "swiftshader"
    ? ["--use-gl=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
    : ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"];
  const executablePath = findChromium();
  logLine(`chromium: ${executablePath || "(playwright default)"}; gl mode: ${GL_MODE}`);
  const browser = await chromium.launch({ headless: true, executablePath,
    args: [...glArgs, "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on("console", (m) => logLine(`console.${m.type()}: ${m.text()}`));
  page.on("pageerror", (e) => logLine(`pageerror: ${e.message}`));
  page.on("requestfailed", (r) => logLine(`requestfailed: ${r.url()} ${r.failure()?.errorText}`));

  const failures = [];
  const shots = [];
  let shotIndex = 0;
  const shot = async (name) => {
    shotIndex += 1;
    const file = path.join(SHOTS_DIR, MODE !== "full" ? `${name}.png` : `${String(shotIndex).padStart(2, "0")}_${name}.png`);
    await page.screenshot({ path: file });
    shots.push(file);
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  // H3 evidence frames (MODE=h3): Docs/evidence/M1/<name>.png; in the full run — ordinary shots.
  const EVIDENCE_DIR = path.join(ROOT, "Docs", "evidence", "M1");
  const evidenceShot = async (name) => {
    if (MODE !== "h3") return shot(name);
    fs.mkdirSync(EVIDENCE_DIR, { recursive: true });
    const file = path.join(EVIDENCE_DIR, `${name}.png`);
    await page.screenshot({ path: file });
    shots.push(file);
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = STEP_TIMEOUT_MS) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(120);
    }
    const s = await state();
    failures.push(`${label}: timeout ${timeout} ms; room=${s?.room} flags=${JSON.stringify(s?.flags)} beat=${JSON.stringify(s?.beat)}`);
    logLine(`FAIL ${label}`);
    return s;
  };
  const click = async (label, pt) => {
    if (!pt || typeof pt.x !== "number") { failures.push(`${label}: no click target`); logLine(`FAIL ${label}: no target`); return false; }
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.click(pt.x, pt.y);
    return true;
  };
  // After a click the probe may still show the standing state for a moment: first wait (briefly) for
  // the walk to start or for an immediate reaction, then for walking AND any action to be over.
  const waitWalk = async (label) => {
    const before = await state();
    const t0 = Date.now();
    while (Date.now() - t0 < 4000) {
      const s = await state();
      if (s && (s.player.walking || s.player.acting || beatKey(s) !== beatKey(before) || (s.puzzle && s.puzzle.open) || s.room !== before.room ||
          Math.hypot(s.player.x - before.player.x, s.player.y - before.player.y) > 2)) break;
      await sleep(100);
    }
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 60000);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  /** Clicks through the dialogue; option choices are taken from `choices` in order (default: first). */
  const finishDialogue = async (label, choices = []) => {
    const lines = [];
    let idle = 0;
    for (let i = 0; i < 60 && idle < 6; i++) {
      const s = await state();
      const key = beatKey(s);
      // a scene staging (fade between lines: the boat at R1, the night by the stove) — busy with no beat on screen
      const staging = s.busy && !(s.view && s.view.open) && !(s.puzzle && s.puzzle.open) && !s.player?.walking;
      if (!key && staging) { await sleep(200); continue; }
      if (!key) { idle += 1; await sleep(150); continue; }
      idle = 0;
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        let pick = choices.length ? choices.shift() : ids[0];
        if (!ids.includes(pick)) pick = ids[0];
        lines.push(`options:${pick}`);
        await click(`${label}: option ${pick}`, s.ui.options[pick]);
      } else {
        lines.push(`${s.beat.speaker || "·"}: ${(s.beat.text || "").slice(0, 50)}`);
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 780 });
      }
      await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 8000);
    }
    return lines;
  };
  const useHotspot = async (id, choices = []) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { failures.push(`hotspot ${id} missing/hidden in ${s.room}`); logLine(`FAIL hotspot ${id}`); return []; }
    await click(`hotspot ${id}`, h);
    await waitWalk(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "" || t.puzzle?.open, 15000);
    return finishDialogue(`hotspot ${id}`, choices);
  };
  const useItemOn = async (item, id, choices = []) => {
    const s = await state();
    await click(`inventory ${item}`, s.ui.inventory[item]);
    await waitFor(`select ${item}`, (t) => t.selected_item === item, 5000);
    return useHotspot(id, choices);
  };
  const roomShots = new Set();
  /** One `real_<ROOM>.png` per room, taken after Agata has settled on arrival. */
  const roomShot = async (room) => {
    if (MODE !== "full" || roomShots.has(room)) return;
    roomShots.add(room);
    await sleep(500);
    const file = path.join(SHOTS_DIR, `real_${room}.png`);
    await page.screenshot({ path: file });
    shots.push(file);
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const goExit = async (target, expectChange = true) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { failures.push(`exit ${target} missing in ${s.room}`); logLine(`FAIL exit ${target}`); return false; }
    const before = s.room;
    await click(`exit → ${target}`, e);
    await waitWalk(`exit → ${target}`);
    if (expectChange) {
      await waitFor(`room == ${target}`, (t) => t.room === target, 45000);
      await sleep(700);
      const ok = (await state()).room === target;
      if (ok) await roomShot(target);
      return ok;
    }
    await waitFor(`exit → ${target}: reaction`, (t) => beatKey(t) !== "" || (t.flags && t.flags.observed_path_loop), 8000);
    await finishDialogue(`exit → ${target}`);
    return (await state()).room !== before;
  };
  const clickUi = async (name) => {
    const s = await state();
    return click(`ui ${name}`, (s.ui.buttons || {})[name]);
  };

  try {
    logLine(`open ${url}`);
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    await page.waitForSelector("#canvas", { timeout: 30000 });
    const t0 = Date.now();
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 })
      .catch((e) => failures.push(`probeReady not set within 90 s: ${e.message}`));
    logLine(`probeReady after ${Date.now() - t0} ms; room=${(await state())?.room}`);
    await sleep(1200);

    if (MODE === "stride") {
      // Defect «ходьба скользит»: a stroboscopic series. Every 100 ms of game time the tree is paused
      // (window.probePause), the sprite state is read and a screenshot taken, so each frame and its
      // numbers (drawn position, sheet frame, speed_scale) describe the same instant. Analysed by
      // tools/stride_frames.py: the planted foot must stay on the same floor pixels between frames.
      fs.rmSync(STRIDE_DIR, { recursive: true, force: true });
      fs.mkdirSync(STRIDE_DIR, { recursive: true });
      await useHotspot("tamara");
      await waitFor("M01 done", (s) => s.flags.done_M01);
      if (!(await goExit("Z4"))) failures.push("Z1→Z4 failed");   // post → lane (Z4) → street
      if (!(await goExit("Z2"))) failures.push("Z4→Z2 failed");
      if (!(await goExit("H1"))) failures.push("Z2→H1 failed");
      await sleep(600);
      // Shadows off for the whole series: the analysis diffs every capture against ref.png and the
      // soft shadow would be read as part of the feet (third argument; older builds ignore it).
      const pause = (p, ts = 1) => page.evaluate(([v, t]) => { window.probePause(v, t, false); }, [p, ts]);
      const series = [];
      // After a pause the next game frame runs the clamped maximum of 8 physics ticks (133 ms of
      // game time); timeScale < 1 shortens that (0.25 → ~33 ms between captures).
      // `clip` limits the screenshot to the band the walk happens in (PNG encoding of a full software-
      // rendered frame is the slow part); the analysis pastes it back at its offset on a grey canvas.
      const capture = async (label, target, maxFrames = 60, timeScale = 1, clip = null) => {
        await click(`stride ${label}`, target);
        await sleep(60);
        for (let i = 0; i < maxFrames; i++) {
          await pause(true, timeScale);
          const s = await state();
          const file = path.join(STRIDE_DIR, `${label}_${String(i).padStart(3, "0")}.png`);
          await page.screenshot(clip ? { path: file, clip } : { path: file });
          series.push({ label, index: i, file: path.basename(file), clip, ticks: s.ticks, physics_frames: s.physics_frames, player: s.player, actor: s.actor });
          const walking = s.player.walking;
          await pause(false, timeScale);
          if (!walking) break;
          await sleep(40);
        }
        await pause(false, 1);
        await waitFor(`${label}: arrived`, (t) => t.player && !t.player.walking && Math.hypot(t.player.x - target.x, t.player.y - target.y) < 20, 60000);
      };
      // Reference frame (floor without the figure near the front edge): Agata at the far strip.
      await click("floor far strip", { x: 1300, y: 720 });
      await waitWalk("far strip");
      await sleep(300);
      await pause(true);
      await page.screenshot({ path: path.join(STRIDE_DIR, "ref.png") });
      const ref = await state();
      await pause(false);
      if (ref.room !== "H1") failures.push(`stride: expected H1 for the reference frame, got ${ref.room}`);
      const STRIDE_MAX = Number(process.env.STRIDE_MAX || 140);
      const STRIDE_MAX_ROOM = 70;
      // In-room series for the eye (GIF only, optional — full software-rendered frames are slow):
      // STRIDE_ROOM=1 adds a left walk with the room visible.
      if (process.env.STRIDE_ROOM === "1") {
        await click("floor start right", { x: 1700, y: 985 });
        await waitWalk("start right");
        await sleep(300);
        await capture("room_left", { x: 880, y: 985 }, STRIDE_MAX_ROOM, 0.5, { x: 600, y: 300, width: 1320, height: 780 });
        await sleep(300);
      }
      // Measurement view: room hidden, flat grey screen — every non-grey pixel is the figure, so the
      // feet are found exactly (the boots are nearly floor-coloured and partly transparent in-room).
      await page.evaluate(() => { if (window.probeIsolate) window.probeIsolate(true); });
      await sleep(200);
      // Four straight walks, one per cardinal row, captured ~33 ms of game time apart (timeScale 0.25):
      // every sheet-frame change falls between two captures, several captures fall inside each frame.
      // Floor points clear of exits (H2: x ≥ 1790; H3/H4: y ≥ 1000) and hotspots.
      // walkTo: the probe may still show the previous (standing) state right after a click, so wait
      // until she is near the point and standing.
      const walkTo = async (label, pt) => {
        await click(label, pt);
        await waitFor(`${label}: arrived`, (t) => t.player && !t.player.walking && Math.hypot(t.player.x - pt.x, t.player.y - pt.y) < 20, 60000);
        await sleep(300);
      };
      await walkTo("floor start right", { x: 1700, y: 985 });
      const H_BAND = { x: 0, y: 640, width: 1920, height: 440 };      // feet and skirt along y ≈ 985
      const V_BAND = { x: 1400, y: 420, width: 500, height: 660 };    // feet column at x ≈ 1650
      await capture("left", { x: 880, y: 985 }, STRIDE_MAX, 0.25, H_BAND);     // row 6
      await sleep(300);
      await capture("right", { x: 1700, y: 985 }, STRIDE_MAX, 0.25, H_BAND);   // row 2
      await sleep(300);
      await walkTo("floor start bottom", { x: 1650, y: 990 });
      await capture("up", { x: 1650, y: 760 }, STRIDE_MAX, 0.25, V_BAND);      // row 4
      await sleep(300);
      await capture("down", { x: 1650, y: 990 }, STRIDE_MAX, 0.25, V_BAND);    // row 0
      await page.evaluate(() => { if (window.probeIsolate) window.probeIsolate(false); });
      const fin = await state();
      if (fin.room !== "H1") failures.push(`stride series must stay in H1, ended in ${fin.room}`);
      const first = series.find((x) => x.actor && x.actor.stride_px);
      fs.writeFileSync(path.join(STRIDE_DIR, "series.json"), JSON.stringify({
        room: "H1", interval_game_ms: 33, isolated: ["left", "right", "up", "down"], ref: { player: ref.player, actor: ref.actor },
        stride_px: first ? first.actor.stride_px : null, samples: series,
      }, null, 2));
      logLine(`stride series: ${series.length} frames in ${path.relative(ROOT, STRIDE_DIR)}`);
      if (series.length < 12) failures.push(`stride series too short (${series.length})`);
      throw { h1done: true };
    }

    if (MODE === "tikhon") {
      // Tikhon (bone puppet): reach H1, do the three M03 steps, catch him lifting his head on his line,
      // then a 6-second idle series (crops around him) for a GIF: breathing, tail wave, ear/head accents.
      const TDIR = path.join(SHOTS_DIR, "tikhon");
      fs.rmSync(TDIR, { recursive: true, force: true });
      fs.mkdirSync(TDIR, { recursive: true });
      await useHotspot("tamara");
      await waitFor("M01 done", (s) => s.flags.done_M01);
      if (!(await goExit("Z4"))) failures.push("Z1→Z4 failed");
      if (!(await goExit("Z2"))) failures.push("Z4→Z2 failed");
      if (!(await goExit("H1"))) failures.push("Z2→H1 failed");
      await sleep(600);
      await shot("tikhon_before_M03");
      await useHotspot("shutter");
      await useHotspot("stove");
      {
        const s = await state();
        await click("hotspot scarf", s.hotspots.scarf);
        await waitWalk("scarf");
        // Through the dialogue; stop on Tikhon's first line and photograph him (head lifted).
        let caught = false;
        for (let i = 0; i < 40; i++) {
          const t = await state();
          if (t.beat && t.beat.type === "line" && t.beat.speaker === "tikhon" && !caught) {
            await sleep(700);
            await shot("tikhon_talks");
            caught = true;
          }
          if (t.beat && t.beat.type === "options") {
            await click("option", Object.values(t.ui.options)[0]);
          } else if (t.beat && t.beat.type) {
            await click("continue", t.ui.dialogue_click || { x: 960, y: 780 });
          } else if (t.flags.done_M03) {
            break;
          }
          await sleep(500);
        }
        if (!caught) failures.push("no Tikhon line caught in M03");
      }
      await waitFor("M03 done", (s) => s.flags.done_M03, 30000);
      await click("floor step back", { x: 1200, y: 960 });
      await waitWalk("step back");
      await sleep(800);
      await shot("tikhon_idle");
      const crop = { x: 240, y: 400, width: 300, height: 220 };
      for (let i = 0; i < 48; i++) {
        await page.screenshot({ path: path.join(TDIR, `idle_${String(i).padStart(2, "0")}.png`), clip: crop });
        await sleep(110);
      }
      logLine(`tikhon series: 48 crops in ${path.relative(ROOT, TDIR)}`);
      throw { h1done: true };
    }

    if (MODE === "h1") {
      // Real Agata in the real H1: reach H1 (M01 → Z2 → H1), then direction / tempo / occlusion frames.
      for (const f of fs.readdirSync(SHOTS_DIR)) if (f.startsWith("H1_real_")) fs.rmSync(path.join(SHOTS_DIR, f), { force: true });
      await useHotspot("tamara");
      await waitFor("M01 done", (s) => s.flags.done_M01);
      if (!(await goExit("Z4"))) failures.push("Z1→Z4 failed");   // post → lane (Z4) → street
      if (!(await goExit("Z2"))) failures.push("Z4→Z2 failed");
      if (!(await goExit("H1"))) failures.push("Z2→H1 failed");
      await sleep(600);
      const walkShot = async (label, target, waitMs) => {
        await click(`floor ${label}`, target);
        await sleep(waitMs);
        const s = await state();
        if (!s.player.walking) failures.push(`${label}: expected to be mid-walk at ${waitMs} ms`);
        await shot(`H1_real_walk_${label}`);
        await waitWalk(label);
      };
      // Right (profile facing right), then down (towards the viewer), then two idle frames 1.2 s apart.
      await walkShot("right", { x: 1700, y: 760 }, 900);
      await walkShot("down", { x: 1700, y: 990 }, 330);
      await sleep(300);
      await shot("H1_real_idle_a");
      const idleA = await state();
      await sleep(1200);
      await shot("H1_real_idle_b");
      const idleB = await state();
      if (idleA.player.x !== idleB.player.x || idleA.player.walking) failures.push("idle: player moved or kept walking");
      // Left (profile facing left) along the near edge, then right again to line up under the window, then up (back).
      await walkShot("left", { x: 1000, y: 990 }, 800);
      await click("floor under window", { x: 1650, y: 990 });
      await waitWalk("under window");
      let s1 = await state();
      await click("hotspot shutter (walks straight up)", s1.hotspots.shutter);
      await sleep(330);
      await shot("H1_real_walk_up");
      await waitWalk("shutter");
      await sleep(300);
      await shot("H1_real_back_at_shutter");
      await finishDialogue("shutter");
      // Behind the table: partially covered by the foreground.
      await click("floor behind table", { x: 900, y: 790 });
      await waitWalk("behind table");
      await sleep(400);
      await shot("H1_real_behind_table");
      // Stove: walks left along the far strip, faces the stove on arrival.
      s1 = await state();
      await click("hotspot stove", s1.hotspots.stove);
      await waitWalk("stove");
      await sleep(300);
      await shot("H1_real_at_stove");
      await finishDialogue("stove");
      // In front of the table: fully visible.
      await click("floor in front of table", { x: 880, y: 985 });
      await waitWalk("front of table");
      await sleep(400);
      await shot("H1_real_front_of_table");
      const fin = await state();
      if (fin.room !== "H1") failures.push(`expected H1, got ${fin.room}`);
      if (!fin.flags.stove_lit || !fin.flags.h1_shutter_open) failures.push("stove/shutter interactions did not register");
      throw { h1done: true };
    }

    // --- Z1: Tamara (M01) ---
    await shot("Z1_post");
    await roomShot("Z1");
    await useHotspot("drawings");
    {
      const s = await state();
      await click("hotspot tamara", s.hotspots.tamara);
      await waitWalk("tamara");
      await waitFor("M01 dialogue", (t) => t.beat && t.beat.type === "line", 8000);
      await sleep(400);
      await shot("dialogue_M01");
      // Tamara's own line: her talk sheet must be playing (probe `npcs.tamara.anim` = talk_*).
      {
        const s0 = await state();
        const key0 = beatKey(s0);
        // since 22.10 Tamara speaks first («Агата? Ты же у меня домой письма отправляла») — no click needed then
        if (!(s0.beat && s0.beat.speaker === "tamara")) {
          await click("M01: continue to Tamara's line", s0.ui.dialogue_click || { x: 960, y: 780 });
          await waitFor("Tamara's line", (t) => beatKey(t) !== key0 && t.beat && t.beat.speaker === "tamara", 8000);
        }
        await sleep(500);
        const s1 = await state();
        const tam = s1.npcs && s1.npcs.tamara;
        if (!tam || !/^talk_/.test(tam.anim) || !tam.talking) failures.push(`Tamara should play her talk sheet during her line, got ${JSON.stringify(tam)}`);
        await shot("dialogue_M01_tamara_talks");
        const f0 = tam ? tam.frame : -1;
        await sleep(300);
        const s2 = await state();
        if (s2.npcs && s2.npcs.tamara && s2.npcs.tamara.frame === f0 && /^talk_/.test(s2.npcs.tamara.anim)) failures.push("Tamara's talk animation did not advance in 300 ms");
      }
      await finishDialogue("M01");
      {
        const s3 = await state();
        const tam = s3.npcs && s3.npcs.tamara;
        if (!tam || !/^idle_/.test(tam.anim)) failures.push(`after M01 Tamara should idle, got ${JSON.stringify(tam)}`);
      }
    }
    await waitFor("M01 done", (s) => s.flags.done_M01 && s.inventory.includes("key_house"));

    // --- Z2 ---
    if (!(await goExit("Z4"))) failures.push("Z1→Z4 failed");
    await shot("Z4_lane");
    await goExit("H3", false);  // the gallery's side porch in the lane is closed: reaction text only
    await waitFor("still Z4", (s) => s.room === "Z4", 2000);
    if (!(await goExit("Z2"))) failures.push("Z4→Z2 failed");
    await shot("Z2_street");

    // --- Z3 → R1 (M02) ---
    if (!(await goExit("Z3"))) failures.push("Z2→Z3 failed");
    await shot("Z3_shore");
    if (!(await goExit("R1"))) failures.push("Z3→R1 failed");
    await shot("R1_pier");
    await useHotspot("instruction");
    await useHotspot("pelageya");
    await waitFor("M02 done", (s) => s.flags.done_M02);

    // --- H1 (M03, V01, Q04) ---
    if (!(await goExit("Z2"))) failures.push("R1→Z2 failed");
    if (!(await goExit("H1"))) failures.push("Z2→H1 failed");
    await shot("H1_room");
    await useHotspot("shutter");
    await useHotspot("stove");
    await useHotspot("scarf", ["ask"]);
    await waitFor("M03 done", (s) => s.flags.done_M03 && s.flags.met_tikhon);
    await sleep(300);
    await shot("H1_tikhon");
    await useHotspot("cups", ["blue"]);
    await useHotspot("photo", ["table"]);
    await waitFor("V01 done", (s) => s.flags.done_V01);
    await useHotspot("shelf", ["A"]);
    await waitFor("Q04 done", (s) => s.flags.done_Q04);

    // --- H4 (V02) ---
    if (!(await goExit("H4"))) failures.push("H1→H4 failed");
    await finishDialogue("V02");
    await waitFor("V02 done", (s) => s.flags.done_V02);
    await shot("H4_attic");
    if (!(await goExit("H1"))) failures.push("H4→H1 failed");

    // --- H2 (M04 part 1) ---
    if (!(await goExit("H2"))) failures.push("H1→H2 failed");
    await shot("H2_workshop");
    await useHotspot("bench");
    await useHotspot("hinges_box");
    await useHotspot("bell");
    await waitFor("hinges in inventory", (s) => s.inventory.includes("door_hinges"));

    // --- H3 (M04 completes, M05 puzzle) ---
    if (!(await goExit("H1"))) failures.push("H2→H1 failed");
    if (!(await goExit("H3"))) failures.push("H1→H3 failed");
    await shot("H3_gallery");
    await useHotspot("school_door");
    await waitFor("M04 done", (s) => s.flags.done_M04);
    // Mirror ЗГ (Director 18.10: «показать то, что описывается»): the click opens the close-up — the
    // mirror face-on with a live reflection (Agata, the gallery behind her) and the old photo; the text
    // plays over it; a click closes it.
    {
      const s = await state();
      await click("hotspot mirror_home", s.hotspots.mirror_home);
      await waitWalk("mirror_home");
      await waitFor("mirror close-up open", (t) => t.view && t.view.open && t.view.type === "mirror", 15000);
      await sleep(900);
      await evidenceShot("H3_v2_mirror_text");
      await finishDialogue("mirror_home");
      await sleep(500);
      await evidenceShot("H3_v2_mirror");
      const v = (await state()).view;
      if (!v.reflection || !v.reflection.shares_world || v.reflection.agata !== "idle_0") failures.push(`mirror reflection: ${JSON.stringify(v.reflection)}`);
      await click("mirror close-up: click to close", v.blank);
      await waitFor("mirror close-up closed", (t) => !(t.view && t.view.open) && !t.busy, 6000);
    }
    await useItemOn("door_hinges", "school_door");
    await waitFor("puzzle open", (s) => s.puzzle && s.puzzle.open);
    await sleep(600);
    await shot("puzzle_closeup");
    await evidenceShot("H3_v2_door_before");
    {
      // Everything with REAL mouse drags (Director 18.10): hinges from the tray into the frame's
      // sockets, the threshold slid under the door's mark, the door closed by its handle.
      const P = async () => (await state()).puzzle;
      const drag = async (label, from, to, opts = {}) => {
        const steps = opts.steps || 14;
        logLine(`drag ${label} (${Math.round(from.x)}, ${Math.round(from.y)}) → (${Math.round(to.x)}, ${Math.round(to.y)})`);
        await page.mouse.move(from.x, from.y);
        await sleep(60);
        await page.mouse.down();
        for (let k = 1; k <= steps; k++) {
          await page.mouse.move(from.x + (to.x - from.x) * k / steps, from.y + (to.y - from.y) * k / steps);
          await sleep(20);
        }
        if (opts.beforeUp) await opts.beforeUp();
        await page.mouse.up();
        await sleep(450);
      };
      const near = (a, b, d = 3) => a && b && Math.hypot(a.x - b.x, a.y - b.y) <= d;
      let p = await P();
      if (Object.keys(p.pieces || {}).length !== 3) failures.push(`three hinges in the tray expected, got ${JSON.stringify(Object.keys(p.pieces || {}))}`);
      // A miss: dropped away from the sockets → back to the tray.
      await drag("hinge_1 → nowhere (miss)", p.pieces.hinge_1, { x: 720, y: 300 });
      await waitFor("missed hinge back in the tray", (t) => t.puzzle && Object.keys(t.puzzle.placed).length === 0 && near(t.puzzle.pieces.hinge_1, t.puzzle.tray.hinge_1), 5000);
      p = await P();
      await drag("hinge_1 → top", p.pieces.hinge_1, { x: p.slots.top.x + 16, y: p.slots.top.y + 12 });
      await waitFor("hinge_1 in the top socket", (t) => t.puzzle.placed.top === "hinge_1", 5000);
      p = await P();
      await drag("hinge_2 → bottom", p.pieces.hinge_2, { x: p.slots.bottom.x - 12, y: p.slots.bottom.y + 18 });
      await waitFor("hinge_2 in the bottom socket", (t) => t.puzzle.placed.bottom === "hinge_2", 5000);
      // Threshold: drag the beam so the V notch comes under the door's mark (snaps within 40 px).
      p = await P();
      await drag("beam: V notch under the door's mark", p.beam, { x: p.beam.x + (p.anchor.x - p.marks[2].x) + 14, y: p.beam.y }, { steps: 10 });
      await waitFor("V notch aligned", (t) => t.puzzle.mark === 2, 5000);
      // Two hinges only: the door does not hold (three are needed).
      p = await P();
      await click("door handle (two hinges)", p.handle);
      await waitFor("wall after the first error", (s) => s.puzzle.view === "wall" && s.puzzle.errors === 1, 8000);
      await sleep(250);
      await evidenceShot("H3_v2_door_wrong_wall");
      await shot("puzzle_wrong_wall");
      await sleep(1700);
      // Third hinge: photographed mid-drag (the target socket glows).
      p = await P();
      await drag("hinge_3 → middle", p.pieces.hinge_3, { x: p.slots.middle.x + 14, y: p.slots.middle.y - 10 }, {
        beforeUp: async () => { await sleep(150); await evidenceShot("H3_v2_door_dragging"); } });
      await waitFor("hinge_3 in the middle socket", (t) => t.puzzle.placed.middle === "hinge_3", 5000);
      // A wrong (straight) notch: no.
      p = await P();
      await drag("beam: straight notch 1 under the mark", p.beam, { x: p.beam.x + (p.anchor.x - p.marks[1].x) - 10, y: p.beam.y }, { steps: 10 });
      await waitFor("notch 1 under the mark", (t) => t.puzzle.mark === 1, 5000);
      p = await P();
      await click("door handle (wrong notch)", p.handle);
      await waitFor("hint after the second error", (s) => s.puzzle.errors === 2 && s.puzzle.hint, 8000);
      await sleep(1800);
      // A click on the V notch brings it under the mark; the handle closes the door.
      p = await P();
      await click("V notch (click)", p.marks[2]);
      await waitFor("V notch aligned by click", (t) => t.puzzle.mark === 2, 5000);
      await sleep(400);
      await evidenceShot("H3_v2_door_ready");
      p = await P();
      await click("door handle (correct)", p.handle);
      await waitFor("puzzle solved (winter view)", (s) => s.puzzle.solved && s.puzzle.view === "winter", 8000);
      await sleep(500);
      await evidenceShot("H3_v2_door_after");
      await shot("puzzle_solved_winter");
      await waitFor("puzzle closed", (s) => !(s.puzzle && s.puzzle.open), 20000);
      await finishDialogue("M05");
    }
    await waitFor("M05 done", (s) => s.flags.done_M05 && !s.inventory.includes("door_hinges"));
    if (MODE === "h3") throw { h1done: true };

    // --- O1 (M06, M07, V03) ---
    if (!(await goExit("O1"))) failures.push("H3→O1 failed");
    await finishDialogue("first entry: «Там зима. А у нас ещё октябрь»");
    await shot("O1_winter_class");
    await useHotspot("sack");
    await useHotspot("notebooks");
    await waitFor("M06 done", (s) => s.flags.done_M06);
    await useHotspot("teacher_drawer");  // close-up of the drawer (photo, drawing, plan) under the M07 lines
    await waitFor("M07 done", (s) => s.flags.done_M07 && s.flags.knows_crossing_plan);
    {
      const s = await state();
      if (s.view && s.view.open) {
        await shot("O1_drawer_closeup");
        await click("close-up: Закрыть", s.view.close);
        await waitFor("drawer close-up closed", (t) => !(t.view && t.view.open), 5000);
      }
    }
    await useHotspot("chalk");
    await useHotspot("bird_drawing", ["leave"]);
    await waitFor("V03 done", (s) => s.flags.done_V03);

    // --- O2 (M08 loop) ---
    if (!(await goExit("O2"))) failures.push("O1→O2 failed");
    await shot("O2_yard");
    await useItemOn("mitten", "porch_step");  // the mitten comes from Agata's bag (M01)
    {
      const s = await state();
      await click("exit → O4 (gate)", s.exits.O4);
      await waitWalk("gate");
      await waitFor("loop observed", (t) => t.flags.observed_path_loop && t.room === "O2", 15000);
      await sleep(900);  // fade-in completes
      await finishDialogue("loop reaction + M08");
    }
    await waitFor("M08 done (the loop alone)", (s) => s.flags.done_M08, 15000);
    await sleep(500);
    await shot("O2_after_loop");

    // --- O1: chalk on the board — «Мама, я иду» (one of three, or none) ---
    if (!(await goExit("O1"))) failures.push("O2→O1 failed");
    await useItemOn("chalk", "board", ["mama"]);
    await waitFor("board: «Мама, я иду»", (s) => s.flags.board_mama && !s.inventory.includes("chalk"));
    await shot("O1_board_written");

    // --- Home through the school door → the night by the stove (N01) → «День второй»; journal, hint, menu ---
    await goExit("H3", false);
    await finishDialogue("night by the stove");
    await waitFor("N01 done (night by the stove)", (s) => s.flags.done_N01 && s.room === "H1" && !s.busy, 60000);
    await shot("H1_morning_day2");
    await clickUi("JournalButton");
    await waitFor("journal open", (s) => s.ui.journal_open, 5000);
    await sleep(400);
    await shot("journal");
    await clickUi("CloseJournal");
    await waitFor("journal closed", (s) => !s.ui.journal_open, 5000);
    await clickUi("HintButton");
    await waitFor("hint shown", (s) => s.last_hint && s.last_hint.includes("1"), 5000);
    await sleep(300);
    await shot("hint_tier1");
    await clickUi("MenuButton");   // «Меню» → the pause → «Сохранить»
    await waitFor("pause open", (s) => s.pause && s.pause.open && s.pause.blur > 0.99, 5000);
    await click("pause «Сохранить»", (await state()).pause.items.save);
    await waitFor("menu open", (s) => s.ui.menu_open, 5000);
    await clickUi("Save1");
    await waitFor("saved slot 1", (s) => s.last_hint && s.last_hint.includes("1"), 5000);
    await sleep(300);
    await shot("menu_slots");
    await clickUi("CloseMenu");
    await waitFor("back to the pause", (s) => !s.ui.menu_open && s.pause.open, 5000);
    await click("pause «Продолжить»", (await state()).pause.items.continue);
    await waitFor("pause closed", (s) => !s.pause.open, 5000);

    const fin = await state();
    logLine(`final: room=${fin.room} inventory=${JSON.stringify(fin.inventory)} flags=${Object.keys(fin.flags).filter((k) => fin.flags[k]).join(",")}`);
    for (const f of ["door_school_installed", "board_mama", "knows_crossing_plan", "done_M08", "done_N01"]) {
      if (!fin.flags[f]) failures.push(`final flag ${f} missing`);
    }
    if (fin.room !== "H1") failures.push(`final room ${fin.room} != H1 (morning by the stove)`);
  } catch (e) {
    if (!(e && e.h1done)) {
      failures.push(`exception: ${e.stack || e.message}`);
      logLine(`exception: ${e.stack || e.message}`);
      try { await shot("error"); } catch (_) {}
    }
  } finally {
    fs.writeFileSync(path.join(SHOTS_DIR, MODE === "full" ? "console.log" : `console_${MODE}.log`), consoleLog.join("\n") + "\n");
    await browser.close();
    server.close();
  }

  console.log("\nScreenshots:");
  for (const s of shots) console.log("  " + path.relative(ROOT, s));
  if (failures.length) {
    console.log("\nFAILURES:");
    for (const f of failures) console.log("  - " + f);
    process.exit(1);
  }
  console.log("\nAll steps reached their expected state.");
}

main().catch((e) => { console.error(e); process.exit(1); });
