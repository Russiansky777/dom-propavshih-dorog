// Headless Chromium for the AI checks that look at the running web build (software WebGL, 1920×1080):
// open the site (or a local build), wait for the game, read window.probeState, settle, grab JPEG frames.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright";

export const FRAME_W = 1920, FRAME_H = 1080;
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function serve(dir, port) {
  const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
    ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".txt": "text/plain" };
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Content-Length": st.size, "Cache-Control": "no-store" });
      fs.createReadStream(file).pipe(res);
    });
  });
  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve(server)));
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

/** Browser + page on `url` with the game loaded (probeReady). Returns helpers. */
export async function openGame(url, { log = () => {} } = {}) {
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const context = await browser.newContext({ viewport: { width: FRAME_W, height: FRAME_H }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  page.setDefaultTimeout(180000);
  const consoleErrors = [];
  page.on("console", (m) => { if (m.type() === "error" && !/^WARNING: |^at: push_warning/.test(m.text()) && consoleErrors.length < 30) consoleErrors.push(m.text().slice(0, 300)); });
  page.on("pageerror", (e) => { if (consoleErrors.length < 30) consoleErrors.push(`pageerror: ${String(e.message).slice(0, 300)}`); });
  const cdp = await context.newCDPSession(page);
  await page.goto(url, { waitUntil: "load", timeout: 180000 });
  await page.waitForFunction(() => window.probeReady === true, null, { timeout: 300000 });
  await sleep(2500);
  log("game loaded");
  const state = async () => { try { return await page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null)); } catch (_) { return null; } };
  const grab = async (w = FRAME_W, quality = 82) => {
    const r = await cdp.send("Page.captureScreenshot", { format: "jpeg", quality, clip: { x: 0, y: 0, width: FRAME_W, height: FRAME_H, scale: w / FRAME_W } });
    return Buffer.from(r.data, "base64");
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.line_id || ""}|${s.beat.text || ""}` : "");
  /** Wait until Agata stands, nothing stages and the state stays the same for 700 ms. */
  const settle = async (maxMs = 60000) => {
    const t0 = Date.now();
    let last = "", stable = Date.now();
    while (Date.now() - t0 < maxMs) {
      const s = await state();
      if (!s) { await sleep(500); continue; }
      const busy = (s.player && (s.player.walking || s.player.acting)) || (s.busy && !beatKey(s) && !(s.puzzle && s.puzzle.open) && !(s.view && s.view.open));
      const k = JSON.stringify([s.room, beatKey(s), Math.round(s.player?.x || 0), Math.round(s.player?.y || 0)]);
      if (busy || k !== last) { last = k; stable = Date.now(); }
      else if (Date.now() - stable > 700) return s;
      await sleep(150);
    }
    return state();
  };
  /** Click through lines / take the first option until no text is on screen (texts are returned). */
  const dismissTexts = async (max = 40) => {
    const seen = [];
    for (let i = 0; i < max; i++) {
      const s = await settle(30000);
      if (!s || !s.beat || !s.beat.type) return seen;
      if (s.beat.type === "options") {
        const o = Object.values((s.ui && s.ui.options) || {})[0];
        if (!o) return seen;
        seen.push(`(вариант) ${Object.keys(s.ui.options)[0]}`);
        await page.mouse.click(o.x, o.y);
      } else {
        seen.push(String(s.beat.text || "").slice(0, 160));
        const at = (s.ui && s.ui.dialogue_click) || { x: 960, y: 900 };
        await page.mouse.click(at.x, at.y);
      }
      await sleep(400);
    }
    return seen;
  };
  return { browser, page, state, grab, settle, dismissTexts, consoleErrors, close: () => browser.close() };
}
