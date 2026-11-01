#!/usr/bin/env python3
"""Страница «N-й заход голоса» для Директора: записи-пробы (pipeline/voice/probe/K3/W###_k.mp3 + .json со STT)
по строкам → папка с index.html, a/*.mp3 и files.json для publish_files (artifacts MCP; после публикации объявить
capabilities {"db": {}} — отметки Директора сохраняются в базе страницы, читать db_list коллекции marks).

    python3 -I tools/voice_round_page.py --rows rows.json --request voice_K18.json [--request voice_K19.json]
        --title "Четырнадцатый заход голоса" --short "Четырнадцатый заход" --k K18 --lead "…" --out /tmp/k14page

rows.json — список {w, line, note, speaker, subtitle[, current: "W012_3 (почему)"]} (образец Docs/voice_pages/rows_K13_example.json):
w — номер записей (W193 → дубли W193_1…3 из запроса), line — id строки (как в запросе), note — что это и зачем
(показывается над дублями), subtitle — текст субтитра в игре, current — запись, которая сейчас в игре (если есть).
Шаблон — Docs/voice_pages/template_round.html (страница «Тринадцатый заход» с подстановками).
"""
from __future__ import annotations
import argparse, json, re, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / 'data/story'
PROBE = ROOT / 'pipeline/voice/probe/K3'
LABELS = 'АБВГД'


def norm(t: str) -> list[str]:
    t = re.sub(r'\[[^\]]*\]', ' ', t).replace('́', '').lower().replace('ё', 'е')
    return re.sub(r'[^а-яa-z0-9 ]+', ' ', t).split()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--rows', required=True)
    ap.add_argument('--request', action='append', required=True, help='pipeline/requests/voice_K##.json (можно несколько)')
    ap.add_argument('--title', required=True)
    ap.add_argument('--short', required=True)
    ap.add_argument('--k', required=True)
    ap.add_argument('--lead', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    out = Path(a.out)
    (out / 'a').mkdir(parents=True, exist_ok=True)
    rows = json.load(open(a.rows, encoding='utf-8'))
    names = {c['id']: c.get('name', c['id']) for c in json.load(open(STORY / 'characters.json', encoding='utf-8'))['characters']}
    names['narrator'] = 'Рассказчик'
    locs = {l['id']: l.get('name', l['id']) for l in json.load(open(STORY / 'locations.json', encoding='utf-8'))['locations']}
    items: dict[str, list] = {}
    for rf in a.request:
        p = Path(rf) if Path(rf).exists() else ROOT / 'pipeline/requests' / rf
        for it in json.load(open(p, encoding='utf-8'))['items']:
            items.setdefault(it['line'], []).append(it)

    def context(lid: str) -> str:
        key = lid.split(':', 1)[-1]
        room = re.sub(r'd$', '', key.split('.')[0])
        return f"{locs.get(room, room)} · {key}"

    def take_entry(tid: str, label: str, text_expected: str, variant: str = '') -> dict:
        js = json.load(open(PROBE / f'{tid}.json', encoding='utf-8'))
        heard = (js.get('stt') or {}).get('text', '')
        hw = set(norm(heard))
        miss = [w for w in norm(text_expected) if w not in hw and len(w) > 2]
        shutil.copyfile(PROBE / f'{tid}.mp3', out / 'a' / f'{tid}.mp3')
        e = {"take": tid, "label": label, "file": f"a/{tid}.mp3", "miss": miss}
        if variant:
            e['variant'] = variant
        return e

    page_rows = []
    for r in rows:
        its = sorted([x for x in items.get(r['line'], []) if x['id'].startswith(r['w'] + '_')], key=lambda x: int(x['take']))
        if not its:
            raise SystemExit(f"{r['w']}: нет дублей в запросах для строки {r['line']}")
        takes = [take_entry(it['id'], LABELS[k], it['text'], it.get('variant', '')) for k, it in enumerate(its)]
        if r.get('current'):
            tid = r['current'].split()[0]
            g = take_entry(tid, 'В игре', r['subtitle'], 'сейчас в игре (' + r['current'].split(' ', 1)[1].strip('()') + ')')
            g['game'] = True
            takes.append(g)
        page_rows.append({"id": r['w'], "n": int(r['w'][1:]), "kind": "pick", "line": r['line'], "who": names.get(r['speaker'], r['speaker']),
                          "context": context(r['line']), "subtitle": r['subtitle'], "before": r['note'], "takes": takes})
    html = open(ROOT / 'Docs/voice_pages/template_round.html', encoding='utf-8').read()
    html = html.replace('{{TITLE_SHORT}}', a.short).replace('{{TITLE}}', a.title).replace('{{K}}', a.k).replace('{{LEAD}}', a.lead)
    html = html.replace('{{ROWS}}', json.dumps(page_rows, ensure_ascii=False))
    (out / 'index.html').write_text(html, encoding='utf-8')
    files = [{"as": "index.html", "path": str(out / 'index.html')}] + [{"as": f"a/{p.name}", "path": str(p)} for p in sorted((out / 'a').glob('*.mp3'))]
    json.dump(files, open(out / 'files.json', 'w'), ensure_ascii=False)
    print('rows', len(page_rows), 'files', len(files), '→', out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
