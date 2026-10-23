#!/usr/bin/env node
// Title screen and pause menu in the web build, REAL mouse and keyboard (Director 23.10: «главное меню и меню паузы»):
//   title (forced by ?title=1 — automated browsers skip it otherwise) → the water and the leaves move, the panel does
//   not → hover «Новая игра» (the leaf and the golden lines follow) → click it → play (lines, a walk) → Esc → the pause
//   over the blurred, held game → «Сохранить» → slot 1 → «Назад» → «Продолжить» → a walk → Esc → «В главное меню» →
//   the title offers «Продолжить» → click it → the game is back where it was left.
//
//   tools/export_web.sh && node tools/menu_web.mjs        (MENU_WEB_PORT, default 8781)
//
// Frames: Docs/evidence/G/menu_{title,title_hover,pause,title_continue}.jpg; log and report: build/shots/menu/.
// Click targets come from window.probeState.title / .pause / .ui (main.gd, title_screen.gd, pause_menu.gd, game_ui.gd).
// Exit code 0 only when every check passed.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "G");
const LOG_DIR = path.join(ROOT, "build", "shots", "menu");
const PORT = Number(process.env.MENU_WEB_PORT || 8781);
// Viewport: 1280×720 by default — software GL (SwiftShader) on a loaded runner draws ~1 frame/s at 1920×1080 and a
// screenshot then waits ~50 s; probe coordinates are canvas px (1920×1080) and are scaled to the viewport.
const VW = Number(process.env.MENU_WEB_W || 1280), VH = Number(process.env.MENU_WEB_H || 720);
const S = VH / 1080;
const SHOT_MS = 240000;

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
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error("No web build. Run tools/export_web.sh first."); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });
  const log = [];
  const logLine = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const checks = [];
  const check = (ok, name, detail = "") => { checks.push({ ok: !!ok, name, detail }); logLine(`${ok ? "OK  " : "FAIL"} ${name}${detail ? " — " + detail : ""}`); };
  const errors = [];
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1 });
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); if (m.type() !== "log") logLine(`console.${m.type()}: ${m.text()}`); });
  page.on("pageerror", (e) => { errors.push(e.message); logLine(`pageerror: ${e.message}`); });
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = 60000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) { const s = await state(); if (s && pred(s)) return s; await sleep(100); }
    check(false, `${label}: timeout`);
    return state();
  };
  const click = async (label, pt) => {
    if (!pt || typeof pt.x !== "number") { check(false, `${label}: no target`); return; }
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x * S, pt.y * S, { steps: 5 });
    await sleep(120);
    await page.mouse.click(pt.x * S, pt.y * S);
  };
  const shot = async (name, opts = {}) => {
    const file = path.join(OUT_DIR, `menu_${name}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 88, timeout: SHOT_MS, ...opts });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const clip = (x, y, width, height) => page.screenshot({ clip: { x: x * S, y: y * S, width: width * S, height: height * S }, timeout: SHOT_MS });
  const move = (pt, steps = 6) => page.mouse.move(pt.x * S, pt.y * S, { steps });
  // Until the game has run `n` more physics frames (a new frame is drawn in between).
  const frames = async (n) => { const f0 = (await state()).physics_frames; await waitFor(`${n} frames`, (t) => t.physics_frames >= f0 + n, 60000); };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const finishDialogue = async (label) => {
    for (let i = 0, idle = 0; i < 80 && idle < 8; i++) {
      const s = await state();
      if (!beatKey(s)) { idle += 1; await sleep(200); continue; }
      idle = 0;
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        await click(`${label}: option ${ids[0]}`, s.ui.options[ids[0]]);
      } else {
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 980 });
      }
      await waitFor(`${label}: next beat`, (t) => beatKey(t) !== beatKey(s), 8000);
    }
  };
  const esc = async () => { logLine("key Escape"); await page.keyboard.press("Escape"); };

  try {
    await page.goto(`http://127.0.0.1:${PORT}/index.html?title=1`, { waitUntil: "load", timeout: 90000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 120000 });
    let s = await waitFor("title open", (t) => t.title && t.title.open && t.title.items && t.title.items.new_game, 30000);
    check(s.title.open && s.paused && !s.room, "the title on launch, the game not started and held", JSON.stringify({ room: s.room, paused: s.paused }));
    check(!s.title.items.continue, "a fresh browser has no save: no «Продолжить»", s.title.order.join(", "));
    check(!s.title.items.quit, "no «Выход» on the web", s.title.order.join(", "));
    check(s.title.signature && s.title.animated, "the signature layer and the animated background are on");
    await sleep(1500);
    // Animation: the water strip changes between two frames, the carved title of the panel does not.
    const w1 = await clip(860, 560, 420, 90), p1 = await clip(150, 60, 380, 330);
    await frames(3);
    const w2 = await clip(860, 560, 420, 90), p2 = await clip(150, 60, 380, 330);
    check(!w1.equals(w2), "the water moves (two frames apart differ)");
    check(p1.equals(p2), "the panel and its title stand still");
    await move({ x: 1500, y: 900 });
    await sleep(300);
    await shot("title");
    // Hover «Новая игра»: the highlight (leaf, golden lines) moves there.
    s = await state();
    await move(s.title.items.new_game, 8);
    s = await waitFor("hover «Новая игра»", (t) => t.title.highlighted === "new_game", 5000);
    check(s.title.highlighted === "new_game", "hover moves the highlight to «Новая игра»");
    await sleep(500);
    await shot("title_hover");
    await click("title «Новая игра»", s.title.items.new_game);
    s = await waitFor("new game: the post office", (t) => t.room === "Z1" && !t.title.open && !t.paused, 30000);
    check(s.room === "Z1" && !s.title.open && !s.paused, "«Новая игра» starts the game at the post office");
    await sleep(1500);
    await finishDialogue("Z1 first lines");
    // A walk across the floor, then Esc in the middle of it.
    s = await state();
    const from = { x: s.player.x, y: s.player.y };
    await click("walk", { x: from.x > 960 ? from.x - 420 : from.x + 420, y: Math.min(Math.max(from.y, 860), 960) });
    await sleep(350);
    await esc();
    s = await waitFor("pause open", (t) => t.pause && t.pause.open && t.pause.blur > 0.99, 8000);
    check(s.pause.open && s.paused, "Esc opens the pause; the tree is held", JSON.stringify({ paused: s.paused, blur: s.pause.blur }));
    const at = { x: s.player.x, y: s.player.y };
    await sleep(2500);
    s = await state();
    check(Math.hypot(s.player.x - at.x, s.player.y - at.y) < 0.5, "Agata stands still under the pause", `moved ${Math.hypot(s.player.x - at.x, s.player.y - at.y).toFixed(1)} px`);
    check(s.pause.hint === "Esc — вернуться" && s.pause.items.save && !s.pause.items.save.disabled, "the pause: «Esc — вернуться», «Сохранить» free");
    await move(s.pause.items.save);
    await waitFor("hover «Сохранить»", (t) => t.pause.hovered === "save", 5000);
    await sleep(300);
    await shot("pause");
    await esc();
    s = await waitFor("Esc closes the pause", (t) => t.pause && !t.pause.open && !t.paused, 8000);
    check(!s.pause.open && !s.paused, "Esc again closes the pause, the game runs on");
    await waitFor("the walk ends", (t) => t.player && !t.player.walking, 120000);
    // Esc → «Сохранить» → slot 1 → «Назад» → «Продолжить».
    await esc();
    s = await waitFor("pause open again", (t) => t.pause && t.pause.open && t.pause.blur > 0.99, 8000);
    await click("pause «Сохранить»", s.pause.items.save);
    s = await waitFor("save slots", (t) => t.ui && t.ui.menu_open && t.ui.menu_mode === "save" && t.ui.buttons.Save1 && t.ui.buttons.Save1.x, 8000);
    await click("«Сохранить» slot 1", s.ui.buttons.Save1);
    s = await waitFor("slot 1 written", (t) => t.ui.slots && t.ui.slots["1"] && t.ui.slots["1"].text !== "Пусто", 8000);
    check(s.ui.slots["1"].text !== "Пусто", "slot 1 holds the save", s.ui.slots["1"].text);
    const saved = { x: s.player.x, y: s.player.y };
    await click("«Назад»", s.ui.buttons.CloseMenu);
    s = await waitFor("back to the pause", (t) => !t.ui.menu_open && t.pause.open, 8000);
    await click("pause «Продолжить»", s.pause.items.continue);
    s = await waitFor("pause closed", (t) => !t.pause.open && !t.paused, 8000);
    check(!s.pause.open, "«Продолжить» closes the pause");
    // Walk on, so the place left differs from slot 1.
    await click("walk on", { x: saved.x > 960 ? saved.x - 300 : saved.x + 300, y: saved.y });
    await waitFor("walked", (t) => t.player && !t.player.walking && Math.hypot(t.player.x - saved.x, t.player.y - saved.y) > 60, 120000);
    s = await state();
    const left = { x: s.player.x, y: s.player.y };
    // Esc → «В главное меню» → the title with «Продолжить» → back in the game where it was left.
    await esc();
    s = await waitFor("pause open (3)", (t) => t.pause && t.pause.open && t.pause.blur > 0.99, 8000);
    await click("pause «В главное меню»", s.pause.items.main_menu);
    s = await waitFor("the title again", (t) => t.title && t.title.open && t.title.items && t.title.items.continue, 10000);
    check(s.title.open && s.title.order[0] === "continue" && s.paused, "«В главное меню» → the title offers «Продолжить» first", `${s.title.order.join(", ")} → ${s.title.continue_slot}`);
    await sleep(600);
    await move(s.title.items.continue);
    await sleep(400);
    await shot("title_continue");
    await click("title «Продолжить»", s.title.items.continue);
    s = await waitFor("continued", (t) => !t.title.open && !t.paused && t.room === "Z1", 20000);
    const d = Math.hypot(s.player.x - left.x, s.player.y - left.y);
    check(!s.title.open && s.room === "Z1" && d < 3, "«Продолжить» loads the newest save — Agata where she was left", `slot ${s.title.continue_slot || "?"}, ${d.toFixed(1)} px off`);
  } catch (e) {
    check(false, `exception: ${e && e.stack ? e.stack : e}`);
  }
  check(errors.length === 0, "console: 0 errors / page errors", errors.slice(0, 5).join(" | "));
  const failed = checks.filter((c) => !c.ok);
  fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, errors }, null, 2));
  fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
  logLine(`${checks.length - failed.length}/${checks.length} checks passed`);
  await browser.close();
  server.close();
  process.exit(failed.length === 0 ? 0 : 1);
}

main();
