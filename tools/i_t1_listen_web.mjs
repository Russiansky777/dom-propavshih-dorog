#!/usr/bin/env node
// Batch I, I-T1 — the takes listening page in the WEB build, real mouse (frames Docs/evidence/I/I_T1_listen_*.jpg):
//
//   tools/export_web.sh && node tools/i_t1_listen_web.mjs      (I_WEB_DIR — another build dir; I_PORT, default 8797)
//
//   the game's index.html is there (the page lives next to the game); /listen/ opens, lists lines with takes;
//   a click on «▶ Дубль 2» starts the audio; a click on a choice marks the row; after a reload the choice is still there
//   (localStorage); «Скачать выбор» gives takes_choice.json with that choice.
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
  ({ chromium } = createRequire(process.env.PLAYWRIGHT_FROM || path.join(ROOT, "package.json"))("playwright"));
}
const WEB_DIR = process.env.I_WEB_DIR ? path.resolve(ROOT, process.env.I_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "I");
const PORT = Number(process.env.I_PORT || 8797);
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".json": "application/json",
  ".ogg": "audio/ogg", ".mp3": "audio/mpeg", ".ttf": "font/ttf", ".wasm": "application/wasm", ".pck": "application/octet-stream" };

function serve(dir) {
  const server = http.createServer((req, res) => {
    let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    if (urlPath.endsWith("/")) urlPath += "index.html";
    const file = path.join(dir, urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Content-Length": st.size, "Cache-Control": "no-store" });
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

const results = [];
const check = (ok, msg) => { results.push([ok, msg]); console.log(`${ok ? "PASS" : "FAIL"}  ${msg}`); };

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "listen", "index.html"))) { console.error(`No listen page in ${WEB_DIR}. Run tools/export_web.sh first.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(), args: ["--autoplay-policy=no-user-gesture-required"] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  check(fs.existsSync(path.join(WEB_DIR, "index.html")), "the game build is next to the page (build/web/index.html)");
  await page.goto(`http://127.0.0.1:${PORT}/listen/`, { waitUntil: "networkidle" });
  await page.waitForSelector(".row, .empty");
  const rows = await page.locator(".row").count();
  check(rows > 0, `the page lists lines with takes: ${rows}`);
  await page.screenshot({ path: path.join(OUT_DIR, "I_T1_listen_list.jpg"), type: "jpeg", quality: 80 });
  if (rows > 0) {
    const first = page.locator(".row").first();
    const id = (await first.getAttribute("id")).slice(2);
    const takes = await first.locator("button.play").count();
    check(takes >= 2, `row ${id}: ${takes} take buttons`);
    const btn = first.locator("button.play").nth(1);
    await btn.click();
    await page.waitForTimeout(700);
    const st = await page.evaluate(() => ({ src: listenPlayer.src, t: listenPlayer.currentTime, paused: listenPlayer.paused, err: listenPlayer.error ? listenPlayer.error.code : 0 }));
    check(st.src.includes("take2") && st.err === 0 && (st.t > 0 || !st.paused), `«▶ Дубль 2» plays take 2: ${JSON.stringify(st)}`);
    await first.locator('input[type="radio"]').nth(1).click();
    await page.waitForTimeout(200);
    check((await page.locator(".row.chosen").count()) === 1, "the chosen row is marked");
    await page.reload({ waitUntil: "networkidle" });
    await page.waitForSelector(".row");
    const kept = await page.evaluate((lid) => JSON.parse(localStorage.getItem("dpd_listen_choice_v1") || "{}")[lid], id);
    check(kept === 2, `after a reload the choice is kept (localStorage): ${kept}`);
    await page.locator(".row").first().scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(OUT_DIR, "I_T1_listen_chosen.jpg"), type: "jpeg", quality: 80 });
    const [dl] = await Promise.all([page.waitForEvent("download"), page.click("#download")]);
    const tmp = path.join(ROOT, "build", "shots", "takes_choice.json");
    fs.mkdirSync(path.dirname(tmp), { recursive: true });
    await dl.saveAs(tmp);
    const j = JSON.parse(fs.readFileSync(tmp, "utf8"));
    check(j.choices && j.choices[id] && j.choices[id].take === 2, `«Скачать выбор»: takes_choice.json has ${id} → 2`);
  }
  check(errors.length === 0, `no console errors: ${errors.join(" | ")}`);
  await browser.close();
  server.close();
  const failed = results.filter((r) => !r[0]).length;
  console.log(`==== I-T1 listen page: ${results.length} checks, ${failed} failed ====`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
