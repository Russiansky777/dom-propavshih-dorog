#!/usr/bin/env node
// Room lighting (fire, lamps, beams, darkness, actor shadows) — FPS of the web build with lighting on
// and off, room by room, plus a walk past the H1 fire (cast shadow moving). Not a test: numbers for
// the report, and a check that every lighting shader compiles in WebGL2 (console has no shader error).
//
//   tools/export_web.sh && node tools/light_fps.mjs
//   LIGHT_WEB_DIR=<dir with index.html> LIGHT_PORT=8772 LIGHT_SECONDS=4 LIGHT_REPEATS=3 node tools/light_fps.mjs
//
// Opens index.html?lightprobe in headless Chromium (software WebGL2 via SwiftShader — far slower than
// any real GPU, so the ON/OFF ratio matters more than the absolute fps), drives the hooks of
// game/scripts/lighting/light_probe.gd (lightGoto / lightEnable / lightWalk / lightState).
// FPS = requestAnimationFrame callbacks per second in the page (Godot draws once per rAF).
// Report: build/reports/light_fps.json, frames build/shots/light/<case>.png, console log.
// Exit code 1 on a page error, a shader error in the console, or a room that did not load.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.resolve(process.env.LIGHT_WEB_DIR || path.join(ROOT, "build", "web"));
const OUT_DIR = path.join(ROOT, "build", "shots", "light");
const REPORT = path.join(ROOT, "build", "reports", "light_fps.json");
const PORT = Number(process.env.LIGHT_PORT || 8772);
const SECONDS = Number(process.env.LIGHT_SECONDS || 4);
const REPEATS = Number(process.env.LIGHT_REPEATS || 3);

const CASES = [
  { name: "H1_dark_fire", room: "H1", flags: "stove_lit", x: 1000, y: 800 },
  { name: "H1_day_fire_beam", room: "H1", flags: "stove_lit,h1_shutter_open", x: 1250, y: 900 },
  { name: "H2_door", room: "H2", flags: "", x: 520, y: 880 },
  { name: "Z1_lamp", room: "Z1", flags: "", x: 560, y: 860 },
];

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
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(path.dirname(REPORT), { recursive: true });
  const log = [];
  const line = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const errors = [];
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on("console", (m) => {
    const t = m.text();
    line(`console.${m.type()}: ${t}`);
    if (/SHADER ERROR|shader compilation failed|SCRIPT ERROR|Failed to compile/i.test(t)) errors.push(t);
  });
  page.on("pageerror", (e) => { line(`pageerror: ${e.message}`); errors.push(e.message); });

  await page.goto(`http://127.0.0.1:${PORT}/index.html?lightprobe`);
  const t0 = Date.now();
  while (Date.now() - t0 < 90000) {
    if (await page.evaluate(() => !!window.lightProbeReady && !!window.lightState)) break;
    await sleep(250);
  }
  if (!(await page.evaluate(() => !!window.lightProbeReady))) {
    line("FAIL: light probe not ready (is ?lightprobe handled? did the game start?)");
    await browser.close(); server.close(); process.exit(1);
  }
  const state = () => page.evaluate(() => JSON.parse(JSON.stringify(window.lightState || {})));
  const fps = (sec) => page.evaluate((s) => new Promise((resolve) => {
    let n = 0; const start = performance.now();
    const tick = () => { n += 1; if (performance.now() - start < s * 1000) requestAnimationFrame(tick); else resolve(n / ((performance.now() - start) / 1000)); };
    requestAnimationFrame(tick);
  }), sec);
  const go = async (c) => {
    await page.evaluate((cc) => window.lightGoto(cc.room, cc.flags, cc.x, cc.y), c);
    let s = {};
    for (let i = 0; i < 40; i++) { await sleep(250); s = await state(); if (s.room === c.room) break; }
    return s;
  };

  const report = { web_dir: path.relative(ROOT, WEB_DIR), renderer: "headless Chromium, ANGLE SwiftShader (software WebGL2)", seconds: SECONDS, cases: {} };
  // The machine may be shared (other builds, other browsers): ON and OFF are interleaved REPEATS
  // times and the medians compared, so a load spike hits both sides.
  const median = (a) => { const b = [...a].sort((x, y) => x - y); return b[Math.floor(b.length / 2)]; };
  for (const c of CASES) {
    await page.evaluate(() => window.lightEnable(true));
    let s = await go(c);
    if (s.room !== c.room) { errors.push(`${c.name}: did not load (state.room=${s.room})`); line(`FAIL ${c.name}: not loaded`); continue; }
    await sleep(1500);
    const ons = [], offs = [];
    let son = {};
    for (let r = 0; r < REPEATS; r++) {
      await page.evaluate(() => window.lightEnable(true));
      await sleep(900);
      ons.push(await fps(SECONDS));
      son = await state();
      if (r === 0) await page.screenshot({ path: path.join(OUT_DIR, `${c.name}.png`), timeout: 180000 });
      await page.evaluate(() => window.lightEnable(false));
      await sleep(900);
      offs.push(await fps(SECONDS));
      if (r === 0) await page.screenshot({ path: path.join(OUT_DIR, `${c.name}_off.png`), timeout: 180000 });
    }
    await page.evaluate(() => window.lightEnable(true));
    const on = median(ons), off = median(offs);
    report.cases[c.name] = { fps_on: +on.toFixed(2), fps_off: +off.toFixed(2), cost_pct: +(100 * (1 - on / off)).toFixed(1),
      runs_on: ons.map((v) => +v.toFixed(2)), runs_off: offs.map((v) => +v.toFixed(2)),
      sources: son.sources ? Object.keys(son.sources).length : 0, shadows: son.shadows, tone: son.player && son.player.tone };
    line(`${c.name}: lighting on ${on.toFixed(2)} fps, off ${off.toFixed(2)} fps (median of ${REPEATS}; cost ${report.cases[c.name].cost_pct} %; runs on ${ons.map((v) => v.toFixed(2))} / off ${offs.map((v) => v.toFixed(2))}) — ${report.cases[c.name].sources} sources, ${son.shadows} shadows, Agata tone ${JSON.stringify(son.player && son.player.tone)}`);
    if (!son.sources || Object.keys(son.sources).length === 0) errors.push(`${c.name}: no lighting sources reported`);
  }
  // A walk past the fire: the cast shadow follows Agata; fps while walking.
  await page.evaluate(() => window.lightEnable(true));
  await go({ room: "H1", flags: "stove_lit", x: 600, y: 860 });
  await sleep(1200);
  await page.evaluate(() => window.lightWalk(1500, 900));
  const walk_fps = await fps(Math.min(SECONDS, 4));
  await page.screenshot({ path: path.join(OUT_DIR, "H1_walk_fire.png"), timeout: 180000 });
  const sw = await state();
  report.h1_walk = { fps: +walk_fps.toFixed(1), player: sw.player, shadows: sw.shadows };
  line(`H1 walk past the fire: ${walk_fps.toFixed(1)} fps, shadows ${sw.shadows}, player ${JSON.stringify(sw.player)}`);
  report.errors = errors;
  fs.writeFileSync(REPORT, JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, "console.log"), log.join("\n") + "\n");
  line(`report: ${path.relative(ROOT, REPORT)}; errors: ${errors.length}`);
  await browser.close();
  server.close();
  process.exit(errors.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
