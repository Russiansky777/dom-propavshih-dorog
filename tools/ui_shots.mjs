#!/usr/bin/env node
// UI frames of the web build with REAL mouse input: the bag (pockets, icons, tooltip, item in hand,
// icon flying in), fonts in the top bar / dialogue / journal / menu, readability at 1280×720, and
// the Zarechye plan (Z1 → plan hotspot, journal button) when the build has it.
//
//   tools/export_web.sh && node tools/ui_shots.mjs        (UI_SHOTS_PORT, default 8774)
//
// Frames: Docs/evidence/M1/ui_*.png; console log: build/shots/ui/console.log. Click targets come from
// window.probeState (main.gd / game_ui.gd probe_positions) — no hard-coded pixels except the empty
// scene points used to move the pointer. Exit code 0 only when every step reached its state.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "M1");
const LOG_DIR = path.join(ROOT, "build", "shots", "ui");
const PORT = Number(process.env.UI_SHOTS_PORT || 8774);
const ONLY = process.env.UI_SHOTS_ONLY || "";   // "map" → only the plan frames

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
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error("No web build. Run tools/export_web.sh first."); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });
  const log = [];
  const logLine = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const failures = [];
  const fail = (m) => { failures.push(m); logLine(`FAIL ${m}`); };
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });

  const open = async (w, h) => {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    page.on("console", (m) => logLine(`console.${m.type()}: ${m.text()}`));
    page.on("pageerror", (e) => { logLine(`pageerror: ${e.message}`); failures.push(`pageerror: ${e.message}`); });
    await page.goto(`http://127.0.0.1:${PORT}/index.html`, { waitUntil: "load", timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 });
    await sleep(1200);
    return page;
  };

  let page = await open(1920, 1080);
  let scale = 1;   // canvas px per game px (1280×720 → 2/3)
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = 30000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) { const s = await state(); if (s && pred(s)) return s; await sleep(100); }
    fail(`${label}: timeout`);
    return state();
  };
  const at = (pt) => ({ x: pt.x * scale, y: pt.y * scale });
  const click = async (label, pt, opts = {}) => {
    if (!pt || typeof pt.x !== "number") { fail(`${label}: no target`); return; }
    const p = at(pt);
    logLine(`click ${label} at (${Math.round(p.x)}, ${Math.round(p.y)})`);
    await page.mouse.click(p.x, p.y, opts);
  };
  const move = async (pt) => { const p = at(pt); await page.mouse.move(p.x, p.y, { steps: 4 }); };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `ui_${name}.png`);
    await page.screenshot({ path: file });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const finishDialogue = async (label) => {
    for (let i = 0, idle = 0; i < 60 && idle < 6; i++) {
      const s = await state();
      if (!beatKey(s)) { idle += 1; await sleep(150); continue; }
      idle = 0;
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        await click(`${label}: option ${ids[0]}`, s.ui.options[ids[0]]);
      } else {
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 780 });
      }
      await waitFor(`${label}: next beat`, (t) => beatKey(t) !== beatKey(s), 6000);
    }
  };
  const useHotspot = async (id) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h) { fail(`hotspot ${id} missing in ${s.room}`); return; }
    await click(`hotspot ${id}`, h);
    await sleep(250);
    await waitFor(`hotspot ${id}: walk`, (t) => t.player && !t.player.walking);
  };
  const goExit = async (target) => {
    const s = await state();
    await click(`exit → ${target}`, s.exits[target]);
    await waitFor(`room ${target}`, (t) => t.room === target, 25000);
    await sleep(800);
  };

  try {
    if (ONLY !== "map") {
      // --- Empty bag, fonts in the top bar ---
      await move({ x: 960, y: 640 });
      await shot("01_topbar_empty_bag");

      // --- M01: Tamara gives the key, the letter, the watch and the mitten → they fly into the bag ---
      await useHotspot("tamara");
      await waitFor("M01 dialogue", (t) => t.beat && t.beat.type === "line", 8000);
      await sleep(300);
      await shot("02_dialogue_fonts");
      // Click through the scene; the last click ends it and the items are granted.
      for (let i = 0; i < 40; i++) {
        const s = await state();
        if (!beatKey(s)) break;
        await click("M01 continue", s.ui.dialogue_click || { x: 960, y: 780 });
        await waitFor("M01 next", (t) => beatKey(t) !== beatKey(s), 6000);
        const t = await state();
        if (t.ui && t.ui.bag && t.ui.bag.animating) break;
      }
      await waitFor("icons flying", (t) => t.ui && t.ui.bag && t.ui.bag.animating, 8000);
      // Freeze the tree mid-flight (window.probePause) so the frame shows icons in the air.
      await page.evaluate(() => window.probePause(true, 0.25));
      for (let i = 0; i < 3; i++) { await page.evaluate(() => window.probePause(false, 0.25)); await sleep(90); await page.evaluate(() => window.probePause(true, 0.25)); }
      await shot("03_items_fly_in");
      await page.evaluate(() => window.probePause(false, 1));
      await finishDialogue("M01 rest");
      const s1 = await waitFor("M01 items in the bag", (t) => t.inventory.includes("key_house") && t.ui.bag && !t.ui.bag.animating, 10000);
      await sleep(400);
      const items = s1.ui.bag.items || {};
      for (const id of ["key_house", "letter_tamara", "pocket_watch", "mitten"]) {
        if (!items[id]) fail(`bag pocket for ${id} missing`);
        else if (!items[id].icon) fail(`${id}: no icon in the pocket`);
      }
      await move({ x: 1300, y: 650 });
      await sleep(200);
      await shot("04_bag_icons");

      // --- Hover → tooltip; click → in hand, pointer carries the icon; second click → back ---
      await move(s1.ui.inventory.letter_tamara);
      await waitFor("tooltip", (t) => t.ui.bag.tooltip, 4000);
      await sleep(250);
      await shot("05_bag_tooltip");
      await click("pocket key_house", s1.ui.inventory.key_house);
      await waitFor("key in hand", (t) => t.selected_item === "key_house", 4000);
      await move({ x: 1180, y: 520 });
      await sleep(250);
      const s2 = await state();
      if (s2.ui.cursor_item !== "key_house") fail(`cursor should carry key_house, got ${s2.ui.cursor_item}`);
      await shot("06_item_in_hand");
      await click("pocket key_house again", s1.ui.inventory.key_house);
      await waitFor("key back", (t) => t.selected_item === "", 4000);
      await click("pocket mitten", s1.ui.inventory.mitten);
      await waitFor("mitten in hand", (t) => t.selected_item === "mitten", 4000);
      await move({ x: 900, y: 640 });
      await click("right click on the scene", { x: 900, y: 640 }, { button: "right" });
      await waitFor("mitten back (right click)", (t) => t.selected_item === "", 4000);

      // --- Journal and menu: fonts ---
      await click("Journal", (await state()).ui.buttons.JournalButton);
      await waitFor("journal open", (t) => t.ui.journal_open, 5000);
      await sleep(400);
      await shot("07_journal");
      await click("Close journal", (await state()).ui.buttons.CloseJournal);
      await waitFor("journal closed", (t) => !t.ui.journal_open, 5000);
      await click("Hint", (await state()).ui.buttons.HintButton);
      await sleep(400);
      await click("Menu", (await state()).ui.buttons.MenuButton);
      await waitFor("menu open", (t) => t.ui.menu_open, 5000);
      await sleep(400);
      await shot("08_menu");
      await click("Close menu", (await state()).ui.buttons.CloseMenu);
      await waitFor("menu closed", (t) => !t.ui.menu_open, 5000);
      await page.close();

      // --- 1280×720: the dialogue must read at this size ---
      page = await open(1280, 720);
      scale = 1280 / 1920;
      await useHotspot("drawings");
      await waitFor("look text", (t) => beatKey(t) !== "", 8000);
      await sleep(300);
      await shot("09_dialogue_1280x720");
      await finishDialogue("look");
      await useHotspot("tamara");
      await waitFor("M01 line", (t) => t.beat && t.beat.type === "line", 8000);
      await sleep(300);
      await shot("10_dialogue_line_1280x720");
      await finishDialogue("M01 720");
      await waitFor("M01 items 720", (t) => t.inventory.includes("key_house") && t.ui.bag && !t.ui.bag.animating, 10000);
      await move({ x: 900, y: 600 });
      await sleep(300);
      await shot("11_bag_1280x720");
    }

    // --- Zarechye plan (if this build has it) ---
    const sm = await state();
    if (sm.hotspots && sm.hotspots.plan && sm.ui && "map_open" in sm.ui) {
      if (scale !== 1) { await page.close(); page = await open(1920, 1080); scale = 1; }
      await useHotspot("plan");
      await waitFor("plan open", (t) => t.ui.map_open, 8000);
      await sleep(150);
      await shot("12_plan_zoom_in");
      await waitFor("plan settled", (t) => t.ui.map && t.ui.map.settled, 6000);
      await sleep(200);
      const m = (await state()).ui.map;
      if (m.here !== "Z1") fail(`plan: «вы здесь» should be Z1, got ${m.here}`);
      if ((m.labels || {}).O1 && m.labels.O1.visible) fail("plan: Olkhovka (O1) must be hidden before a visit");
      await shot("13_plan_open");
      await page.keyboard.press("Escape");
      await waitFor("plan closed", (t) => !t.ui.map_open, 6000);
    }
  } catch (e) {
    fail(`exception: ${e.stack || e.message}`);
    try { await shot("error"); } catch (_) {}
  } finally {
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    await browser.close();
    server.close();
  }
  if (failures.length) { console.log("\nFAILURES:\n  - " + failures.join("\n  - ")); process.exit(1); }
  console.log("\nAll UI steps reached their expected state.");
}

main().catch((e) => { console.error(e); process.exit(1); });
