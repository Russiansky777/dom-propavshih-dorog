#!/usr/bin/env node
// H1 after the Director's notes of 18.10 in the WEB build with REAL mouse input (window.probeState):
//
//   tools/export_web.sh && node tools/h1_web.mjs        (H1_WEB_DIR — another build dir; H1_PORT, default 8777)
//
// From a new game: Tamara (M01) → lane Z4 → street Z2 → H1. Then, with the frames Docs/evidence/M1/H1_v2_*.png:
//   01 start   — Tikhon is in the room at once (his hotspot visible before M03, centred on the armchair),
//                the shelf sockets on the stove side, no shelf;
//   02 hover   — the pointer on the oven door shows «Печь» next to the pointer;
//   03 stove   — a real click on the oven door: Agata walks to the stand in front of the door, the stove is lit;
//   04 m03     — shutter, scarf → M03 plays (Tikhon's lines from the armchair, «Ты здесь один?» / «Печь тоже здесь.»);
//   05 sockets — the pointer on the sockets: «Крепления для полки»;
//   06 shelf   — click the sockets → Q04 option A «В углу у печи» → the shelf on the stove side, Tikhon on it
//                (his hotspot moved onto the shelf), sockets gone; a click on the stove door still → stove;
//   08 attic   — the attic exit is a mark «up» under the ceiling in the stove corner, the gallery the only
//                «down» at the bottom; click → H4, and back down → Agata in the stove corner.
// Exit code 0 only when every step reached its state and the console has no errors (Godot warnings — e.g. a
// voice recording waiting for re-recording after a text change — are listed, not counted).
// Log: build/shots/h1/console.log, report build/shots/h1/report.json.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.H1_WEB_DIR ? path.resolve(ROOT, process.env.H1_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "M1");
const LOG_DIR = path.join(ROOT, "build", "shots", "h1");
const PORT = Number(process.env.H1_PORT || 8777);

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
  const consoleWarnings = [];   // Godot push_warning arrives as console.error «WARNING: …» (+ «at: push_warning»)
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
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
    const file = path.join(OUT_DIR, `H1_v2_${name}.png`);
    await page.screenshot({ path: file });
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
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 60000);
  };
  /** Clicks through beats; options from `choices` in order. Calls onBeat(state) for every new beat. */
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
      await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 10000);
    }
    return lines;
  };
  const useHotspot = async (id, choices = [], at = null) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `hotspot ${id} visible in ${s.room}`); return []; }
    await click(`hotspot ${id}`, at || h);
    await waitIdle(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "", 15000);
    return finish(`hotspot ${id}`, choices);
  };
  const goExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { check(false, `exit ${target} in ${s.room}`); return false; }
    await click(`exit → ${target}`, e);
    await waitIdle(`exit → ${target}`);
    await waitFor(`room == ${target}`, (t) => t.room === target, 45000);
    await sleep(800);
    return (await state()).room === target;
  };
  const hover = async (pt) => {
    await page.mouse.move(pt.x - 30, pt.y - 10);
    await sleep(120);
    await page.mouse.move(pt.x, pt.y, { steps: 4 });
    await sleep(900);
  };

  try {
    await page.goto(`http://127.0.0.1:${PORT}/index.html`, { waitUntil: "load", timeout: 60000 });
    await page.waitForSelector("#canvas", { timeout: 30000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 120000 });
    await sleep(1500);
    // M01 → H1
    await useHotspot("tamara");
    await waitFor("M01 done", (s) => s.flags.done_M01);
    check(await goExit("Z4"), "Z1 → Z4");
    check(await goExit("Z2"), "Z4 → Z2");
    check(await goExit("H1"), "Z2 → H1");
    await sleep(1200);
    let s = await state();
    // 01: Tikhon is in the room at once, in the armchair (hotspot centre on the chair: x 405–535, y 690–890).
    const t0 = s.hotspots.tikhon;
    check(t0 && t0.visible && !s.flags.started_M03, `Tikhon is in H1 before M03 (hotspot visible: ${JSON.stringify(t0)})`);
    check(t0 && t0.x > 405 && t0.x < 535 && t0.y > 690 && t0.y < 890, `his hotspot is on the armchair (${t0 && Math.round(t0.x)}, ${t0 && Math.round(t0.y)})`);
    check(s.hotspots.shelf && s.hotspots.shelf.visible && s.hotspots.shelf.label === "Крепления для полки", `the sockets on the stove side are a hotspot from the start (${JSON.stringify(s.hotspots.shelf)})`);
    await page.mouse.move(1500, 1000);
    await sleep(600);
    await shot("01_start");
    // 02: hover the oven door → «Печь».
    const door = { x: 220, y: 490 };
    await hover(door);
    s = await state();
    await shot("02_hover_stove");
    // 03: real click on the oven door → walks in front of it, the stove is lit.
    await click("oven door", door);
    await waitIdle("oven door");
    await waitFor("stove reaction", (t) => beatKey(t) !== "" || t.flags.stove_lit, 15000);
    s = await state();
    check(s.flags.stove_lit, "a click on the oven door used the stove (stove_lit)");
    check(Math.hypot(s.player.x - 215, s.player.y - 795) < 14, `Agata stands in front of the oven door (${Math.round(s.player.x)}, ${Math.round(s.player.y)})`);
    await sleep(500);
    await shot("03_stove_click");
    await finish("stove text");
    // 04: shutter, scarf → M03 from the armchair.
    await useHotspot("shutter");
    let caught = false;
    const m03 = await (async () => {
      const st = await state();
      await click("hotspot scarf", st.hotspots.scarf);
      await waitIdle("scarf");
      await waitFor("scarf: reaction", (t) => beatKey(t) !== "", 15000);
      return finish("M03", ["ask"], async (b) => {
        if (!caught && b.beat.type === "line" && b.beat.speaker === "tikhon" && (b.beat.text || "").includes("Печь тоже здесь")) {
          await sleep(800);
          await shot("04_m03_tikhon_in_armchair");
          caught = true;
        }
      });
    })();
    s = await waitFor("M03 done", (t) => t.flags.done_M03 && t.flags.met_tikhon, 30000);
    check(caught, "Tikhon's line «Печь тоже здесь.» shown (frame 04)");
    check(m03.some((l) => l.includes("Ты здесь один?")), "«Ты здесь один?» in M03");
    const t1 = s.hotspots.tikhon;
    check(t1 && Math.abs(t1.x - t0.x) < 1 && Math.abs(t1.y - t0.y) < 1, "after M03 Tikhon is still in the armchair");
    // 05: hover the sockets → «Крепления для полки».
    const sock = s.hotspots.shelf;
    check(sock && sock.visible, "the sockets hotspot is there after M03");
    await hover(sock);
    s = await state();
    await shot("05_hover_sockets");
    // 06: click the sockets → Q04 A → shelf on the stove side, Tikhon on it.
    const q04 = await useHotspot("shelf", ["A"]);
    s = await waitFor("Q04 done", (t) => t.flags.done_Q04 && t.flags.q04_corner_stove, 30000);
    check(q04.length >= 4, `Q04 lines played: ${q04.length}`);
    const t2 = s.hotspots.tikhon;
    check(t2 && t2.x > 478 && t2.x < 576 && t2.y > 352 && t2.y < 504, `after Q04 A his hotspot moved onto the shelf (${t2 && Math.round(t2.x)}, ${t2 && Math.round(t2.y)})`);
    await click("floor (step back)", { x: 1150, y: 900 });
    await waitIdle("step back");
    await sleep(1500);
    await page.mouse.move(t2.x, t2.y - 10);
    await sleep(900);
    await shot("06_shelf_a_tikhon");
    // The stove door is still the stove after Q04.
    await click("oven door again", door);
    await waitIdle("oven door again");
    s = await waitFor("stove look", (t) => beatKey(t) !== "", 15000);
    check(s.beat && (s.beat.text || "").includes("гнёзда"), `the stove look mentions the sockets: «${s.beat && s.beat.text}»`);
    await finish("stove look");
    // 08: the attic — mark «up» under the ceiling in the stove corner (no second «down» at the bottom).
    s = await state();
    const att = s.exits.H4;
    check(att && att.y < 300 && att.x > 560 && att.x < 860, `attic exit up under the ceiling by the stove (${att && Math.round(att.x)}, ${att && Math.round(att.y)})`);
    const gal = s.exits.H3;
    check(gal && gal.y > 1000, `gallery exit at the bottom edge (${gal && Math.round(gal.x)}, ${gal && Math.round(gal.y)})`);
    await hover(att);
    await shot("08_hover_attic");
    check(await goExit("H4"), "the «up» mark → attic H4");
    await sleep(800);
    await finish("H4 entry (V02)");
    check(await goExit("H1"), "attic → back down to H1");
    s = await state();
    check(Math.hypot(s.player.x - 700, s.player.y - 800) < 40, `back from the attic Agata is in the stove corner (${Math.round(s.player.x)}, ${Math.round(s.player.y)})`);
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
  console.log(`h1_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
