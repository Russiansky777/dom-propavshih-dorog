#!/usr/bin/env node
// Agata sprites vs live 3D — FPS and frame time of the web build in the same room, same spot, modes
// interleaved (REPEATS), standing and walking. Not a test: numbers for the report + a check that the
// 3D shader compiles in WebGL2 (no shader error in the console).
//
//   AGATA_WEB_DIR=<dir with index.html> node tools/agata_fps.mjs
//   env: AGATA_PORT=8781 AGATA_SECONDS=4 AGATA_REPEATS=3 AGATA_ROOMS=H1,Z2
//
// Opens index.html?lightprobe&agataprobe in headless Chromium (software WebGL2 via SwiftShader — far
// slower than any real GPU: compare the two modes, not the absolute numbers). Hooks: lightGoto/lightWalk
// (game/scripts/lighting/light_probe.gd), agataMode/agataState (game/scripts/actors/player.gd).
// FPS = requestAnimationFrame callbacks per second; frame time = median / p95 of rAF intervals.
// Report: build/reports/agata_fps.json (+ AGATA_REPORT), frames build/shots/agata/<case>_<mode>.png.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.resolve(process.env.AGATA_WEB_DIR || path.join(ROOT, "build", "web"));
const OUT_DIR = path.resolve(process.env.AGATA_SHOTS || path.join(ROOT, "build", "shots", "agata"));
const REPORT = path.resolve(process.env.AGATA_REPORT || path.join(ROOT, "build", "reports", "agata_fps.json"));
const PORT = Number(process.env.AGATA_PORT || 8781);
const SECONDS = Number(process.env.AGATA_SECONDS || 4);
const REPEATS = Number(process.env.AGATA_REPEATS || 3);
const ROOMS = (process.env.AGATA_ROOMS || "H1,Z2").split(",");
const PLACES = { H1: { flags: "done_M01,done_M02,house_unlocked,done_M03,met_tikhon", stand: [1200, 1000], walk: [[700, 900], [1500, 950]] },
  Z2: { flags: "done_M01,done_M02", stand: [960, 900], walk: [[500, 900], [1450, 900]] } };
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".ico": "image/x-icon" };

function serve(dir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Content-Length": st.size,
        "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-store" });
      fs.createReadStream(file).pipe(res);
    });
  });
  return new Promise((resolve) => server.listen(PORT, "127.0.0.1", () => resolve(server)));
}

function findChromium() {
  try { const p = chromium.executablePath(); if (p && fs.existsSync(p)) return p; } catch (_) {}
  const base = process.env.PLAYWRIGHT_BROWSERS_PATH || "/opt/pw-browsers";
  if (fs.existsSync(base)) for (const d of fs.readdirSync(base)) {
    if (!d.startsWith("chromium-")) continue;
    const cand = path.join(base, d, "chrome-linux", "chrome");
    if (fs.existsSync(cand)) return cand;
  }
  return undefined;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const median = (a) => { const b = [...a].sort((x, y) => x - y); return b[Math.floor(b.length / 2)]; };

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(path.dirname(REPORT), { recursive: true });
  const log = [];
  const line = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const errors = [];
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--no-sandbox", "--disable-dev-shm-usage"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on("console", (m) => { const t = m.text(); line(`console.${m.type()}: ${t}`);
    if (/SHADER ERROR|shader compilation failed|SCRIPT ERROR|Failed to compile|not loaded/i.test(t)) errors.push(t); });
  page.on("pageerror", (e) => { line(`pageerror: ${e.message}`); errors.push(e.message); });
  await page.goto(`http://127.0.0.1:${PORT}/index.html?lightprobe&agataprobe`);
  const t0 = Date.now();
  while (Date.now() - t0 < 120000) {
    if (await page.evaluate(() => !!window.lightProbeReady && !!window.agataProbeReady && !!window.agataState)) break;
    await sleep(300);
  }
  if (!(await page.evaluate(() => !!window.agataProbeReady))) { line("FAIL: agata probe not ready"); await browser.close(); server.close(); process.exit(1); }
  const state = () => page.evaluate(() => JSON.parse(JSON.stringify(window.agataState || {})));
  const measure = (sec) => page.evaluate((s) => new Promise((resolve) => {
    const ts = []; const start = performance.now();
    const tick = (t) => { ts.push(t); if (t - start < s * 1000) requestAnimationFrame(tick); else {
      const d = []; for (let i = 1; i < ts.length; i++) d.push(ts[i] - ts[i - 1]); d.sort((a, b) => a - b);
      resolve({ fps: (ts.length - 1) / ((ts[ts.length - 1] - ts[0]) / 1000), ms_median: d[Math.floor(d.length / 2)], ms_p95: d[Math.floor(d.length * 0.95)] }); } };
    requestAnimationFrame(tick);
  }), sec);
  const report = { web_dir: path.relative(ROOT, WEB_DIR) || WEB_DIR, renderer: "headless Chromium, ANGLE SwiftShader (software WebGL2), 1920x1080", seconds: SECONDS, repeats: REPEATS, cases: {} };
  for (const room of ROOMS) {
    const P = PLACES[room];
    for (const kind of ["stand", "walk"]) {
      const runs = { sprites: [], "3d": [] };
      for (let r = 0; r < REPEATS; r++) {
        for (const mode of ["sprites", "3d"]) {
          const at = kind === "stand" ? P.stand : P.walk[0];
          await page.evaluate((a) => window.lightGoto(a.room, a.flags, a.x, a.y), { room, flags: P.flags, x: at[0], y: at[1] });
          await sleep(1200);
          await page.evaluate((m) => window.agataMode(m), mode);
          await sleep(1200);
          if (kind === "walk") await page.evaluate((b) => window.lightWalk(b[0], b[1]), P.walk[1]);
          await sleep(300);
          const m = await measure(SECONDS);
          const st = await state();
          runs[mode].push({ ...m, state: st });
          if (r === 0) await page.screenshot({ path: path.join(OUT_DIR, `${room}_${kind}_${mode}.png`), timeout: 180000 });
          line(`${room} ${kind} ${mode}: ${m.fps.toFixed(2)} fps, frame ${m.ms_median.toFixed(1)} ms (p95 ${m.ms_p95.toFixed(1)}) — mode ${st.mode}${st.is3d ? ` 3d frame ${st.size} @${st.render_scale}` : ""}, walking ${st.walking}`);
          if (mode === "3d" && !st.is3d) errors.push(`${room} ${kind}: 3D mode did not start`);
        }
      }
      const agg = (a) => ({ fps: +median(a.map((x) => x.fps)).toFixed(2), ms_median: +median(a.map((x) => x.ms_median)).toFixed(1), ms_p95: +median(a.map((x) => x.ms_p95)).toFixed(1), runs_fps: a.map((x) => +x.fps.toFixed(2)) });
      const s = agg(runs.sprites), d = agg(runs["3d"]);
      report.cases[`${room}_${kind}`] = { sprites: s, "3d": d, fps_ratio_3d_to_sprites: +(d.fps / s.fps).toFixed(3) };
      line(`== ${room} ${kind}: sprites ${s.fps} fps / ${s.ms_median} ms, 3D ${d.fps} fps / ${d.ms_median} ms (ratio ${(d.fps / s.fps).toFixed(3)})`);
    }
  }
  report.errors = errors;
  fs.writeFileSync(REPORT, JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, "console.log"), log.join("\n") + "\n");
  line(`report: ${REPORT}; errors: ${errors.length}`);
  await browser.close(); server.close();
  process.exit(errors.length ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
