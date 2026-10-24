#!/usr/bin/env node
// Batch H, T8 — the boat at the turn and the house after Pelageya, in the WEB build with REAL mouse input:
//
//   tools/export_web.sh && node tools/h_t8_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8794)
//
//   D1  ?start=pier_first — a click on the house door before the pier: Agata «Записи подождут. Сперва к причалу…»,
//       the door stays shut; down to the pier, the talk with Pelageya (M02); back — the door now names the key.
//   B1  ?start=boat_turn — the turn: the boat by the plate, Pelageya by it, «В лодку» shown; the pier without the boat;
//       back to the turn, a click on Pelageya: the empty boat slides off along the rope (frame mid-way) and comes back
//       with the ribbon; «В лодку» at the plate → into the boat (the crossing begins).
// Frames: Docs/evidence/H/T8_web_*.jpg. Exit code 0 only when every check passed and the console has no errors.

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
const LOG_DIR = path.join(ROOT, "build", "shots", "h_t8");
const PORT = Number(process.env.H_PORT || 8794);

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
    const file = path.join(OUT_DIR, `T8_web_${name}.jpg`);
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

  try {
    // --- D1: the house door before and after Pelageya ---  (H_ONLY=B1 — skip D1)
    let s;
    if (process.env.H_ONLY !== "B1") {
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=pier_first`);
    s = await waitFor("D1: game up on the street with the key", (t) => t.room === "Z2" && t.exits && t.exits.H1, 240000);
    await playThrough("D1: start", { quietMs: 2500 });
    s = await state();
    check(s.exits.H1 && !s.exits.H1.open, "D1: the house door shut before the pier");
    await click("exit → H1 (house door)", s.exits.H1);
    await waitIdle("door");
    s = await waitFor("D1: Agata says why", (t) => t.beat && t.beat.type, 30000);
    check(/Сперва к причалу/.test(s.beat.text || "") && s.beat.speaker === "agata", `D1: «${s.beat.text}» (${s.beat.speaker})`);
    await shot("D1_door_before_M02");
    await playThrough("D1: line", { quietMs: 1500 });
    check((await state()).room === "Z2", "D1: still on the street");
    s = await state();
    check(/причал/.test(s.goal || ""), `D1: journal goal leads to the pier («${s.goal}»)`);
    check(await goExit("R1"), "D1: down to the pier");
    const lines = await useHotspot("pelageya", { choices: ["leave"] });
    check(lines.length >= 8, `D1: the talk with Pelageya (${lines.length} beats)`);
    check(await goExit("Z2"), "D1: back up to the street");
    s = await state();
    await click("exit → H1 (house door, after M02)", s.exits.H1);
    await waitIdle("door after M02");
    s = await waitFor("D1: the door after M02", (t) => t.beat && t.beat.type, 30000);
    check(/ключ/.test(s.beat.text || "") && !/Сперва к причалу/.test(s.beat.text || ""), `D1: after M02 the door names the key («${s.beat.text}»)`);
    await shot("D1_door_after_M02");
    await playThrough("D1: line 2", { quietMs: 1500 });
    }

    // --- B1: the boat at the turn, M17, «В лодку» ---
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=boat_turn`);
    s = await waitFor("B1: game up at the turn", (t) => t.room === "Z3" && t.hotspots && t.hotspots.pelageya, 240000);
    await playThrough("B1: start", { quietMs: 2500 });
    s = await state();
    check(s.hotspots.pelageya.visible, "B1: Pelageya at the turn");
    check(s.exits.R2 && s.exits.R2.visible && !s.exits.R2.open, "B1: «В лодку» at the plate, closed before the empty boat");
    await shot("B1_boat_at_turn");
    check(await goExit("R1"), "B1: to the pier");
    s = await state();
    check(!(s.hotspots.boat && s.hotspots.boat.visible) && !(s.hotspots.pelageya && s.hotspots.pelageya.visible) && !s.exits.R2, "B1: the pier — no boat, no Pelageya, no «В лодку»");
    await shot("B1_pier_without_boat");
    check(await goExit("Z3"), "B1: back to the turn");
    s = await state();
    await click("hotspot pelageya", s.hotspots.pelageya);
    await waitIdle("pelageya");
    await waitFor("B1: M17 starts", (t) => t.beat && t.beat.type, 30000);
    // First line, then the boat goes: a frame while it slides along the rope.
    s = await state();
    await click("B1: continue (first line)", s.ui.dialogue_click || { x: 960, y: 780 });
    await sleep(1600);
    await shot("B1_M17_boat_slides");
    const m17 = await playThrough("B1: M17", { quietMs: 30000 });   // the boat slides 3.4 s with no line on screen (slow under swiftshader)
    check(m17.some((l) => /лента лежит/.test(l)) && m17.some((l) => /Мамина лента/.test(l)), `B1: the empty boat came back with the ribbon (${m17.length} beats)`);
    s = await state();
    check(s.exits.R2 && s.exits.R2.visible && s.exits.R2.open, "B1: «В лодку» open after M17");
    await shot("B1_after_M17");
    await click("exit → R2 (into the boat)", s.exits.R2);
    await waitIdle("into the boat");
    s = await waitFor("B1: into the boat — the crossing", (t) => t.room === "R2" || (t.mechanic && t.mechanic.open), 60000);
    await sleep(1500);
    check(s.room === "R2" || (s.mechanic && s.mechanic.open), `B1: from the turn into the boat (room ${s.room})`);
    await shot("B1_into_boat");
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
