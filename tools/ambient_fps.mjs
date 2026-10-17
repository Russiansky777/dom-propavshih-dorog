#!/usr/bin/env node
// «Живой мир» — FPS of the web build with the ambient layer on and off, room by room, plus a real
// walk through a Z2 puddle (splash events read back from the game). Not a test: numbers for the report.
//
//   tools/export_web.sh && node tools/ambient_fps.mjs
//   AMBIENT_WEB_DIR=<dir with index.html> AMBIENT_PORT=8771 AMBIENT_SECONDS=5 node tools/ambient_fps.mjs
//
// Opens index.html?ambientprobe in headless Chromium (software WebGL2 — far slower than any real GPU,
// so the ON/OFF ratio matters more than the absolute fps), uses the probe hooks of
// game/scripts/ambient/ambient_probe.gd (ambientGoto / ambientEnable / ambientFlag / ambientWalk /
// ambientState). FPS = requestAnimationFrame callbacks per second in the page (Godot draws once per
// rAF). Report: build/reports/ambient_fps.json, frames build/shots/ambient/<room>.png, console log.
// Exit code 1 on a page error, a shader error in the console, or a room that did not load.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.resolve(process.env.AMBIENT_WEB_DIR || path.join(ROOT, "build", "web"));
const OUT_DIR = path.join(ROOT, "build", "shots", "ambient");
const REPORT = path.join(ROOT, "build", "reports", "ambient_fps.json");
const PORT = Number(process.env.AMBIENT_PORT || 8771);
const SECONDS = Number(process.env.AMBIENT_SECONDS || 5);
const ROOMS = (process.env.AMBIENT_ROOMS || "Z2,Z3,R1,H1,H2,O1,O2").split(",");

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
    if (/SHADER ERROR|shader compilation failed|SCRIPT ERROR/i.test(t)) errors.push(t);
  });
  page.on("pageerror", (e) => { line(`pageerror: ${e.message}`); errors.push(e.message); });

  await page.goto(`http://127.0.0.1:${PORT}/index.html?ambientprobe`);
  const t0 = Date.now();
  while (Date.now() - t0 < 90000) {
    if (await page.evaluate(() => !!window.ambientProbeReady && !!window.ambientState)) break;
    await sleep(250);
  }
  if (!(await page.evaluate(() => !!window.ambientProbeReady))) {
    line("FAIL: ambient probe not ready (is ?ambientprobe handled? did the game start?)");
    await browser.close(); server.close(); process.exit(1);
  }
  const state = () => page.evaluate(() => JSON.parse(JSON.stringify(window.ambientState || {})));
  const fps = (sec) => page.evaluate((s) => new Promise((resolve) => {
    let n = 0; const start = performance.now();
    const tick = () => { n += 1; if (performance.now() - start < s * 1000) requestAnimationFrame(tick); else resolve(n / ((performance.now() - start) / 1000)); };
    requestAnimationFrame(tick);
  }), sec);

  const report = { web_dir: path.relative(ROOT, WEB_DIR), renderer: "headless Chromium, ANGLE SwiftShader (software WebGL2)", seconds: SECONDS, rooms: {} };
  for (const room of ROOMS) {
    await page.evaluate((r) => { window.ambientEnable(true); if (r === "H1") window.ambientFlag("h1_shutter_open", true); window.ambientGoto(r, "default"); }, room);
    let s = {};
    for (let i = 0; i < 40; i++) { await sleep(250); s = await state(); if (s.room === room) break; }
    if (s.room !== room) { errors.push(`${room}: did not load (state.room=${s.room})`); line(`FAIL ${room}: not loaded`); continue; }
    await sleep(1500);
    const on = await fps(SECONDS);
    const son = await state();
    await page.screenshot({ path: path.join(OUT_DIR, `${room}.png`) });
    await page.evaluate(() => window.ambientEnable(false));
    await sleep(800);
    const off = await fps(SECONDS);
    await page.evaluate(() => window.ambientEnable(true));
    report.rooms[room] = { fps_on: +on.toFixed(1), fps_off: +off.toFixed(1), cost_pct: +(100 * (1 - on / off)).toFixed(1),
      godot_fps_on: son.fps, sway: son.sway, water: son.water, puddles: son.puddles, rain: son.rain, dust_particles: son.dust_particles };
    line(`${room}: ambient on ${on.toFixed(1)} fps, off ${off.toFixed(1)} fps (${report.rooms[room].cost_pct} %) — sway ${son.sway}, water ${son.water}, puddles ${son.puddles}, rain ${son.rain}, dust ${son.dust_particles}`);
  }
  // A real walk through the big Z2 puddle: splashes and prints come from the game itself.
  await page.evaluate(() => { window.ambientEnable(true); window.ambientGoto("Z2", "default"); });
  await sleep(1500);
  await page.evaluate(() => window.ambientWalk(1200, 835));
  for (let i = 0; i < 60; i++) { await sleep(250); const s = await state(); if (s.player && !s.player.walking) break; }
  await page.evaluate(() => window.ambientWalk(1790, 862));
  let walk = {};
  for (let i = 0; i < 80; i++) {
    await sleep(200);
    walk = await state();
    if (i === 8) await page.screenshot({ path: path.join(OUT_DIR, "Z2_walk.png") });
    if (walk.player && !walk.player.walking && i > 3) break;
  }
  report.z2_walk = { steps: walk.steps, splashes: walk.splashes, prints_made: walk.prints_made, events: walk.events };
  line(`Z2 walk: ${walk.steps} steps, ${walk.splashes} splashes, ${walk.prints_made} prints; events ${JSON.stringify(walk.events)}`);
  if (!(walk.splashes >= 1)) errors.push("Z2 walk through the puddle: no splash");
  report.errors = errors;
  fs.writeFileSync(REPORT, JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, "console.log"), log.join("\n") + "\n");
  line(`report: ${path.relative(ROOT, REPORT)}; errors: ${errors.length}`);
  await browser.close();
  server.close();
  process.exit(errors.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
