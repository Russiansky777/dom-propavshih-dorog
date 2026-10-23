#!/usr/bin/env node
// Batch G, the story/rooms part, in the WEB build with REAL mouse input (window.probeState + the ?ambientprobe hooks
// ambientFlag / ambientItem / ambientGoto to put the story where a part begins; every step inside a part is a click):
//
//   tools/export_web.sh && node tools/g_story_web.mjs        (G_WEB_DIR — another build dir; G_PORT, default 8781;
//                                                               G_PART=h1,mill,office,rope,rope_after,boat,nina — a subset)
//
//   h1     — new game: Tamara (M01) → lane → street → H1. While the shutter is closed the workshop says why not (G7);
//            the leaning shelf names the wet towel on the bench (G9); stove → shutter → towel → M03 ends with Tikhon
//            asking for his shelf (G11); the towel hangs on the left hook, the bench is bare, the shelf leans (G12,
//            batch 9 art); shelf → «В углу у печи» → shelf A, Tikhon on its felt; the stove look «устроился» (G14).
//   mill   — day 2 at the mill (G18): M09 → the passage; the mirror refuses without leave; Pavel's leave (M09b) ends
//            with «Иди за мной», he walks off, the fade — in the passage he is there, and the mirror is taken once.
//   office — M3 (G20, G21, G22): Pavel is in the office, the lever of the sluice on the hook, the clamp on the table;
//            Pavel says to take the clamp; lever, journal, clamp taken.
//   rope   — M15s–M16s (G17, G28, C27): the brace and the knot at the plate (Pelageya takes the rope off her stopper);
//            after the knot the rope runs from the plate ring over the water; at the pier her stopper is empty and
//            says where the rope is.
//   boat   — G38: at the far pier on the night of the crossing «К лодке» is refused by Pelageya.
//   nina   — G29: M19 — Nina says «Пойдём в тепло» on her porch, walks to her door, then the fade into her room.
// Frames: build/shots/g_story/*.png (the chosen ones are copied to Docs/evidence/G/story_*.png by hand).
// Exit code 0 only when every check passed and the console has no errors (Godot warnings are listed, not counted).

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = process.env.G_WEB_DIR ? path.resolve(ROOT, process.env.G_WEB_DIR) : path.join(ROOT, "build", "web");
const OUT_DIR = path.join(ROOT, "build", "shots", "g_story");
const PORT = Number(process.env.G_PORT || 8781);
const PARTS = (process.env.G_PART || "h1,mill,office,rope,boat,nina").split(",");

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json", ".ico": "image/x-icon",
  ".txt": "text/plain",
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

// The state of the story at the start of a part (what the earlier scenes leave), like RoomManager.start_at.
const DAY1 = ["done_M01", "met_tamara", "house_unlocked", "house_open", "started_M03", "done_M03", "met_tikhon", "stove_lit",
  "h1_shutter_open", "h1_scarf_removed", "done_M04", "done_M05", "door_school_installed", "done_M06", "seen_class_traces",
  "done_M07", "done_M08", "done_N01", "board_mama", "v03_marked", "v03_add_boat", "mitten_placed"];
const TO_M13A = ["done_M09", "met_pavel", "seen_office_door", "seen_office_photo", "seen_shift_schedule", "done_M09s",
  "done_M09b", "pavel_agreed_signals", "pavel_blessed_mirror", "office_mirror_mounted", "office_mirror_clamped",
  "bell_clapper_hung", "done_M10", "done_M11", "done_M12", "office_unbolted", "done_M13a"];
const TO_M15A = ["done_M13", "has_key_sluice", "has_clamp", "has_journal_manager", "pavel_answer_promise", "done_M14",
  "sluice_key_inserted", "pond_lowered", "sluice_opened", "nina_mirror_clamped", "nina_time_compared", "done_M15a",
  "evening_dusk", "has_brace_plate"];

