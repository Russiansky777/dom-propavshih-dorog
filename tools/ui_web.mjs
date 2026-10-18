#!/usr/bin/env node
// Interface remarks of Director 18.10 in the WEB build, with REAL mouse moves and clicks:
//   «старорусский курсор»; the big exit arrow cursor removed; a destination icon at the exit caption;
//   the hint («Подсказка») in large letters with the Space tip; «ПОЧТА» on the post-office sign in Z4.
//
//   node tools/ui_web.mjs             (after tools/export_web.sh; port UI_WEB_PORT, default 8777;
//                                      UI_WEB_DIR — another build folder, UI_WEB_OUT — output folder)
//
// Reads window.probeState.ui.exit_hints (GameUi.exit_hints_probe: cursor kind, caption, icon, rects, the
// hint panel) and the canvas CSS cursor Godot sets from the cursor images (UiCursors). The cursor image
// itself is fetched from its blob URL and checked (32×32, dark ink + cream contour); for the frames it is
// laid over the page at the pointer (an <img>, pointer-events none) — a headless screenshot has no OS
// cursor. Steps:
//   1. Z1, pointer on the wall: CSS cursor = the old-Russian arrow image (not the browser arrow);
//   2. Tamara → another image (talk), the letters → another one (look);
//   3. the post-office door (exit): the SAME arrow image as on the wall (no exit arrow cursor), caption
//      «На улицу» with the icon «street» left of it, in the frame;
//   4. Space: names with icons;
//   5. «Подсказка»: panel with text ≥ 36 px of the 1920 canvas, the Space tip; a click puts it away;
//   6. M01 with Tamara, out to Z4: the sign «ПОЧТА» (frame + close crop), the street mark → icon + caption;
//   7. a 1280×720 window: the hint panel fits, its text ≥ 24 screen px;
//   0 console errors.
// Output: build/shots/ui/{report.json, console.log, *.png}. Exit code 0 only when every check passed.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.UI_WEB_DIR ? path.resolve(ROOT, process.env.UI_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = process.env.UI_WEB_OUT ? path.resolve(ROOT, process.env.UI_WEB_OUT) : path.join(ROOT, "build", "shots", "ui");
const PORT = Number(process.env.UI_WEB_PORT || 8777);
const ONLY = process.env.UI_WEB_ONLY || "";   // "space": stop after the reveal frame (quick re-shoot)

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript",
  ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png",
  ".json": "application/json", ".css": "text/css", ".ico": "image/x-icon",
};

