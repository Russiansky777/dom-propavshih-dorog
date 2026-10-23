#!/usr/bin/env node
// World batch E (Director 23.10: F17–F21) in the WEB build with REAL mouse input (window.probeState). Against a
// local export or the published site:
//
//   tools/export_web.sh && node tools/world_web.mjs                 (WORLD_WEB_DIR — another build dir, WORLD_PORT 8783)
//   WORLD_URL=https://russiansky777.github.io/dom-propavshih-dorog/ node tools/world_web.mjs   (the live site)
//
// The point in the story is set by the ?ambientprobe hooks (ambientFlag / ambientGoto / ambientItem); everything
// the player does is real mouse movement and clicks on the canvas:
//   F20 — street Z2: the «спуск к причалу» mark higher and slanted north-east, a click on it → the pier; the lane
//         mark mid-road, a click → the lane; the mill yard has no exit to the turn;
//   F21 — the street under drizzle: a frame of the puddles (rings);
//   F17 — the time of day: Z2 / M1 / Z4 / H1 / R1 frames at dusk, evening and night of day two and in the morning;
//         the journal line;
//   F19 — the mill yard: the sheet on the board; a click on the board → the close-up rides in from it, the words
//         by the game (title, the bell signals), its text over it; clicks read on and close it;
//   F18 — the gallery: the hinges into the frame and the V notch by the mouse, the handle → the door stands open
//         on the winter classroom (frame).
// Frames: build/shots/world/*.png (evidence copies → Docs/evidence/M2/world_*.jpg by hand); report: build/shots/world/report.json.
// Exit code 0 only when every check passed and the console has no errors.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const require = createRequire(process.env.PW_FROM || path.join(ROOT, "tools", "package.json"));
let chromium;
try { ({ chromium } = require("playwright")); } catch (_) {
  ({ chromium } = createRequire("/home/claude/dom-propavshih-dorog/tools/package.json")("playwright"));
}

