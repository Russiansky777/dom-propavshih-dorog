#!/usr/bin/env python3
"""Лицензии шрифтов для экрана «Лицензии» (ревью 12.11: «в игре нет текста лицензий» — нужно до Steam).

Движок отдаёт свою лицензию и сведения о сторонних компонентах сам (Engine.get_license_text, get_copyright_info,
get_license_info — https://docs.godotengine.org/en/stable/about/complying_with_licenses.html); шрифты игры идут под
SIL Open Font License 1.1, которая требует прикладывать к шрифту сведения об авторах и текст лицензии. Файлы OFL.txt
лежат рядом со шрифтами (game/assets/fonts/<шрифт>/OFL.txt), но .txt в сборку не попадает (экспорт берёт *.json) —
этот инструмент собирает их в game/data/licenses.json, откуда экран их и читает.

  python3 tools/make_licenses.py            собрать game/data/licenses.json
  python3 tools/make_licenses.py --check    файл соответствует шрифтам: у каждой папки шрифта есть запись с её OFL.txt
                                            целиком и именами её файлов .ttf/.otf (код 1 — нет)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "game" / "assets" / "fonts"
OUT = ROOT / "game" / "data" / "licenses.json"
NAMES = {"pt_serif": "PT Serif", "old_standard_tt": "Old Standard TT", "bad_script": "Bad Script"}


def build() -> dict:
    fonts = []
    for d in sorted(p for p in FONTS.iterdir() if p.is_dir()):
        files = sorted(f.name for f in d.iterdir() if f.suffix.lower() in (".ttf", ".otf"))
        lic = d / "OFL.txt"
        fonts.append({"id": d.name, "name": NAMES.get(d.name, d.name), "files": files,
                      "license": "SIL Open Font License 1.1",
                      "text": lic.read_text(encoding="utf-8").replace("\r\n", "\n").strip() if lic.exists() else ""})
    return {"_comment": "Лицензии шрифтов игры для экрана «Лицензии» (tools/make_licenses.py из game/assets/fonts/<шрифт>/OFL.txt; "
                        "не править руками). Лицензию движка и его сторонних компонентов экран берёт у самого движка.",
            "fonts": fonts}


def problems(doc: dict) -> list[str]:
    out = []
    want = build()
    have = {f.get("id"): f for f in doc.get("fonts", [])}
    for f in want["fonts"]:
        if not f["files"]:
            continue
        if not f["text"]:
            out.append(f"шрифт {f['id']}: рядом нет OFL.txt — лицензию приложить нечем")
            continue
        h = have.get(f["id"])
        if h is None:
            out.append(f"шрифт {f['id']}: нет записи в game/data/licenses.json — python3 tools/make_licenses.py")
        elif h.get("text") != f["text"] or h.get("files") != f["files"] or h.get("name") != f["name"]:
            out.append(f"шрифт {f['id']}: запись в game/data/licenses.json не совпадает с папкой шрифта — пересобрать")
    for fid in have:
        if fid not in {f["id"] for f in want["fonts"]}:
            out.append(f"запись {fid}: такого шрифта в game/assets/fonts нет")
    return out


def main() -> int:
    if "--check" in sys.argv:
        doc = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
        bad = problems(doc)
        # самопроверка: запись с обрезанным текстом лицензии и пропавшая запись ловятся
        broken = json.loads(json.dumps(build()))
        if broken["fonts"]:
            broken["fonts"][0]["text"] = broken["fonts"][0]["text"][:200]
            lost = {"fonts": build()["fonts"][1:]}
            if not problems(broken) or not problems(lost):
                bad.append("самопроверка: обрезанная лицензия или пропавший шрифт не пойманы")
        for b in bad:
            print("FAIL  лицензии шрифтов: " + b)
        print(f"[licenses] make_licenses --check: {'OK' if not bad else 'FAIL'} ({len(doc.get('fonts', []))} шрифтов)")
        return 1 if bad else 0
    doc = build()
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"[licenses] {len(doc['fonts'])} шрифтов → {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
