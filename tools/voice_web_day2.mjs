#!/usr/bin/env node
// Day two's voice in the WEB build with REAL clicks — the full voice-over of 23.10 (Director: «полную озвучку»).
//
//   node tools/voice_web_day2.mjs        (after tools/export_web.sh; port VOICE_PORT, default 8776)
//
// Starts from the morning of day two (`?start=day2`: day one done, its choices made), unlocks audio through the menu
// (music and sounds at 0 %, voice 100 %), SAVES into a menu slot, starts a NEW GAME (post office) and LOADS that slot —
// day two from a save — then walks with real
// clicks: house → street → mill yard; Pavel (M09): his voice, Agata's answer, «дальше» cuts and starts the next line;
// the mill wheel — the narrator (ZAKADR) reads the look. Checks the line on screen and the voice playing agree (line id,
// speaker), the signal leaves the page (output RMS), 0 console errors. Output: build/shots/voice_day2/{report.json,
// console.log, pavel.png}. Exit code 0 only when every check passed.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.VOICE_WEB_DIR ? path.resolve(ROOT, process.env.VOICE_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "build", "shots", "voice_day2");
const PORT = Number(process.env.VOICE_PORT || 8776);
const VIEW_W = Number(process.env.VOICE_VIEW_W || 960);
const VIEW_H = Math.round(VIEW_W * 9 / 16);
const S = VIEW_W / 1920;

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

