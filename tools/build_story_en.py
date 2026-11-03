#!/usr/bin/env python3
"""Английская копия данных истории для игры: data/story + перевод data/l10n/en.json → game/data/story_en.

    python3 -I tools/build_story_en.py            # собрать (вызывается из tools/sync_story_data.sh)
    python3 -I tools/build_story_en.py --check    # только проверить, что копия свежая (код 1 — нет)
    python3 -I tools/build_story_en.py --import-tsv DIR   # перенести готовые части ChatGPT (en_part*_done.tsv) в en.json

Зачем (Директор 02.11–03.11: английские субтитры поверх русского голоса и английский голос — по выбору в меню): игра
читает тексты из res://data/story (русский) или res://data/story_en (английский, StoryData по настройке субтитров).
Копия — те же файлы, что data/story, где каждая видимая игроку строка заменена английской по тем же id и путям JSON,
что у tools/export_texts.py (выгрузка ChatGPT) и tools/import_texts.py. Поэтому сцены, комнаты, условия — одни и те же;
меняются только слова. Копия пересобирается при каждой синхронизации данных — устареть не может.

data/l10n/en.json: {"_comment", "rows": {id: {"ru": исходник, "en": перевод}}}. Строка, чей русский исходник с тех пор
изменился или которой нет в переводе, остаётся русской и попадает в отчёт `stale`/`missing` — её надо перевести заново
(tools/export_texts.py → ChatGPT → --import-tsv). Подстановки ({n} и т. п.) проверяются, как в import_texts.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import shutil
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
L10N = ROOT / "data" / "l10n" / "en.json"
OUT = ROOT / "game" / "data" / "story_en"


def _mod(name: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parent / f"{name}.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


ex = _mod("export_texts")
imp = _mod("import_texts")


def _set(doc, path, value):
    cur = doc
    for k in path[:-1]:
        cur = cur[k]
    cur[path[-1]] = value


def load_l10n() -> dict:
    if not L10N.exists():
        return {}
    return json.loads(L10N.read_text(encoding="utf-8")).get("rows", {})


def build() -> dict:
    """{rel: doc} of the English copy and the report."""
    rows = ex.collect()
    tr = load_l10n()
    docs: dict[str, object] = {}
    report = {"translated": 0, "stale": [], "missing": [], "placeholders": []}
    for f in sorted(STORY.rglob("*.json")):
        docs[str(f.relative_to(STORY))] = json.loads(f.read_text(encoding="utf-8"))
    for r in rows:
        if not r.importable:
            continue
        t = tr.get(r.id)
        if t is None or not str(t.get("en", "")).strip():
            report["missing"].append(r.id)
            continue
        if t.get("ru") != r.text:
            report["stale"].append(r.id)
            continue
        en = str(t["en"])
        if imp.placeholders(imp.strip_gloss(r.text)) != imp.placeholders(en):
            report["placeholders"].append(r.id)
            continue
        rel = str(Path(r.file).relative_to("data/story"))
        _set(docs[rel], r.path, en)
        report["translated"] += 1
    return {"docs": docs, "report": report}


def write(docs: dict) -> int:
    if OUT.exists():
        for f in OUT.rglob("*.json"):
            if str(f.relative_to(OUT)) not in docs:
                f.unlink()
    n = 0
    for rel, doc in docs.items():
        p = OUT / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        s = json.dumps(doc, ensure_ascii=False, indent=1) + "\n"
        if not p.exists() or p.read_text(encoding="utf-8") != s:
            tmp = p.with_suffix(p.suffix + ".tmp")
            tmp.write_text(s, encoding="utf-8")
            tmp.replace(p)
            n += 1
    return n


def import_tsv(d: Path) -> int:
    rows = {}
    for f in sorted(d.glob("en_part*_done.tsv")):
        with open(f, encoding="utf-8", newline="") as fh:
            for row in csv.DictReader(fh, delimiter="\t"):
                rows[row["id"]] = {"ru": ex.unesc(row["ru"]), "en": ex.unesc(row["en"])}
    doc = {"_comment": "Английский перевод видимых игроку строк (ChatGPT по пакету Docs/translation_en, 02.11.2026; "
                       "Директор 02.11 23:39). Ключ — id выгрузки tools/export_texts.py; ru — исходник на момент перевода "
                       "(если он изменился, строка в игре остаётся русской до нового перевода); en — перевод. "
                       "Сборка копии для игры — tools/build_story_en.py.",
           "rows": rows}
    L10N.parent.mkdir(parents=True, exist_ok=True)
    L10N.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"[story_en] {len(rows)} rows → {L10N.relative_to(ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--import-tsv")
    ap.add_argument("--report", action="store_true", help="print stale/missing ids")
    a = ap.parse_args()
    if a.import_tsv:
        return import_tsv(Path(a.import_tsv))
    b = build()
    rep = b["report"]
    summary = (f"[story_en] translated {rep['translated']}, stale {len(rep['stale'])}, missing {len(rep['missing'])}, "
               f"placeholder mismatches {len(rep['placeholders'])}")
    if a.check:
        bad = []
        for rel, doc in b["docs"].items():
            p = OUT / rel
            if not p.exists() or json.loads(p.read_text(encoding="utf-8")) != doc:
                bad.append(rel)
        extra = [str(f.relative_to(OUT)) for f in OUT.rglob("*.json") if str(f.relative_to(OUT)) not in b["docs"]] if OUT.exists() else []
        print(summary)
        if bad or extra:
            print(f"[story_en] FAIL: the copy is stale — {len(bad)} file(s) differ, {len(extra)} extra; run tools/sync_story_data.sh")
            return 1
        print("[story_en] OK: the copy is fresh")
        return 0
    n = write(b["docs"])
    print(summary + f"; wrote {n} file(s) → {OUT.relative_to(ROOT)}")
    if a.report:
        for k in ("stale", "missing", "placeholders"):
            for i in rep[k]:
                print(f"  {k}: {i}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
