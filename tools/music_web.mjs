#!/usr/bin/env node
// Background music in the WEB build with REAL clicks (MusicDirector, data/story/music.json).
//
//   node tools/music_web.mjs            (after tools/export_web.sh; port MUSIC_PORT, default 8773)
//
// Chromium runs with the real browsers' autoplay policy flag (user gesture required). An init script
// records every AudioContext the page creates and taps whatever is connected to the destination
// with an AnalyserNode, so the check sees the context state AND the signal that actually leaves
// the page; a dropout detector (AudioWorklet) behind Godot's output node counts buffer underruns
// (render quanta of exact zeros after the music started). MusicDirector publishes
// `window.musicState` (decks, themes, gains, bus volume). The viewport is 960×540 by default
// (MUSIC_VIEW_W): software WebGL draws a 1920×1080 frame in ≈0.9 s here, 960×540 in ≈0.15 s —
// still a slow machine; clicks are scaled from the game's 1920×1080 coordinates.
// Steps and expectations:
//   1. before any input: music locked, no deck playing (the AudioContext state is recorded: real
//      browsers keep it suspended; headless Chromium may already grant activation);
//   2. first click (on Tamara in Z1): context «running», theme «roads» plays, position grows,
//      output RMS above silence;
//   3. M01 dialogue: music ducked by duck_dialogue_db; after it — back to full;
//   4. Z1 → Z4 → Z2 (same theme): same deck, no restart; Z2 → H1: crossfade to «home»;
//      H1 → H2: same deck, no restart;
//   5. menu slider «Музыка» clicked at 50 % → Music bus −12 dB; the page is reloaded and the
//      setting comes back from user:// (IndexedDB) before any click;
//   6. the whole run: 0 console errors / page errors; dropouts and the longest main-thread task
//      during the room changes are reported next to the audio buffer length.
// Output: build/shots/music/{report.json, console.log, menu_slider.png}. Exit code 0 only when every
// check passed.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.MUSIC_WEB_DIR ? path.resolve(ROOT, process.env.MUSIC_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "build", "shots", "music");
const PORT = Number(process.env.MUSIC_PORT || 8773);
const STEP_TIMEOUT_MS = 40000;
const VIEW_W = Number(process.env.MUSIC_VIEW_W || 960);
const VIEW_H = Math.round(VIEW_W * 9 / 16);
const S = VIEW_W / 1920;   // game (1920×1080) → page coordinates

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

