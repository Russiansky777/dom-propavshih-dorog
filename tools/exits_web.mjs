#!/usr/bin/env node
// Exit hints in the WEB build with REAL mouse moves and clicks (Director 18.10: «Проход в галерею не
// интуитивен, что нужно нажать вниз»; in Z4 the street is down at the bottom edge too).
//
//   node tools/exits_web.mjs          (after tools/export_web.sh; port EXITS_PORT, default 8776;
//                                      EXITS_WEB_DIR — another build folder)
//
// Reads window.probeState.ui.exit_hints (GameUi.exit_hints_probe: marks, cursor kind, caption, reveal)
// and the canvas CSS cursor Godot sets from the cursor images (UiCursors; since 18.10 the cursor over an exit is
// the ordinary old-Russian arrow — the big exit arrows are gone, tools/ui_web.mjs checks the rest). Steps:
//   1. Z1 (post office): the pointer on the drawn door → the ordinary arrow (CSS url), caption «На улицу», no mark;
//   2. Space → every visible hotspot and exit named; gone after ≈1.5 s;
//   3. talk to Tamara (M01), out through the door to the lane Z4;
//   4. Z4: a down mark at the bottom edge, visible; pointer on it → mark lit, the same ordinary arrow,
//      caption «На улицу»; click on the mark → the street Z2;
//   5. Z2: marks left (lane) and right (mill); the porch door → H1;
//   6. H1: the gallery exit (mark or drawn door, as the H1 data has it) — pointer → its cursor and
//      «В галерею»; click → H3;
//   7. H3: the living-room exit — pointer → its cursor; click → H1;
//   8. pointer on the floor → the same ordinary arrow; 0 console errors.
// Output: build/shots/exits/{report.json, console.log, *.png}. Exit code 0 only when every check passed.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.EXITS_WEB_DIR ? path.resolve(ROOT, process.env.EXITS_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = process.env.EXITS_OUT_DIR ? path.resolve(ROOT, process.env.EXITS_OUT_DIR) : path.join(ROOT, "build", "shots", "exits");
const PORT = Number(process.env.EXITS_PORT || 8776);

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

  const server = await serve(WEB_DIR);
  const url = `http://127.0.0.1:${PORT}/index.html`;
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage"] });
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  let leaving = false;
  page.on("console", (m) => { logLine(`console.${m.type()}: ${m.text()}`); if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => { logLine(`pageerror: ${e.message}`); errors.push(`pageerror: ${e.message}`); });
  page.on("requestfailed", (r) => {
    const aborted = /ERR_ABORTED/.test(r.failure()?.errorText || "");
    if (!(aborted && (leaving || /index\.(pck|wasm)$/.test(r.url())))) errors.push(`requestfailed ${r.url()}`);
  });

  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const hints = async () => ((await state())?.ui?.exit_hints) || {};
  const cssCursor = () => page.evaluate(() => getComputedStyle(document.querySelector("#canvas")).cursor);
  const waitFor = async (label, pred, timeout = 30000) => {
    const t0 = Date.now();
    let s = null;
    while (Date.now() - t0 < timeout) {
      s = await state();
      if (s && pred(s)) return s;
      await sleep(120);
    }
    failures.push(`${label}: timeout ${timeout} ms`);
    logLine(`FAIL ${label}: timeout; room=${s?.room} beat=${JSON.stringify(s?.beat)?.slice(0, 200)}`);
    return s;
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const click = async (label, pt) => {
    if (!pt || typeof pt.x !== "number") { failures.push(`${label}: no click target`); logLine(`FAIL ${label}: no target`); return false; }
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 3 });
    await page.mouse.click(pt.x, pt.y);
    return true;
  };
  // Moves the pointer and waits until the published state shows the expected cursor kind (the probe
  // refreshes every 0.4 s of game time — slower than that under software GL), then lets the mark ease in.
  const hover = async (label, pt, kind = null) => {
    logLine(`hover ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 6 });
    if (kind !== null) {
      const t0 = Date.now();
      while (Date.now() - t0 < 8000) {
        const h = await hints();
        if (h.cursor === kind) break;
        await sleep(150);
      }
    }
    await sleep(700);
  };
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
  const waitWalkDone = (label) => waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 60000);
  const goRoom = async (label, pt, target) => {
    await click(label, pt);
    const s = await waitFor(`${label}: room == ${target}`, (t) => t.room === target, 45000);
    await sleep(900);
    await finishDialogue(`${label}: arrival`);
    return s && s.room === target;
  };
  const report = { url, steps: {} };

  try {
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 });
    await sleep(1500);
    let s = await state();
    check(s.room === "Z1" && s.ui && s.ui.exit_hints, "start in Z1, exit hints published", `room ${s.room}`);
    const cursorIdle = await cssCursor();
    report.steps.cursor_idle = cursorIdle;

    // 1. Drawn door in Z1.
    let h = s.ui.exit_hints;
    check(h.cues.Z4 && h.cues.Z4.dir === "door" && h.cues.Z4.x === undefined, "Z1: the post-office door is drawn in the art — no mark", JSON.stringify(h.cues.Z4));
    await hover("Z1 door → Z4", s.exits.Z4, "arrow");
    h = await hints();
    let css = await cssCursor();
    check(h.cursor === "arrow" && /url\(/.test(css), "Z1: the ordinary old-Russian arrow on the door (CSS image, no exit cursor)", `kind ${h.cursor}, css ${css.slice(0, 60)}…`);
    check(h.hover === "На улицу", "Z1: caption «На улицу»", h.hover);
    const cssDoor = css;
    await page.screenshot({ path: path.join(OUT_DIR, "web_Z1_door_hover.png") });

    // 2. Space.
    await page.mouse.move(960, 160);
    await sleep(500);
    await page.keyboard.press("Space");
    await sleep(500);
    s = await state();
    h = s.ui.exit_hints;
    const want = Object.entries(s.hotspots).filter(([, v]) => v.visible).map(([k]) => `hotspot:${k}`).concat(Object.keys(s.exits).map((k) => `exit:${k}`));
    const missing = want.filter((w) => !(h.revealed || []).includes(w));
    check(h.reveal && missing.length === 0, "Space: every visible hotspot and exit named", `${(h.revealed || []).length} shown; missing ${JSON.stringify(missing)}`);
    await page.screenshot({ path: path.join(OUT_DIR, "web_Z1_space.png") });
    await sleep(1600);
    h = await hints();
    check(!h.reveal, "the reveal ends after ≈1.5 s", JSON.stringify({ reveal: h.reveal }));

    // 3. Tamara, then out.
    s = await state();
    await click("hotspot tamara", s.hotspots.tamara);
    await waitFor("M01 starts", (t) => beatKey(t) !== "", 30000);
    await finishDialogue("M01");
    await waitFor("M01 done", (t) => t.flags.done_M01, 15000);
    s = await state();
    check(await goRoom("Z1 door → Z4", s.exits.Z4, "Z4"), "through the post-office door to the lane Z4");

    // 4. Z4: the street is down.
    s = await state();
    h = s.ui.exit_hints;
    const m = h.cues.Z2 || {};
    check(m.dir === "down" && m.y >= 1000 && m.alpha > 0.4, "Z4: a visible down mark at the bottom edge for the street", JSON.stringify(m));
    await page.mouse.move(960, 400);
    await sleep(300);
    await page.screenshot({ path: path.join(OUT_DIR, "web_Z4_marks.png") });
    await hover("Z4 street mark", { x: m.x, y: m.y }, "arrow");
    h = await hints();
    css = await cssCursor();
    check(h.cues.Z2.hot && h.cursor === "arrow" && css === cssDoor, "Z4: pointer on the mark — lit, the same ordinary arrow (no exit-arrow cursor)",
      `hot ${h.cues.Z2.hot}, kind ${h.cursor}, css ${css.slice(0, 50)}…`);
    check(h.hover === "На улицу", "Z4: caption «На улицу»", h.hover);
    await page.screenshot({ path: path.join(OUT_DIR, "web_Z4_street_hover.png") });
    check(await goRoom("Z4 street mark → Z2", { x: m.x, y: m.y }, "Z2"), "click on the mark → the street Z2");

    // 5. Z2.
    s = await state();
    h = s.ui.exit_hints;
    check(h.cues.Z4?.dir === "left" && h.cues.M1?.dir === "right", "Z2: marks left (lane) and right (mill)", JSON.stringify({ Z4: h.cues.Z4, M1: h.cues.M1 }));
    await page.screenshot({ path: path.join(OUT_DIR, "web_Z2_marks.png") });
    check(await goRoom("Z2 porch → H1", s.exits.H1, "H1"), "the porch door → H1");

    // 6. H1 → the gallery.
    s = await state();
    h = s.ui.exit_hints;
    const g = h.cues.H3 || {};
    check(g.dir && (g.dir === "door" || (g.alpha > 0.4 && typeof g.x === "number")), "H1: the gallery exit has a mark or is a drawn door", JSON.stringify(g));
    const gpt = typeof g.x === "number" ? { x: g.x, y: g.y } : s.exits.H3;
    await hover("H1 gallery exit", gpt, "arrow");
    h = await hints();
    css = await cssCursor();
    check(h.cursor === "arrow" && css === cssDoor, "H1: the ordinary arrow on the gallery exit", `kind ${h.cursor} (${g.dir}), css ${css.slice(0, 50)}…`);
    check(h.hover === "В галерею", "H1: caption «В галерею»", h.hover);
    await page.screenshot({ path: path.join(OUT_DIR, "web_H1_gallery_hover.png") });
    check(await goRoom("H1 → H3", gpt, "H3"), "click → the gallery H3");

    // 7. H3 → H1.
    s = await state();
    h = s.ui.exit_hints;
    const b = h.cues.H1 || {};
    const bpt = typeof b.x === "number" ? { x: b.x, y: b.y } : s.exits.H1;
    await hover("H3 living-room exit", bpt, "arrow");
    h = await hints();
    css = await cssCursor();
    check(h.cursor === "arrow" && css === cssDoor, "H3: the ordinary arrow on the living-room exit", `kind ${h.cursor} (${b.dir})`);
    await page.screenshot({ path: path.join(OUT_DIR, "web_H3_back_hover.png") });

    // 8. Floor → ordinary pointer.
    await hover("H3 floor", { x: 960, y: 880 }, "arrow");
    h = await hints();
    css = await cssCursor();
    check(h.cursor === "arrow" && css === cssDoor, "on the floor: the same old-Russian arrow", `kind '${h.cursor}', css ${css.slice(0, 50)}`);
    check(await goRoom("H3 → H1", bpt, "H1"), "click → back to H1");
  } catch (e) {
    failures.push(`exception: ${e && e.stack ? e.stack : e}`);
    logLine(`exception: ${e && e.stack ? e.stack : e}`);
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
  console.log(`\n==== exits web: ${checks.length} checks, ${checks.filter((c) => c.ok).length} OK, ${failures.length} failure(s) ====`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main();
