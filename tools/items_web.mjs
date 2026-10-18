#!/usr/bin/env node
// Items and choices after the Director's notes of 18.10 in the WEB build with REAL mouse input
// (window.probeState; agent «предметы и выборы»):
//
//   tools/export_web.sh && node tools/items_web.mjs     (ITEMS_WEB_DIR — another build dir; ITEMS_PORT, default 8779;
//                                                        ITEMS_PART=2 — only frames 07–10, state of 06 set by the probe hooks)
//
// From a new game: Tamara (M01) → lane Z4 → street Z2, then with the frames Docs/evidence/M1/items_web_*.png:
//   01 door locked  — a click on the porch door: «Заперто. Ключ … у меня в сумке», still on the street;
//   02 key in hand  — a click on the key's pocket: the key is in hand, pointer on the door;
//   03 unlocked     — a click on the door with the key: «Замок поддался … Ключ останется в двери», the key is
//                     gone from the bag, house_unlocked; after the text Agata is in H1;
//   04 H1 before    — (shutter, stove, scarf → M03) the photo on the stove ledge, two cups on the window sill;
//   05 photo table  — photo → «На столе»: Agata's reaction; the photo hotspot is on the side table;
//   06 cup blue     — cups → «Синяя»: the blue cup on the side table (its hotspot there), Tikhon's V01 line;
//   07 shelf/white  — photo → «На полке», cups → «Белая»: hotspots on the corner shelf / side table;
//   F5 → F9 keeps the places; back to the street and in again — the door is open without the key;
//   08 chalk desk   — O1 (state set by the ambientprobe hooks: the door installed, M06 done): the chalk on a
//                     pupil's desk, the hover caption; a click → Agata picks it up from the aisle;
//   09 board        — chalk from the bag on the board (after the path loop flag): written, M08 done, the chalk
//                     is not in the bag;
//   10 mark         — the bird picture → «Оставить свою пометку».
// Exit code 0 only when every step reached its state and the console has no errors.
// Log: build/shots/items/console.log, report build/shots/items/report.json.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.ITEMS_WEB_DIR ? path.resolve(ROOT, process.env.ITEMS_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = process.env.ITEMS_OUT_DIR ? path.resolve(process.env.ITEMS_OUT_DIR) : path.join(ROOT, "Docs", "evidence", "M1");
const LOG_DIR = process.env.ITEMS_LOG_DIR ? path.resolve(process.env.ITEMS_LOG_DIR) : path.join(ROOT, "build", "shots", "items");
const PORT = Number(process.env.ITEMS_PORT || 8779);
// ITEMS_PART=2 — start after frame 06 (state set by hooks): on a loaded 2-core machine the full run takes > 50 min.
const PART = process.env.ITEMS_PART || "all";

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
  page.setDefaultTimeout(180000);   // swiftshader on a loaded 2-core machine: a frame can take seconds
  page.on("console", (m) => {
    const t = m.text();
    if (m.type() === "error") {
      if (/^WARNING: /.test(t) || /at: push_warning/.test(t)) consoleWarnings.push(t);
      else consoleErrors += 1;
    }
    logLine(`console.${m.type()}: ${t}`);
  });
  page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });

  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = 60000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(150);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `items_web_${name}.png`);
    await page.screenshot({ path: file, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const waitIdle = async (label) => {
    const before = await state();
    const t0 = Date.now();
    while (Date.now() - t0 < 4000) {
      const s = await state();
      if (s && (s.player.walking || s.player.acting || beatKey(s) !== beatKey(before) || s.room !== before.room ||
          Math.hypot(s.player.x - before.player.x, s.player.y - before.player.y) > 2)) break;
      await sleep(100);
    }
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 240000);
  };
  const finish = async (label, choices = [], onBeat = null) => {
    const lines = [];
    let idle = 0;
    for (let i = 0; i < 60 && idle < 6; i++) {
      const s = await state();
      const key = beatKey(s);
      if (!key) { idle += 1; await sleep(150); continue; }
      idle = 0;
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
      await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 60000);
    }
    return lines;
  };
  const useHotspot = async (id, choices = [], onBeat = null) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `hotspot ${id} visible in ${s.room}`); return []; }
    await click(`hotspot ${id}`, h);
    await waitIdle(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "", 60000);
    return finish(`hotspot ${id}`, choices, onBeat);
  };
  const goExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { check(false, `exit ${target} in ${s.room}`); return false; }
    await click(`exit → ${target}`, e);
    await waitIdle(`exit → ${target}`);
    await waitFor(`room == ${target}`, (t) => t.room === target || beatKey(t) !== "", 120000);
    await sleep(800);
    return (await state()).room === target;
  };
  const hover = async (pt) => {
    await page.mouse.move(pt.x - 30, pt.y - 10);
    await sleep(120);
    await page.mouse.move(pt.x, pt.y, { steps: 4 });
    await sleep(900);
  };
  const pocket = async (item) => {
    const s = await state();
    const p = s.ui.inventory && s.ui.inventory[item];
    if (!p) { check(false, `the bag shows ${item}`); return false; }
    await click(`bag pocket ${item}`, p);
    await waitFor(`${item} in hand`, (t) => t.selected_item === item, 5000);
    return true;
  };
  const near = (h, x0, y0, x1, y1) => h && h.x >= x0 && h.x <= x1 && h.y >= y0 && h.y <= y1;

  try {
    await page.goto(`http://127.0.0.1:${PORT}/index.html?ambientprobe`, { waitUntil: "load", timeout: 60000 });
    await page.waitForSelector("#canvas", { timeout: 30000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 120000 });
    await sleep(1500);
    let s;
    if (PART !== "2") {
    // M01 → street.
    await useHotspot("tamara");
    s = await waitFor("M01 done", (t) => t.flags.done_M01);
    check(s.inventory.includes("key_house"), "Tamara gave the key");
    check(await goExit("Z4"), "Z1 → Z4");
    check(await goExit("Z2"), "Z4 → Z2");

    // 01: the porch door without the key.
    s = await state();
    check(s.exits.H1 && !s.exits.H1.open, "the porch door is locked before the key is applied");
    await click("porch door (no key)", s.exits.H1);
    await waitIdle("porch door");
    s = await waitFor("locked text", (t) => beatKey(t) !== "", 60000);
    check(s.room === "Z2" && (s.beat.text || "").includes("Ключ") && (s.beat.text || "").includes("сумке"), `locked: «${s.beat && s.beat.text}», still on the street`);
    await sleep(500);
    await shot("01_door_locked");
    await finish("locked text");
    // 02: the key in hand, pointer on the door.
    check(await pocket("key_house"), "a click on the key's pocket takes it in hand");
    s = await state();
    await hover(s.exits.H1);
    await shot("02_key_in_hand");
    // 03: the key on the door.
    await click("porch door with the key", s.exits.H1);
    await waitIdle("door with key");
    s = await waitFor("unlock text", (t) => beatKey(t) !== "", 60000);
    check((s.beat.text || "").includes("Ключ останется в двери"), `unlock: «${s.beat && s.beat.text}»`);
    check(!s.inventory.includes("key_house") && s.flags.house_unlocked, `the key left the bag (${s.inventory.join(",")}), house_unlocked`);
    await sleep(400);
    await shot("03_door_unlocked");
    await finish("unlock text");
    s = await waitFor("in H1 after the unlock", (t) => t.room === "H1", 120000);
    check(s.room === "H1", "after the text Agata walks into the house");
    await sleep(1200);

    // H1: M03 to light the room, then V01.
    await useHotspot("shutter");
    await useHotspot("stove");
    await useHotspot("scarf", ["ask"]);
    s = await waitFor("M03 done", (t) => t.flags.done_M03, 120000);
    await click("floor (step back)", { x: 1250, y: 960 });
    await waitIdle("step back");
    await page.mouse.move(1500, 1040);
    await sleep(1200);
    s = await state();
    check(near(s.hotspots.photo, 686, 462, 722, 504), `04: the photo on the stove ledge (${JSON.stringify(s.hotspots.photo)})`);
    check(near(s.hotspots.cups, 1580, 478, 1654, 516), `04: the cups on the window sill (${JSON.stringify(s.hotspots.cups)})`);
    await shot("04_H1_before");
    // 05: photo → table, with the reaction on screen.
    let reaction = "";
    await useHotspot("photo", ["table"], async (b) => {
      if (!reaction && b.beat.type !== "options" && (b.beat.text || "").includes("у кресла")) {
        reaction = b.beat.text;
        await sleep(500);
        await shot("05_photo_table");
      }
    });
    s = await state();
    check(reaction !== "", `«На столе» → Agata's reaction «${reaction}»`);
    check(s.flags.v01_photo_table && near(s.hotspots.photo, 647, 676, 705, 742), `the photo hotspot moved onto the side table (${JSON.stringify(s.hotspots.photo)})`);
    // 06: cups → blue.
    let tikhon = false;
    await useHotspot("cups", ["blue"], async (b) => {
      if (b.beat.speaker === "tikhon") tikhon = true;
    });
    s = await state();
    check(s.flags.v01_cup_blue && near(s.hotspots.cups, 800, 733, 856, 773), `the blue cup on the side table (${JSON.stringify(s.hotspots.cups)})`);
    check(tikhon || s.flags.done_V01, "V01: Tikhon checks his place after both choices");
    await click("floor (step back)", { x: 1250, y: 960 });
    await waitIdle("step back");
    await page.mouse.move(1500, 1040);
    await sleep(800);
    await shot("06_photo_table_cup_blue");
    } else {
      // Part 2 (ITEMS_PART=2): the state after frame 06 set by the ambientprobe hooks — the door unlocked by the
      // key, M01–M03 done, the photo on the side table, the blue cup — then the same real clicks as in a full run.
      for (const f of ["done_M01", "met_tamara", "knows_pier_trace", "has_key_house", "has_letter_tamara", "has_pocket_watch",
        "has_mitten", "done_M02", "house_unlocked", "done_M03", "started_M03", "met_tikhon", "house_open", "stove_lit",
        "h1_shutter_open", "h1_scarf_removed", "v01_photo_table", "v01_cup_blue", "done_V01"]) {
        await page.evaluate((fl) => window.ambientFlag(fl, true), f);
      }
      await page.evaluate(() => window.ambientGoto("H1", "default"));
      s = await waitFor("in H1 (part 2)", (t) => t.room === "H1", 120000);
      await sleep(1500);
      s = await state();
      check(near(s.hotspots.photo, 647, 676, 705, 742) && near(s.hotspots.cups, 800, 733, 856, 773), "part 2: photo and blue cup on the side table");
    }
    // 07: photo → shelf, cups → white.
    await useHotspot("photo", ["shelf"]);
    await useHotspot("cups", ["white"]);
    s = await state();
    check(s.flags.v01_photo_shelf && !s.flags.v01_photo_table && near(s.hotspots.photo, 680, 296, 706, 326), `the photo on the corner shelf (${JSON.stringify(s.hotspots.photo)})`);
    check(s.flags.v01_cup_white && !s.flags.v01_cup_blue, "white cup chosen, blue back");
    await click("floor (step back)", { x: 1250, y: 960 });
    await waitIdle("step back");
    await page.mouse.move(1500, 1040);
    await sleep(800);
    await shot("07_photo_shelf_cup_white");
    // F5 → F9 keeps the places and the unlocked door.
    await page.keyboard.press("F5");
    await sleep(800);
    await page.keyboard.press("F9");
    await sleep(2500);
    s = await state();
    check(s.flags.v01_photo_shelf && s.flags.v01_cup_white && s.flags.house_unlocked && !s.inventory.includes("key_house"), "after F5/F9: photo on the shelf, white cup, door unlocked, no key");
    // Out to the street and back in — no key needed.
    check(await goExit("Z2"), "H1 → Z2");
    s = await state();
    check(s.exits.H1 && s.exits.H1.open, "the porch door stays open");
    check(await goExit("H1"), "Z2 → H1 without the key");

    // O1 via the probe hooks (the door installed, M06 done) — then real clicks.
    for (const f of ["done_M04", "seen_school_door", "seen_workshop", "seen_bell", "seen_mirror_home", "knows_rule_things_remember",
      "done_M05", "door_school_installed", "done_M06", "seen_class_traces"]) {
      await page.evaluate((fl) => window.ambientFlag(fl, true), f);
    }
    await page.evaluate(() => window.ambientGoto("O1", "default"));
    s = await waitFor("in O1", (t) => t.room === "O1", 120000);
    await sleep(1500);
    s = await state();
    const ch = s.hotspots.chalk;
    check(ch && ch.visible && near(ch, 584, 766, 642, 800), `08: the chalk hotspot on the pupil's desk (${JSON.stringify(ch)})`);
    await hover(ch);
    await shot("08_chalk_on_desk");
    await useHotspot("chalk");
    s = await state();
    check(s.inventory.includes("chalk") && !(s.hotspots.chalk && s.hotspots.chalk.visible), "the chalk taken from the desk");
    // 09: the board.
    await page.evaluate(() => window.ambientFlag("observed_path_loop", true));
    await sleep(300);
    await finish("after loop flag");
    check(await pocket("chalk"), "chalk in hand");
    s = await state();
    await click("board with the chalk", s.hotspots.board);
    await waitIdle("board");
    await waitFor("board text", (t) => beatKey(t) !== "", 60000);
    await finish("board");
    s = await waitFor("M08 done", (t) => t.flags.done_M08, 20000);
    check(s.flags.wrote_on_board && !s.inventory.includes("chalk"), `written; the chalk stays at the board, not in the bag (${s.inventory.join(",")})`);
    await sleep(600);
    await shot("09_board_written");
    // 10: the pencil mark.
    await useHotspot("bird_drawing", ["mark"]);
    s = await state();
    check(s.flags.v03_marked, "V03 mark chosen");
    await page.mouse.move(1500, 1040);
    await sleep(800);
    await shot("10_bird_mark");
  } catch (e) {
    check(false, `exception: ${e && e.stack ? e.stack : e}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors} (Godot warnings, not errors: ${consoleWarnings.filter((w) => w.startsWith("WARNING")).join(" | ") || "none"})`);
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures }, null, 1));
    await browser.close();
    server.close();
  }
  const ok = checks.filter((c) => c.ok).length;
  console.log(`items_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
