#!/usr/bin/env node
// Ревью 01.11 (В-10): дымовой прогон собранного wasm перед публикацией сайта — то, что ломается только в веб-сборке
// (атласы, сжатие текстур, JS-мост, загрузка .pck), не должно доходить до Директора.
//   tools/export_web.sh && node tools/smoke_web.mjs        (SMOKE_WEB_PORT, default 8791; PLAYWRIGHT_FROM, SMOKE_CHROME_CHANNEL — как в CI)
// Шаги: страница с ?title=1 → игра готова (window.probeReady) → титул открыт → «Новая игра» (window.probeTitle) →
// первая комната построена (probeState.room) → несколько секунд игры. Ошибки консоли (console.error, pageerror) —
// провал, кроме известных безвредных (см. BENIGN). Код 0 — всё прошло; отчёт build/shots/smoke/report.json.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.join(ROOT, "build", "web");
const OUT = path.join(ROOT, "build", "shots", "smoke");
const PORT = Number(process.env.SMOKE_WEB_PORT || 8791);
const { chromium } = createRequire(process.env.PLAYWRIGHT_FROM || path.join(ROOT, "package.json"))("playwright");
// Messages a healthy build still prints (the WebGL driver of a headless runner, autoplay without a gesture).
const BENIGN = [/GPU stall due to ReadPixels/i, /AudioContext was not allowed to start/i, /WebGL: INVALID_OPERATION: bindBuffer/i,
  /favicon\.ico/i, /Automatic fallback to software WebGL/i];
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".ico": "image/x-icon", ".txt": "text/plain" };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function serve(dir) {
  const server = http.createServer((req, res) => {
    const p = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, p === "/" ? "index.html" : p);
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

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error("No web build. Run tools/export_web.sh first."); process.exit(2); }
  fs.mkdirSync(OUT, { recursive: true });
  const checks = [], errors = [], logs = [];
  const check = (ok, name, detail = "") => { checks.push({ ok: !!ok, name, detail }); console.log(`${ok ? "OK  " : "FAIL"} ${name}${detail ? " — " + detail : ""}`); };
  const server = await serve(WEB_DIR);
  const launch = { headless: true, args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    "--ignore-gpu-blocklist", "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] };
  if (process.env.SMOKE_CHROME_CHANNEL) launch.channel = process.env.SMOKE_CHROME_CHANNEL;
  const browser = await chromium.launch(launch);
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on("console", (m) => { logs.push(`${m.type()}: ${m.text()}`); if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => { logs.push(`pageerror: ${e.message}`); errors.push(e.message); });
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (pred, timeout) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) { const s = await state(); if (s && pred(s)) return s; await sleep(200); }
    return null;
  };
  try {
    const t0 = Date.now();
    await page.goto(`http://127.0.0.1:${PORT}/index.html?title=1`, { waitUntil: "load", timeout: 120000 });
    const ready = await page.waitForFunction(() => window.probeReady === true, null, { timeout: 180000 }).then(() => true, () => false);
    check(ready, "the game starts (probeReady)", `${((Date.now() - t0) / 1000).toFixed(1)} s`);
    let s = ready ? await waitFor((x) => x.title && x.title.open, 60000) : null;
    check(!!s, "the title opens");
    if (s) {
      await page.evaluate(() => window.probeTitle && window.probeTitle("new_game"));
      s = await waitFor((x) => x.room && x.room !== "", 120000);
      check(!!s, "«Новая игра» builds the first room", s ? s.room : "no room");
      if (s) {
        const f0 = s.physics_frames || 0;
        await sleep(4000);
        const s2 = await state();
        check(s2 && (s2.physics_frames || 0) > f0, "the game runs on (frames advance)", s2 ? `${f0} → ${s2.physics_frames}` : "");
      }
    }
  } catch (e) {
    check(false, "no exception in the run", String(e));
  }
  const bad = errors.filter((t) => !BENIGN.some((re) => re.test(t)));
  check(bad.length === 0, "no console errors", bad.slice(0, 5).join(" | "));
  await page.screenshot({ path: path.join(OUT, "last.jpg"), type: "jpeg", quality: 80, timeout: 120000 }).catch(() => {});
  await browser.close();
  server.close();
  const ok = checks.every((c) => c.ok);
  fs.writeFileSync(path.join(OUT, "report.json"), JSON.stringify({ ok, checks, errors, logs: logs.slice(-200) }, null, 1));
  process.exit(ok ? 0 : 1);
}
main();
