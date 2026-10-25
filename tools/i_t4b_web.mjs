#!/usr/bin/env node
// I-T4b — villagers v2 in their rooms in the WEB build (web copies of the sheets, feature web_atlas): for each villager
// a row stands / listens / talks (two frames: mouth) / walks (the walk cycle in place, profile row) → 
// Docs/evidence/i_t4/web_<id>.jpg, plus web_all.jpg. Hooks: game/scripts/actors/npc_probe.gd (?npcprobe).
//
//   tools/export_web.sh && node tools/i_t4b_web.mjs      (H_WEB_DIR — another build dir; H_PORT, default 8797; H_ONLY=nina,ilya)
// Exit code 0 when every villager was found in its room on a web copy of its sheet and the console has no errors.

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
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "i_t4");
const LOG_DIR = path.join(ROOT, "build", "shots", "i_t4b");
const PORT = Number(process.env.H_PORT || 8797);

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


const IDS = ["nina", "ilya", "ilya_wife", "ulyana", "mitya", "pelageya", "pavel", "tamara"];

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}. Run tools/export_web.sh first.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });
  const log = [];
  const line = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const failures = [];
  const check = (ok, msg) => { line(`${ok ? "OK  " : "FAIL"} ${msg}`); if (!ok) failures.push(msg); };
  let consoleErrors = 0;
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.setDefaultTimeout(180000);
  page.on("console", (m) => {
    const t = m.text();
    if (m.type() === "error" && !/^WARNING: /.test(t) && !/at: push_warning/.test(t)) { consoleErrors += 1; line(`console.error: ${t}`); }
  });
  page.on("pageerror", (e) => { consoleErrors += 1; line(`pageerror: ${e.message}`); });
  await page.goto(`http://127.0.0.1:${PORT}/index.html?npcprobe`);
  const t0 = Date.now();
  while (Date.now() - t0 < 240000) {
    if (await page.evaluate(() => !!window.npcProbeReady && !!window.npcInfo)) break;
    await sleep(500);
  }
  if (!(await page.evaluate(() => !!window.npcProbeReady))) {
    line("FAIL: npc probe not ready (is ?npcprobe handled? did a room load?)");
    await browser.close(); server.close(); process.exit(1);
  }
  const info = () => page.evaluate(() => JSON.parse(JSON.stringify(window.npcInfo || {})));
  const only = (process.env.H_ONLY || "").split(",").filter(Boolean);
  const rows = [];
  for (const id of IDS.filter((i) => !only.length || only.includes(i))) {
    await page.evaluate((i) => window.npcShow(i), id);
    let s = {};
    for (let k = 0; k < 120; k++) { await sleep(250); s = await info(); if (s.npcs && s.npcs[id]) break; }
    const n = s.npcs && s.npcs[id];
    if (!n) { check(false, `${id}: not found in a room (room=${s.room})`); continue; }
    await sleep(1500);
    check(String(n.sheet_dir).includes("characters_web/"), `${id} in ${s.room}: sheet ${n.sheet_dir} (texture_scale ${n.texture_scale})`);
    const box = await page.locator("canvas").first().boundingBox();
    const tiles = [];
    for (const [st, dir, wait] of [["idle", null, 2500], ["listen", null, 2500], ["talk", null, 2500], ["talk", null, 220], ["walk", 2, 1200]]) {
      await page.evaluate((a) => window.npcSet(a[0], a[1], a[2]), [id, st, dir]);
      await sleep(wait);
      s = await info();
      const m = s.npcs[id];
      if (st === "walk" && !String(m.anim).startsWith("walk")) { line(`${id}: no walk sheet — skipped`); continue; }
      const kx = box.width / s.viewport[0], ky = box.height / s.viewport[1];
      const h = Math.min(1000, Math.max(300, 430 * m.scale * ky * 1.25));
      const w = Math.round(h * 0.62);
      const x = Math.max(0, Math.min(box.width - w, box.x + m.x * kx - w / 2));
      const y = Math.max(0, Math.min(box.height - h, box.y + m.y * ky - h + 40 * ky));
      const file = path.join(LOG_DIR, `${id}_${tiles.length}_${st}.png`);
      await page.screenshot({ path: file, clip: { x, y, width: w, height: h } });
      tiles.push({ file, st, anim: m.anim });
    }
    line(`${id}: ${tiles.map((t) => `${t.st}=${t.anim}`).join(" ")}`);
    rows.push({ id, room: s.room, tiles });
  }
  fs.writeFileSync(path.join(LOG_DIR, "tiles.json"), JSON.stringify(rows, null, 1));
  check(consoleErrors === 0, `console errors: ${consoleErrors}`);
  fs.writeFileSync(path.join(LOG_DIR, "log.txt"), log.join("\n") + "\n");
  await browser.close();
  server.close();
  // the rows are assembled into Docs/evidence/i_t4/web_*.jpg by tools/i_t4b_tiles.py (PIL)
  process.exit(failures.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
