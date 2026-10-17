#!/usr/bin/env node
// Scripted walkthrough of the web build with real canvas clicks + screenshots.
//
//   node tools/screenshots.mjs            (after tools/export_web.sh)
//
// Serves build/web on localhost, opens it in headless Chromium with software WebGL,
// waits for `window.probeReady` (set by Main.gd via JavaScriptBridge), then clicks
// floor → mirror → exit → latch → exit back, saving build/shots/NN_*.png after each
// step and build/shots/console.log with every console message / page error.
//
// Exit code 0 only when every step reached its expected game state.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const WEB_DIR = path.join(ROOT, "build", "web");
const SHOTS_DIR = path.join(ROOT, "build", "shots");
const PORT = Number(process.env.SHOTS_PORT || 8765);
const GL_MODE = process.env.SHOTS_GL || "angle"; // "angle" (default) or "swiftshader"
const STEP_TIMEOUT_MS = 20000;

// Game-space coordinates (1920x1080 canvas, 1:1 with the viewport below).
const CLICKS = {
  floor: { x: 1100, y: 980 },          // walk; in front of the table (y > 1000 ⇒ player over it)
  behind_table: { x: 900, y: 860 },    // walk behind the table occluder
  mirror: { x: 560, y: 330 },          // mirror frame hotspot → sets mirror_mounted
  exit_to_office: { x: 1860, y: 850 }, // RoomHouse exit
  latch: { x: 300, y: 420 },           // RoomOffice latch → sets office_latch_open
  exit_to_house: { x: 60, y: 850 },    // RoomOffice exit
  new_game_button: { x: 222, y: 86 },  // HUD "New game" button (top-left panel)
};

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".json": "application/json",
  ".css": "text/css",
  ".ico": "image/x-icon",
};

