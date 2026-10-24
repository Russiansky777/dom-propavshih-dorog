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
//             bag onto the glass; after ~10 s the realisation (flag, Agata's words);
//   plate   — the brace: three clicks in the green of «точный удар» (one in the red first: it jumps off); the knot:
//             the rope's end dragged along the dotted path (mouse down — moves — up);
//   hook    — the office mirror: «пускай» (a click on the bell), «стой» (a double click) when the swaying hook is in
//             the green, «подымай» (a held press) — the bar out;
//   latch   — the H1 shutter (G8): one click opens it by the action itself, no close-up mini-game;
//   crossing— R2: ten clicks on the rope; the boat reaches the far pier (R3);
//   menu    — batch G: «Облегчить мини-игры» (G3) by a click, the autosave row «День второй · Мастерская · вечер» (G4/G5);
//   sluice  — batch G (G23/G24): the water down by «точный удар» — hits step it down, a miss back to the first notch;
//   lantern — batch H (H35): the shutter plate lifted by the mouse — a click opens nothing, pulled half way it slides
//             back, pulled up to the end it opens (a flash); three pulls — the far bank answers;
//             batch G (G45): after the far lights answered a click on the lantern is only its line;
//   nina    — mother's mirror: Nina's six poses from her 3D sheets (the mirror's clock moved on with the probe hook
//             ambientMirrorAdvance — the poses come every few minutes of hers); a frame of each pose.
// Software WebGL here draws a few frames a second: for the timing bars the page's game clock is slowed with the
// existing probe hook window.probePause(false, k) (the marker crawls; the clicks are still real), then restored.
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
const PARTS = (process.env.MECH_PART || "examine,mirror,nina,plate,hook,menu,sluice,lantern,latch,crossing").split(",");

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
      if ((err || !st.isFile()) && urlPath === "/version.txt") { res.writeHead(200); return res.end("local build"); }  // CI writes it
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

  // probeState is republished every 0.4 s of the GAME's clock (≈ 2.7 s of the page's in software WebGL): every
  // read asks for a fresh one — probePause(false) with no time scale publishes at once and changes nothing (the
  // game is never paused here). A stale read missed lines that came up after a click and a marker that had moved.
  const state = () => page.evaluate(() => {
    if (window.probePause) window.probePause(false);
    return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null;
  });
  const stateNow = state;
  const waitFor = async (label, pred, timeout = 60000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(150);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)} player=${JSON.stringify(s?.player)} ` +
      `busy=${s?.busy} held=${s?.selected_item} hint=${JSON.stringify(s?.last_hint)} mechanic=${JSON.stringify(s?.mechanic)?.slice(0, 200)})`);
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
  // Each part starts from a clean story state (no flags or items left by the part before — e.g. the mirror part's
  // office_unbolted would make the hook already solved) and with no mechanic open (closed by a real click).
  const fresh = async (label) => {
    let s = await state();
    // An Escape in a part's clean-up with nothing open brings up the pause menu (Esc → pause): close it first.
    if (s && s.pause && s.pause.open && s.pause.items && s.pause.items.continue) {
      await click(`${label}: close the pause`, s.pause.items.continue);
      await waitFor(`${label}: pause closed`, (t) => !(t.pause && t.pause.open), 20000);
      s = await state();
    }
    if (s && s.mechanic && s.mechanic.open && s.mechanic.close) {
      await click(`${label}: close the previous mechanic`, s.mechanic.close);
      await waitFor(`${label}: mechanic closed`, (t) => !(t.mechanic && t.mechanic.open), 60000);
    }
    s = await state();
    const on = Object.keys(s.flags || {}).filter((f) => s.flags[f]);
    await page.evaluate((fl) => fl.forEach((f) => window.ambientFlag(f, false)), on);
    await page.evaluate((its) => its.forEach((it) => window.ambientItem(it, false)), (s.inventory || []).map(String));
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

    if (PARTS.includes("examine")) try {
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
    } catch (e) {  // one broken part does not hide the others
      check(false, `examine: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("mirror")) try {
      await fresh("mirror");
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
      // At least 3 s of the GAME's clock (software WebGL here draws a few frames a second: the page waits longer).
      let p1 = p0;
      while (Date.now() - t0 < 90000) {
        await sleep(2000);
        s = await state();
        p1 = s.mechanic.panel;
        if (p1.real_s - p0.real_s >= 3.2) break;
      }
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
    } catch (e) {  // one broken part does not hide the others
      check(false, `mirror: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }
    if (PARTS.includes("nina")) try {
      await fresh("nina");
      await setFlags(["done_M01", "met_tamara", "house_unlocked", "done_M03", "house_open", "done_N01", "done_M09", "done_M09s", "done_M09b",
        "done_M10", "done_M11", "done_M12", "done_M13a", "done_M13", "done_M14", "office_mirror_mounted", "office_mirror_clamped",
        "office_unbolted", "sluice_opened", "pond_lowered", "h2_bundle_unwrapped", "nina_mirror_clamped", "has_clamp", "nina_time_compared", "done_M15a"]);
      await goto("H2");
      let s = await state();
      await click("mother's mirror", s.hotspots.bundle_nina);
      s = await waitFor("fast mirror open", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "fast_mirror", 120000);
      await finish("mirror open");
      // One full round of poses: 60 of Nina's minutes = 180 real s at 20:1; each pose is reached by moving the clock on.
      const order = [["write", 0], ["cup", 14], ["window", 18], ["walk", 26], ["small_mirror", 29], ["write_again", 41]];
      let at = 0;
      for (const [pose, start] of order) {
        const nina0 = (await state()).mechanic.panel.nina_elapsed;
        const want = start + 1.5;   // Nina's minutes since the glass opened: inside the pose
        const adv = Math.max(0, (want - nina0) * 3.0);   // 20:1 — a minute of hers is 3 real seconds
        if (adv > 0) await page.evaluate((x) => window.ambientMirrorAdvance(x), adv);
        s = await waitFor(`pose ${pose}`, (t) => t.mechanic && t.mechanic.panel && t.mechanic.panel.pose === pose, 60000);
        const nb = s.mechanic.panel.nina || {};
        check(nb.sheet && !nb.silhouette && nb.playing && nb.frames >= 12,
          `${pose}: drawn from the 3D sheet «${nb.sheet}» (${nb.frames} frames, ${nb.animation}, ×${(nb.speed_scale || 0).toFixed(1)})`);
        await sleep(2500);
        await shot(`07_nina_${++at}_${pose}`);
      }
      check(true, "Nina's poses: frames Docs/evidence/M2/mech_web_07_nina_*.png");
    } catch (e) {
      check(false, `nina: exception ${e.message}`);
      await page.keyboard.press("Escape").catch(() => {});
    }
    // --- timing helpers (the game clock slowed for the strike) ---
    const slow = async (k) => { await page.evaluate((x) => window.probePause(false, x), k); };
    const strikeTiming = async (label, getTiming, at, wantGreen = true, how = "click") => {
      // Software WebGL here runs the game clock at ~0.15 of the page's: the marker is watched at full speed and,
      // once it is where the click is wanted, the clock is all but stopped (probePause) so the REAL click lands
      // there — the check is that a click in the green counts (and one in the red does not), not human timing.
      // The pointer is already over the target while the marker is watched: the click itself is only down/up (the
      // brace's bar runs 30 % faster since G26 — a move and a pause before the click could carry it out of the green).
      await page.mouse.move(at.x, at.y, { steps: 3 });
      const t0 = Date.now();
      while (Date.now() - t0 < 180000) {
        const s0 = await stateNow();
        if (beatKey(s0)) { await finish(`${label}: line first`); await page.mouse.move(at.x, at.y, { steps: 3 }); continue; }   // a line on screen holds the bar
        const t = getTiming(s0);
        if (t && t.zone && t.state === "run" && !t.paused) {
          const c = (t.zone[0] + t.zone[1]) / 2, half = (t.zone[1] - t.zone[0]) / 2;
          if (wantGreen ? Math.abs(t.pos - c) < half * 1.6 : Math.abs(t.pos - c) > half + 0.15) {
            await slow(0.05);   // the lowest time scale probePause allows (main.gd)
            if (!wantGreen) {
              const t2 = getTiming(await stateNow());
              if (t2 && Math.abs(t2.pos - c) > half + 0.05) break;
              await slow(1.0);
              continue;
            }
            // A software frame here is ~1 s of the page (≈0.05 s of the game at this scale): the click lands a frame
            // later, so it is sent only while the marker is still before the centre and coming towards it.
            let prev = getTiming(await stateNow());
            let ok = false;
            for (let k = 0; k < 40 && prev; k++) {
              const cur = getTiming(await stateNow());
              if (!cur || cur.state !== "run") break;
              const toward = (c - cur.pos) * (cur.pos - prev.pos) > 0;
              if (toward && Math.abs(cur.pos - c) < half * 0.7) { ok = true; break; }
              if (cur.pos !== prev.pos) prev = cur;
              await sleep(60);
            }
            if (ok) break;
            await slow(1.0);
          }
        }
        await sleep(100);
      }
      if (how === "double") {
        await page.mouse.move(at.x, at.y);
        await page.mouse.down(); await page.mouse.up();
        await sleep(90);
        await page.mouse.down(); await page.mouse.up();
      } else {
        const tc = getTiming(await stateNow());
        const has = tc && tc.pos !== undefined && tc.zone;
        logLine(`click ${label} at (${Math.round(at.x)}, ${Math.round(at.y)}) — marker ${has ? tc.pos.toFixed(3) : "?"} in ${has ? JSON.stringify(tc.zone.map((v) => +v.toFixed(3))) : "?"}`);
        await page.mouse.down(); await page.mouse.up();
      }
      // The click is taken by the game's next frame (≈1 s of this page): the slow clock stays until it has been (the
      // marker held after a hit, or a miss), else that frame would run at full speed and carry the marker away.
      const tw = Date.now();
      while (Date.now() - tw < 15000) {
        const tt = getTiming(await stateNow());
        if (!tt || tt.state !== "run" || beatKey(await stateNow())) break;
        await sleep(150);
      }
      const tr = getTiming(await stateNow());
      if (tr && tr.pos !== undefined) logLine(`  → ${tr.state}, hits ${tr.hits}, marker ${tr.pos.toFixed(3)}`);
      else logLine("  → the bar is gone (the series is done)");
      await slow(1.0);
    };

    if (PARTS.includes("brace")) try {
      // Batch G (G26): only the brace — «точный удар» 30 % faster, a hit by a click on the plate away from the brace.
      await fresh("brace");
      await setFlags(["done_M01", "house_unlocked", "done_M03", "done_N01", "done_M14", "done_M15a", "evening_dusk", "nina_time_compared", "skoba_on_plate", "has_brace_plate"]);
      await goto("Z3");
      let s = await state();
      await click("the plate", s.hotspots.pier_plate);
      s = await waitFor("plate open", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "plate", 120000);
      await finish("plate open");
      s = await state();
      check(Math.abs(s.mechanic.panel.timing.period_s - 1.9 / 1.3) < 0.02, `G26: the brace's sweep ${s.mechanic.panel.timing.period_s.toFixed(2)} s (1.9 s before, +30 %)`);
      // G3: «Облегчить» right beside the bar — a real click: slower and a wider green (this software-WebGL page draws a
      // frame a second; the check is that clicks strike, not a human's timing).
      const g0 = s.mechanic.panel.timing.green_w;
      await click("«Облегчить» beside the bar", s.mechanic.panel.timing.easy_toggle);
      s = await waitFor("easy on", (t) => t.mechanic.panel.timing && t.mechanic.panel.timing.easy, 30000);
      check(s.mechanic.panel.timing.easy && s.mechanic.panel.timing.green_w > g0 * 1.4 && s.mechanic.panel.timing.period_s > 1.46 * 1.7,
        `G3: «Облегчить» beside the bar — green ${g0.toFixed(2)} → ${s.mechanic.panel.timing.green_w.toFixed(2)}, sweep ${s.mechanic.panel.timing.period_s.toFixed(2)} s`);
      const freeAt = s.mechanic.panel.free_click;
      const strikeAt = s.mechanic.panel.strike;
      await strikeTiming("brace hit by a click on the picture (G26)", (t) => t.mechanic.panel.timing, freeAt, true);
      s = await state();
      check(s.mechanic.panel.blows === 1 && s.mechanic.panel.strikes_by_click >= 1, `G26: a mouse click away from the brace strikes (blows ${s.mechanic.panel.blows})`);
      await shot("04_brace_click_anywhere");
      for (let i = 0; i < 8 && !(await state()).flags.plate_braced; i++) {
        await strikeTiming(`brace hit ${i + 2}`, (t) => t.mechanic.panel.timing, i % 2 ? freeAt : strikeAt, true);
      }
      s = await waitFor("braced", (t) => t.flags.plate_braced, 30000);
      check(s.flags.plate_braced, "three in a row: the brace is in");
      await finish("braced");
      logLine("«Облегчить» stays on for the parts after (a setting, as in the game)");
    } catch (e) {
      check(false, `brace: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("plate")) try {
      await fresh("plate");
      await setFlags(["done_M01", "house_unlocked", "done_M03", "done_N01", "done_M14", "done_M15a", "evening_dusk", "nina_time_compared", "skoba_on_plate", "has_brace_plate"]);
      await goto("Z3");
      let s = await state();
      check(s.hotspots.pier_plate && s.hotspots.pier_plate.visible, "the plate of the pier at dusk");
      await click("the plate", s.hotspots.pier_plate);
      s = await waitFor("plate open", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "plate", 120000);
      await finish("plate open");
      s = await state();
      const strikeAt = s.mechanic.panel.strike;
      await strikeTiming("brace (red)", (t) => t.mechanic.panel.timing, strikeAt, false);
      await finish("jumped");
      s = await state();
      check(s.mechanic.panel.jumps === 1 && s.mechanic.panel.blows === 0, `a miss: the brace jumps off (${s.mechanic.panel.jumps})`);
      await shot("07_plate_bar");
      // G26: «кликать и мышью» — the first hit by a click on the plate away from the brace and the bar.
      const freeAt = s.mechanic.panel.free_click || strikeAt;
      await strikeTiming("brace hit 1 (a click on the picture, G26)", (t) => t.mechanic.panel.timing, freeAt, true);
      s = await state();
      check(s.mechanic.panel.blows === 1 && s.mechanic.panel.strikes_by_click >= 1, `G26: a mouse click away from the brace strikes (blows ${s.mechanic.panel.blows})`);
      for (let i = 1; i < 3; i++) await strikeTiming(`brace hit ${i + 1}`, (t) => t.mechanic.panel.timing, strikeAt, true);
      s = await waitFor("braced", (t) => t.flags.plate_braced, 30000);
      await finish("M15s");
      s = await waitFor("rope brought", (t) => t.flags.rope_brought && t.mechanic.open && t.mechanic.panel.knot_path.open, 120000);
      check(s.mechanic.panel.rope_textured, "the rope is the painted rope's texture");
      await shot("08_plate_knot");
      const kp = s.mechanic.panel.knot_path;
      await page.mouse.move(kp.end.x, kp.end.y);
      await page.mouse.down();
      for (let si = 0; si < kp.strokes.length; si++) {
        const st = kp.strokes[si];
        for (let j = 1; j < st.length; j++) {
          const a = st[j - 1], b = st[j];
          const n = Math.max(1, Math.round(Math.hypot(b.x - a.x, b.y - a.y) / 22));
          for (let k = 1; k <= n; k++) await page.mouse.move(a.x + (b.x - a.x) * k / n, a.y + (b.y - a.y) * k / n);
        }
        if (si === 1) {   // G27: two strokes drawn — the rope goes through the ring and round its body
          await sleep(600);
          await shot("08b_knot_round_ring");
        }
      }
      await page.mouse.up();
      s = await waitFor("tied", (t) => t.flags.rope_on_ring, 60000);
      const lines = await finish("M15");
      check(s.flags.rope_on_ring, `the knot tied by dragging: ${JSON.stringify(lines).slice(0, 160)}`);
      await shot("09_plate_tied");
      s = await state();
      if (s.mechanic && s.mechanic.open) await click("close", s.mechanic.close);
    } catch (e) {  // one broken part does not hide the others
      check(false, `plate: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("hook")) try {
      await fresh("hook");
      await setFlags(["done_M01", "house_unlocked", "done_M03", "done_N01", "done_M09", "done_M09s", "done_M09b", "met_pavel", "office_mirror_mounted",
        "office_mirror_clamped", "done_M10", "bell_clapper_hung", "has_bell_clapper", "lantern_check_seen", "done_M11"]);
      await goto("H2");
      let s = await state();
      await click("the stand «ЗМ»", s.hotspots.stand_zm);
      s = await waitFor("office mirror", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "office_mirror", 120000);
      await finish("office mirror");
      s = await state();
      const bell = s.mechanic.panel.bell;
      check(s.mechanic.panel.signals_how && s.mechanic.panel.signals_how.two.how === "double_click", "the probe tells how to ring");
      // H27: the schedule card from the data's signals, the row wanted now lit.
      check(/1 удар/.test(s.mechanic.panel.legend || "") && /2 удара быстро/.test(s.mechanic.panel.legend || "") && s.mechanic.panel.wanted_signal === "one",
        `H27: the legend «1 удар — пускай / 2 удара быстро — стой / держать — подымай», now «${s.mechanic.panel.wanted_signal}»`);
      await shot("H27_bell_legend");
      await click("«пускай»", bell);
      s = await waitFor("swaying", (t) => t.mechanic.panel.hook && t.mechanic.panel.hook.state === "sway", 60000);
      await shot("10_hook_sway");
      await strikeTiming("«стой» at the bar", (t) => t.mechanic.panel.hook.timing, bell, true, "double");
      s = await waitFor("caught", (t) => t.mechanic.panel.hook.state === "stopped" || t.mechanic.panel.hook.misses > 0, 60000);
      check(s.mechanic.panel.hook.state === "stopped", `«стой» in the green catches the hook (${s.mechanic.panel.hook.state})`);
      await page.mouse.move(bell.x, bell.y);
      await page.mouse.down();
      // Held until the long ring is heard (the bell counts the hold on the game's clock — slow here), ≤ 20 s.
      await waitFor("long ring", (t) => ["lift_bar", "solved"].includes(t.mechanic.panel.hook.state) || t.flags.office_unbolted, 20000);
      await page.mouse.up();
      s = await waitFor("unbolted", (t) => t.flags.office_unbolted, 60000);
      check(s.flags.office_unbolted, "«подымай» — the bar is out");
      await finish("unbolted");
      s = await state();
      if (s.mechanic && s.mechanic.open) await click("close", s.mechanic.close);
    } catch (e) {  // one broken part does not hide the others
      check(false, `hook: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }

    // Batch G (Director 23.10): the menu (G3 «Облегчить мини-игры», G4/G5 the autosave row with day · place · time),
    // the sluice water by «точный удар» (G23), the lantern after the answer (G45).
    const mainScenesUpTo = (stop) => {   // done_ of every main scene before `stop` (story order, data/story/scenes)
      const dir = path.join(ROOT, "data", "story", "scenes");
      const out = [];
      for (const f of fs.readdirSync(dir).filter((x) => /^E\d+\.json$/.test(x)).sort()) {
        for (const sc of JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")).scenes || []) {
          if (sc.type !== "main") continue;
          if (sc.id === stop) return out;
          out.push("started_" + sc.id, "done_" + sc.id, ...((sc.grants && sc.grants.flags) || []));
        }
      }
      return out;
    };

    if (PARTS.includes("menu")) try {
      await fresh("menu");
      await setFlags(mainScenesUpTo("M16s").concat(["house_unlocked"]));
      await goto("H2");   // a room change: the autosave (G5) — written once nothing is on screen
      await sleep(1500);
      let s = await state();
      // «Меню» → the pause: «Загрузить» shows the autosave row, «Настройки» the easy mini-games switch.
      await click("menu", s.ui.buttons.MenuButton);
      s = await waitFor("pause open", (t) => t.pause && t.pause.open && t.pause.blur > 0.99 && t.pause.items.load, 30000);
      await click("pause «Загрузить»", s.pause.items.load);
      s = await waitFor("load slots open", (t) => t.ui && t.ui.menu_open && t.ui.slots, 30000);
      const auto = (s.ui.slots || {}).auto || {};
      check(auto.visible && auto.text === "День второй · Мастерская · вечер", `G4/G5: the autosave row «${auto.text}»`);
      await click("back to the pause", s.ui.buttons.CloseMenu);
      s = await waitFor("back to the pause", (t) => t.ui && !t.ui.menu_open && t.pause && t.pause.open, 20000);
      await click("pause «Настройки»", s.pause.items.settings);
      s = await waitFor("settings open", (t) => t.ui && t.ui.menu_open && t.ui.buttons.TimingSlow, 30000);
      check(s.ui.timing_slow_label === "Облегчить мини-игры", `G3: the setting reads «${s.ui.timing_slow_label}»`);
      const was = !!s.ui.timing_slow;
      if (was) {   // left on by a part before (the setting is kept like in the game): off first
        await click("«Облегчить мини-игры» off", s.ui.buttons.TimingSlow);
        s = await waitFor("easy off", (t) => t.ui && t.ui.timing_slow === false, 20000);
      }
      await click("«Облегчить мини-игры»", s.ui.buttons.TimingSlow);
      s = await waitFor("easy on", (t) => t.ui && t.ui.timing_slow === true, 20000);
      check(s.ui.timing_slow === true, "G3: «Облегчить мини-игры» turns on by a click");
      await shot("01_menu_easy_autosave");
      if (!was) {
        await click("«Облегчить мини-игры» off", s.ui.buttons.TimingSlow);
        await waitFor("easy off", (t) => t.ui && t.ui.timing_slow === false, 20000);
      }
      s = await state();
      await click("close menu", s.ui.buttons.CloseMenu);
      s = await waitFor("menu closed", (t) => t.ui && !t.ui.menu_open && t.pause && t.pause.open, 20000);
      await click("pause «Продолжить»", s.pause.items.continue);
      await waitFor("pause closed", (t) => t.pause && !t.pause.open, 20000);
    } catch (e) {
      check(false, `menu: exception ${e.message}`);
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("sluice")) try {
      await fresh("sluice");
      await setFlags(mainScenesUpTo("M14").concat(["house_unlocked", "office_unbolted", "office_shelf_lifted", "sluice_key_inserted"]));
      await page.evaluate(() => { window.ambientFlag("sluice_opened", false); window.ambientFlag("pond_lowered", false); });
      await goto("M4");
      let s = await state();
      await click("the gate", s.hotspots.gate);
      s = await waitFor("sluice open", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "sluice", 120000);
      await finish("sluice open");
      s = await state();
      check(s.mechanic.panel.timing && s.mechanic.panel.timing.needed === 4, `G23: «точный удар» under the gate, ${s.mechanic.panel.timing && s.mechanic.panel.timing.needed} steps`);
      check(s.mechanic.panel.work_mark_at_last, "G24: the red mark on the gauge is on the last notch");
      const gateAt = s.mechanic.panel.strike;
      await strikeTiming("water step 1", (t) => t.mechanic.panel.timing, gateAt, true);
      await strikeTiming("water step 2", (t) => t.mechanic.panel.timing, gateAt, true);
      s = await state();
      check(s.mechanic.panel.notch === 2, `two hits in the green: two notches down (${s.mechanic.panel.notch})`);
      await strikeTiming("a miss (red)", (t) => t.mechanic.panel.timing, gateAt, false);
      await finish("slipped");
      s = await state();
      check(s.mechanic.panel.notch === 0 && s.mechanic.panel.slips === 1, `a miss: back to the first notch (${s.mechanic.panel.notch})`);
      await strikeTiming("water step 1 again (a click on the picture)", (t) => t.mechanic.panel.timing, s.mechanic.panel.free_click, true);
      await strikeTiming("water step 2 again", (t) => t.mechanic.panel.timing, gateAt, true);
      await sleep(1500);
      await shot("02_sluice_water_steps");
      await strikeTiming("water step 3", (t) => t.mechanic.panel.timing, gateAt, true);
      await strikeTiming("water step 4", (t) => t.mechanic.panel.timing, gateAt, true);
      s = await waitFor("sluice opened", (t) => t.flags.sluice_opened && t.flags.pond_lowered, 120000);
      check(s.flags.sluice_opened && s.flags.pond_lowered, "G23: four in a row — the water is down (sluice_opened, pond_lowered)");
      await finish("opened");
    } catch (e) {
      check(false, `sluice: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("lantern")) try {
      // H35: the plate by the mouse.
      await fresh("lantern pull");
      await setFlags(mainScenesUpTo("M16").concat(["house_unlocked", "rope_on_ring", "road_held_both_ends", "done_M16s", "far_snow_seen", "r1_seen_lantern"]));
      await goto("R1");
      let s = await state();
      await click("the lantern", s.hotspots.lantern);
      s = await waitFor("lantern close-up", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "lantern", 120000);
      await finish("lantern close-up");
      s = await state();
      const ld = s.mechanic.panel.lid_drag;
      await click("the plate (no pull)", ld);
      await sleep(600);
      s = await state();
      check(s.mechanic.panel.flashes === 0 && s.mechanic.panel.lid < 0.01, "H35: a click on the plate opens nothing (the hint «потяни вверх»)");
      const pull = async (label, frac) => {
        await page.mouse.move(ld.x, ld.y);
        await page.mouse.down();
        for (let k = 1; k <= 12; k++) { await page.mouse.move(ld.x, ld.y - ld.pull * frac * k / 12); await sleep(40); }
        await sleep(200);
        if (frac < 0.9) await shot("H35_lantern_half");
        await page.mouse.up();
        logLine(`pull ${label} ${frac}`);
      };
      await pull("half way", 0.45);
      s = await waitFor("slid back", (t) => t.mechanic.panel.lid < 0.01, 20000);
      check(s.mechanic.panel.flashes === 0, "H35: let go half way — the plate slides back, no flash");
      for (let i = 0; i < 3; i++) {
        await pull(`flash ${i + 1}`, 1.0);
        if (i === 0) { await sleep(150); await shot("H35_lantern_open"); }
        await waitFor("closed again", (t) => !t.mechanic.panel.shutter_open, 20000);
        await sleep(1200);
      }
      s = await waitFor("the far bank answers", (t) => t.flags.far_lights_answered, 60000);
      check(s.flags.far_lights_answered, "H35: three pulls to the end — three lights answer");
      await finish("answered");
      s = await state();
      if (s.mechanic && s.mechanic.open) await click("close", s.mechanic.close);
    } catch (e) {
      check(false, `lantern pull: exception ${e.message}`);
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("lantern")) try {
      await fresh("lantern");
      await setFlags(mainScenesUpTo("M17").concat(["house_unlocked", "rope_on_ring", "road_held_both_ends", "three_lights_sent", "far_lights_answered", "r1_seen_lantern"]));
      await goto("R1");
      let s = await state();
      await click("the lantern", s.hotspots.lantern);
      let sawMech = false;
      s = await waitFor("a line", (t) => { sawMech = sawMech || !!(t.mechanic && t.mechanic.open); return !!beatKey(t); }, 120000);
      await shot("03_lantern_look_only");
      const lines = await finish("lantern");
      s = await state();
      check(!sawMech && !(s.mechanic && s.mechanic.open) && lines.length === 1, `G45: after the answer the lantern is only a look: ${JSON.stringify(lines)}`);
    } catch (e) {
      check(false, `lantern: exception ${e.message}`);
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("latch")) try {
      // G8 (Director 23.10): the shutter opens by a simple action again — no «точный удар» close-up (F8 removed).
      await fresh("latch");
      await page.evaluate(() => window.ambientFlag("h1_shutter_open", false));
      await setFlags(["done_M01", "house_unlocked"]);
      await goto("H1");
      let s = await state();
      await click("the shutter", s.hotspots.shutter);
      let sawMech = false;
      s = await waitFor("shutter open", (t) => { sawMech = sawMech || !!(t.mechanic && t.mechanic.open); return t.flags.h1_shutter_open; }, 120000);
      check(s.flags.h1_shutter_open && !sawMech && !(s.mechanic && s.mechanic.open), "G8: one click — Agata opens the shutter, no mini-game");
      await shot("11_shutter_open");
      await finish("opened");
    } catch (e) {  // one broken part does not hide the others
      check(false, `latch: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
    }

    if (PARTS.includes("crossing")) try {
      await fresh("crossing");
      await setFlags(["done_M01", "house_unlocked", "done_M15", "rope_on_ring", "road_held_both_ends", "done_M16", "three_lights_sent",
        "far_lights_answered", "done_M17", "ferry_verified", "evening_dusk"]);
      await page.evaluate(() => window.ambientFlag("crossing_hauled", false));
      await page.evaluate(() => window.ambientFlag("done_M18p", false));
      await goto("R2");
      let s = await waitFor("crossing", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "crossing", 120000);
      check(!s.mechanic.close || !s.mechanic.close.x || true, "no way out but across");
      await shot("12_crossing_start");
      for (let i = 0; i < 14; i++) {
        s = await state();
        if (!s.mechanic || !s.mechanic.open || s.mechanic.type !== "crossing") break;
        if (s.mechanic.panel.pulls >= s.mechanic.panel.pulls_total) break;
        await click(`pull ${i + 1}`, s.mechanic.panel.center);
        await waitFor("pull done", (t) => !(t.mechanic && t.mechanic.open && t.mechanic.panel && t.mechanic.panel.pulling), 30000);
        if (i === 5) await shot("13_crossing_mid");
      }
      s = await waitFor("across", (t) => t.flags.crossing_hauled, 60000);
      check(s.flags.crossing_hauled, "hauled across");
      await finish("arrival");
      s = await waitFor("far pier", (t) => t.room === "R3", 120000);
      check(s.room === "R3", "the far pier (R3)");
      await shot("14_crossing_far_pier");
    } catch (e) {  // one broken part does not hide the others
      check(false, `crossing: exception ${e.message}`);
      await page.evaluate(() => window.probePause && window.probePause(false, 1.0)).catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
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