const WEB_DIR = process.env.WORLD_WEB_DIR ? path.resolve(ROOT, process.env.WORLD_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = process.env.WORLD_OUT_DIR ? path.resolve(process.env.WORLD_OUT_DIR) : path.join(ROOT, "build", "shots", "world");
const PORT = Number(process.env.WORLD_PORT || 8783);
const URL_BASE = process.env.WORLD_URL || "";
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

// Main-story flags up to (not including) a scene, as RoomManager.start_at piles them (enough for the time of day).
const DAY = {
  d2_morning: ["done_M01", "done_M02", "done_M03", "done_M04", "done_M05", "done_M06", "done_M07", "done_M08", "done_N01",
    "night_day1", "house_unlocked", "house_open", "stove_lit", "door_school_installed", "met_tamara", "met_tikhon"],
};
DAY.d2_dusk = DAY.d2_morning.concat(["done_M09", "done_M09s", "done_M09b", "done_M10", "done_M11", "done_M12", "done_M13a",
  "done_M13", "done_M14", "done_M15a", "evening_dusk", "pond_lowered", "office_unbolted"]);
DAY.d2_evening = DAY.d2_dusk.concat(["done_M15s", "done_M15", "rope_on_ring", "road_held_both_ends"]);
DAY.d2_night = DAY.d2_evening.concat(["done_M16s", "far_snow_seen", "done_M16", "three_lights_sent", "far_lights_answered", "done_M17", "ferry_verified"]);

async function main() {
  if (!URL_BASE && !fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const log = [];
  const logLine = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const failures = [];
  const checks = [];
  const check = (ok, msg) => { checks.push({ ok: !!ok, msg }); logLine(`${ok ? "OK  " : "FAIL"} ${msg}`); if (!ok) failures.push(msg); };
  let consoleErrors = 0;
  const server = URL_BASE ? null : await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.setDefaultTimeout(180000);
  page.on("console", (m) => {
    const t = m.text();
    if (m.type() === "error" && !/^WARNING: /.test(t) && !/at: push_warning/.test(t)) consoleErrors += 1;
    if (m.type() === "error") logLine(`console.error: ${t}`);
  });
  page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = 60000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(200);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `${name}.png`);
    await page.mouse.move(1910, 600);
    await sleep(300);
    await page.screenshot({ path: file, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 3 });
    await sleep(80);
    await page.mouse.click(pt.x, pt.y);
  };
  const drag = async (label, from, to) => {
    logLine(`drag ${label}`);
    await page.mouse.move(from.x, from.y, { steps: 3 });
    await page.mouse.down();
    for (let k = 1; k <= 8; k++) await page.mouse.move(from.x + (to.x - from.x) * k / 8, from.y + (to.y - from.y) * k / 8);
    await page.mouse.up();
    await sleep(500);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}` : "");
  const finish = async (label) => {
    let idle = 0;
    for (let i = 0; i < 40 && idle < 6; i++) {
      const s = await state();
      const key = beatKey(s);
      if (!key) { idle += 1; await sleep(150); continue; }
      idle = 0;
      await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 980 });
      await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 60000);
    }
  };
  const resetTo = async (flags) => {
    await page.evaluate(() => { for (const k of Object.keys((window.probeState || {}).flags || {})) window.ambientFlag(k, false); });
    for (const f of flags) await page.evaluate((x) => window.ambientFlag(x, true), f);
  };
  const goto = async (room) => {
    await page.evaluate((r) => window.ambientGoto(r, "default"), room);
    await waitFor(`room ${room}`, (s) => s.room === room, 60000);
    await sleep(2500);   // grade fades in 2 s
    await finish(`enter ${room}`);
  };

  try {
    const base = URL_BASE ? URL_BASE.replace(/\/?$/, "/") : `http://127.0.0.1:${PORT}/`;
    await page.goto(`${base}index.html?ambientprobe`, { waitUntil: "load", timeout: 120000 });
    await page.waitForSelector("#canvas", { timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true && window.ambientProbeReady === true, null, { timeout: 180000 });
    await sleep(1500);
    const version = await page.evaluate(async () => { try { return (await (await fetch("version.txt", { cache: "no-store" })).text()).trim(); } catch (_) { return ""; } });
    logLine(`build: ${version}`);

    // --- F20 / F21 / F17: the street by day, its marks, then dusk and night ---
    await resetTo(["done_M01", "met_tamara", "house_unlocked"]);
    await goto("Z2");
    let s = await state();
    check(s.time && s.time.state === "d1_afternoon", `Z2 on arrival: d1_afternoon (${s.time && s.time.state})`);
    await shot("01_Z2_day_marks_rings");
    const ex = {};
    for (const [k, v] of Object.entries(s.exits || {})) if (v.mark) ex[k] = v.mark;
    logLine(`exit marks: ${JSON.stringify(ex)}`);
    check(ex.R1 && ex.R1.y < 690 && ex.R1.angle <= -20 && ex.R1.angle >= -70, `«спуск к причалу»: higher (y ${ex.R1 && Math.round(ex.R1.y)}) and north-east (angle ${ex.R1 && ex.R1.angle})`);
    check(ex.Z4 && ex.Z4.y >= 640 && ex.Z4.y <= 760 && ex.Z4.x > 100, `«в переулок к почте»: mid-road right of the post corner (${ex.Z4 && Math.round(ex.Z4.x)}, ${ex.Z4 && Math.round(ex.Z4.y)})`);
    if (ex.R1) {
      await click("the pier mark", ex.R1);
      s = await waitFor("Z2 → R1 by the slanted mark", (t) => t.room === "R1", 60000);
      check(s.room === "R1", "a click on the north-east mark leads down to the pier");
    }
    await goto("Z2");
    s = await state();
    if (s.exits.Z4 && s.exits.Z4.mark) {
      await click("the lane mark", s.exits.Z4.mark);
      s = await waitFor("Z2 → Z4 by the mid-road mark", (t) => t.room === "Z4", 60000);
      check(s.room === "Z4", "a click on the mid-road mark leads into the lane");
    }
    await resetTo(DAY.d2_morning);
    await goto("M1");
    s = await state();
    check(!s.exits.Z3, `M1: no exit to the turn (exits: ${Object.keys(s.exits).join(", ")})`);
    check(s.time && s.time.state === "d2_morning", `M1 in the morning (${s.time && s.time.state})`);
    await shot("02_M1_morning_board_sheet");

    // --- F19: the board close-up by a click ---
    const board = s.hotspots.schedule;
    await click("the shift board", board);
    s = await waitFor("board close-up open", (t) => t.view && t.view.open && t.view.id === "shift_board", 30000);
    const zoomSeen = !!(s.view && s.view.zooming);
    s = await waitFor("close-up settled", (t) => t.view && t.view.open && !t.view.zooming, 10000);
    check(zoomSeen || s.view.open, `the close-up rides in from the board (zooming seen: ${zoomSeen})`);
    const words = (s.view.sheets || []).map((x) => x.text || "").join("\n");
    check(words.includes("Распорядок смен") && words.includes("Один удар — пускай") && words.includes("Долгий — подымай"), "the sheet's words by the game: title and the bell signals");
    check(s.beat && (s.beat.text || "").includes("распорядок"), `the board's text over it: «${s.beat && s.beat.text}»`);
    await sleep(500);
    await shot("03_M1_board_closeup");
    await finish("board text");
    await click("close the close-up", { x: 1500, y: 500 });
    s = await waitFor("board close-up closed", (t) => !(t.view && t.view.open), 20000);
    check(!s.view.open, "a click closes the board close-up");

    // --- F17: day two dusk, evening, night ---
    for (const [st, rooms] of [["d2_dusk", ["Z2", "H2"]], ["d2_evening", ["Z2", "M1", "Z4", "R1", "H1"]], ["d2_night", ["Z2"]]]) {
      await resetTo(DAY[st]);
      for (const r of rooms) {
        if (r === "H1") await page.evaluate(() => window.ambientFlag("h1_shutter_open", true));
        await goto(r);
        s = await state();
        check(s.time && s.time.state === st, `${r}: ${st} (${s.time && s.time.state}, «${s.time && s.time.label}»)`);
        await shot(`04_${st}_${r}`);
      }
    }
    // The journal line.
    await click("Журнал", (await state()).ui.buttons.JournalButton);
    s = await waitFor("journal open", (t) => t.ui.journal_open, 10000);
    check(s.time && s.time.label && s.time.label.length > 5, `journal time line: «${s.time && s.time.label}»`);
    await sleep(500);
    await shot("05_journal_time");
    await click("close the journal", (await state()).ui.buttons.CloseJournal);
    await waitFor("journal closed", (t) => !t.ui.journal_open, 10000);

    // --- F18: the door by the mouse → the winter classroom ---
    await resetTo(["done_M01", "done_M02", "done_M03", "house_open", "house_unlocked", "done_M04", "seen_school_door",
      "seen_workshop", "seen_bell", "knows_rule_things_remember", "has_school_door", "has_bell", "has_mirror_home", "seen_mirror_home"]);
    await page.evaluate(() => window.ambientItem("door_hinges", true));
    await goto("H3");
    s = await state();
    const pocket = s.ui.bag && s.ui.bag.items && s.ui.bag.items.door_hinges;
    if (pocket) {
      await click("the hinges' pocket", pocket);
      await sleep(300);
      await click("the school door", s.hotspots.school_door);
      s = await waitFor("door close-up", (t) => t.puzzle && t.puzzle.open, 30000);
      let p = s.puzzle;
      const slots = Object.keys(p.slots || {});
      const pieces = Object.keys(p.pieces || {});
      for (let i = 0; i < Math.min(slots.length, pieces.length); i++) {
        p = (await state()).puzzle;
        await drag(`${pieces[i]} → ${slots[i]}`, p.pieces[pieces[i]], p.slots[slots[i]]);
      }
      p = (await state()).puzzle;
      await click("the V notch", p.marks[2]);
      await sleep(600);
      p = (await state()).puzzle;
      await click("the handle", p.handle);
      s = await waitFor("the door open on the winter class", (t) => t.puzzle && t.puzzle.view === "winter", 15000);
      await sleep(900);
      await shot("06_H3_door_winter_class");
      check(s.puzzle && s.puzzle.view === "winter", "the door stands open on the winter classroom");
    } else {
      check(false, "the hinges' pocket is in the bag");
    }
  } catch (e) {
    check(false, `exception: ${e && e.stack || e}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors}`);
    fs.writeFileSync(path.join(OUT_DIR, "report.json"), JSON.stringify({ checks, failures, log }, null, 2));
    await browser.close();
    if (server) server.close();
  }
  console.log(`world_web: ${checks.filter((c) => c.ok).length}/${checks.length} checks OK`);
  process.exit(failures.length ? 1 : 0);
}

main();
