#!/usr/bin/env node
// The shared mechanics of the Director's notes 23.10 (F4–F9, F12, F14) in the WEB build with REAL mouse input
// (window.probeState; agent «механики»). Against a local export or the published site:
//
//   tools/export_web.sh && node tools/mech_web.mjs                 (MECH_WEB_DIR — another build dir, MECH_PORT 8781)
//   MECH_URL=https://russiansky777.github.io/dom-propavshih-dorog/ node tools/mech_web.mjs   (the live site)
//   MECH_PART=examine,mirror                                         (only some parts; default: all)
//
// The state of a point in the story is set by the ?ambientprobe hooks (ambientFlag / ambientGoto / ambientItem);
// everything the player does is real mouse movement and clicks on the canvas:
//   examine — hover a pocket: the magnifier; click it: the item full screen + Agata's line; a click reads it, the
//             next closes; a double click opens it too; Esc closes; a single click still takes the item in hand;
//   mirror  — mother's mirror: the wall clock beside the glass turns 2°/s by the page's clock; the watch from the
//             bag onto the glass; after ~10 s the realisation (flag, Agata's words).
// Frames: Docs/evidence/M2/mech_web_*.png; log and report: build/shots/mech/.
// Exit code 0 only when every check passed and the console has no errors.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
// Playwright lives in the main checkout's tools/node_modules (worktrees have none): PW_FROM overrides.
const require = createRequire(process.env.PW_FROM || path.join(ROOT, "tools", "package.json"));
let chromium;
try { ({ chromium } = require("playwright")); } catch (_) {
  ({ chromium } = createRequire("/home/claude/dom-propavshih-dorog/tools/package.json")("playwright"));
}

