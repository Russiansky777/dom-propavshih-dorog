#!/usr/bin/env node
// Recorded voice in the WEB build with REAL clicks (VoiceDirector, data/story/voice.json — `window.voiceState`).
//
//   node tools/voice_web.mjs            (after tools/export_web.sh; port VOICE_PORT, default 8775)
//
// Chromium with the real browsers' autoplay policy (user gesture required). An init script taps
// everything connected to the AudioContext destination with an AnalyserNode (as tools/music_web.mjs),
// so the check hears the signal that actually leaves the page. To hear the voice alone, the first
// clicks set «Музыка» and «Звуки» to 0 % in the menu (they also unlock audio); the voice bus stays 100 %.
// Steps and expectations:
//   1. menu: music and sounds at 0 % → their buses muted; output silent;
//   2. click Tamara (Z1): M01 starts; the voice of M01_0 (Agata) plays — voiceState.line, playing;
//   3. «дальше» → M01_1 (Tamara): her voice plays, output RMS well above silence;
//   4. «дальше» mid-line → M01_1 is cut (event stop/advance), M01_2 plays;
//   5. after the scene no voice plays and the output falls silent again;
//   6. menu slider «Голос» at 50 % → Voice bus ≈ −12 dB;
//   7. the whole run: 0 console errors / page errors.
// Output: build/shots/voice/{report.json, console.log, tamara.png}. Exit code 0 only when every check passed.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.VOICE_WEB_DIR ? path.resolve(ROOT, process.env.VOICE_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "build", "shots", "voice");
const PORT = Number(process.env.VOICE_PORT || 8775);
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
  const url = `http://127.0.0.1:${PORT}/index.html`;
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
    check(v && v.manifest_lines >= 19 && (v.errors || []).length === 0, "web build carries the voice manifest", `${v?.manifest_lines} lines, errors ${JSON.stringify(v?.errors)}`);

    // 1. Music and sounds to 0 % (the menu clicks also unlock the AudioContext).
    let s = await state();
    await click("ui MenuButton", s.ui.buttons.MenuButton);
    s = await waitFor("menu open", state, (t) => t.ui && t.ui.menu_open && t.ui.music_slider && t.ui.voice_slider, 8000);
    const r0 = s.ui.music_slider;
    await click("music slider at 0 %", { x: r0.x + 1, y: r0.y + r0.h / 2 });
    const rs = s.ui.sfx_slider;
    await click("sound slider at 0 %", { x: rs.x + 1, y: rs.y + rs.h / 2 });
    const m = await waitFor("music muted", music, (x) => x.music_volume <= 0.02, 5000);
    const fx = await waitFor("sounds muted", sfx, (x) => x.sfx_volume <= 0.02, 5000);
    check(m.music_volume <= 0.02 && fx.sfx_volume <= 0.02, "music and sounds at 0 % for a clean voice measurement",
      `music ${m.music_volume?.toFixed(2)}, sounds ${fx.sfx_volume?.toFixed(2)}`);
    check(s.ui.voice_slider && s.ui.voice_slider.value === 100, "menu shows «Голос» at 100 %", JSON.stringify(s.ui.voice_slider));
    await click("CloseMenu", s.ui.buttons.CloseMenu);
    await sleep(800);
    const quiet0 = await rms(600);
    report.steps.silence_before = quiet0;
    check(quiet0.rms_db < -60, "before the dialogue the output is silent", `${quiet0.rms_db.toFixed(1)} dBFS, ${quiet0.taps} tap(s)`);

    // 2. Tamara → M01, Agata's first line.
    s = await state();
    await click("hotspot tamara", s.hotspots.tamara);
    v = await waitFor("M01_0 voice", voice, (x) => x.line === "M01_0" && x.playing, 30000);
    check(v.line === "M01_0" && v.playing && v.speaker === "agata", "M01_0: Agata's voice plays with her line", JSON.stringify({ line: v.line, speaker: v.speaker, mode: v.mode }));
    const a0 = await rms(500);
    check(a0.rms_db > -40, "Agata's voice leaves the page", `${a0.rms_db.toFixed(1)} dBFS`);

    // 3. «дальше» → Tamara.
    s = await state();
    await click("continue → M01_1", s.ui.dialogue_click);
    v = await waitFor("M01_1 voice", voice, (x) => x.line === "M01_1" && x.playing, 8000);
    check(v.line === "M01_1" && v.playing && v.speaker === "tamara" && v.mode === "plain", "M01_1: Tamara's voice plays", JSON.stringify({ line: v.line, speaker: v.speaker, length: v.length }));
    const t1 = await rms(1200);
    report.steps.tamara = { voice: v, rms: t1 };
    check(t1.rms_db > -40, "Tamara's voice leaves the page (output RMS)", `${t1.rms_db.toFixed(1)} dBFS`);
    const mm = await music();
    check(mm.dialogue && Math.abs(mm.duck_db - -5) < 0.3, "music stays ducked while she speaks", `duck ${mm.duck_db?.toFixed(2)} dB`);
    await page.screenshot({ path: path.join(OUT_DIR, "tamara.png") });

    // 4. «дальше» mid-line → cut, next line.
    v = await voice();
    const posAtClick = v.position;
    s = await state();
    await click("continue mid-line → M01_2", s.ui.dialogue_click);
    v = await waitFor("M01_2 voice", voice, (x) => x.line === "M01_2" && x.playing, 8000);
    const cut = (v.events || []).filter((e) => e.kind === "stop" && e.line === "M01_1");
    check(cut.length >= 1 && cut[cut.length - 1].reason === "advance", "the click cuts Tamara mid-line", `at ${posAtClick?.toFixed(2)} of ${report.steps.tamara.voice.length?.toFixed(2)} s; ${JSON.stringify(cut.slice(-1))}`);
    check(v.line === "M01_2" && v.playing, "M01_2 (Agata) starts at once", JSON.stringify({ line: v.line, speaker: v.speaker }));

    // 5. End of the scene: silence.
    s = await state();
    await click("continue → end of M01", s.ui.dialogue_click);
    await waitFor("M01 done", state, (t) => t.flags.done_M01, 10000);
    for (let i = 0; i < 6; i++) {
      s = await state();
      if (!s.beat || !s.beat.type) break;
      await click("continue (narration)", s.ui.dialogue_click || { x: 960, y: 900 });
      await sleep(400);
    }
    v = await waitFor("no voice after the scene", voice, (x) => !x.playing, 8000);
    check(!v.playing, "after the scene no voice plays", JSON.stringify({ line: v.line, plays: v.plays }));
    await sleep(500);
    const quiet1 = await rms(600);
    check(quiet1.rms_db < -60, "the output falls silent again", `${quiet1.rms_db.toFixed(1)} dBFS`);

    // 6. «Голос» at 50 %.
    s = await state();
    await click("ui MenuButton", s.ui.buttons.MenuButton);
    s = await waitFor("menu open", state, (t) => t.ui && t.ui.menu_open && t.ui.voice_slider, 8000);
    const rv = s.ui.voice_slider;
    await click("voice slider at 50 %", { x: rv.x + rv.w * 0.5, y: rv.y + rv.h * 0.5 });
    v = await waitFor("voice volume ≈ 50 %", voice, (x) => Math.abs(x.voice_volume - 0.5) <= 0.03, 4000);
    check(Math.abs(v.voice_volume - 0.5) <= 0.03 && Math.abs(v.bus_volume_db - 20 * Math.log10(v.voice_volume * v.voice_volume)) < 0.05,
      "«Голос» at 50 % → Voice bus ≈ −12 dB", `volume ${v.voice_volume?.toFixed(2)}, bus ${v.bus_volume_db?.toFixed(2)} dB`);
    report.steps.final_voice = v;
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
  console.log(`\n==== voice web: ${checks.length} checks, ${checks.filter((c) => c.ok).length} OK, ${failures.length} failure(s) ====`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main();
