// Страница listen/: в режиме проверки (data.review) кнопка ▶ играет запись проверки, а не старый дубль той же строки.
// Дефект 29.10 (Директор: «произносимое и написанное не соответствует, перепутано»): обработчик клика искал строку
// сначала в data.lines (дубли 25.10), и у 55 строк, у которых были дубли, звучала старая запись под новым текстом.
// Запуск: node tools/listen_review_web.mjs — код 0, если ▶ у каждой строки проверки ставит в плеер её собственный файл.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";
import { createRequire } from "node:module";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch (_) {
  ({ chromium } = createRequire(process.env.PLAYWRIGHT_FROM || path.join(ROOT, "package.json"))("playwright"));
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "listen-"));
fs.copyFileSync(path.join(ROOT, "game/web/listen/index.html"), path.join(dir, "index.html"));
const data = {
  generated_at: "test",
  lines: [{ id: "M09_3", speaker: "pavel", speaker_name: "Павел", group: "M09", context: "", text: "старый текст", direction: {},
            takes: [{ take: 1, main: true, ogg: "takes/M09_3_t1.ogg", mp3: "takes/M09_3_t1.mp3" }] }],
  review: [{ id: "M09_3", speaker: "pavel", speaker_name: "Павел", group: "M09", context: "", text: "новый текст", voice_text: "", note: "",
             takes: [{ take: 1, main: true, mp3: "review/src/M09_3.mp3" }] },
           { id: "M01_0", speaker: "tamara", speaker_name: "Тамара", group: "M01", context: "", text: "только новая", voice_text: "", note: "",
             takes: [{ take: 1, main: true, mp3: "review/src/M01_0.mp3" }] }],
  review_title: "Проверка",
};
fs.writeFileSync(path.join(dir, "takes.json"), JSON.stringify(data));
const srv = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split("?")[0]));
  if (fs.existsSync(p) && fs.statSync(p).isFile()) { res.writeHead(200); res.end(fs.readFileSync(p)); }
  else { res.writeHead(404); res.end(); }
}).listen(0);
const port = srv.address().port;
const browser = await chromium.launch(process.env.LISTEN_CHROME_CHANNEL ? { channel: process.env.LISTEN_CHROME_CHANNEL } : {});
const page = await browser.newPage();
await page.goto(`http://127.0.0.1:${port}/index.html`);
await page.waitForSelector("button.play");
let bad = 0;
for (const r of data.review) {
  await page.click(`#r-${r.id} button.play`);
  const src = await page.evaluate(() => (window.listenPlayer && window.listenPlayer.src) || "");
  const want = r.takes[0].mp3;
  const ok = src.endsWith(want);
  console.log(`${ok ? "PASS" : "FAIL"}  ${r.id}: ▶ → ${src.replace(/^.*?\/\/[^/]+\//, "")} (ждали ${want})`);
  if (!ok) bad++;
}
await browser.close();
srv.close();
process.exit(bad ? 1 : 0);