// Runs in the page before Godot: keeps every AudioContext and taps the destination.
const INIT_SCRIPT = () => {
  window.__audioContexts = [];
  window.__analysers = [];
  const Orig = window.AudioContext || window.webkitAudioContext;
  if (Orig) {
    const Wrapped = class extends Orig {
      constructor(...args) { super(...args); window.__audioContexts.push(this); }
    };
    window.AudioContext = Wrapped;
    window.webkitAudioContext = Wrapped;
  }
  // Dropout detector in the audio thread: after the music has started, a render quantum of exact
  // zeros is a buffer underrun (the main thread did not mix in time — Godot's single-threaded web
  // build mixes stream playback on the main thread). Godot outputs 16-bit-quantised PCM, music never
  // has digital silence mid-track, and faded decks sit at −80 dB, not at 0.
  window.__gaps = { gaps: 0, zeroQuanta: 0, quanta: 0, started: false };
  const GAP_SRC = `class GapDetector extends AudioWorkletProcessor {
    constructor() { super(); this.started = false; this.zeroRun = 0; this.gaps = 0; this.zeroQuanta = 0; this.quanta = 0; this.longest = 0; }
    process(inputs) {
      const ch = inputs[0] && inputs[0][0];
      if (!ch) return true;
      let nz = false;
      for (let i = 0; i < ch.length; i++) { if (ch[i] !== 0) { nz = true; break; } }
      this.quanta++;
      if (nz) { if (this.zeroRun > 0 && this.started) this.gaps++; this.longest = Math.max(this.longest, this.zeroRun); this.zeroRun = 0; this.started = true; }
      else if (this.started) { this.zeroRun++; this.zeroQuanta++; }
      if (this.quanta % 94 === 0) this.port.postMessage({ gaps: this.gaps, zeroQuanta: this.zeroQuanta, quanta: this.quanta, started: this.started, longestQuanta: this.longest, zeroRun: this.zeroRun });
      return true;
    }
  }
  registerProcessor("gap-detector", GapDetector);`;
  const gapUrl = URL.createObjectURL(new Blob([GAP_SRC], { type: "text/javascript" }));
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    if (dest instanceof AudioDestinationNode && !this.__musicTap) {
      this.__musicTap = true;
      const src = this;
      const ctx = this.context;
      const an = ctx.createAnalyser();
      an.fftSize = 4096;
      origConnect.call(src, an);
      window.__analysers.push(an);
      // Godot's stream output is its AudioWorkletNode («godot-processor»); sample playback buses
      // are plain gain nodes and carry nothing here.
      if (ctx.audioWorklet && !window.__gapNode && (typeof AudioWorkletNode !== "undefined" && src instanceof AudioWorkletNode)) {
        window.__gapNode = "pending";
        ctx.audioWorklet.addModule(gapUrl).then(() => {
          const det = new AudioWorkletNode(ctx, "gap-detector");
          const mute = ctx.createGain();
          mute.gain.value = 0;
          det.port.onmessage = (e) => { window.__gaps = e.data; };
          origConnect.call(src, det);
          origConnect.call(det, mute);
          origConnect.call(mute, ctx.destination);
          window.__gapNode = det;
        }).catch((e) => { window.__gapNode = "failed: " + e; });
      }
    }
    return origConnect.call(this, dest, ...rest);
  };
  window.__idbKeys = () => new Promise((res) => {
    const rq = indexedDB.open("/userfs");
    rq.onerror = () => res([]);
    rq.onsuccess = () => {
      try {
        const k = rq.result.transaction("FILE_DATA", "readonly").objectStore("FILE_DATA").getAllKeys();
        k.onsuccess = () => { res(k.result.map(String)); rq.result.close(); };
        k.onerror = () => res([]);
      } catch (_) { res([]); }
    };
  });
  window.__longTasks = [];
  try {
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) window.__longTasks.push({ t: e.startTime, d: e.duration });
    }).observe({ type: "longtask", buffered: true });
  } catch (_) {}
  window.__audioProbe = () => {
    let rms = 0;
    for (const an of window.__analysers) {
      const buf = new Float32Array(an.fftSize);
      an.getFloatTimeDomainData(buf);
      let s = 0;
      for (const v of buf) s += v * v;
      rms = Math.max(rms, Math.sqrt(s / buf.length));
    }
    return {
      contexts: window.__audioContexts.map((c) => ({ state: c.state, sampleRate: c.sampleRate, time: c.currentTime })),
      taps: window.__analysers.length,
      rms_db: rms > 0 ? 20 * Math.log10(rms) : -200,
      gaps: window.__gaps,
      gap_detector: typeof window.__gapNode === "string" ? window.__gapNode : (window.__gapNode ? "on" : "off"),
    };
  };
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
  const warnings = [];
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
  logLine(`chromium: ${executablePath || "(playwright default)"}; autoplay policy: user-gesture-required`);
  const browser = await chromium.launch({ headless: true, executablePath,
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=user-gesture-required"] });
  const context = await browser.newContext({ viewport: { width: VIEW_W, height: VIEW_H }, deviceScaleFactor: 1 });
  await context.addInitScript(INIT_SCRIPT);
  let leaving = false;  // requests aborted because the page is being closed are not errors
  const watch = (pg) => {
    pg.on("console", (m) => {
      logLine(`console.${m.type()}: ${m.text()}`);
      if (m.type() === "error") errors.push(m.text());
      if (m.type() === "warning") warnings.push(m.text());
    });
    pg.on("pageerror", (e) => { logLine(`pageerror: ${e.message}`); errors.push(`pageerror: ${e.message}`); });
    pg.on("requestfailed", (r) => {
      logLine(`requestfailed: ${r.url()} ${r.failure()?.errorText}`);
      // Godot's loader aborts its own streaming request for index.pck/index.wasm on every load
      // (seen without any music code too); a closing page aborts whatever is in flight.
      const aborted = /ERR_ABORTED/.test(r.failure()?.errorText || "");
      if (!(aborted && (leaving || /index\.(pck|wasm)$/.test(r.url())))) errors.push(`requestfailed ${r.url()}`);
    });
  };
  let page = await context.newPage();
  watch(page);

  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const music = () => page.evaluate(() => (window.musicState ? JSON.parse(JSON.stringify(window.musicState)) : null));
  const audio = () => page.evaluate(() => window.__audioProbe());
  const waitFor = async (label, fn, pred, timeout = STEP_TIMEOUT_MS) => {
    const t0 = Date.now();
    let v = null;
    while (Date.now() - t0 < timeout) {
      v = await fn();
      if (v && pred(v)) return v;
      await sleep(150);
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
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const finishDialogue = async (label) => {
    let idle = 0;
    for (let i = 0; i < 60 && idle < 6; i++) {
      const s = await state();
      const key = beatKey(s);
      if (!key) { idle += 1; await sleep(150); continue; }
      idle = 0;
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        await click(`${label}: option ${ids[0]}`, s.ui.options[ids[0]]);
      } else {
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 780 });
      }
      await waitFor(`${label}: beat advanced`, state, (t) => beatKey(t) !== key, 8000);
    }
  };
  const goExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { failures.push(`exit ${target} missing in ${s.room}`); return false; }
    await click(`exit → ${target}`, e);
    await waitFor(`room == ${target}`, state, (t) => t.room === target, 60000);
    await sleep(400);
    return (await state()).room === target;
  };
  const activeDeck = (m) => (m && m.active_deck >= 0 ? m.decks[m.active_deck] : null);
  const settled = (m, theme) => {
    const a = activeDeck(m);
    return a && a.theme === theme && a.playing && a.gain >= 0.999 && !m.decks[1 - m.active_deck].playing;
  };
  const report = { url, steps: {} };

  try {
    // --- 1. Before any input -------------------------------------------------------------------
    logLine(`open ${url}`);
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 });
    await waitFor("musicState published", music, (m) => m && m.target, 10000);
    await sleep(1500);
    let m = await music();
    let a = await audio();
    report.steps.before_click = { music: m, audio: a };
    check(a.contexts.length >= 1, "page created an AudioContext", `${a.contexts.length}`);
    report.steps.before_click.note = "AudioContext before the first click: " + a.contexts.map((c) => c.state).join(",") +
      (a.contexts.every((c) => c.state === "suspended") ? "" : " (headless Chromium granted activation; real browsers keep it suspended — the music waits for the click either way)");
    logLine(report.steps.before_click.note);
    check(m && m.unlocked === false && m.target === "roads", "before the first click: music locked, target roads", `unlocked=${m?.unlocked} target=${m?.target}`);
    check(m && !m.decks.some((d) => d.playing), "before the first click no deck plays");

    // --- 2. First click: Tamara (M01) --------------------------------------------------------
    const s0 = await state();
    await click("first click: hotspot tamara", s0.hotspots.tamara);
    a = await waitFor("AudioContext running after the click", audio, (x) => x.contexts.length && x.contexts.every((c) => c.state === "running"), 8000);
    check(a.contexts.every((c) => c.state === "running"), "after the first click the AudioContext is running", a.contexts.map((c) => c.state).join(","));
    m = await waitFor("roads playing", music, (x) => x.unlocked && activeDeck(x)?.theme === "roads" && activeDeck(x)?.playing, 5000);
    check(m.unlocked && activeDeck(m)?.theme === "roads" && activeDeck(m)?.playing, "after the click the theme of Z1 (roads) plays", JSON.stringify(activeDeck(m)));
    const p1 = activeDeck(m)?.position ?? 0;
    await sleep(1500);
    m = await music();
    const p2 = activeDeck(m)?.position ?? 0;
    check(p2 > p1 + 0.5, "playback position grows", `${p1.toFixed(2)} → ${p2.toFixed(2)} s in 1.5 s`);
    await sleep(1500);
    a = await audio();
    report.steps.after_click = { music: m, audio: a };
    check(a.taps > 0 && a.rms_db > -60, "signal leaves the page (output RMS above silence)", `${a.rms_db.toFixed(1)} dBFS, ${a.taps} tap(s)`);
    check(a.gap_detector === "on" && a.gaps.started, "dropout detector runs in the audio thread", `${a.gap_detector}`);
    const gaps0 = a.gaps.gaps;

    // --- 3. M01 dialogue: ducking --------------------------------------------------------------
    await waitFor("M01 dialogue", state, (t) => t.beat && t.beat.type === "line", 15000);
    await sleep(800);
    m = await music();
    const full = -7.0;  // roads volume_db (music.json)
    check(m.dialogue && Math.abs(m.duck_db - -5) < 0.3, "M01 line: music ducked by duck_dialogue_db", `duck ${m.duck_db?.toFixed(2)} dB`);
    check(Math.abs(activeDeck(m).volume_db - (full - 5)) < 0.3, "roads under the dialogue at −12 dB", `${activeDeck(m).volume_db.toFixed(2)} dB`);
    const roadsDeck = m.active_deck;
    const roadsStarts = activeDeck(m).starts;
    await finishDialogue("M01");
    await waitFor("M01 done", state, (t) => t.flags.done_M01, 10000);
    await sleep(800);
    m = await music();
    check(!m.dialogue && Math.abs(m.duck_db) < 0.05, "after the dialogue the music is back to full", `duck ${m.duck_db?.toFixed(2)} dB`);

    // --- 4. Rooms: same theme continues, other theme crossfades -----------------------------
    const longT0 = await page.evaluate(() => performance.now());
    let pos = activeDeck(m).position;
    for (const room of ["Z4", "Z2"]) {
      if (!(await goExit(room))) { check(false, `reach ${room}`); break; }
      m = await music();
      check(m.active_deck === roadsDeck && activeDeck(m).theme === "roads" && activeDeck(m).starts === roadsStarts && activeDeck(m).position > pos,
        `${room} (roads): same deck, no restart, position grows`, `deck ${m.active_deck} starts ${activeDeck(m).starts} pos ${activeDeck(m).position.toFixed(2)}`);
      pos = activeDeck(m).position;
    }
    if (await goExit("H1")) {
      m = await music();
      check(m.target === "home" && activeDeck(m).theme === "home" && m.active_deck !== roadsDeck, "H1: home starts on the other deck (crossfade)", `target ${m.target}`);
      m = await waitFor("home settled", music, (x) => settled(x, "home"), 8000);
      check(settled(m, "home") && m.decks[roadsDeck].paused, "H1: crossfade done, roads paused", JSON.stringify(m.decks.map((d) => [d.theme, d.playing, d.paused, d.gain.toFixed(2)])));
      const homeDeck = m.active_deck;
      const homeStarts = activeDeck(m).starts;
      pos = activeDeck(m).position;
      if (await goExit("H2")) {
        await sleep(600);
        m = await music();
        check(m.active_deck === homeDeck && activeDeck(m).starts === homeStarts && activeDeck(m).position > pos + 0.5 && m.target === "home",
          "H1 → H2 (home): same deck, no restart, position grows", `pos ${pos.toFixed(2)} → ${activeDeck(m).position.toFixed(2)}`);
      } else check(false, "reach H2");
    } else check(false, "reach H1");
    await sleep(500);
    a = await audio();
    report.steps.rooms = { music: m, audio: a };
    check(a.rms_db > -60, "signal still present after the room changes", `${a.rms_db.toFixed(1)} dBFS`);
    const longest = await page.evaluate((t0) => window.__longTasks.filter((x) => x.t >= t0).reduce((mx, x) => Math.max(mx, x.d), 0), longT0);
    report.steps.rooms.longest_task_ms = longest;
    report.steps.rooms.gaps = a.gaps;
    const bufferMs = m.output_latency * 1000;
    const gapText = `${a.gaps.gaps - gaps0} gap(s), ${a.gaps.zeroQuanta} silent quanta of ${a.gaps.quanta}, longest ${a.gaps.longestQuanta} × 128 frames; ` +
      `audio buffer (output latency) ${bufferMs.toFixed(0)} ms, longest main-thread task ${longest.toFixed(0)} ms`;
    report.steps.rooms.dropouts = gapText;
    if (longest > bufferMs) {
      // The single-threaded web build mixes on the main thread: a task longer than the buffer
      // starves it whatever the game does. Software WebGL on this 2-CPU container is such a case.
      logLine(`WARN dropouts not judged here — the main thread was blocked longer than the audio buffer: ${gapText}`);
      report.warnings = (report.warnings || []).concat([`dropouts not judged: ${gapText}`]);
    } else {
      check(a.gaps.gaps - gaps0 === 0, "no dropouts (buffer underruns) through dialogue and 4 room changes", gapText);
    }

    // --- 5. Menu slider → bus, saved in user:// and back after a reload ----------------------
    let s = await state();
    await click("ui MenuButton", s.ui.buttons.MenuButton);
    s = await waitFor("menu open with the music slider", state, (t) => t.ui && t.ui.menu_open && t.ui.music_slider, 5000);
    const r = s.ui.music_slider;
    // Godot's HSlider maps the click across the whole control width (grabber margins aside).
    await click("music slider at 50 %", { x: r.x + r.w * 0.5, y: r.y + r.h * 0.5 });
    m = await waitFor("volume ≈ 50 %", music, (x) => Math.abs(x.music_volume - 0.5) <= 0.03, 4000);
    check(Math.abs(m.music_volume - 0.5) <= 0.03 && Math.abs(m.bus_volume_db - 20 * Math.log10(m.music_volume * m.music_volume)) < 0.05,
      "slider at 50 % → music volume ≈ 0.5, Music bus ≈ −12 dB", `volume ${m.music_volume.toFixed(2)}, bus ${m.bus_volume_db.toFixed(2)} dB`);
    await sleep(500);
    await page.screenshot({ path: path.join(OUT_DIR, "menu_slider.png") });
    const chosen = m.music_volume;
    // Settings are written 0.5 s after the last change; Godot syncs user:// to IndexedDB on the
    // next frames.
    await waitFor("settings saved", music, (x) => x.settings_saves >= 1, 10000);
    const keys = await waitFor("settings.cfg in IndexedDB", () => page.evaluate(() => (window.__idbKeys ? window.__idbKeys() : [])),
      (k) => Array.isArray(k) && k.some((x) => x.endsWith("/settings.cfg")), 30000);
    check(Array.isArray(keys) && keys.some((x) => x.endsWith("/settings.cfg")), "settings.cfg reaches IndexedDB (/userfs)");
    leaving = true;
    await page.close();
    page = await context.newPage();
    watch(page);
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    leaving = false;
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 });
    m = await waitFor("musicState after reload", music, (x) => x && x.target, 10000);
    check(Math.abs(m.music_volume - chosen) < 0.001 && m.unlocked === false, "a new page load gets the volume back from user:// (IndexedDB), before any click",
      `volume ${m.music_volume?.toFixed(2)}, bus ${m.bus_volume_db?.toFixed(2)} dB`);
    report.steps.after_reload = { music: m };
  } catch (e) {
    failures.push(`exception: ${e && e.stack ? e.stack : e}`);
    logLine(`exception: ${e && e.stack ? e.stack : e}`);
  }

  check(errors.length === 0, "console: 0 errors / page errors", errors.slice(0, 5).join(" | "));
  report.checks = checks;
  report.console_errors = errors;
  report.console_warnings = warnings;
  report.failures = failures;
  fs.writeFileSync(path.join(OUT_DIR, "report.json"), JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, "console.log"), consoleLog.join("\n") + "\n");
  await browser.close();
  server.close();
  console.log(`\n==== music web: ${checks.length} checks, ${checks.filter((c) => c.ok).length} OK, ${failures.length} failure(s) ====`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main();