function serve(dir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) { res.writeHead(403); return res.end(); }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, {
        "Content-Type": MIME[path.extname(file)] || "application/octet-stream",
        "Content-Length": st.size,
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "require-corp",
        "Cache-Control": "no-store",
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
  const consoleLog = [];
  const logLine = (s) => { const line = `[${new Date().toISOString()}] ${s}`; consoleLog.push(line); console.log(line); };
  const errors = [];
  const checks = [];
  const failures = [];
  const check = (ok, label, detail = "") => {
    checks.push({ ok: !!ok, label, detail });
    logLine(`${ok ? "OK  " : "FAIL"} ${label}${detail ? " — " + detail : ""}`);
    if (!ok) failures.push(`${label}${detail ? " — " + detail : ""}`);
    return !!ok;
  };
  const report = { steps: {} };

  const server = await serve(WEB_DIR);
  const url = `http://127.0.0.1:${PORT}/index.html`;
  report.url = url;
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage"] });
  let leaving = false;

  async function openPage(w, h) {
    const context = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    const page = await context.newPage();
    page.setDefaultTimeout(150000);   // software GL on a shared 2-core box: frames can take long
    page.on("console", (m) => { logLine(`console.${m.type()}: ${m.text()}`); if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => { logLine(`pageerror: ${e.message}`); errors.push(`pageerror: ${e.message}`); });
    page.on("requestfailed", (r) => {
      const aborted = /ERR_ABORTED/.test(r.failure()?.errorText || "");
      if (!(aborted && (leaving || /index\.(pck|wasm)$/.test(r.url())))) errors.push(`requestfailed ${r.url()}`);
    });
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 120000 });
    await sleep(1500);
    return page;
  }

  // Canvas px of the 1920×1080 game → page px (the canvas fills the viewport, aspect keep).
  const toPage = (page, k) => (pt) => ({ x: pt.x * k, y: pt.y * k });

  try {
    const page = await openPage(1920, 1080);
    const P = toPage(page, 1.0);
    const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
    const hints = async () => ((await state())?.ui?.exit_hints) || {};
    const cssCursor = () => page.evaluate(() => getComputedStyle(document.querySelector("#canvas")).cursor);
    let mouse = { x: 0, y: 0 };
    const move = async (pt, steps = 6) => { mouse = P(pt); await page.mouse.move(mouse.x, mouse.y, { steps }); };
    const waitFor = async (label, pred, timeout = 30000) => {
      const t0 = Date.now();
      let s = null;
      while (Date.now() - t0 < timeout) {
        s = await state();
        if (s && pred(s)) return s;
        await sleep(120);
      }
      failures.push(`${label}: timeout ${timeout} ms`);
      logLine(`FAIL ${label}: timeout; room=${s?.room}`);
      return s;
    };
    const hover = async (label, pt, pred) => {
      logLine(`hover ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
      await move(pt);
      const t0 = Date.now();
      while (Date.now() - t0 < 8000) {
        const h = await hints();
        if (pred(h)) break;
        await sleep(150);
      }
      await sleep(600);
      return hints();
    };
    const click = async (label, pt) => {
      if (!pt || typeof pt.x !== "number") { failures.push(`${label}: no click target`); return false; }
      logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
      await move(pt, 3);
      await page.mouse.click(mouse.x, mouse.y);
      return true;
    };
    const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
    const finishDialogue = async (label) => {
      let idle = 0;
      for (let i = 0; i < 40 && idle < 6; i++) {
        const s = await state();
        const key = beatKey(s);
        if (!key) { idle += 1; await sleep(150); continue; }
        idle = 0;
        if (s.beat.type === "options") {
          const ids = Object.keys(s.ui.options || {});
          await click(`${label}: option ${ids[0]}`, s.ui.options[ids[0]]);
        } else {
          await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 900 });
        }
        await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 8000);
      }
    };
    // The CSS cursor image: size, ink / cream pixel counts, hot spot; saved as PNG.
    const cursorInfo = async (css, name) => {
      const m = /url\("?([^")]+)"?\)\s*(\d+)?\s*(\d+)?/.exec(css || "");
      if (!m) return null;
      const info = await page.evaluate(async ([src]) => {
        const img = new Image();
        img.src = src;
        await img.decode();
        const c = document.createElement("canvas");
        c.width = img.width; c.height = img.height;
        const g = c.getContext("2d");
        g.drawImage(img, 0, 0);
        const d = g.getImageData(0, 0, c.width, c.height).data;
        let ink = 0, cream = 0;
        for (let i = 0; i < d.length; i += 4) {
          if (d[i + 3] < 230) continue;
          if (Math.abs(d[i] - 0x3d) < 20 && Math.abs(d[i + 1] - 0x25) < 20 && Math.abs(d[i + 2] - 0x13) < 20) ink++;
          else if (Math.abs(d[i] - 0xf3) < 20 && Math.abs(d[i + 1] - 0xe5) < 20 && Math.abs(d[i + 2] - 0xc4) < 20) cream++;
        }
        return { w: img.width, h: img.height, ink, cream, png: c.toDataURL("image/png") };
      }, [m[1]]);
      info.hx = Number(m[2] || 0); info.hy = Number(m[3] || 0); info.src = m[1];
      fs.writeFileSync(path.join(OUT_DIR, `css_cursor_${name}.png`), Buffer.from(info.png.split(",")[1], "base64"));
      delete info.png;
      return info;
    };
    // Lay the current CSS cursor image over the page at the pointer, take the frame, remove it.
    const shot = async (name, clip = null) => {
      const css = await cssCursor();
      const m = /url\("?([^")]+)"?\)\s*(\d+)?\s*(\d+)?/.exec(css || "");
      if (m) {
        await page.evaluate(([src, x, y]) => {
          const el = document.createElement("img");
          el.id = "__cursor_overlay"; el.src = src;
          el.style.cssText = `position:fixed;left:${x}px;top:${y}px;pointer-events:none;z-index:99999;image-rendering:pixelated`;
          document.body.appendChild(el);
        }, [m[1], mouse.x - Number(m[2] || 0), mouse.y - Number(m[3] || 0)]);
        await sleep(80);
      }
      const opts = { path: path.join(OUT_DIR, `${name}.png`) };
      if (clip) opts.clip = clip;
      await page.screenshot(opts);
      await page.evaluate(() => document.getElementById("__cursor_overlay")?.remove());
    };
    const inFrame = (r) => r.length === 4 && r[0] >= 0 && r[1] >= 80 && r[0] + r[2] <= 1920 && r[1] + r[3] <= 1080;

    let s = await state();
    check(s.room === "Z1" && s.ui && s.ui.exit_hints, "start in Z1, probe published", `room ${s.room}`);

    // 1. The ordinary pointer: an image, not the browser arrow.
    let h = {};
    for (const pt of [{ x: 960, y: 900 }, { x: 600, y: 940 }, { x: 960, y: 170 }]) {
      h = await hover("Z1 empty spot", pt, (t) => t.cursor === "arrow" && t.hover === "");
      if (h.cursor === "arrow" && h.hover === "") break;
    }
    check(h.cursor === "arrow" && h.hover === "", "pointer on an empty spot", JSON.stringify({ cursor: h.cursor, hover: h.hover }));
    const cssArrow = await cssCursor();
    const arrow = await cursorInfo(cssArrow, "arrow");
    report.steps.css_arrow = cssArrow.slice(0, 80);
    check(arrow && arrow.w === 32 && arrow.h === 32 && arrow.ink > 20 && arrow.cream > 20,
      "the ordinary pointer is the old-Russian arrow image (32×32, ink + cream)", JSON.stringify(arrow));
    check(arrow && arrow.hx <= 3 && arrow.hy <= 3, "its hot spot is at the tip", arrow ? `${arrow.hx}, ${arrow.hy}` : "");

    // 2. Character → talk, object → look.
    h = await hover("Tamara", s.hotspots.tamara, (t) => t.cursor === "talk");
    let css = await cssCursor();
    const talk = await cursorInfo(css, "talk");
    check(h.cursor === "talk" && talk && css !== cssArrow && talk.w === 32, "Tamara: arrow with a banderole (another image)", `kind ${h.cursor}`);
    await shot("ui_web_talk");
    h = await hover("letters", s.hotspots.letters, (t) => t.cursor === "look");
    css = await cssCursor();
    const look = await cursorInfo(css, "look");
    check(h.cursor === "look" && look && css !== cssArrow && css !== talk?.src && look.w === 32, "letters: «перст» (another image)", `kind ${h.cursor}`);
    await shot("ui_web_look");

    // 3. The post-office door: the same arrow, caption + icon.
    h = await hover("Z1 door → Z4", s.exits.Z4, (t) => t.hover === "На улицу" && t.hover_icon !== "");
    css = await cssCursor();
    check(h.cursor === "arrow" && css === cssArrow, "exit: the ordinary arrow — no exit-arrow cursor", `kind ${h.cursor}, same css ${css === cssArrow}`);
    check(h.hover === "На улицу" && h.hover_icon === "street", "exit: caption «На улицу» with the icon «street»", `${h.hover} / ${h.hover_icon}`);
    check(h.icon_rect.length === 4 && h.icon_rect[0] + h.icon_rect[2] <= h.hover_rect[0] + 0.5 && inFrame(h.icon_rect) && inFrame(h.hover_rect),
      "icon left of the caption, both in the frame", JSON.stringify({ icon: h.icon_rect, caption: h.hover_rect }));
    await shot("ui_web_Z1_exit_icon");

    // 4. Space.
    await move({ x: 960, y: 900 });
    await sleep(400);
    await page.keyboard.press("Space");
    await sleep(450);
    // The reveal lasts 1.5 s of game time — freeze the tree for the frame (software GL frames are slow).
    await page.evaluate(() => window.probePause && window.probePause(true));
    await sleep(300);
    h = await hints();
    check(h.reveal, "Space: reveal on", JSON.stringify(h.revealed));
    await shot("ui_web_Z1_space");
    await page.evaluate(() => window.probePause && window.probePause(false));
    await sleep(1600);
    if (ONLY === "space") { await page.close(); throw new Error("__only_space__"); }

    // 5. The hint panel.
    s = await state();
    await click("Подсказка", s.ui.buttons.HintButton);
    s = await waitFor("hint panel shown", (t) => t.ui.exit_hints.hint_panel && t.ui.exit_hints.hint_panel.visible, 8000);
    let hp = s.ui.exit_hints.hint_panel;
    check(hp.visible && hp.text_px >= 36, "hint text large (≥ 36 px of the 1920 canvas)", `${hp.text_px} px`);
    check(hp.tip === "Пробел — показать все места и действия", "the Space tip in the hint window", hp.tip);
    check(inFrame(hp.rect), "hint panel in the frame under the bar", JSON.stringify(hp.rect));
    report.steps.hint_1920 = hp;
    await move({ x: 600, y: 960 });   // empty floor (not the drawings on the table: a click there is a look)
    await sleep(300);
    await shot("ui_web_hint_1920");
    await page.mouse.click(mouse.x, mouse.y);
    s = await waitFor("hint panel away after a click", (t) => !t.ui.exit_hints.hint_panel.visible, 6000);
    check(!s.ui.exit_hints.hint_panel.visible, "a click puts the hint away");
    await waitFor("walk done", (t) => t.player && !t.player.walking, 30000);

    // 6. Tamara (M01), out to Z4: the sign and the street mark.
    s = await state();
    await click("hotspot tamara", s.hotspots.tamara);
    // Software GL walks slowly: advance every line of M01 until its flag is set.
    const tm = Date.now();
    while (Date.now() - tm < 90000) {
      const t = await state();
      if (t.flags.done_M01 && !beatKey(t)) break;
      if (t.beat && t.beat.type === "line") { await click("M01: continue", t.ui.dialogue_click || { x: 960, y: 900 }); await sleep(600); }
      else if (t.beat && t.beat.type === "options") { const ids = Object.keys(t.ui.options || {}); await click(`M01: option ${ids[0]}`, t.ui.options[ids[0]]); await sleep(600); }
      await sleep(200);
    }
    check((await state()).flags.done_M01, "M01 with Tamara done");
    s = await state();
    await click("Z1 door → Z4", s.exits.Z4);
    s = await waitFor("room Z4", (t) => t.room === "Z4", 45000);
    await sleep(1200);
    await finishDialogue("Z4 arrival");
    check(s.room === "Z4", "through the post-office door to the lane Z4");
    await move({ x: 1000, y: 470 });
    await sleep(600);
    await page.screenshot({ path: path.join(OUT_DIR, "ui_web_Z4_sign_frame.png") });
    await page.screenshot({ path: path.join(OUT_DIR, "ui_web_Z4_sign_crop.png"), clip: { x: 230, y: 180, width: 240, height: 180 } });
    h = await hints();
    const m = h.cues.Z2 || { x: 840, y: 1036 };
    h = await hover("Z4 street mark", { x: m.x, y: m.y }, (t) => t.hover === "На улицу" && t.hover_icon !== "");
    css = await cssCursor();
    check(h.cursor === "arrow" && css === cssArrow, "Z4 street mark: the ordinary arrow", `kind ${h.cursor}`);
    check(h.cues.Z2.hot && h.hover_icon === "street" && inFrame(h.icon_rect) && h.icon_rect[0] + h.icon_rect[2] <= h.hover_rect[0] + 0.5,
      "Z4: mark lit, caption with its icon, in the frame", JSON.stringify({ icon: h.icon_rect, caption: h.hover_rect }));
    await shot("ui_web_Z4_street_hover");
    s = await state();
    h = await hover("Z4 side porch → H3", s.exits.H3, (t) => t.hover_icon === "door");
    check(h.hover_icon === "door" && h.cursor === "arrow", "Z4 side porch: icon «door», ordinary arrow", `${h.hover} / ${h.hover_icon}`);
    await shot("ui_web_Z4_porch_hover");
    await page.close();

    // 7. 1280×720: the hint panel.
    const small = await openPage(1280, 720);
    const k = 1280 / 1920;
    const st2 = () => small.evaluate(() => JSON.parse(JSON.stringify(window.probeState)));
    let s2 = await st2();
    const b = s2.ui.buttons.HintButton;
    await small.mouse.move(b.x * k, b.y * k, { steps: 4 });
    await small.mouse.click(b.x * k, b.y * k);
    const t0 = Date.now();
    while (Date.now() - t0 < 8000) {
      s2 = await st2();
      if (s2.ui.exit_hints.hint_panel.visible) break;
      await sleep(150);
    }
    hp = s2.ui.exit_hints.hint_panel;
    check(hp.visible && hp.text_px * k >= 24, "1280×720: hint text ≥ 24 screen px", `${(hp.text_px * k).toFixed(1)} px`);
    check(inFrame(hp.rect), "1280×720: hint panel in the frame", JSON.stringify(hp.rect));
    await small.mouse.move(900, 470);
    await sleep(400);
    await small.screenshot({ path: path.join(OUT_DIR, "ui_web_hint_1280x720.png") });
    report.steps.hint_1280 = hp;
    await small.close();
  } catch (e) {
    if (String(e && e.message) === "__only_space__") {
      logLine("UI_WEB_ONLY=space: stopped after the reveal frame");
    } else {
    failures.push(`exception: ${e && e.stack ? e.stack : e}`);
    logLine(`exception: ${e && e.stack ? e.stack : e}`);
    }
  }

  check(errors.length === 0, "console: 0 errors / page errors", errors.slice(0, 5).join(" | "));
  report.checks = checks;
  report.console_errors = errors;
  report.failures = failures;
  fs.writeFileSync(path.join(OUT_DIR, "report.json"), JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, "console.log"), consoleLog.join("\n") + "\n");
  leaving = true;
  await browser.close();
  server.close();
  console.log(`\n==== ui web: ${checks.length} checks, ${checks.filter((c) => c.ok).length} OK, ${failures.length} failure(s) ====`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main();