async function main() {
  if (!fs.existsSync(path.join(WEB_DIR, "index.html"))) { console.error(`No web build at ${WEB_DIR}. Run tools/export_web.sh first.`); process.exit(2); }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const log = [];
  const logLine = (s) => { const l = `[${new Date().toISOString()}] ${s}`; log.push(l); console.log(l); };
  const failures = [];
  const checks = [];
  const check = (ok, msg) => { checks.push({ ok: !!ok, msg }); logLine(`${ok ? "OK  " : "FAIL"} ${msg}`); if (!ok) failures.push(msg); };
  let consoleErrors = 0;
  const server = await serve(WEB_DIR);
  const browser = await chromium.launch({ headless: true, executablePath: findChromium(),
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
      "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.setDefaultTimeout(180000);
  page.on("console", (m) => {
    const t = m.text();
    // A missing file is counted by its response below (a local export has no version.txt — not an error of the game).
    if (m.type() === "error" && !/^WARNING: /.test(t) && !/at: push_warning/.test(t) && !/^Failed to load resource/.test(t)) consoleErrors += 1;
    if (m.type() === "error" || m.type() === "warning") logLine(`console.${m.type()}: ${t}`);
  });
  page.on("pageerror", (e) => { consoleErrors += 1; logLine(`pageerror: ${e.message}`); });
  page.on("response", (r) => {
    if (r.status() >= 400 && !/version\.txt$/.test(r.url().split("?")[0])) { consoleErrors += 1; logLine(`http ${r.status()}: ${r.url()}`); }
  });

  // A fresh probeState on every read (probePause(false) publishes at once and changes nothing).
  const state = () => page.evaluate(() => {
    if (window.probePause) window.probePause(false);
    return window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null;
  });
  const waitFor = async (label, pred, timeout = 60000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await state();
      if (s && pred(s)) return s;
      await sleep(150);
    }
    const s = await state();
    check(false, `${label}: timeout ${timeout} ms (room=${s?.room} beat=${JSON.stringify(s?.beat)} mechanic=${JSON.stringify(s?.mechanic)?.slice(0, 160)})`);
    return s;
  };
  const shot = async (name) => {
    const file = path.join(OUT_DIR, `${name}.png`);
    await page.screenshot({ path: file, timeout: 180000 });
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };
  const click = async (label, pt) => {
    logLine(`click ${label} at (${Math.round(pt.x)}, ${Math.round(pt.y)})`);
    await page.mouse.move(pt.x, pt.y, { steps: 3 });
    await sleep(80);
    await page.mouse.click(pt.x, pt.y);
  };
  const beatKey = (s) => (s && s.beat && s.beat.type ? `${s.beat.type}|${s.beat.text || ""}|${s.beat.prompt || ""}` : "");
  const waitIdle = async (label) => {
    const before = await state();
    const t0 = Date.now();
    while (Date.now() - t0 < 4000) {
      const s = await state();
      if (s && (s.player.walking || s.player.acting || beatKey(s) !== beatKey(before) || s.room !== before.room ||
          Math.hypot(s.player.x - before.player.x, s.player.y - before.player.y) > 2)) break;
      await sleep(100);
    }
    return waitFor(`${label}: walk finished`, (s) => s.player && !s.player.walking && !s.player.acting, 90000);
  };
  /** Clicks through beats; options from `choices` in order. onBeat(state) for every new beat (before the click). */
  const finish = async (label, choices = [], onBeat = null) => {
    const lines = [];
    let idle = 0;
    for (let i = 0; i < 80 && idle < 8; i++) {
      const s = await state();
      const key = beatKey(s);
      if (!key) { idle += 1; await sleep(200); continue; }
      idle = 0;
      if (onBeat) await onBeat(s);
      if (s.beat.type === "options") {
        const ids = Object.keys(s.ui.options || {});
        let pick = choices.length ? choices.shift() : ids[0];
        if (!ids.includes(pick)) pick = ids[0];
        lines.push(`options:${pick}`);
        await click(`${label}: option ${pick}`, s.ui.options[pick]);
      } else {
        lines.push(`${s.beat.speaker || "·"}: ${s.beat.text || ""}`);
        await click(`${label}: continue`, s.ui.dialogue_click || { x: 960, y: 980 });
      }
      await waitFor(`${label}: beat advanced`, (t) => beatKey(t) !== key, 60000);
    }
    return lines;
  };
  const useHotspot = async (id, choices = [], onBeat = null) => {
    const s = await state();
    const h = s.hotspots[id];
    if (!h || !h.visible) { check(false, `hotspot ${id} visible in ${s.room} (${JSON.stringify(h)})`); return []; }
    await click(`hotspot ${id}`, h);
    await waitIdle(`hotspot ${id}`);
    await waitFor(`hotspot ${id}: reaction`, (t) => beatKey(t) !== "" || (t.mechanic && t.mechanic.open) || (t.view && t.view.open), 20000);
    return finish(`hotspot ${id}`, choices, onBeat);
  };
  const clickExit = async (target) => {
    const s = await state();
    const e = s.exits[target];
    if (!e) { check(false, `exit ${target} in ${s.room}`); return null; }
    await click(`exit → ${target}`, e);
    await waitIdle(`exit → ${target}`);
    await sleep(600);
    return state();
  };
  const goExit = async (target) => {
    await clickExit(target);
    await waitFor(`room == ${target}`, (t) => t.room === target, 60000);
    await sleep(1000);
    return (await state()).room === target;
  };
  const setFlags = async (flags, on = true) => { for (const f of flags) await page.evaluate(([x, v]) => window.ambientFlag(x, v), [f, on]); };
  const giveItems = async (items) => { for (const it of items) await page.evaluate((x) => window.ambientItem(x, true), it); };
  const fresh = async (label) => {
    let s = await state();
    if (s && s.mechanic && s.mechanic.open && s.mechanic.close) {
      await click(`${label}: close the previous mechanic`, s.mechanic.close);
      await waitFor(`${label}: mechanic closed`, (t) => !(t.mechanic && t.mechanic.open), 60000);
    }
    await finish(`${label}: lines left`);
    s = await state();
    const on = Object.keys(s.flags || {}).filter((f) => s.flags[f]);
    await setFlags(on, false);
    await page.evaluate((its) => its.forEach((it) => window.ambientItem(it, false)), (s.inventory || []).map(String));
  };
  const goto = async (room, spawn = "default", drain = true) => {
    await page.evaluate(([r, sp]) => window.ambientGoto(r, sp), [room, spawn]);
    await waitFor(`room ${room}`, (s) => s.room === room, 60000);
    await sleep(1500);
    return drain ? finish(`enter ${room}`) : [];
  };
  const slow = async (k) => { await page.evaluate((x) => window.probePause(false, x), k); };
  // «Точный удар»: watch the marker at full speed, all but stop the game clock when it is in the green, click for real.
  const strikeTiming = async (label, getTiming, at) => {
    await page.mouse.move(at.x, at.y, { steps: 3 });
    const t0 = Date.now();
    while (Date.now() - t0 < 180000) {
      const s0 = await state();
      if (beatKey(s0)) { await finish(`${label}: line first`); await page.mouse.move(at.x, at.y, { steps: 3 }); continue; }
      const t = getTiming(s0);
      if (t && t.zone && t.state === "run" && !t.paused) {
        const c = (t.zone[0] + t.zone[1]) / 2, half = (t.zone[1] - t.zone[0]) / 2;
        if (Math.abs(t.pos - c) < half * 0.5) {
          await slow(0.05);
          const t2 = getTiming(await state());
          if (t2 && Math.abs(t2.pos - c) < half * 0.9) break;
          await slow(1.0);
        }
      }
      await sleep(100);
    }
    logLine(`click ${label} at (${Math.round(at.x)}, ${Math.round(at.y)})`);
    await page.mouse.down(); await page.mouse.up();
    await sleep(400);
    await slow(1.0);
  };

  try {
    await page.goto(`http://127.0.0.1:${PORT}/index.html?ambientprobe`, { waitUntil: "load", timeout: 120000 });
    await page.waitForSelector("#canvas", { timeout: 60000 });
    await page.waitForFunction(() => window.probeReady === true && window.ambientProbeReady === true, null, { timeout: 180000 });
    await sleep(1500);
    const version = await page.evaluate(async () => { try { return (await (await fetch("version.txt", { cache: "no-store" })).text()).trim(); } catch (_) { return ""; } });
    logLine(`build: ${version}`);

    // ---------------------------------------------------------------- H1, day one, from a new game
    if (PARTS.includes("h1")) try {
      await useHotspot("tamara");
      await waitFor("M01 done", (s) => s.flags.done_M01, 60000);
      check(await goExit("Z4"), "Z1 → Z4");
      check(await goExit("Z2"), "Z4 → Z2");
      // the key from the bag on the porch door → H1
      let s = await state();
      const kp = s.ui.inventory && s.ui.inventory.key_house;
      check(!!kp, "the key is in the bag");
      if (kp) {
        await click("bag pocket key_house", kp);
        await waitFor("key in hand", (t) => t.selected_item === "key_house", 10000);
      }
      s = await state();
      await click("porch door with the key", s.exits.H1);
      await waitIdle("door with key");
      await waitFor("unlock text", (t) => beatKey(t) !== "", 60000);
      await finish("unlock text");
      s = await waitFor("in H1", (t) => t.room === "H1", 120000);
      check(s.room === "H1", "Z2 → H1 with the key");
      await sleep(1500);
      // G7: the workshop in the dark — Agata says why not, the room stays.
      s = await clickExit("H2");
      s = await waitFor("G7: a line instead of the dark workshop", (t) => beatKey(t) !== "", 20000);
      check(s.room === "H1" && (s.beat.text || "").includes("темно"), `G7: shutter closed → «${s.beat && s.beat.text}», still in ${s.room}`);
      await sleep(400);
      await shot("01_h1_dark_refusal");
      await finish("G7 line");
      check((await state()).room === "H1", "G7: Agata stays in the living room");
      // G9: the leaning shelf names the wet towel on the bench.
      let lines = await useHotspot("shelf");
      check(lines.some((l) => l.includes("мокрый платок") && l.includes("ни лечь")), `G9: the shelf speaks of the wet towel: ${JSON.stringify(lines)}`);
      // stove → shutter → towel → M03 with Tikhon's request (G11).
      await useHotspot("stove");
      await waitFor("stove lit", (t) => t.flags.stove_lit, 20000);
      await useHotspot("shutter");
      await waitFor("shutter open", (t) => t.flags.h1_shutter_open, 20000);
      lines = await useHotspot("scarf", ["ask"]);
      s = await waitFor("M03 done", (t) => t.flags.done_M03 && t.flags.met_tikhon, 60000);
      lines = lines.concat(await finish("M03 rest"));
      check(lines.some((l) => l.startsWith("tikhon") && l.includes("повесь мне полку")), `G11: Tikhon asks for his shelf at the end of M03: ${JSON.stringify(lines).slice(0, 400)}`);
      check(lines.some((l) => l.includes("Лапами вешать")), "G11: «Лапами вешать — не моё»");
      s = await state();
      const L = s.layers || {};
      check(L.bench_bare && L.hook_coat && L.shelf_leaning && !L.shelf_stove && !L.shelf_table, `G12 (batch 9): bench bare, towel on the hook, one shelf leaning: ${JSON.stringify({b: L.bench_bare, h: L.hook_coat, l: L.shelf_leaning, a: L.shelf_stove, B: L.shelf_table})}`);
      await click("floor (step aside)", { x: 1000, y: 900 });
      await waitIdle("step aside");
      await sleep(1500);
      await page.mouse.move(1700, 1000);
      await sleep(500);
      await shot("02_h1_towel_on_hook_shelf_leaning");
      // G12/G14: the shelf → A; Tikhon on it; the stove look.
      lines = await useHotspot("shelf", ["A"]);
      s = await waitFor("Q04 A", (t) => t.flags.done_Q04 && t.flags.q04_corner_stove, 60000);
      const tk = s.hotspots.tikhon;
      check(tk && tk.x > 440 && tk.x < 545 && tk.y > 340 && tk.y < 500, `G12: Tikhon's hotspot on shelf A (${tk && Math.round(tk.x)}, ${tk && Math.round(tk.y)})`);
      const L2 = s.layers || {};
      check(L2.shelf_stove && !L2.shelf_leaning && !L2.shelf_table && !L2.holes_stove, `G12: one shelf at a time — A up, its sockets covered: ${JSON.stringify({a: L2.shelf_stove, l: L2.shelf_leaning, B: L2.shelf_table, holes: L2.holes_stove})}`);
      await click("floor (step back)", { x: 1150, y: 900 });
      await waitIdle("step back");
      await sleep(1500);
      await page.mouse.move(1700, 1000);
      await sleep(500);
      await shot("03_h1_shelf_A_tikhon");
      s = await state();
      await click("the stove again", s.hotspots.stove);
      await waitIdle("the stove again");
      s = await waitFor("stove look", (t) => beatKey(t) !== "", 20000);
      check((s.beat.text || "").includes("устроился") && !(s.beat.text || "").includes("гнёзд"), `G14: the stove after the shelf: «${s.beat.text}»`);
      await finish("stove look");
    } catch (e) { check(false, `h1: exception ${e.message}`); }

    // ---------------------------------------------------------------- the mill, Pavel's leave (G18)
    if (PARTS.includes("mill")) try {
      await fresh("mill");
      await setFlags(DAY1);
      await goto("M1", "from_Z2");
      let lines = await useHotspot("pavel");
      check((await state()).flags.done_M09, `M09 with Pavel: ${JSON.stringify(lines).slice(0, 200)}`);
      await useHotspot("pavel");
      await useHotspot("schedule");
      let s = await state();
      if (s.view && s.view.open && s.view.close) await click("close the board", s.view.close);
      else if (s.view && s.view.open) await page.keyboard.press("Escape");   // with nothing open Esc is the pause menu
      await sleep(800);
      check(await goExit("M2"), "M1 → M2 (the passage)");
      await useHotspot("office_door");
      await useHotspot("photo");
      s = await state();
      if (s.mechanic && s.mechanic.open && s.mechanic.close) { await click("close the photo", s.mechanic.close); await sleep(800); }
      await finish("M09s");
      lines = await useHotspot("mirror");
      s = await state();
      check(!(s.inventory || []).includes("mirror_mill") && lines.some((l) => l.includes("Без спросу")), `G18: no mirror before Pavel's leave: ${JSON.stringify(lines)}`);
      check(await goExit("M1"), "M2 → M1");
      lines = await useHotspot("pavel");
      s = await waitFor("G18: led into the passage", (t) => t.room === "M2" && t.flags.pavel_blessed_mirror, 60000);
      lines = lines.concat(await finish("M09b rest"));
      check(lines.some((l) => l.includes("Иди за мной")), `G18: «Иди за мной»: ${JSON.stringify(lines).slice(0, 300)}`);
      s = await state();
      check(s.hotspots.pavel && s.hotspots.pavel.visible, "G18: Pavel is in the passage after the fade");
      await sleep(800);
      await shot("04_mill_passage_pavel");
      lines = await useHotspot("mirror");
      s = await state();
      check((s.inventory || []).filter((i) => i === "mirror_mill").length === 1 && lines.some((l) => l.includes("Бери")), `G18: the mirror taken once in the passage, with «Бери»: ${JSON.stringify(lines)}`);
      check(!(s.hotspots.mirror && s.hotspots.mirror.visible), "G18: the mirror is gone from the passage");
    } catch (e) { check(false, `mill: exception ${e.message}`); }

    // ---------------------------------------------------------------- the office (G20, G21, G22)
    if (PARTS.includes("office")) try {
      await fresh("office");
      await setFlags(DAY1.concat(TO_M13A));
      await goto("M3", "from_M2");
      let s = await state();
      check(s.hotspots.pavel && s.hotspots.pavel.visible, "G21: Pavel is in the office (not behind the closed door)");
      check(s.hotspots.key_nail && s.hotspots.key_nail.visible && s.hotspots.key_nail.label === "Рычаг затвора", `G20: «${s.hotspots.key_nail && s.hotspots.key_nail.label}» on the hook`);
      check(s.hotspots.clamp && s.hotspots.clamp.visible && s.hotspots.clamp.y > 780, `G22: the clamp on the table (${s.hotspots.clamp && Math.round(s.hotspots.clamp.y)})`);
      check(s.layers && s.layers.hook_empty && s.layers.sluice_lever && s.layers.clamp_table, `batch 9: the empty hook, the lever on it, the clamp on the table: ${JSON.stringify(s.layers)}`);
      await page.mouse.move(1700, 1000);
      await sleep(600);
      await shot("05_m3_office_lever_clamp");
      let lines = await useHotspot("pavel");
      check(lines.some((l) => l.includes("струбцину")), `G22: Pavel says to take the clamp: ${JSON.stringify(lines)}`);
      lines = await useHotspot("key_nail");
      lines = lines.concat(await useHotspot("journal"));
      lines = lines.concat(await useHotspot("clamp"));
      s = await waitFor("M13 done", (t) => t.flags.done_M13, 60000);
      lines = lines.concat(await finish("M13"));
      check((s.inventory || []).includes("key_sluice") && (s.inventory || []).includes("clamp"), `lever and clamp in the bag: ${JSON.stringify(s.inventory)}`);
      check(s.layers && s.layers.hook_empty && !s.layers.sluice_lever && !s.layers.clamp_table, "batch 9: taken — only the empty hook, no clamp on the table");
      check(lines.some((l) => l.includes("Рычаг затвора")), `G20: the lever is called «рычаг затвора»: ${JSON.stringify(lines).slice(0, 300)}`);
    } catch (e) { check(false, `office: exception ${e.message}`); }

    // ---------------------------------------------------------------- the rope (G17, G28, C27)
    if (PARTS.includes("rope")) try {
      await fresh("rope");
      await setFlags(DAY1.concat(TO_M13A, TO_M15A, ["skoba_on_plate"]));
      await goto("Z3", "from_Z2");
      let s = await state();
      await click("the plate", s.hotspots.pier_plate);
      s = await waitFor("plate open", (t) => t.mechanic && t.mechanic.open && t.mechanic.type === "plate", 120000);
      await finish("plate open");
      s = await state();
      const strikeAt = s.mechanic.panel.strike;
      for (let i = 0; i < 3; i++) await strikeTiming(`brace hit ${i + 1}`, (t) => t.mechanic.panel.timing, strikeAt);
      s = await waitFor("braced", (t) => t.flags.plate_braced, 60000);
      const m15s = await finish("M15s");
      check(m15s.some((l) => l.includes("со своего стопора")) && m15s.some((l) => l.includes("снимает канат со стопора")), `G28: Pelageya takes the rope off her stopper: ${JSON.stringify(m15s).slice(0, 400)}`);
      s = await waitFor("rope brought", (t) => t.flags.rope_brought && t.mechanic.open && t.mechanic.panel.knot_path.open, 120000);
      const kp = s.mechanic.panel.knot_path;
      await page.mouse.move(kp.end.x, kp.end.y);
      await page.mouse.down();
      for (const st of kp.strokes) {
        for (let j = 1; j < st.length; j++) {
          const a = st[j - 1], b = st[j];
          const n = Math.max(1, Math.round(Math.hypot(b.x - a.x, b.y - a.y) / 22));
          for (let k = 1; k <= n; k++) await page.mouse.move(a.x + (b.x - a.x) * k / n, a.y + (b.y - a.y) * k / n);
        }
      }
      await page.mouse.up();
      s = await waitFor("tied", (t) => t.flags.rope_on_ring, 60000);
      await finish("M15");
      s = await state();
      if (s.mechanic && s.mechanic.open && s.mechanic.close) await click("close", s.mechanic.close);
      await waitFor("plate closed", (t) => !(t.mechanic && t.mechanic.open), 60000);
      await finish("after the plate");
      s = await state();
      check(s.room === "Z3" || s.room === "R1", `after the knot: ${s.room}`);
      if (s.room === "Z3") {
        await page.mouse.move(1700, 1000);
        await sleep(1200);
        await shot("06_z3_rope_from_ring");
        await goto("R1", "from_Z2");
      }
      await finish("M16s");
      s = await state();
      check(s.hotspots.stopper_empty && s.hotspots.stopper_empty.visible && !(s.hotspots.rope && s.hotspots.rope.visible), "C27/G28: at the pier the stopper is empty");
      const sp = Object.keys(s.layers || {}).filter((k) => k.startsWith("stopper_empty") && s.layers[k]);
      check(sp.length === 1, `C27: one empty-stopper patch for the light of the moment: ${JSON.stringify(sp)}`);
      await page.mouse.move(1700, 1000);
      await sleep(1000);
      await shot("07_r1_stopper_empty");
      const look = await useHotspot("stopper_empty");
      check(look.some((l) => l.includes("кольце плиты у поворота")), `C27: the empty stopper says where the rope is: ${JSON.stringify(look)}`);
    } catch (e) { check(false, `rope: exception ${e.message}`); }

    // ---------------------------------------------------------------- after the knot, without the mini-games (G28, C27)
    // (the brace and the knot by real clicks need a quiet machine — tools/mech_web.mjs «plate»; here the story state
    // right after M15: where the rope is, at the turn and at the pier)
    if (PARTS.includes("rope_after")) try {
      await fresh("rope_after");
      await setFlags(DAY1.concat(TO_M13A, TO_M15A, ["skoba_on_plate", "plate_braced", "rope_brought", "rope_on_ring",
        "road_held_both_ends", "done_M15s", "started_M15", "done_M15"]));
      await goto("Z3", "from_Z2");
      let s = await state();
      check(s.room === "Z3", "Z3 after the knot");
      await page.mouse.move(1700, 1000);
      await sleep(1500);
      await shot("06_z3_rope_from_ring");
      await goto("R1", "from_Z2");
      await finish("M16s");
      s = await state();
      check(s.hotspots.stopper_empty && s.hotspots.stopper_empty.visible && !(s.hotspots.rope && s.hotspots.rope.visible), "C27/G28: at the pier the stopper is empty");
      const sp = Object.keys(s.layers || {}).filter((k) => k.startsWith("stopper_empty") && s.layers[k]);
      check(sp.length === 1, `C27: one empty-stopper patch for the light of the moment: ${JSON.stringify(sp)}`);
      await page.mouse.move(1700, 1000);
      await sleep(1000);
      await shot("07_r1_stopper_empty");
      const look = await useHotspot("stopper_empty");
      check(look.some((l) => l.includes("кольце плиты у поворота")), `C27: the empty stopper says where the rope is: ${JSON.stringify(look)}`);
    } catch (e) { check(false, `rope_after: exception ${e.message}`); }

    // ---------------------------------------------------------------- no boat ride back before the shuttle (G38)
    if (PARTS.includes("boat")) try {
      await fresh("boat");
      await setFlags(DAY1.concat(TO_M13A, TO_M15A, ["skoba_on_plate", "plate_braced", "rope_brought", "rope_on_ring", "done_M15s",
        "done_M15", "far_snow_seen", "done_M16s", "far_lights_answered", "done_M16", "done_M17", "ferry_verified", "done_M18p", "done_M18"]));
      await goto("R3", "from_R2");
      let s = await clickExit("R2");
      s = await waitFor("G38: a line instead of a ride back", (t) => beatKey(t) !== "", 20000);
      check(s.room === "R3" && s.beat.speaker === "pelageya" && !(s.mechanic && s.mechanic.open), `G38: «${s.beat && s.beat.text}» (${s.beat && s.beat.speaker}), still at ${s.room}`);
      await finish("G38");
    } catch (e) { check(false, `boat: exception ${e.message}`); }

    // ---------------------------------------------------------------- Nina walks home (G29)
    if (PARTS.includes("nina")) try {
      let s = await state();
      if (!s.flags.done_M18) {
        await fresh("nina");
        await setFlags(DAY1.concat(TO_M13A, TO_M15A, ["rope_on_ring", "done_M15", "done_M16", "done_M17", "done_M18p", "done_M18"]));
      }
      await goto("O4", "from_R3", false);
      let caught = false, walked = false;
      const lines = await finish("M19", [], async (b) => {
        if (!caught && b.beat.speaker === "nina" && (b.beat.text || "").includes("Пойдём в тепло")) {
          check(b.room === "O4" && b.hotspots.nina && b.hotspots.nina.visible, "G29: Nina says «Пойдём в тепло» on her porch");
          caught = true;
        }
        if (caught && !walked && b.room === "O3") walked = true;
      });
      s = await waitFor("M19 → O3", (t) => t.room === "O3", 60000);
      check(caught && lines.some((l) => l.includes("Ходики")), `G29: her line on the street, then «Ходики» in the room: ${JSON.stringify(lines).slice(0, 400)}`);
      check(s.hotspots.nina && s.hotspots.nina.visible && s.flags.m19_nina_home, "G29/G41: in the room Nina is there (m19_nina_home)");
    } catch (e) { check(false, `nina: exception ${e.message}`); }
  } finally {
    await browser.close();
    if (server) server.close();
  }
  const report = { version: new Date().toISOString(), parts: PARTS, checks, failures, consoleErrors };
  fs.writeFileSync(path.join(OUT_DIR, "report.json"), JSON.stringify(report, null, 1));
  fs.writeFileSync(path.join(OUT_DIR, "console.log"), log.join("\n") + "\n");
  logLine(`${checks.filter((c) => c.ok).length}/${checks.length} checks, console errors ${consoleErrors}`);
  process.exit(failures.length === 0 && consoleErrors === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