const WEB_DIR = process.env.MECH_WEB_DIR ? path.resolve(ROOT, process.env.MECH_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = process.env.MECH_OUT_DIR ? path.resolve(process.env.MECH_OUT_DIR) : path.join(ROOT, "Docs", "evidence", "M2");
const LOG_DIR = path.join(ROOT, "build", "shots", "mech");
const PORT = Number(process.env.MECH_PORT || 8781);
const URL_BASE = process.env.MECH_URL || "";
const PARTS = (process.env.MECH_PART || "examine,mirror").split(",");

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
  try { const p = chromium.executablePath(); if (p && fs.existsSync(p)) return p; } catch (_) {}
  return undefined;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (!URL_BASE && !fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });
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
    if (m.type() === "error" || m.type() === "warning") logLine(`console.${m.type()}: ${t}`);
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
    const file = path.join(OUT_DIR, `mech_web_${name}.png`);
    await page.screenshot({ path: file, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 3 });
    await sleep(80);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}` : "");
  const finish = async (label) => {
    const lines = [];
    let idle = 0;
    for (let i = 0; i < 40 && idle < 6; i++) {
      const s = await state();
      const key = beatKey(s);
      if (!key) { idle += 1; await sleep(150); continue; }
      idle = 0;
      lines.push(`${s.beat.speaker || "·"}: ${s.beat.text || ""}`);
      await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 980 });
      await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 60000);
    }
    return lines;
  };
  const setFlags = async (flags) => {
    for (const f of flags) await page.evaluate((x) => window.ambientFlag(x, true), f);
  };
  const giveItems = async (items) => {
    for (const it of items) await page.evaluate((x) => window.ambientItem(x, true), it);
  };
  const goto = async (room) => {
    await page.evaluate((r) => window.ambientGoto(r, "default"), room);
    await waitFor(`room ${room}`, (s) => s.room === room, 60000);
    await sleep(1200);
    await finish(`enter ${room}`);
  };

  try {
    const base = URL_BASE ? URL_BASE.replace(/\/?$/, "/") : `http://127.0.0.1:${PORT}/`;
    await page.goto(`${base}index.html?ambientprobe`, { waitUntil: "load", timeout: 120000 });
    await page.waitForSelector("#canvas", { timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true && window.ambientProbeReady === true, null, { timeout: 180000 });
    await sleep(1500);
    check(await page.evaluate(() => typeof window.ambientItem === "function"), "window.ambientItem exists (playtest hook)");
    const version = await page.evaluate(async () => { try { return (await (await fetch("version.txt", { cache: "no-store" })).text()).trim(); } catch (_) { return ""; } });
    logLine(`build: ${version}`);

    if (PARTS.includes("examine")) {
      await setFlags(["done_M01", "met_tamara", "house_unlocked", "done_M03", "house_open"]);
      await giveItems(["pocket_watch", "photo_bridge", "plan_crossing", "journal_manager"]);
      await goto("H1");
      let s = await state();
      const pk = s.ui.bag.items;
      check(pk.photo_bridge && pk.plan_crossing && pk.pocket_watch, "the bag shows the given items");
      // Hover → magnifier; a click on it → the close-up.
      await page.mouse.move(pk.photo_bridge.x - 40, pk.photo_bridge.y + 30);
      await sleep(200);
      await page.mouse.move(pk.photo_bridge.x, pk.photo_bridge.y, { steps: 5 });
      await sleep(900);
      await shot("01_bag_magnifier");
      await click("magnifier on the bridge photo", pk.photo_bridge.badge);
      s = await waitFor("examine open", (t) => t.examine && t.examine.open && t.examine.item === "photo_bridge", 20000);
      check(s.examine.source === "art" && s.examine.picture && s.examine.picture.w > 900, `the photo full screen (${JSON.stringify(s.examine.picture)})`);
      check(s.beat && s.beat.speaker === "agata" && (s.beat.text || "").includes("канат"), `Agata's line over it: «${s.beat && s.beat.text}»`);
      await sleep(600);
      await shot("02_examine_photo");
      await click("read the line", { x: 1500, y: 880 });
      await waitFor("line read", (t) => !beatKey(t), 20000);
      await click("close by a click", { x: 1500, y: 880 });
      s = await waitFor("examine closed", (t) => !(t.examine && t.examine.open), 20000);
      check(!s.examine.open && s.selected_item === "", "a click after the line closes it; nothing in hand");
      // A double click on the plan.
      await page.mouse.move(pk.plan_crossing.x, pk.plan_crossing.y, { steps: 3 });
      await page.mouse.dblclick(pk.plan_crossing.x, pk.plan_crossing.y);
      s = await waitFor("examine plan by double click", (t) => t.examine && t.examine.open && t.examine.item === "plan_crossing", 20000);
      check(s.examine.open && s.selected_item === "", "a double click opens the plan, nothing stays in hand");
      await sleep(600);
      await shot("03_examine_plan");
      await finish("plan line");
      await page.keyboard.press("Escape");
      s = await waitFor("Esc closes", (t) => !(t.examine && t.examine.open), 20000);
      check(!s.examine.open, "Esc closes the close-up");
      // The journal (page beside the book), the watch (going).
      await click("magnifier on the journal", (await state()).ui.bag.items.journal_manager.badge);
      s = await waitFor("examine journal", (t) => t.examine && t.examine.open && t.examine.item === "journal_manager", 20000);
      check(s.examine.note, "the journal: the page with the last record beside it");
      await sleep(500);
      await shot("04_examine_journal");
      await finish("journal line");
      await click("close", s.examine.close);
      await waitFor("closed", (t) => !(t.examine && t.examine.open), 20000);
      // A single click still takes the item in hand.
      s = await state();
      await click("single click on the watch", s.ui.bag.items.pocket_watch);
      s = await waitFor("watch in hand", (t) => t.selected_item === "pocket_watch", 10000);
      check(s.selected_item === "pocket_watch" && !(s.examine && s.examine.open), "a single click: in hand, no close-up");
      await page.mouse.click(s.ui.bag.items.pocket_watch.x, s.ui.bag.items.pocket_watch.y, { button: "right" });
      await waitFor("put back", (t) => t.selected_item === "", 10000);
    }

    if (PARTS.includes("mirror")) {
      await setFlags(["done_M01", "met_tamara", "house_unlocked", "done_M03", "house_open", "done_N01", "done_M09", "done_M09s", "done_M09b",
        "done_M10", "done_M11", "done_M12", "done_M13a", "done_M13", "done_M14", "office_mirror_mounted", "office_mirror_clamped",
        "office_unbolted", "sluice_opened", "pond_lowered", "h2_bundle_unwrapped", "nina_mirror_clamped", "has_clamp"]);
      await giveItems(["pocket_watch", "journal_manager"]);
      await goto("H2");
      let s = await state();
      check(s.hotspots.bundle_nina && s.hotspots.bundle_nina.visible, "mother's mirror on the bench");
      await click("mother's mirror", s.hotspots.bundle_nina);
      s = await waitFor("fast mirror open", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "fast_mirror", 120000);
      await finish("mirror open");
      s = await state();
      const p0 = s.mechanic.panel;
      const t0 = Date.now();
      await sleep(6000);
      s = await state();
      const p1 = s.mechanic.panel;
      const dt = (p1.real_s - p0.real_s);
      const dm = ((p1.loupe_minute_deg - p0.loupe_minute_deg) % 360 + 360) % 360;
      check(dt > 3 && Math.abs(dm - dt * 2) < 0.6, `the wall clock up close turns 2°/s: ${dm.toFixed(2)}° in ${dt.toFixed(2)} s of the game (${((Date.now() - t0) / 1000).toFixed(1)} s on the page)`);
      check(!p1.holding, "Agata's watch is not there by itself");
      await shot("05_mirror_clock");
      await finish("hint");
      // The watch from the bag onto the glass.
      s = await state();
      await click("the watch in the bag", s.ui.bag.items.pocket_watch);
      await waitFor("watch in hand", (t) => t.selected_item === "pocket_watch", 10000);
      await click("the glass", s.mechanic.panel.glass);
      s = await waitFor("watch held", (t) => t.mechanic && t.mechanic.panel && t.mechanic.panel.holding, 20000);
      check(s.inventory.includes("pocket_watch") && !s.flags.nina_time_compared, "held to the glass, still in the bag, no realisation yet");
      await finish("watch held");
      await sleep(4000);
      await shot("06_mirror_both_clocks");
      s = await waitFor("compared", (t) => t.flags.nina_time_compared, 60000);
      const lines = await finish("realisation");
      check(lines.join(" ").includes("На моих три минуты") && lines.join(" ").includes("Пока я сплю"), `Agata's words: ${JSON.stringify(lines)}`);
      s = await state();
      check(s.flags.done_M15a, "M15а done");
    }
  } catch (e) {
    check(false, `exception: ${e.message}`);
  }
  check(consoleErrors === 0, `console errors: ${consoleErrors}`);
  fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n"));
  fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures, url: URL_BASE || "local" }, null, 2));
  await browser.close();
  if (server) server.close();
  console.log(`mech_web: ${checks.length - failures.length}/${checks.length} OK`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main();
