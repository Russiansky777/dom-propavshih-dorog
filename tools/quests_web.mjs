#!/usr/bin/env node
// The optional stories Q02 «На карте вырос сад» and Q06 «Второй верстак» (Director 23.10 11:51) in the WEB build with
// REAL mouse input (window.probeState), from ?start=freewalk (the class after the lesson with mum, Docs/ACCEPTANCE_M3.md):
//
//   tools/export_web.sh && node tools/quests_web.mjs      (QUESTS_WEB_DIR — another build dir; QUESTS_PORT, default 8781)
//
//   Q02  the class O1: a click on «Старая карта Ольховки» → Agata knows the map, Ulyana runs off, the map close-up
//        (look); the street O4: Ulyana by her father's garden — «На твоей карте моего дома почти нет» — «Тогда помоги
//        мне его найти»; back in the class: the map with the tracing sheet, three lines dragged with the mouse along the
//        dotted guides (one let go midway first — it slips back), «Там теперь смородина», the choice at once → B.
//   Q06  the street: «Мастерская Ильи» → Mitya / Ilya, the second bench close-up: the wedge (does not fit, comes back),
//        the key, the stop block seated, the wooden screw by «точный удар» (one in the red, three in the green), the board →
//        «Держит», the choice at once → A; the shed door on the street is open (frame).
//   B8   batch 8 art (ChatGPT 23.10): the class board — mum's chalk answer, the date, Ulyana's reply (layers from the probe);
//        a double click on an item in the bag — its drawn close-up; school door → gallery → home: M23c, mum's coat on the
//        hook, a click on it — the sleeve close-up (Q03).
// Software WebGL draws a few frames a second: for the timing bar the game clock is slowed with window.probePause(false, k)
// once the marker is where the click is wanted — the click itself is real.
// Frames: Docs/evidence/M3/quests_web_*.jpg. Exit code 0 only when every check passed and the console has no errors.
// Log: build/shots/quests/console.log, report.json there.

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
const WEB_DIR = process.env.QUESTS_WEB_DIR ? path.resolve(ROOT, process.env.QUESTS_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "Docs", "evidence", "M3");
const LOG_DIR = path.join(ROOT, "build", "shots", "quests");
const PORT = Number(process.env.QUESTS_PORT || 8781);
const RUNS = (process.env.QUESTS_RUNS || "Q02,Q06,B8").split(",");

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
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.setDefaultTimeout(180000);
  page.on("console", (m) => {
    const t = m.text();
    if (m.type() === "error") {
      if (/^WARNING: /.test(t) || /at: push_warning/.test(t)) consoleWarnings.push(t);
      else consoleErrors += 1;
    }
    if (m.type() === "error" || m.type() === "warning") logLine(`console.${m.type()}: ${t}`);
  });
  page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });

  // A fresh probe on every read (probePause(false) with no time scale publishes at once and changes nothing).
  const state = () => page.evaluate(() => {
    if (window.probePause) window.probePause(false);
    return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null;
  });
  const waitFor = async (label, pred, timeout = 90000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(150);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)} mechanic=${JSON.stringify(s?.mechanic)?.slice(0, 300)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `quests_web_${name}.jpg`);
    await page.screenshot({ path: file, type: "jpeg", quality: 82, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 3 });
    await sleep(80);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.speaker || ""}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  /** Clicks through beats (options from `choices` in order) until `done(state)` or `quietMs` without a beat. */
  const playThrough = async (label, { choices = [], done = null, quietMs = 3500, timeout = 240000 } = {}) => {
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
      while (Date.now() - t1 < 15000) {
        const t = await state();
        if (beatKey(t) !== key) break;
        await sleep(120);
      }
      quietSince = Date.now();
    }
    check(false, `${label}: did not finish in ${timeout} ms`);
    return lines;
  };
  const waitIdle = async (label) => {
    await sleep(400);
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 90000);
  };
  const useHotspot = async (id, opts = {}) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `hotspot ${id} visible in ${s.room}`); return []; }
    await click(`hotspot ${id}`, h);
    await waitIdle(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "" || (t.mechanic && t.mechanic.open) || (t.view && t.view.open), 30000);
    return playThrough(`hotspot ${id}`, opts);
  };
  const goExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { check(false, `exit ${target} in ${s.room}`); return false; }
    await click(`exit → ${target}`, e);
    await waitIdle(`exit → ${target}`);
    await waitFor(`room == ${target}`, (t) => t.room === target, 60000);
    await sleep(800);
    await playThrough(`enter ${target}`, { quietMs: 1500 });
    return (await state()).room === target;
  };
  const closeMechanic = async (label) => {
    const s = await state();
    if (s.mechanic && s.mechanic.open && s.mechanic.close) {
      await click(`${label}: «Закрыть»`, s.mechanic.close);
      await waitFor(`${label}: close-up put away`, (t) => !(t.mechanic && t.mechanic.open), 60000);
    }
  };
  /** Real drag: press at the first point, move along in small steps, let go (or not). */
  const drag = async (label, pts, release = true) => {
    logLine(`drag ${label}: ${pts.length} points`);
    await page.mouse.move(pts[0].x, pts[0].y, { steps: 2 });
    await sleep(120);
    await page.mouse.down();
    for (let j = 1; j < pts.length; j++) {
      const a = pts[j - 1], b = pts[j];
      const n = Math.max(1, Math.round(Math.hypot(b.x - a.x, b.y - a.y) / 16));
      for (let k = 1; k <= n; k++) await page.mouse.move(a.x + (b.x - a.x) * k / n, a.y + (b.y - a.y) * k / n);
    }
    await sleep(150);
    if (release) await page.mouse.up();
    await sleep(300);
  };
  const slow = async (k) => { await page.evaluate((x) => window.probePause(false, x), k); };
  const strikeTiming = async (label, at, wantGreen) => {
    // The probe here is read about once a second while the marker crosses the bar in 1.9 s: at full speed the read
    // almost never lands in the middle of the green. So the game clock is slowed FIRST (0.05, the lowest probePause
    // allows), the marker is watched crawling, and the REAL click goes in once it is where the click is wanted.
    const t0 = Date.now();
    let slowed = false;
    while (Date.now() - t0 < 180000) {
      const s0 = await state();
      if (beatKey(s0)) {
        if (slowed) { await slow(1.0); slowed = false; }
        await playThrough(`${label}: line first`, { quietMs: 800 });
        continue;
      }
      const t = s0.mechanic && s0.mechanic.panel && s0.mechanic.panel.timing;
      if (t && t.zone && t.state === "run" && !t.paused) {
        if (!slowed) { await slow(0.05); slowed = true; continue; }
        const c = (t.zone[0] + t.zone[1]) / 2, half = (t.zone[1] - t.zone[0]) / 2;
        if (wantGreen ? Math.abs(t.pos - c) < half * 0.6 : Math.abs(t.pos - c) > half + 0.1) break;
      }
      await sleep(60);
    }
    await click(label, at);
    await sleep(400);
    await slow(1.0);
  };
  const open = async (start) => {
    logLine(`=== ?start=${start}`);
    await page.goto(`http://127.0.0.1:${PORT}/index.html?start=${start}`, { waitUntil: "load", timeout: 120000 });
    await page.waitForSelector("#canvas", { timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 240000 });
    await sleep(1500);
    await playThrough(`start ${start}`, { quietMs: 2000 });
  };

  let s = null;
  let lines = [];
  try {
    await open("freewalk");
    s = await state();
    check(s.room === "O1" && s.flags.done_M22, `?start=freewalk: the class after the lesson with mum (${s.room})`);
    logLine(`build: ${fs.statSync(path.join(WEB_DIR, "index.pck")).mtime.toISOString()} (index.pck)`);

    if (RUNS.includes("Q02")) {
      check(s.hotspots.village_map && s.hotspots.village_map.visible, "Q02: «Старая карта Ольховки» on the class wall");
      lines = await useHotspot("village_map", { done: (t) => t.mechanic && t.mechanic.open && !beatKey(t) });
      s = await state();
      check(s.flags.q02_seen_map && lines.some((l) => l.includes("один забор")) && lines.some((l) => l.startsWith("ulyana")),
        `the map: Agata knows it — the empty plot; Ulyana runs to show the garden (${lines.length} lines)`);
      check(s.mechanic.type === "tracing" && s.mechanic.panel.phase === "look" && s.mechanic.panel.ring_visible, `the map close-up, look: the plot ringed (${JSON.stringify(s.mechanic.panel.phase)})`);
      await sleep(600);
      await shot("1_map_look");
      await closeMechanic("map");
      s = await state();
      check(!(s.hotspots.ulyana && s.hotspots.ulyana.visible), "Ulyana has left the class");
      check(await goExit("O2"), "class → school yard");
      check(await goExit("O4"), "yard → street");
      s = await state();
      check(s.hotspots.ulyana && s.hotspots.ulyana.visible, "Ulyana by her father's garden on the street");
      await page.mouse.move(400, 1000);
      await sleep(600);
      await shot("2_O4_ulyana");
      lines = await useHotspot("ulyana");
      s = await state();
      check(s.flags.q02_asked_ulyana && lines.some((l) => l.includes("моего дома почти нет")) && lines.some((l) => l.includes("помоги мне его найти")),
        `«На твоей карте моего дома почти нет» — «Тогда помоги мне его найти»: ${JSON.stringify(lines).slice(0, 200)}`);
      check(await goExit("O2"), "street → yard");
      check(await goExit("O1"), "yard → class");
      await useHotspot("village_map", { done: (t) => t.mechanic && t.mechanic.open && !beatKey(t) });
      s = await waitFor("the tracing sheet laid, the view on the plot", (t) => t.mechanic && t.mechanic.open && t.mechanic.panel.phase === "trace" && t.mechanic.panel.trace.open, 120000);
      await sleep(500);
      await shot("3_map_trace");
      const strokes = s.mechanic.panel.trace.strokes;
      check(strokes.length === 3, `three dotted lines to draw (${strokes.length})`);
      // Let go in the middle of the first line: the pencil slips back, nothing lost.
      await drag("rows, let go midway", strokes[0].slice(0, 2));
      await playThrough("slipped", { quietMs: 1500 });
      s = await state();
      check(s.mechanic.panel.slips === 1 && s.mechanic.panel.trace.loops_done === 0, `let go midway: back to the line's start, no penalty (${s.mechanic.panel.trace.state})`);
      for (let i = 0; i < strokes.length; i++) {
        await drag(`line ${i + 1}`, strokes[i]);
        if (i < strokes.length - 1) {
          s = await waitFor(`line ${i + 1} drawn`, (t) => t.mechanic.panel.trace.loops_done >= i + 1, 60000);
          if (i === 0) await shot("4_map_rows_drawn");
        }
      }
      s = await waitFor("all three lines → «Там теперь смородина»", (t) => t.flags.q02_traced || (t.beat && (t.beat.text || "").includes("смородина")), 120000);
      lines = await playThrough("traced → choice B", { choices: ["B"], done: (t) => t.flags.done_Q02 && !beatKey(t) });
      s = await state();
      check(lines.some((l) => l.includes("Там теперь смородина")) && lines.includes("options:B"), `«Там теперь смородина» and the choice at once: ${JSON.stringify(lines).slice(0, 220)}`);
      check(s.flags.q02_new_primary && !s.flags.q02_old_under_new && s.flags.done_Q02, "B — the tracing to Ulyana; Q02 done");
      check(!(s.mechanic && s.mechanic.open), "the close-up is put away");
      s = await waitFor("Ulyana back in the class", (t) => t.hotspots.ulyana && t.hotspots.ulyana.visible, 30000);
      lines = await useHotspot("village_map");
      s = await state();
      check(!(s.mechanic && s.mechanic.open) && !lines.some((l) => l.startsWith("options")), `once: afterwards only a look (${JSON.stringify(lines)})`);
    }

    if (RUNS.includes("Q06")) {
      s = await state();
      if (s.room === "O1") { check(await goExit("O2"), "class → yard"); }
      check(await goExit("O4"), "→ street");
      s = await state();
      check(s.hotspots.ilya_workshop && s.hotspots.ilya_workshop.visible, "Q06: «Мастерская Ильи» on the street");
      lines = await useHotspot("ilya_workshop", { done: (t) => t.mechanic && t.mechanic.open && !beatKey(t) });
      check(lines.some((l) => l.includes("Два человека здесь уже не помещаются")) && lines.some((l) => l.includes("Тогда сделаем место третьему")),
        `Mitya / Ilya: ${JSON.stringify(lines)}`);
      s = await state();
      check(s.mechanic.type === "workbench" && s.mechanic.panel.step === 0, `the second bench close-up, step 1 (${s.mechanic.panel.step})`);
      await sleep(500);
      await shot("5_bench_step1");
      await click("the wedge", s.mechanic.panel.fastenings.wedge);
      await waitFor("the wedge tried — Ilya says why", (t) => beatKey(t) !== "", 60000);
      lines = await playThrough("the wedge", { quietMs: 1500 });
      s = await waitFor("the wedge back on the cloth", (t) => !t.mechanic.panel.busy, 60000);
      check(s.mechanic.panel.step === 0 && s.mechanic.panel.tries_wrong === 1 && lines.some((l) => l.includes("болтаться")), `the wedge does not fit, no penalty: ${JSON.stringify(lines)}`);
      await click("the key", s.mechanic.panel.fastenings.key);
      s = await waitFor("the key in the groove", (t) => t.flags.q06_fastening_fit, 60000);
      await playThrough("fitted", { quietMs: 1500 });
      s = await state();
      await click("the stop block", s.mechanic.panel.stop);
      s = await waitFor("the stop block in its slot", (t) => t.flags.q06_stop_in, 60000);
      await playThrough("stopped", { quietMs: 1500 });
      s = await waitFor("step 3: the vise and «точный удар»", (t) => t.mechanic.panel.step === 2 && t.mechanic.panel.timing && t.mechanic.panel.timing.zone, 60000);
      await shot("6_bench_vise");
      const screw = s.mechanic.panel.screw;
      await strikeTiming("the screw (red)", screw, false);
      await playThrough("slipped", { quietMs: 1500 });
      s = await state();
      check(s.mechanic.panel.slips === 1 && s.mechanic.panel.turns === 0, `a strike in the red: the screw slips back (${s.mechanic.panel.slips})`);
      for (let i = 0; i < 3; i++) await strikeTiming(`the screw, hit ${i + 1}`, screw, true);
      s = await waitFor("the vise tight", (t) => t.flags.q06_vise_tight, 60000);
      await playThrough("tightened", { quietMs: 1500 });
      s = await state();
      check(s.mechanic.panel.step === 3, `step 4: the board (${s.mechanic.panel.step})`);
      await click("the board", s.mechanic.panel.board);
      await waitFor("the board laid — Ilya", (t) => beatKey(t) !== "", 90000);
      lines = await playThrough("checked → choice A", { choices: ["A"], done: (t) => t.flags.done_Q06 && !beatKey(t) });
      s = await state();
      check(lines.some((l) => l.includes("Держит")) && lines.includes("options:A"), `«Держит» and the choice at once: ${JSON.stringify(lines).slice(0, 220)}`);
      check(s.flags.q06_table_at_ilya && !s.flags.q06_table_at_agata && s.flags.done_Q06, "A — the bench stays at Ilya's; Q06 done");
      await page.mouse.move(400, 1000);
      await sleep(800);
      await shot("7_O4_shed_open");
      lines = await useHotspot("ilya_workshop");
      s = await state();
      check(!(s.mechanic && s.mechanic.open) && lines.some((l) => l.includes("троим")), `once: afterwards only a look (${JSON.stringify(lines)})`);
    }
    if (RUNS.includes("B8")) {
      // Batch 8 art in the web build (ChatGPT 23.10): the drawn states by flags and the clicks on them.
      await open("freewalk");
      s = await state();
      const L = s.layers || {};
      const shown = Object.keys(L).filter((k) => L[k]);
      check(s.flags.board_mama && L.nina_answer_mama && L.nina_answer_date && L.ulyana_bird_reply && !L.nina_answer_here && !L.nina_answer_ilya,
        `batch 8, the class board: mum's chalk answer under «Мама, я иду», the date, Ulyana's reply by the bird (${JSON.stringify(shown)})`);
      await page.mouse.move(400, 1000);
      await sleep(600);
      await shot("8_b8_class_board");
      // «Рассмотреть»: a double click on an item in the bag → its drawn close-up.
      const B8_ITEMS = ["key_house", "door_hinges", "brace_plate", "chalk", "mitten", "bell_clapper", "clamp", "school_ribbon", "journal_manager", "pocket_watch"];
      const inv = (s.ui && s.ui.inventory) || {};
      const it = Object.keys(inv).find((k) => B8_ITEMS.includes(k));
      if (!it) {
        check(false, `an item with a drawn close-up in the bag (${JSON.stringify(Object.keys(inv))})`);
      } else {
        logLine(`double click ${it} in the bag at (${Math.round(inv[it].x)}, ${Math.round(inv[it].y)})`);
        await page.mouse.move(inv[it].x, inv[it].y, { steps: 3 });
        await sleep(120);
        await page.mouse.dblclick(inv[it].x, inv[it].y);
        s = await waitFor(`examine ${it}`, (t) => t.examine && t.examine.open, 30000);
        check(s.examine && s.examine.item === it && s.examine.source === "art", `«Рассмотреть» ${it}: the drawn close-up (${JSON.stringify(s.examine).slice(0, 160)})`);
        await sleep(800);
        await shot(`9_b8_examine_${it}`);
        // Agata's line over the picture first (a click there goes to the line), then «Закрыть».
        await playThrough("examine: Agata's line", { quietMs: 1200 });
        s = await state();
        if (s.examine && s.examine.open) await click("examine: «Закрыть»", s.examine.close);
        await waitFor("examine put away", (t) => !(t.examine && t.examine.open), 30000);
        s = await state();
        if (s.ui && s.ui.cursor_item) { await page.mouse.click(960, 600, { button: "right" }); await sleep(400); }   // put back
      }
      // Mum's coat on the hook in Dunya's house (M23c): through the school door, the gallery, home.
      check(await goExit("H3"), "class → the gallery (school door)");
      s = await state();
      const gotoH1 = s.exits.H1;
      if (gotoH1) {
        await click("exit → H1", gotoH1);
        await waitIdle("exit → H1");
        await waitFor("room == H1", (t) => t.room === "H1", 60000);
      }
      await playThrough("M23c: mum in her sister's house", { done: (t) => t.flags.done_M23c && !beatKey(t) && t.room === "H1", timeout: 300000 });
      s = await state();
      check(s.room === "H1" && s.flags.done_M23c && s.layers && s.layers.nina_coat, `H1 after M23c: mum's coat drawn on the hook (${s.room}, coat ${s.layers && s.layers.nina_coat})`);
      check(s.hotspots.nina_coat && s.hotspots.nina_coat.visible, "the coat is a hotspot (not hidden behind Nina)");
      await page.mouse.move(400, 1000);
      await sleep(600);
      await shot("10_b8_H1_coat");
      lines = await useHotspot("nina_coat", { done: (t) => t.view && t.view.open && !beatKey(t), timeout: 120000 });
      s = await state();
      check(s.view && s.view.open && s.view.id === "sleeve" && s.flags.q03_seen_sleeve, `a click on the coat: the sleeve close-up (Q03) (${JSON.stringify(s.view).slice(0, 120)})`);
      if (s.view && s.view.open && s.view.close) {
        await click("sleeve: «Закрыть»", s.view.close);
        await waitFor("the sleeve put away", (t) => !(t.view && t.view.open), 30000);
      }
    }
  } catch (e) {
    check(false, `exception: ${e.message}`);
  } finally {
    check(consoleErrors === 0, `console errors: ${consoleErrors} (Godot warnings, not errors: ${consoleWarnings.length})`);
    fs.writeFileSync(path.join(LOG_DIR, "console.log"), log.join("\n") + "\n");
    fs.writeFileSync(path.join(LOG_DIR, "report.json"), JSON.stringify({ checks, failures, warnings: consoleWarnings }, null, 1));
    await browser.close();
    server.close();
  }
  const ok = checks.filter((c) => c.ok).length;
  console.log(`quests_web: ${ok}/${checks.length} checks passed`);
  process.exit(failures.length ? 1 : 0);
}

main();
