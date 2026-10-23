#!/usr/bin/env python3
"""Покрытие озвучки: что в игре должно звучать, что записано и актуально, что устарело, чего нет — и сколько символов
осталось синтезировать. Набор строк — тот же, что берёт конвейер (pipeline/voice/eleven_voice.py: реплики сцен и
заданий, слова варианта выбора, закадровые фразы по правилам data/story/voice.json, мысли Агаты, слова персонажей
рядом с Агатой); манифест — assets/voice/ru/manifest.json.

Не должны звучать (и не считаются недостающими): задания-резерв (quests.json reserve: true — в игре их нет), ключи
без ссылок в данных игры (игрок их не увидит), отложенные (voice.json → by_speaker.<персонаж>.hold), запасные записи
другого голоса (ключ читает персонаж).

  python3 tools/voice_coverage.py            таблица по блокам и итог
  python3 tools/voice_coverage.py --json F   то же в JSON (списки id по статусам)
  python3 tools/voice_coverage.py --list     плюс id недостающих и устаревших
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
MANIFEST = ROOT / "assets" / "voice" / "ru" / "manifest.json"

_spec = importlib.util.spec_from_file_location("eleven_voice", ROOT / "pipeline" / "voice" / "eleven_voice.py")
ev = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ev)

BLOCK_OF_TEXT = {"ru_E0_E1": "1 день первый", "ru_bag": "1 день первый", "ru_E2_E3": "2 день второй",
                 "ru_mechanics": "2 день второй", "ru_E4_E5": "3 дни 3–4, эпилог"}
BLOCK_OF_EPISODE = {0: "1 день первый", 1: "1 день первый", 2: "2 день второй", 3: "2 день второй",
                    4: "3 дни 3–4, эпилог", 5: "3 дни 3–4, эпилог"}


def sha1(t: str) -> str:
    return hashlib.sha1(t.encode("utf-8")).hexdigest()


def scene_blocks() -> dict[str, str]:
    out: dict[str, str] = {}
    for f in sorted((STORY / "scenes").glob("E*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        for sc in d.get("scenes", []):
            out[str(sc["id"])] = BLOCK_OF_EPISODE.get(int(d.get("episode", 0)), "?")
    for q in json.loads((STORY / "quests.json").read_text(encoding="utf-8")).get("quests", []):
        out[str(q["id"])] = "4 истории (резерв)" if q.get("reserve") else "4 истории"
    return out


def kind_of(lid: str, ln: dict) -> str:
    if ln.get("kind") != "narration":
        if ln["speaker"] == "narrator":
            return "закадровые строки сцен"
        return "реплики Агаты в сценах" if ln["speaker"] == "agata" else "реплики персонажей в сценах"
    if ln.get("as_line"):
        return "слова персонажа рядом с Агатой"
    if ln.get("profile") == "inner":
        return "мысли Агаты (by_speaker)"
    if ln["speaker"] == "agata":
        return "мысли/слова Агаты (line)"
    return "закадровый: осмотры, действия, крупные планы"


def coverage() -> dict:
    lines = ev.all_lines()
    blocks = scene_blocks()
    man = (json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}).get("lines", {})
    rows = []
    for lid, ln in lines.items():
        narr = ln.get("kind") == "narration"
        if narr and not ln.get("assigned", True):
            continue   # запасная запись другого голоса — не цель покрытия
        block = (BLOCK_OF_TEXT.get(ln["source"], "4 истории" if ln["source"].startswith("ru_Q") else "?")
                 if narr else blocks.get(ln["scene"], "?"))
        status = ""
        if narr and not ln.get("used", True):
            status = "не звучит: нет ссылок в данных"
        elif narr and ln.get("hold"):
            status = "не звучит: отложено (hold)"
        elif not narr and block.endswith("(резерв)"):
            status = "не звучит: задание-резерв"
        else:
            e = man.get(lid)
            if e is None:
                status = "нет записи"
            elif "stale" in e or e.get("text_sha1") != sha1(ln["text"]):
                status = "устарела"
            elif e.get("voice_sha1", e.get("text_sha1")) != sha1(ev.api_text(ln)):
                status = "теги изменены"
            elif not (MANIFEST.parent / str(e.get("file", "-"))).is_file():
                status = "нет файла"
            else:
                status = "записана"
        rows.append({"id": lid, "block": block, "kind": kind_of(lid, ln), "speaker": ln["speaker"], "status": status,
                     "chars": len(ev.api_text(ln))})
    return {"rows": rows}


def main() -> int:
    cov = coverage()
    rows = cov["rows"]
    todo = {"нет записи", "устарела", "теги изменены", "нет файла"}
    blocks = sorted({r["block"] for r in rows})
    statuses = ["записана", "устарела", "теги изменены", "нет файла", "нет записи",
                "не звучит: нет ссылок в данных", "не звучит: отложено (hold)", "не звучит: задание-резерв"]
    print(f"{'блок':22} " + " ".join(f"{s[:14]:>14}" for s in statuses) + f" {'к синтезу, симв.':>17}")
    total_chars = 0
    for b in blocks:
        br = [r for r in rows if r["block"] == b]
        ch = sum(r["chars"] for r in br if r["status"] in todo)
        total_chars += ch
        print(f"{b:22} " + " ".join(f"{sum(1 for r in br if r['status'] == s):>14}" for s in statuses) + f" {ch:>17}")
    print(f"{'итого':22} " + " ".join(f"{sum(1 for r in rows if r['status'] == s):>14}" for s in statuses) + f" {total_chars:>17}")
    print()
    kinds = sorted({r["kind"] for r in rows})
    for k in kinds:
        kr = [r for r in rows if r["kind"] == k]
        print(f"  {k:46} всего {len(kr):4}  записано {sum(1 for r in kr if r['status'] == 'записана'):4}  "
              f"к синтезу {sum(1 for r in kr if r['status'] in todo):4} ({sum(r['chars'] for r in kr if r['status'] in todo)} симв.)")
    if "--list" in sys.argv:
        for s in ("устарела", "теги изменены", "нет файла", "нет записи", "не звучит: нет ссылок в данных",
                  "не звучит: отложено (hold)", "не звучит: задание-резерв"):
            ids = [r["id"] for r in rows if r["status"] == s]
            if ids:
                print(f"\n{s} ({len(ids)}): {', '.join(ids)}")
    if "--json" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--json") + 1])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(cov, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