function serve(dir) {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
    let file = path.join(dir, urlPath === "/" ? "index.html" : urlPath);
    if (!file.startsWith(dir)) {
      res.writeHead(403);
      return res.end();
    }
    fs.stat(file, (err, st) => {
      if (err || !st.isFile()) {
        res.writeHead(404);
        return res.end("not found");
      }
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
  // Playwright's own lookup first; fall back to the preinstalled browser under /opt/pw-browsers.
  try {
    const p = chromium.executablePath();
    if (p && fs.existsSync(p)) return p;
  } catch (_) {}
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
  fs.mkdirSync(SHOTS_DIR, { recursive: true });
  const consoleLog = [];
  const logLine = (s) => {
    const line = `[${new Date().toISOString()}] ${s}`;
    consoleLog.push(line);
    console.log(line);
  };

  const server = await serve(WEB_DIR);
  const url = `http://127.0.0.1:${PORT}/index.html`;

  const glArgs =
    GL_MODE === "swiftshader"
      ? ["--use-gl=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"]
      : ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"];
  const executablePath = findChromium();
  logLine(`chromium: ${executablePath || "(playwright default)"}; gl mode: ${GL_MODE}`);

  const browser = await chromium.launch({
    headless: true,
    executablePath,
    args: [...glArgs, "--no-sandbox", "--disable-dev-shm-usage", "--autoplay-policy=no-user-gesture-required"],
  });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on("console", (m) => logLine(`console.${m.type()}: ${m.text()}`));
  page.on("pageerror", (e) => logLine(`pageerror: ${e.message}`));
  page.on("requestfailed", (r) => logLine(`requestfailed: ${r.url()} ${r.failure()?.errorText}`));

  const failures = [];
  const shots = [];
  let shotIndex = 0;

  const shot = async (name) => {
    shotIndex += 1;
    const file = path.join(SHOTS_DIR, `${String(shotIndex).padStart(2, "0")}_${name}.png`);
    await page.screenshot({ path: file });
    shots.push(file);
    logLine(`screenshot ${path.relative(ROOT, file)}`);
  };

  const probe = () => page.evaluate(() => (window.probeState ? JSON.parse(JSON.stringify(window.probeState)) : null));

  const waitFor = async (label, predicate, timeout = STEP_TIMEOUT_MS) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      const s = await probe();
      if (s && predicate(s)) return s;
      await sleep(100);
    }
    const s = await probe();
    failures.push(`${label}: timeout after ${timeout} ms; state=${JSON.stringify(s)}`);
    logLine(`FAIL ${label}: state=${JSON.stringify(s)}`);
    return s;
  };

  const clickGame = async (label, pt) => {
    logLine(`click ${label} at (${pt.x}, ${pt.y})`);
    await page.mouse.click(pt.x, pt.y);
  };

  const waitIdle = (label) => waitFor(`${label}: player stopped`, (s) => s.player && s.player.walking === false);

  try {
    logLine(`open ${url}`);
    await page.goto(url, { waitUntil: "load", timeout: 60000 });
    await page.waitForSelector("#canvas", { timeout: 30000 });

    // WebGL sanity check in this Chromium (independent of Godot).
    const webgl = await page.evaluate(() => {
      const c = document.createElement("canvas");
      const gl = c.getContext("webgl2");
      if (!gl) return { ok: false };
      const dbg = gl.getExtension("WEBGL_debug_renderer_info");
      return {
        ok: true,
        renderer: dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
        version: gl.getParameter(gl.VERSION),
      };
    });
    logLine(`webgl2: ${JSON.stringify(webgl)}`);
    if (!webgl.ok) failures.push("WebGL2 context unavailable in headless Chromium");

    // Wait for the engine: Main.gd sets window.probeReady once the first room is loaded.
    const t0 = Date.now();
    await page.waitForFunction(() => window.probeReady === true, null, { timeout: 90000 }).catch((e) => {
      failures.push(`probeReady not set within 90 s: ${e.message}`);
    });
    logLine(`probeReady after ${Date.now() - t0} ms; state=${JSON.stringify(await probe())}`);
    await sleep(1500); // let a few frames render
    await shot("house");

    // 1. Walk on the floor (in front of the table), then behind the table.
    await clickGame("floor", CLICKS.floor);
    await waitFor("walk started", (s) => s.player && (s.player.walking || s.player.x > 600));
    await waitIdle("walk to floor");
    await shot("walk_front_of_table");
    await clickGame("behind table", CLICKS.behind_table);
    await waitIdle("walk behind table");
    await shot("walk_behind_table");

    // 2. Mirror frame → mirror_mounted.
    await clickGame("mirror", CLICKS.mirror);
    await waitFor("mirror_mounted flag", (s) => s.flags && s.flags.mirror_mounted === true);
    await sleep(400);
    await shot("mirror_mounted");

    // 3. Exit → RoomOffice.
    await clickGame("exit to office", CLICKS.exit_to_office);
    await waitFor("room == RoomOffice", (s) => s.room === "RoomOffice");
    await sleep(600);
    await shot("office");

    // 4. Latch → office_latch_open.
    await clickGame("latch", CLICKS.latch);
    await waitFor("office_latch_open flag", (s) => s.flags && s.flags.office_latch_open === true);
    await sleep(400);
    await shot("latch_open");

    // 5. Exit back → RoomHouse; the door must now show its open state.
    await clickGame("exit to house", CLICKS.exit_to_house);
    await waitFor("room == RoomHouse", (s) => s.room === "RoomHouse");
    await sleep(600);
    await shot("back_home");

    const finalState = await probe();
    logLine(`final state: ${JSON.stringify(finalState)}`);
    if (!finalState || finalState.room !== "RoomHouse" || !finalState.flags?.office_latch_open || !finalState.flags?.mirror_mounted) {
      failures.push(`final state unexpected: ${JSON.stringify(finalState)}`);
    }

    // 6. Keyboard save (F5) → "New game" button → keyboard load (F9): flags must come back.
    //    Also proves the canvas swallows F5 instead of letting the browser reload the page.
    await waitIdle("before F5");
    const beforeF5 = await probe();
    await page.keyboard.press("F5"); // canvas already has focus (focus_canvas_on_start + prior clicks)
    const afterF5 = await waitFor("F5 saved (hint)", (s) => s.last_hint && s.last_hint.startsWith("Сохранено"));
    if (!afterF5) failures.push("page reloaded or probe lost after pressing F5 (browser reload not prevented)");
    await clickGame("New game button", CLICKS.new_game_button);
    await waitFor("new game cleared flags", (s) => s.flags && Object.keys(s.flags).length === 0 && s.room === "RoomHouse");
    await sleep(300);
    await shot("new_game");
    await page.keyboard.press("F9");
    await waitFor("F9 restored flags", (s) => s.flags?.office_latch_open === true && s.flags?.mirror_mounted === true);
    await sleep(600);
    await shot("after_f9_load");
    const loaded = await probe();
    const samePos =
      loaded && beforeF5 && Math.abs(loaded.player.x - beforeF5.player.x) < 1 && Math.abs(loaded.player.y - beforeF5.player.y) < 1;
    if (!loaded || loaded.room !== "RoomHouse" || !samePos) {
      failures.push(`state after F9 unexpected (expected player at ${JSON.stringify(beforeF5?.player)}): ${JSON.stringify(loaded)}`);
    }
  } catch (e) {
    failures.push(`exception: ${e.stack || e.message}`);
    logLine(`exception: ${e.stack || e.message}`);
    try { await shot("error"); } catch (_) {}
  } finally {
    fs.writeFileSync(path.join(SHOTS_DIR, "console.log"), consoleLog.join("\n") + "\n");
    await browser.close();
    server.close();
  }

  console.log("\nScreenshots:");
  for (const s of shots) console.log("  " + path.relative(ROOT, s));
  if (failures.length) {
    console.log("\nFAILURES:");
    for (const f of failures) console.log("  - " + f);
    process.exit(1);
  }
  console.log("\nAll steps reached their expected state.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
