"""«Утро 1 ноября — на выбор»: decision page (cards with options: picture/video + text, «Эта», note) → db marks.
Style and marks logic — the voice pages' (k10page). Spec: rows.json in this folder."""
import json, re, shutil, sys
from pathlib import Path
# usage: python3 -I tools/decision_page.py rows.json <out_dir> "<title>" <media_dir>
#   rows.json — список карточек {id, n, section?, title, ctx?, info: [..], figs?: [{src, cap}], multi?: true,
#   options: [{id, label, text?, media?: [file]}], none_label?} (образец Docs/decision_pages/rows_morning_2026-11-01.json);
#   media — папка с картинками/видео, на которые ссылаются карточки; потом publish_files по files.json и
#   declare_capabilities {"db": {}}; отметки Директора — db_list коллекции marks ({pick, note, at}).
ROOT = Path(__file__).resolve().parent.parent
rows = json.load(open(sys.argv[1], encoding='utf-8'))
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
TITLE = sys.argv[3] if len(sys.argv) > 3 else 'На выбор'
# the page's lead line (01.11: it was hard-coded from the morning page and showed on every page)
LEAD = sys.argv[5] if len(sys.argv) > 5 else 'В каждой карточке выберите вариант («Эта») или напишите своё; отметки сохраняются сами, выбранное сразу пойдёт в работу.'
MEDIA = Path(sys.argv[4]) if len(sys.argv) > 4 else Path(sys.argv[1]).parent / 'media'
head = open(ROOT / 'Docs/decision_pages/template_head.html', encoding='utf-8').read().replace('{{TITLE}}', TITLE)
extra_css = '''
.opt { display: grid; gap: 8px; padding: 10px; border-radius: 5px; background: var(--field); border: 1px solid transparent; }
.opt.on { border-color: var(--gold); }
.opt .ol { font-family: var(--f-display); font-weight: 700; color: var(--gold); font-size: 1.1rem; }
.opt p { margin: 0; font-size: .95rem; }
.opt img, .opt video { width: 100%; height: auto; border-radius: 4px; display: block; background: #000; }
.opt .media2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr)); gap: 8px; }
.opt .media2 img, .opt .media2 video { max-height: 420px; object-fit: contain; }
.info { margin: 0; font-size: .95rem; color: var(--ink); max-width: 64ch; }
.info + .info { color: var(--muted); }
.fig { display: grid; gap: 6px; }
.fig img, .fig video { width: 100%; border-radius: 4px; display: block; }
.fig figcaption { color: var(--muted); font-size: .85rem; }
'''
body = '''</style></head><body>
<div class="wrap">
  <h1>{{TITLE}} — на выбор</h1>
  <p class="lead">{{LEAD}}</p>
  <div class="bar" role="status">
    <span class="count" id="count">Отмечено 0 из 0</span>
    <span class="meter" aria-hidden="true"><i id="meterfill"></i></span>
    <button type="button" class="b-filter" id="filter" aria-pressed="false">Только неотмеченные</button>
    <span class="save" id="save">Подключаю хранилище…</span>
    <button type="button" class="copy" id="copy" hidden>Скопировать отметки</button>
  </div>
  <div id="list" class="wrap" style="padding:0;gap:18px"></div>
</div>
<script>
const ROWS = ''' + json.dumps(rows, ensure_ascii=False) + ''';
const marks = {};
let db = null, local = false, onlyOpen = false;
const queues = {};
const KEY = "{{KEY}}";
function load() { try { const s = localStorage.getItem(KEY); if (s) Object.assign(marks, JSON.parse(s)); } catch (e) {} }
function keepLocal() { try { localStorage.setItem(KEY, JSON.stringify(marks)); } catch (e) {} }
function el(tag, attrs = {}, kids = []) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) { if (k === "text") n.textContent = v; else if (k === "class") n.className = v; else n.setAttribute(k, v); }
  for (const c of kids) if (c) n.append(c);
  return n;
}
function media(m) {
  if (!m) return null;
  if (m.endsWith(".mp3")) return el("audio", {src: m, controls: "", preload: "metadata", style: "width:100%"});
  if (m.endsWith(".mp4")) return el("video", {src: m, poster: m.replace(".mp4", "_poster.jpg"), controls: "", loop: "", muted: "", playsinline: "", preload: "metadata"});
  return el("img", {src: m, alt: "", loading: "lazy"});
}
function render() {
  const list = document.getElementById("list");
  list.textContent = "";
  let shown = 0, lastSect = "";
  for (const r of ROWS) {
    if (onlyOpen && (marks[r.id] || {}).pick) continue;
    if (r.section && r.section !== lastSect) { lastSect = r.section; list.append(el("h2", {text: r.section})); }
    list.append(card(r));
    shown++;
  }
  if (!shown) list.append(el("p", {class: "empty", text: "Всё отмечено. Спасибо!"}));
  progress();
}
function card(r) {
  const m = marks[r.id] || {};
  const c = el("article", {class: "card" + (m.pick === "none" ? " redo" : m.pick ? " ok" : ""), id: "c-" + r.id});
  c.append(el("div", {class: "head"}, [el("span", {class: "num", text: r.n}), el("span", {class: "who", text: r.title}), r.ctx ? el("span", {class: "ctx", text: r.ctx}) : null]));
  for (const p of (r.info || [])) c.append(el("p", {class: "info", text: p}));
  for (const f of (r.figs || [])) c.append(el("figure", {class: "fig", style: "margin:0"}, [media(f.src), f.cap ? el("figcaption", {text: f.cap}) : null]));
  for (const o of r.options) {
    // r.multi: several options may be chosen — the pick is a comma-joined list
    const picks = String(m.pick || "").split(",").filter(Boolean);
    const on = r.multi ? picks.includes(o.id) : m.pick === o.id;
    const box = el("div", {class: "opt" + (on ? " on" : "")});
    box.append(el("div", {class: "row", style: "align-items:center;justify-content:space-between"}, [el("span", {class: "ol", text: o.label}), btn(on ? "Выбрано" : "Эта", "b-pick", on, () => setMark(r.id, {pick: r.multi ? (on ? picks.filter(x => x !== o.id) : picks.concat([o.id])).join(",") : (on ? "" : o.id)}))]));
    if (o.text) box.append(el("p", {text: o.text}));
    if (o.media && o.media.length) box.append(el("div", {class: "media2"}, o.media.map(media)));
    c.append(box);
  }
  if (r.none !== false) c.append(el("div", {class: "row"}, [btn(r.none_label || "Ни один — напишу своё", "b-redo", m.pick === "none", () => setMark(r.id, {pick: m.pick === "none" ? "" : "none"}))]));
  const ta = el("textarea", {id: "note-" + r.id, rows: "2", placeholder: r.placeholder || "Заметка (необязательно)"});
  ta.value = m.note || "";
  let timer = null;
  ta.addEventListener("input", () => { clearTimeout(timer); timer = setTimeout(() => setMark(r.id, {note: ta.value}, false), 900); });
  ta.addEventListener("blur", () => { clearTimeout(timer); if ((marks[r.id] || {}).note !== ta.value) setMark(r.id, {note: ta.value}, false); });
  c.append(ta);
  return c;
}
function btn(label, cls, on, fn) { const b = el("button", {type: "button", class: cls, "aria-pressed": on ? "true" : "false", text: label}); b.addEventListener("click", fn); return b; }
function setMark(id, patch, rerender = true) {
  marks[id] = Object.assign({pick: "", note: ""}, marks[id] || {}, patch, {at: new Date().toISOString()});
  keepLocal();
  const r = ROWS.find(x => x.id === id);
  if (rerender) { const old = document.getElementById("c-" + id); if (old) old.replaceWith(card(r)); }
  progress();
  write(id);
}
function write(id) {
  if (!db || local) return;
  const body = Object.assign({}, marks[id]);
  queues[id] = (queues[id] || Promise.resolve()).then(() => db.collection("marks").doc(id).set(body)).then(
    () => status("Сохранено " + new Date().toLocaleTimeString("ru-RU", {hour: "2-digit", minute: "2-digit"})),
    (e) => { local = true; status("Не сохраняется на странице (" + (e && e.code || "ошибка") + ") — нажмите «Скопировать отметки»", true); document.getElementById("copy").hidden = false; });
}
function progress() {
  const n = ROWS.filter(r => (marks[r.id] || {}).pick || (marks[r.id] || {}).note).length;
  document.getElementById("count").textContent = "Отмечено " + n + " из " + ROWS.length;
  document.getElementById("meterfill").style.width = (ROWS.length ? 100 * n / ROWS.length : 0) + "%";
}
function status(t, warn = false) { const s = document.getElementById("save"); s.textContent = t; s.classList.toggle("warn", warn); }
document.getElementById("filter").addEventListener("click", (ev) => { onlyOpen = !onlyOpen; ev.currentTarget.setAttribute("aria-pressed", onlyOpen ? "true" : "false"); render(); });
document.getElementById("copy").addEventListener("click", async () => {
  const text = JSON.stringify({what: "{{TITLE}}", marks}, null, 1);
  try { await navigator.clipboard.writeText(text); status("Скопировано — вставьте в чат"); }
  catch (e) { const ta = el("textarea", {}); ta.value = text; document.querySelector(".wrap").append(ta); ta.select(); status("Выделено — скопируйте и вставьте в чат"); }
});
document.addEventListener("play", (ev) => { for (const a of document.querySelectorAll("video")) if (a !== ev.target) a.pause(); }, true);
load();
render();
(async () => {
  try { db = window.claude ? await window.claude.use("db") : null; } catch (e) { db = null; }
  if (!db) { local = true; status("Хранилище недоступно — отметки только в этом браузере, в конце нажмите «Скопировать отметки»", true); document.getElementById("copy").hidden = false; return; }
  status("Отметки сохраняются");
  db.collection("marks").onSnapshot((snap) => {
    let changed = false;
    for (const d of snap.docs) {
      const v = d.data();
      if (!v) continue;
      const cur = marks[d.id] || {};
      if (!cur.at || (v.at && v.at > cur.at)) { marks[d.id] = Object.assign({}, v); changed = true; }
    }
    if (changed) { keepLocal(); render(); }
  }, (e) => { status("Связь с хранилищем прервана — отметки только в этом браузере", true); document.getElementById("copy").hidden = false; local = true; });
})();
</script>
</body></html>'''
html = head + extra_css + body
import hashlib
html = html.replace('{{TITLE}}', TITLE).replace('{{LEAD}}', LEAD).replace('{{KEY}}', 'decision_' + hashlib.sha1(TITLE.encode('utf-8')).hexdigest()[:8])   # localStorage key per page (the marks themselves live in the page's db)
open(OUT / 'index.html', 'w', encoding='utf-8').write(html)
# media files referenced
files = [{"as": "index.html", "path": str(OUT / 'index.html')}]
seen = set()
for r in rows:
    for f in (r.get('figs') or []):
        seen.add(f['src'])
    for o in r['options']:
        for m in o.get('media', []):
            seen.add(m)
for m in sorted(seen):
    p = MEDIA / Path(m).name
    files.append({"as": m, "path": str(p)})
    if m.endswith('.mp4'):
        pp = MEDIA / Path(m.replace('.mp4', '_poster.jpg')).name
        if pp.exists():
            files.append({"as": m.replace('.mp4', '_poster.jpg'), "path": str(pp)})
json.dump(files, open(OUT / 'files.json', 'w'), ensure_ascii=False)
print('rows', len(rows), 'files', len(files))
