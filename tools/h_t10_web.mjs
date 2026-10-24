#!/usr/bin/env node
// Batch H, T10 — the art of batch 10c in the WEB build with REAL mouse input (frames Docs/evidence/H/T10_*.jpg):
//
//   tools/export_web.sh && node tools/h_t10_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8795)
//
//   Z3  ?start=boat_turn — the boat at the plate at dusk; M17: the boat slides off along the rope (frame mid-way);
//   R1  the pier without the boat at dusk; ?start=t10_turn_day — the boat by day at the turn, the pier by day;
//   H2  ?start=t10_h2 — the office mirror in the stand «ЗМ», a click: the close-up with the wedges; ?start=t10_h2_done — driven;
//   Z1  ?start=t10_post — the new counter, Tamara behind it, Agata beside (the talk), the drawings on the counter;
//   O4  ?start=classmama — Mitya's board by the fence;   H3  ?start=bedtime — the school photo in its frame;
//   EP  ?start=epilogue — the bridge (EP_tamara) and the beam end with the cut (EP_beam) as they come in the epilogue.
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
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "H");
const LOG_DIR = path.join(ROOT, "build", "shots", "h_t10");
const PORT = Number(process.env.H_PORT || 8795);

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
    const file = path.join(OUT_DIR, `T10_${name}.jpg`);
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

  const start = async (id, ready) => {
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=${id}`);
    const s = await waitFor(`${id}: game up`, ready, 240000);
    await playThrough(`${id}: start`, { quietMs: 2500 });
    await sleep(1200);
    return s;
  };
  try {
    let s;
    // --- Z3 dusk, R1 dusk, M17 ---
    s = await start("boat_turn", (t) => t.room === "Z3" && t.hotspots && t.hotspots.pelageya);
    check(s.exits.R2 && s.exits.R2.visible, "Z3 dusk: the boat at the plate («В лодку» shown)");
    await shot("Z3_dusk_boat");
    check(await goExit("R1"), "R1: to the pier");
    await sleep(800);
    s = await state();
    check(!s.exits.R2 && !(s.hotspots.boat && s.hotspots.boat.visible), "R1 dusk: the pier without the boat");
    await shot("R1_dusk_no_boat");
    check(await goExit("Z3"), "Z3: back to the turn");
    s = await state();
    await click("hotspot pelageya", s.hotspots.pelageya);
    await waitIdle("pelageya");
    await waitFor("M17 starts", (t) => t.beat && t.beat.type, 30000);
    s = await state();
    await click("M17: continue (first line)", s.ui.dialogue_click || { x: 960, y: 780 });
    await sleep(1000);
    await shot("M17_boat_slides");
    const m17 = await playThrough("M17", { quietMs: 30000 });
    check(m17.some((l) => /лента лежит/.test(l)), `M17: the empty boat came back with the ribbon (${m17.length} beats)`);
    s = await state();
    check(s.exits.R2 && s.exits.R2.open, "Z3: «В лодку» open after M17");
    await shot("Z3_after_M17");

    // --- by day ---
    s = await start("t10_turn_day", (t) => t.room === "Z3" && t.exits);
    check(s.exits.R2 && s.exits.R2.visible, "Z3 day: the boat at the plate");
    await shot("Z3_day_boat");
    check(await goExit("R1"), "R1 day: to the pier");
    await sleep(800);
    s = await state();
    check(!(s.hotspots.boat && s.hotspots.boat.visible), "R1 day: the pier without the boat");
    await shot("R1_day_no_boat");

    // --- H2: the office mirror, the wedges ---
    s = await start("t10_h2", (t) => t.room === "H2" && t.hotspots && t.hotspots.stand_zm);
    await shot("H2_mirror_loose");
    await click("stand_zm", s.hotspots.stand_zm);
    await waitIdle("stand_zm");
    s = await waitFor("H2: the mirror close-up", (t) => t.mechanic && t.mechanic.open, 60000);
    await sleep(1200);
    check(s.mechanic && s.mechanic.open, "H2: the close-up with the wedges opens");
    await shot("H2_wedges_closeup");
    await closeMechanic("H2");
    s = await start("t10_h2_done", (t) => t.room === "H2" && t.hotspots && t.hotspots.stand_zm);
    await shot("H2_mirror_driven");
    await click("stand_zm", s.hotspots.stand_zm);
    await waitIdle("stand_zm");
    s = await waitFor("H2: the close-up (driven)", (t) => t.mechanic && t.mechanic.open, 60000);
    await sleep(1200);
    await shot("H2_wedges_closeup_driven");

    // --- Z1: the counter ---
    s = await start("t10_post", (t) => t.room === "Z1" && t.hotspots && t.hotspots.tamara);
    await shot("Z1_counter");
    await click("hotspot tamara", s.hotspots.tamara);
    await waitIdle("tamara");
    await waitFor("Z1: Tamara talks", (t) => t.beat && t.beat.type, 30000);
    await sleep(600);
    s = await state();
    check(s.player && s.player.x > 1300, `Z1: Agata stands at the right end of the counter (x ${s.player && Math.round(s.player.x)})`);
    await shot("Z1_talk");
    await playThrough("Z1: talk", { choices: ["leave"], quietMs: 2500 });
    s = await state();
    await click("hotspot drawings", s.hotspots.drawings);
    await waitIdle("drawings");
    await sleep(1200);
    await shot("Z1_drawings");
    await playThrough("Z1: drawings", { quietMs: 2500 });

    // --- O4: Mitya's board ---
    s = await start("classmama", (t) => t.room === "O4" && t.hotspots);
    await shot("O4_board");

    // --- H3: the school photo ---
    s = await start("bedtime", (t) => t.room === "H3" && t.hotspots);
    await shot("H3_photo_school");
    if (s.hotspots.photo_school && s.hotspots.photo_school.visible) {
      await click("hotspot photo_school", s.hotspots.photo_school);
      await waitIdle("photo_school");
      await sleep(900);
      await shot("H3_photo_look");
      await playThrough("H3: photo", { quietMs: 2500 });
    } else check(false, "H3: photo_school hotspot visible");

    // --- the epilogue: the bridge and the beam end ---
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=epilogue`);
    await waitFor("epilogue: game up", (t) => t.room !== undefined, 240000);
    const seen = new Set();
    const t0 = Date.now();
    while (Date.now() - t0 < 420000 && seen.size < 2) {
      s = await state();
      if (s && (s.room === "EP_tamara" || s.room === "EP_beam") && !seen.has(s.room)) {
        await sleep(2500);
        s = await state();
        if (s.room === "EP_tamara" || s.room === "EP_beam") { seen.add(s.room); await shot(s.room === "EP_tamara" ? "EP_tamara_bridge" : "EP_beam_end"); }
      }
      const key = beatKey(s);
      if (key) { await click("epilogue: continue", (s.ui && s.ui.dialogue_click) || { x: 960, y: 780 }); await sleep(500); }
      else await sleep(250);
    }
    check(seen.has("EP_tamara"), "EP_tamara reached and framed");
    check(seen.has("EP_beam"), "EP_beam reached and framed");
  } catch (e) {
    check(false, `exception: ${e.message}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors} (Godot warnings, not errors: ${consoleWarnings.length})`);
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures, warnings: consoleWarnings }, null, 1));
    await browser.close();
    server.close();
  }
  const ok = checks.filter((c) => c.ok).length;
  console.log(`h_t8_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
