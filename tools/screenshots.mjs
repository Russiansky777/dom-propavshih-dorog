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
const WEB_DIR = path.join(ROOT, "build", "web");
const SHOTS_DIR = path.join(ROOT, "build", "shots", "m1");
const PORT = Number(process.env.SHOTS_PORT || 8765);
const GL_MODE = process.env.SHOTS_GL || "angle";
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
  fs.rmSync(SHOTS_DIR, { recursive: true, force: true });
  fs.mkdirSync(SHOTS_DIR, { recursive: true });
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
    const file = path.join(SHOTS_DIR, `${String(shotIndex).padStart(2, "0")}_${name}.png`);
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
  const waitWalk = async (label) => {
    await sleep(250);
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  /** Clicks through the dialogue; option choices are taken from `choices` in order (default: first). */
  const finishDialogue = async (label, choices = []) => {
    const lines = [];
    let idle = 0;
    for (let i = 0; i < 60 && idle < 6; i++) {
      const s = await state();
      const key = beatKey(s);
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
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "" || t.puzzle?.open, 6000);
    return finishDialogue(`hotspot ${id}`, choices);
  };
  const useItemOn = async (item, id, choices = []) => {
    const s = await state();
    await click(`inventory ${item}`, s.ui.inventory[item]);
    await waitFor(`select ${item}`, (t) => t.selected_item === item, 5000);
    return useHotspot(id, choices);
  };
  const goExit = async (target, expectChange = true) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { failures.push(`exit ${target} missing in ${s.room}`); logLine(`FAIL exit ${target}`); return false; }
    const before = s.room;
    await click(`exit → ${target}`, e);
    await waitWalk(`exit → ${target}`);
    if (expectChange) {
      await waitFor(`room == ${target}`, (t) => t.room === target, 20000);
      await sleep(700);
      return (await state()).room === target;
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

    // --- Z1: Tamara (M01) ---
    await shot("Z1_post");
    await useHotspot("drawings");
    {
      const s = await state();
      await click("hotspot tamara", s.hotspots.tamara);
      await waitWalk("tamara");
      await waitFor("M01 dialogue", (t) => t.beat && t.beat.type === "line", 8000);
      await sleep(400);
      await shot("dialogue_M01");
      await finishDialogue("M01");
    }
    await waitFor("M01 done", (s) => s.flags.done_M01 && s.inventory.includes("key_house"));

    // --- Z2 ---
    if (!(await goExit("Z2"))) failures.push("Z1→Z2 failed");
    await shot("Z2_street");
    await goExit("H3", false);  // closed: reaction text only
    await waitFor("still Z2", (s) => s.room === "Z2", 2000);

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
    await useHotspot("mirror_home");
    await useItemOn("door_hinges", "school_door");
    await waitFor("puzzle open", (s) => s.puzzle && s.puzzle.open);
    await sleep(500);
    await shot("puzzle_closeup");
    {
      let p = (await state()).puzzle;
      // Wrong attempt: top + middle sockets, first notch.
      await click("piece hinge_1", p.pieces.hinge_1); await sleep(200);
      await click("slot top", p.slots.top); await sleep(300);
      p = (await state()).puzzle;
      await click("piece hinge_2", p.pieces.hinge_2); await sleep(200);
      await click("slot middle", p.slots.middle); await sleep(300);
      await click("mark 0", p.marks[0]); await sleep(200);
      await click("check (wrong)", p.check);
      await waitFor("wall shown after the first error", (s) => s.puzzle.view === "wall" && s.puzzle.errors === 1, 8000);
      await sleep(300);
      await shot("puzzle_wrong_wall");
      await click("check (wrong again)", p.check);
      await waitFor("hint after the second error", (s) => s.puzzle.errors === 2 && s.puzzle.hint, 8000);
      // Fix: move hinge_2 to the bottom socket, notch 2.
      p = (await state()).puzzle;
      await click("slot middle (return piece)", p.slots.middle); await sleep(300);
      p = (await state()).puzzle;
      await click("piece hinge_2", p.pieces.hinge_2); await sleep(200);
      await click("slot bottom", p.slots.bottom); await sleep(300);
      await click("mark 2", p.marks[2]); await sleep(200);
      await click("check (correct)", p.check);
      await waitFor("puzzle solved (winter view)", (s) => s.puzzle.solved && s.puzzle.view === "winter", 8000);
      await sleep(400);
      await shot("puzzle_solved_winter");
      await waitFor("puzzle closed", (s) => !(s.puzzle && s.puzzle.open), 15000);
      await finishDialogue("M05");
    }
    await waitFor("M05 done", (s) => s.flags.done_M05 && !s.inventory.includes("door_hinges"));

    // --- O1 (M06, M07, V03) ---
    if (!(await goExit("O1"))) failures.push("H3→O1 failed");
    await shot("O1_winter_class");
    await useHotspot("sack");
    await useHotspot("notebooks");
    await waitFor("M06 done", (s) => s.flags.done_M06);
    await useHotspot("teacher_drawer");
    await waitFor("M07 done", (s) => s.flags.done_M07 && s.flags.knows_trip_14);
    await useHotspot("chalk");
    await useHotspot("bird_drawing", ["leave"]);
    await waitFor("V03 done", (s) => s.flags.done_V03);

    // --- O2 (M08 loop) ---
    if (!(await goExit("O2"))) failures.push("O1→O2 failed");
    await shot("O2_yard");
    await useHotspot("mitten");
    await useItemOn("mitten", "porch_step");
    {
      const s = await state();
      await click("exit → O4 (gate)", s.exits.O4);
      await waitWalk("gate");
      await waitFor("loop observed", (t) => t.flags.observed_path_loop && t.room === "O2", 15000);
      await sleep(900);  // fade-in completes
      await finishDialogue("loop reaction");
    }
    await sleep(500);
    await shot("O2_after_loop");

    // --- O1: chalk on the board → M08 ---
    if (!(await goExit("O1"))) failures.push("O2→O1 failed");
    await useItemOn("chalk", "board");
    await waitFor("M08 done", (s) => s.flags.wrote_on_board && s.flags.done_M08);
    await shot("O1_board_written");

    // --- Home through the school door; journal, hint, menu ---
    if (!(await goExit("H3"))) failures.push("O1→H3 failed");
    await shot("H3_back_home");
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
    await clickUi("MenuButton");
    await waitFor("menu open", (s) => s.ui.menu_open, 5000);
    await clickUi("Save1");
    await waitFor("saved slot 1", (s) => s.last_hint && s.last_hint.includes("1"), 5000);
    await sleep(300);
    await shot("menu_slots");
    await clickUi("CloseMenu");

    const fin = await state();
    logLine(`final: room=${fin.room} inventory=${JSON.stringify(fin.inventory)} flags=${Object.keys(fin.flags).filter((k) => fin.flags[k]).join(",")}`);
    for (const f of ["door_school_installed", "wrote_on_board", "knows_trip_14", "done_M08"]) {
      if (!fin.flags[f]) failures.push(`final flag ${f} missing`);
    }
    if (fin.room !== "H3") failures.push(`final room ${fin.room} != H3`);
  } catch (e) {
    failures.push(`exception: ${e.stack || e.message}`);
    logLine(`exception: ${e.stack || e.message}`);
    try { await shot("error"); } catch (_) {}
  } finally {
    fs.writeFileSync(path.join(SHOTS_DIR, "console.log"), consoleLog.join("\n") + "\n");
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