// Runs in the page before Godot: taps the destination (stream worklet and sample buses alike).
const INIT_SCRIPT = () => {
  window.__analysers = [];
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    if (dest instanceof AudioDestinationNode && !this.__voiceTap) {
      this.__voiceTap = true;
      const an = this.context.createAnalyser();
      an.fftSize = 2048;
      origConnect.call(this, an);
      window.__analysers.push(an);
    }
    return origConnect.call(this, dest, ...rest);
  };
  // Peak of the short-term RMS over the last `ms`, sampled every 20 ms (a voice has pauses between words).
  window.__rmsWindow = (ms) => new Promise((resolve) => {
    let best = 0;
    const t0 = performance.now();
    const tick = () => {
      for (const an of window.__analysers) {
        const buf = new Float32Array(an.fftSize);
        an.getFloatTimeDomainData(buf);
        let s = 0;
        for (const v of buf) s += v * v;
        best = Math.max(best, Math.sqrt(s / buf.length));
      }
      if (performance.now() - t0 < ms) setTimeout(tick, 20);
      else resolve({ rms_db: best > 0 ? 20 * Math.log10(best) : -200, taps: window.__analysers.length });
    };
    tick();
  });
};

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
  const url = `http://127.0.0.1:${PORT}/index.html?start=day2`;
  const executablePath = findChromium();
  const browser = await chromium.launch({ headless: true, executablePath,
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=user-gesture-required"] });
  const context = await browser.newContext({ viewport: { width: VIEW_W, height: VIEW_H }, deviceScaleFactor: 1 });
  await context.addInitScript(INIT_SCRIPT);
  const page = await context.newPage();
  let leaving = false;
  page.on("console", (m) => { logLine(`console.${m.type()}: ${m.text()}`); if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => { logLine(`pageerror: ${e.message}`); errors.push(`pageerror: ${e.message}`); });
  page.on("requestfailed", (r) => {
    const aborted = /ERR_ABORTED/.test(r.failure()?.errorText || "");
    if (!(aborted && (leaving || /index\.(pck|wasm)$/.test(r.url())))) errors.push(`requestfailed ${r.url()}`);
  });

  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const voice = () => page.evaluate(() => (window.voiceState ? JSON.parse(JSON.stringify(window.voiceState)) : null));
  const music = () => page.evaluate(() => (window.musicState ? JSON.parse(JSON.stringify(window.musicState)) : null));
  const sfx = () => page.evaluate(() => (window.sfxState ? JSON.parse(JSON.stringify(window.sfxState)) : null));
  const rms = (ms) => page.evaluate((x) => window.__rmsWindow(x), ms);
  const waitFor = async (label, fn, pred, timeout = 30000) => {
    const t0 = Date.now();
    let v = null;
    while (Date.now() - t0 < timeout) {
      v = await fn();
      if (v && pred(v)) return v;
      await sleep(100);
    }
    failures.push(`${label}: timeout ${timeout} ms`);
    logLine(`FAIL ${label}: timeout; last ${JSON.stringify(v)?.slice(0, 400)}`);
    return v;
  };
  const click = async (label, pt) => {
    if (!pt || typeof pt.x !== "number") { failures.push(`${label}: no click target`); logLine(`FAIL ${label}: no target`); return false; }
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.click(pt.x * S, pt.y * S);
    return true;
  };
  const report = { url, steps: {} };

  try {
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 });
    let v = await waitFor("voiceState published", voice, (x) => x && typeof x.plays === "number", 15000);
    check(v && v.manifest_lines >= 300 && (v.errors || []).length === 0, "web build carries the full voice manifest",
      `${v?.manifest_lines} lines, errors ${JSON.stringify(v?.errors)}`);
    let s = await waitFor("start=day2: morning of day two in the house", state, (t) => t.room === "H1" && t.flags && t.flags.done_N01, 20000);
    check(s.room === "H1" && s.flags.done_N01 && !s.flags.done_M09, "?start=day2 — the house, day one done, day two not started",
      JSON.stringify({ room: s.room, done_N01: s.flags.done_N01 }));

    // «Меню» → the pause → «Настройки»: music and sounds at 0 % (clicks unlock the AudioContext), voice stays 100 %.
    await click("ui MenuButton", s.ui.buttons.MenuButton);
    s = await waitFor("pause open", state, (t) => t.pause && t.pause.open && t.pause.blur > 0.99 && t.pause.items.settings, 8000);
    await click("pause «Настройки»", s.pause.items.settings);
    s = await waitFor("settings open", state, (t) => t.ui && t.ui.menu_open && t.ui.music_slider && t.ui.voice_slider, 8000);
    await click("music slider at 0 %", { x: s.ui.music_slider.x + 1, y: s.ui.music_slider.y + s.ui.music_slider.h / 2 });
    await click("sound slider at 0 %", { x: s.ui.sfx_slider.x + 1, y: s.ui.sfx_slider.y + s.ui.sfx_slider.h / 2 });
    await waitFor("music muted", music, (x) => x.music_volume <= 0.02, 5000);
    check(s.ui.voice_slider.value === 100, "«Голос» at 100 %", JSON.stringify(s.ui.voice_slider));
    // A real save of this morning into a menu slot (pause «Сохранить»); then «В главное меню» → «Новая игра» and
    // pause «Загрузить» — day two starts from a save.
    await click("CloseMenu (back to the pause)", s.ui.buttons.CloseMenu);
    s = await waitFor("back to the pause", state, (t) => t.ui && !t.ui.menu_open && t.pause && t.pause.open, 8000);
    await click("pause «Сохранить»", s.pause.items.save);
    s = await waitFor("save slots open", state, (t) => t.ui && t.ui.menu_open && t.ui.menu_mode === "save", 8000);
    const saveKey = Object.keys(s.ui.buttons).filter((k) => k.startsWith("Save") && !/auto/i.test(k)).sort()[0];
    check(!!saveKey, "the menu offers a save slot", Object.keys(s.ui.buttons).join(", "));
    const slot = saveKey ? saveKey.slice(4) : "";
    await click(`save into slot ${slot}`, s.ui.buttons[saveKey]);
    s = await waitFor("saved hint", state, (t) => /Сохранено/.test(String(t.last_hint || "")), 8000);
    check(/Сохранено/.test(String(s.last_hint || "")), `saved into slot ${slot}`, String(s.last_hint || ""));
    // «Новая игра» wipes the state (the post office, day one), then «Загрузить» the slot: day two comes back from the save.
    // (Same page: across a page reload headless Chromium did not keep user:// — IndexedDB — in this harness.)
    await click("CloseMenu (back to the pause)", s.ui.buttons.CloseMenu);
    s = await waitFor("back to the pause", state, (t) => t.ui && !t.ui.menu_open && t.pause && t.pause.open, 8000);
    await click("pause «В главное меню»", s.pause.items.main_menu);
    s = await waitFor("title open", state, (t) => t.title && t.title.open && t.title.items && t.title.items.new_game, 8000);
    await click("title «Новая игра»", s.title.items.new_game);
    s = await waitFor("new game: post office", state, (t) => t.room === "Z1" && t.flags && !t.flags.done_N01, 20000);
    check(s.room === "Z1" && !s.flags.done_N01, "«Новая игра»: back at the post office, day one not done", JSON.stringify({ room: s.room }));
    await sleep(800);
    s = await state();
    await click("ui MenuButton", s.ui.buttons.MenuButton);
    s = await waitFor("pause open", state, (t) => t.pause && t.pause.open && t.pause.blur > 0.99 && t.pause.items.load, 8000);
    await click("pause «Загрузить»", s.pause.items.load);
    s = await waitFor("load slots open", state, (t) => t.ui && t.ui.menu_open && t.ui.buttons["Load" + slot], 8000);
    await sleep(400);
    await click(`load slot ${slot}`, s.ui.buttons["Load" + slot]);
    s = await waitFor("loaded: morning of day two", state, (t) => t.room === "H1" && t.flags && t.flags.done_N01 && !t.flags.done_M09, 20000);
    check(s.room === "H1" && s.flags.done_N01 && !s.flags.done_M09, "«Загрузить»: the morning of day two from the save",
      JSON.stringify({ room: s.room, done_N01: s.flags.done_N01 }));
    if (s.ui.menu_open && s.ui.buttons.CloseMenu) await click("CloseMenu", s.ui.buttons.CloseMenu);
    await sleep(800);
    // a morning line may be on screen (Tikhon) — click it away
    for (let i = 0; i < 8; i++) {
      s = await state();
      if (!s.beat || !s.beat.type) break;
      await click("continue", s.ui.dialogue_click || { x: 960, y: 900 });
      await sleep(500);
    }

    // House → street → mill yard, by the exits on screen.
    s = await state();
    await click("exit to the street", s.exits.Z2);
    s = await waitFor("street Z2", state, (t) => t.room === "Z2" && !t.transition, 40000);
    check(s.room === "Z2", "walked out to the street");
    await sleep(600);
    s = await state();
    await click("exit to the mill", s.exits.M1);
    s = await waitFor("mill yard M1", state, (t) => t.room === "M1" && !t.transition, 40000);
    check(s.room === "M1", "walked to the mill yard");
    await sleep(800);

    // Pavel: M09 — his voice, then Agata's.
    s = await state();
    await click("hotspot pavel", s.hotspots.pavel);
    v = await waitFor("M09_0 voice", voice, (x) => x.line === "M09_0" && x.playing, 40000);
    // probeState is republished on the game's clock (≈ every 2–3 s of the page in software WebGL): wait for this beat
    const beatOn = (id) => waitFor(`beat ${id} published`, state, (t) => t.beat && t.beat.line_id === id && t.ui && t.ui.dialogue_click, 10000);
    s = await beatOn("M09_0");
    check(v.line === "M09_0" && v.playing && v.speaker === "pavel", "M09_0: Pavel's voice plays with his line on screen",
      JSON.stringify({ line: v.line, speaker: v.speaker, beat: s.beat && s.beat.line_id, length: v.length }));
    check(s.beat && s.beat.line_id === v.line, "the subtitle on screen is the line that sounds", JSON.stringify(s.beat));
    const p0 = await rms(900);
    report.steps.pavel = { voice: v, rms: p0 };
    check(p0.rms_db > -40, "Pavel's voice leaves the page", `${p0.rms_db.toFixed(1)} dBFS`);
    await page.screenshot({ path: path.join(OUT_DIR, "pavel.png") });
    await click("continue → M09_1", s.ui.dialogue_click);
    v = await waitFor("M09_1 voice", voice, (x) => x.line === "M09_1" && x.playing, 8000);
    check(v.line === "M09_1" && v.playing && v.speaker === "agata", "M09_1: Agata answers in her voice", JSON.stringify({ line: v.line, speaker: v.speaker }));
    const heard = ["M09_0", "M09_1"];
    const a1 = await rms(700);
    check(a1.rms_db > -40, "Agata's voice leaves the page", `${a1.rms_db.toFixed(1)} dBFS`);
    s = await beatOn("M09_1");
    await click("continue → M09_2", s.ui.dialogue_click);
    v = await waitFor("M09_2 voice", voice, (x) => x.line === "M09_2" && x.playing, 8000);
    check(v.line === "M09_2" && v.speaker === "pavel", "M09_2: Pavel again", JSON.stringify({ line: v.line, speaker: v.speaker, length: v.length }));
    heard.push(v.line);
    // «дальше» in the middle of Pavel's long line (≈13 s): his voice stops, the next line starts at once.
    s = await beatOn("M09_2");
    v = await voice();
    const pos2 = v.position;
    await click("continue mid-line → M09_3", s.ui.dialogue_click);
    v = await waitFor("M09_3 voice", voice, (x) => x.line === "M09_3" && x.playing, 8000);
    const cut = (v.events || []).filter((e) => e.kind === "stop" && e.line === "M09_2");
    check(cut.length >= 1 && cut[cut.length - 1].reason === "advance" && v.line === "M09_3",
      "«дальше» cuts Pavel mid-line and starts the next line", `at ${pos2?.toFixed(2)} s; ${JSON.stringify(cut.slice(-1))}`);
    heard.push(v.line);
    // to the end of the conversation
    for (let i = 0; i < 20; i++) {
      s = await state();
      if (!s.beat || !s.beat.type) break;
      const vv = await voice();
      if (vv.line && vv.line !== heard[heard.length - 1]) heard.push(vv.line);
      if (!s.ui || !s.ui.dialogue_click) { await sleep(400); continue; }
      const opts = Object.values((s.ui && s.ui.options) || {});
      if (s.beat.type === "options" && opts.length) await click("option", opts[0]);
      else await click("continue", s.ui.dialogue_click || { x: 960, y: 900 });
      await sleep(450);
    }
    v = await waitFor("silence after M09", voice, (x) => !x.playing, 10000);
    const lastLines = (v.events || []).filter((e) => e.kind === "start").map((e) => e.line);
    for (const l of lastLines) if (l && !heard.includes(l)) heard.push(l);
    report.steps.m09_heard = heard;
    const want = Array.from({ length: 8 }, (_, i) => `M09_${i}`);
    check(want.every((l) => heard.includes(l)) && want.every((l, i) => i === 0 || heard.indexOf(l) > heard.indexOf(want[i - 1])),
      "all eight M09 lines voiced, in order", heard.join(", "));

    // The wheel: the narrator reads the look.
    s = await state();
    await click("hotspot wheel", s.hotspots.wheel);
    v = await waitFor("M1.wheel.look voice", voice, (x) => x.line === "M1.wheel.look" && x.playing, 30000);
    check(v.line === "M1.wheel.look" && v.playing && v.speaker === "narrator" && v.kind === "narration",
      "the wheel's look in the narrator's voice (ZAKADR)", JSON.stringify({ line: v.line, speaker: v.speaker, kind: v.kind }));
    const n1 = await rms(800);
    check(n1.rms_db > -40, "the narrator leaves the page", `${n1.rms_db.toFixed(1)} dBFS`);
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
  console.log(`\n==== voice web (day two): ${checks.length} checks, ${checks.filter((c) => c.ok).length} OK, ${failures.length} failure(s) ====`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main();
