#!/usr/bin/env node
// Blocks 3–5 (M3) in the WEB build with REAL mouse input (window.probeState), from the start points of
// data/story/start_points.json (the same links as in Docs/ACCEPTANCE_M3.md):
//
//   tools/export_web.sh && node tools/olkhovka_web.mjs      (OLKH_WEB_DIR — another build dir; OLKH_PORT, default 8779)
//
//   A  ?start=olkhovka — the far pier → «Тропа к улице» → O4 at night (M19: Mitya knocks, mother on the porch) → her
//      room O3 at night; a click on the clock (M19c: the watch against the clock, Nina's twenty years at the hand
//      mirror), M20 by itself (Ilya «Ты не выросла», Ulyana, the wife) → the morning; a click on Nina → M21.
//   B  ?start=span — the turn Z3: M25 starts by itself, the windlass close-up opens; «Пускай» and no stop → the log
//      knocks against the stone (bumped, no penalty), «Пускай» does nothing until «Подымай»; then «Пускай» → «Стой»
//      at the ring → laid; the inscription «Ольховка — Заречье»; the frame with the log on the pier.
//   C  ?start=epilogue — M26 «через три недели, в среду»: every frame (EP_tamara … EP_dinner) in story order, the
//      last line is Ulyana's «А завтра тоже можно прийти?», the dinner frame stays with «Конец», the traces and
//      «Начать заново»; a click on it → a new game at the post office.
// Frames: Docs/evidence/M3/*.png. Exit code 0 only when every step reached its state and the console has no
// errors (Godot warnings are listed, not counted). Log: build/shots/olkhovka/console.log, report.json there.

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
const WEB_DIR = process.env.OLKH_WEB_DIR ? path.resolve(ROOT, process.env.OLKH_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "M3");
const LOG_DIR = path.join(ROOT, "build", "shots", "olkhovka");
const PORT = Number(process.env.OLKH_PORT || 8779);
// The windlass moves in game time; swiftshader on a small machine runs the page at ~1–2 fps (physics capped at 8
// steps a frame), so the log can take minutes of real time to come down (measured 23.10: ~60× slower than game time) — wait for states that long.
const SLOW = Number(process.env.OLKH_SLOW_MS || 600000);

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
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}. Run tools/export_web.sh first.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.mkdirSync(LOG_DIR, { recursive: true });
  const log = [];
  const logLine = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const failures = [];
  const checks = [];
  const check = (ok, msg) => { checks.push({ ok: !!ok, msg }); logLine(`${ok ? "OK  " : "FAIL"} ${msg}`); if (!ok) failures.push(msg); };
  let consoleErrors = 0;
  const consoleWarnings = [];
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  let page = null;
  const state = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));
  const waitFor = async (label, pred, timeout = 60000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(150);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)} frame=${JSON.stringify(s?.frame?.frame)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `${name}.png`);
    // swiftshader on a small machine: a 1920x1080 WebGL frame can take long while the game runs — wait for it.
    await page.screenshot({ path: file, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.speaker || ""}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const waitIdle = async (label) => {
    const before = await state();
    const t0 = Date.now();
    while (Date.now() - t0 < 4000) {
      const s = await state();
      if (s && (s.player.walking || s.player.acting || beatKey(s) !== beatKey(before) || s.room !== before.room ||
          Math.hypot(s.player.x - before.player.x, s.player.y - before.player.y) > 2)) break;
      await sleep(100);
    }
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 60000);
  };
  /** Clicks through beats (options from `choices` in order) until `done(state)` or `quietMs` without a beat.
   *  onBeat(state) sees every new beat. Returns the lines «speaker: text». */
  const playThrough = async (label, { choices = [], done = null, quietMs = 4000, timeout = 240000, onBeat = null } = {}) => {
    const lines = [];
    const t0 = Date.now();
    let quietSince = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (done && s && done(s)) return lines;
      const key = beatKey(s);
      if (!key) {
        if (!done && Date.now() - quietSince > quietMs) return lines;
        await sleep(150);
        continue;
      }
      quietSince = Date.now();
      if (onBeat) await onBeat(s);
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        let pick = choices.length ? choices.shift() : ids[0];
        if (!ids.includes(pick)) pick = ids[0];
        lines.push(`options:${pick}`);
        await click(`${label}: option ${pick}`, s.ui.options[pick]);
      } else {
        lines.push(`${s.beat.speaker || "·"}: ${s.beat.text || ""}`);
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 780 });
      }
      const t1 = Date.now();
      while (Date.now() - t1 < 10000) {
        const t = await state();
        if (beatKey(t) !== key) break;
        await sleep(120);
      }
      quietSince = Date.now();
    }
    check(false, `${label}: did not finish in ${timeout} ms`);
    return lines;
  };
  const useHotspot = async (id, opts = {}) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `hotspot ${id} visible in ${s.room}`); return []; }
    await click(`hotspot ${id}`, h);
    await waitIdle(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "", 20000);
    return playThrough(`hotspot ${id}`, opts);
  };
  const goExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { check(false, `exit ${target} in ${s.room}`); return false; }
    await click(`exit → ${target}`, e);
    await waitIdle(`exit → ${target}`);
    await waitFor(`room == ${target}`, (t) => t.room === target, 45000);
    await sleep(800);
    return (await state()).room === target;
  };
  const open = async (start) => {
    if (page) await page.close();
    page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
    page.on("console", (m) => {
      const t = m.text();
      if (m.type() === "error") {
        if (/^WARNING: /.test(t) || /at: push_warning/.test(t)) consoleWarnings.push(t);
        else consoleErrors += 1;
      }
      logLine(`console.${m.type()}: ${t}`);
    });
    page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });
    logLine(`=== ?start=${start}`);
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=${start}`, { waitUntil: "load", timeout: 60000 });
    await page.waitForSelector("#canvas", { timeout: 30000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 180000 });
    await sleep(1500);
  };

  let s = null;
  let lines = [];
  const RUNS = (process.env.OLKH_RUNS || "A,B,C").split(",");   // OLKH_RUNS=B,C — only those parts
  try {
    // ---- A: Olkhovka at night, mother's room, the morning of day three.
    if (RUNS.includes("A")) {
    await open("olkhovka");
    s = await state();
    check(s.room === "R3" && s.flags.done_M18 && !s.flags.started_M19, `start point olkhovka: far pier after M18 (${s.room})`);
    check(await goExit("O4"), "R3 → O4 «Тропа к улице»");
    let caughtO4 = false;
    lines = await playThrough("M19", { done: (t) => t.flags.done_M19 && t.room === "O3" && !t.busy, onBeat: async (b) => {
      if (!caughtO4 && b.room === "O4" && (b.beat.text || "").includes("Илья! Сестра")) { await sleep(600); await shot("A1_O4_night_mitya"); caughtO4 = true; }
    } });
    check(caughtO4, "O4 at night: Mitya knocks «Илья! Сестра твоя…» (frame A1)");
    s = await state();
    check(s.flags.done_M19 && s.room === "O3", `M19 → mother's room O3 (${s.room}); ${lines.length} beats`);
    check(s.npcs.nina && s.npcs.nina.visible, `Nina is a figure in her room (${JSON.stringify(s.npcs.nina)})`);
    await page.mouse.move(400, 1000);
    await sleep(800);
    await shot("A2_O3_night");
    let caughtB12 = false;
    lines = await useHotspot("clock", { done: (t) => t.flags.done_M20 && t.flags.morning_day3 && !t.busy, timeout: 300000, onBeat: async (b) => {
      if (!caughtB12 && (b.beat.text || "").startsWith("Двадцать лет я в него смотрела")) { await sleep(500); await shot("A3_O3_B12_nina"); caughtB12 = true; }
    } });
    s = await state();
    check(s.flags.done_M19c && s.flags.o3_clock_compared, "a click on the clock → M19c");
    check(caughtB12, "B12: «Двадцать лет я в него смотрела…»");
    check(lines.some((l) => l.includes("Ты не выросла")), "M20: Ilya «Ты не выросла»");
    check(s.flags.done_M20 && s.flags.morning_day3, "M20 → the morning of day three");
    await sleep(1000);
    await page.mouse.move(400, 1000);
    await shot("A4_O3_morning");
    lines = await useHotspot("nina");
    s = await state();
    check(s.flags.done_M21 && lines.some((l) => l.includes("семьдесят два")), "a click on Nina → M21 (Dunya died at 72)");
    }

    // ---- B: the first span — windlass with real clicks on the three plaques.
    if (RUNS.includes("B")) {
    await open("span");
    s = await waitFor("M25 starts by itself at the turn", (t) => t.room === "Z3" && t.flags.started_M25, 60000);
    let caughtSpan = false;
    await playThrough("M25 (before the windlass)", { done: (t) => t.mechanic && t.mechanic.open, onBeat: async (b) => {
      if (!caughtSpan && b.frame && b.frame.frame === "F_span") { await sleep(500); await shot("B1_F_span"); caughtSpan = true; }
    } });
    check(caughtSpan, "the turn frame F_span with Ilya and Pelageya");
    s = await state();
    const P = s.mechanic.panel || {};
    check(s.mechanic.type === "windlass" && P.state === "wait" && P.plaque_lower && P.plaque_stop && P.plaque_raise, `the windlass close-up with three plaques (${JSON.stringify(P)})`);
    await shot("B2_windlass_wait");
    await click("plaque «Пускай»", P.plaque_lower);
    s = await waitFor("lowered past the ring → bumped", (t) => t.mechanic.panel && t.mechanic.panel.state === "bumped", SLOW);
    await sleep(500);
    await shot("B3_windlass_bumped");
    check(!s.flags.span_first_laid, "bumped: nothing laid, no penalty");
    await click("plaque «Пускай» (while bumped)", P.plaque_lower);
    await sleep(5000);
    s = await state();
    check(s.mechanic.panel.state === "bumped", `«Пускай» while against the stone does nothing (${s.mechanic.panel.state})`);
    await click("plaque «Подымай»", P.plaque_raise);
    s = await waitFor("hauled back up", (t) => t.mechanic.panel && t.mechanic.panel.state === "wait", SLOW);
    await click("plaque «Пускай»", P.plaque_lower);
    const rest = s.mechanic.panel.rest, tol = s.mechanic.panel.tolerance;
    s = await waitFor("near the ring", (t) => t.mechanic.panel && t.mechanic.panel.pos >= rest - tol * 0.5, SLOW);
    await click("plaque «Стой» at the ring", P.plaque_stop);
    s = await waitFor("the log settles on the ring", (t) => (t.mechanic.panel && t.mechanic.panel.state === "solved") || t.flags.span_first_laid, SLOW);
    await sleep(400);
    await shot("B4_windlass_laid");
    let caughtDone = false;
    lines = await playThrough("M25 (after the log)", { choices: ["roads"], done: (t) => t.flags.done_M25, onBeat: async (b) => {
      if (!caughtDone && b.frame && b.frame.frame === "F_span_done") { await sleep(500); await shot("B5_F_span_done"); caughtDone = true; }
    } });
    s = await state();
    check(s.flags.span_first_laid && s.flags.done_M25, "M25 done: the first log laid");
    check(s.flags.beam_roads, "the inscription «Ольховка — Заречье» chosen by a click");
    check(caughtDone, "the frame with the log on the pier (F_span_done)");
    }

    // ---- C: the epilogue to the last frame, then «Начать заново».
    if (RUNS.includes("C")) {
    await open("epilogue");
    const framesSeen = [];
    let last = "";
    lines = await playThrough("M26", { done: (t) => t.flags.done_M26 && t.frame && t.frame.hold && t.frame.new_game, timeout: 1500000, onBeat: async (b) => {
      const f = b.frame && b.frame.frame;
      if (f && !framesSeen.includes(f)) { framesSeen.push(f); await sleep(700); await shot(`C_${String(framesSeen.length).padStart(2, "0")}_${f}`); }
      if (b.beat.type === "line") last = `${b.beat.speaker}: ${b.beat.text}`;
    } });
    const want = ["EP_tamara", "EP_boat", "EP_pavel", "EP_beam", "EP_lesson", "EP_dinner"];
    check(JSON.stringify(framesSeen) === JSON.stringify(want), `epilogue frames in order: ${framesSeen.join(", ")}`);
    check(last.startsWith("ulyana: А завтра тоже можно прийти"), `the last line is Ulyana's: «${last}»`);
    check(lines.some((l) => l.includes("Доучись. Мост теперь есть")), "C20: «Доучись. Мост теперь есть — будешь приезжать»");
    s = await state();
    check(s.frame.open && s.frame.frame === "EP_dinner" && s.frame.hold, "the dinner frame stays");
    check((s.frame.traces || "").length > 0, `traces of the choices listed: «${(s.frame.traces || "").split("\n").slice(0, 3).join(" / ")}…»`);
    await sleep(800);
    await shot("C_99_the_end");
    await click("«Начать заново»", s.frame.new_game);
    s = await waitFor("a new game at the post office", (t) => t.room === "Z1" && !(t.frame && t.frame.open) && !t.flags.done_M26, 30000);
    check(s.room === "Z1", "«Начать заново» → Z1, the frame closed");
    }
  } catch (e) {
    check(false, `exception: ${e && e.stack ? e.stack : e}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors} (Godot warnings, not errors: ${consoleWarnings.filter((w) => w.startsWith("WARNING")).length})`);
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures, warnings: consoleWarnings }, null, 1));
    await browser.close();
    server.close();
  }
  const ok = checks.filter((c) => c.ok).length;
  console.log(`olkhovka_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
