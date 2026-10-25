#!/usr/bin/env python3
"""Страница прослушивания дублей озвучки (I-T1, Директор 25.10) → build/web/listen/.

    python3 -I tools/listen_page.py [--out build/web/listen] [--takes assets/voice/ru_takes]

Берёт game/web/listen/index.html, шрифт игры и дубли из assets/voice/ru_takes (manifest.json пишет
pipeline/voice/eleven_voice.py, запрос "takes"), кладёт рядом takes.json: по строке — id, кто, где (сцена или комната),
текст, режиссура (data/story: поле direction), дубли (ogg и mp3 для Safari). Директор слушает и отмечает выбор
(localStorage), «Скачать выбор» — JSON для I-T3. Дублей нет — страница всё равно собирается (пишет «запись ещё не пришла»).
Вызывается из tools/export_web.sh после экспорта игры.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"


def read(p: Path, default=None):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=str(ROOT / "build" / "web" / "listen"))
    ap.add_argument("--takes", default=str(ROOT / "assets" / "voice" / "ru_takes"))
    a = ap.parse_args()
    out, tdir = Path(a.out), Path(a.takes)
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "game" / "web" / "listen" / "index.html", out / "index.html")
    (out / "fonts").mkdir(exist_ok=True)
    for f in ("OldStandard-Regular.ttf", "OldStandard-Bold.ttf"):
        src = ROOT / "game" / "assets" / "fonts" / "old_standard_tt" / f
        if src.is_file():
            shutil.copyfile(src, out / "fonts" / f)

    names = {c.get("id"): c.get("name", c.get("id")) for c in (read(STORY / "characters.json", {}) or {}).get("characters", [])}
    names.setdefault("narrator", "Рассказчик")
    locs = {}
    for l in (read(STORY / "locations.json", {}) or {}).get("locations", []):
        locs[l.get("id")] = l.get("name", l.get("id"))
    scenes, order = {}, []
    for f in sorted((STORY / "scenes").glob("E*.json")):
        for sc in (read(f, {}) or {}).get("scenes", []):
            scenes[sc["id"]] = sc
            order.append(sc["id"])
    for q in (read(STORY / "quests.json", {}) or {}).get("quests", []):
        scenes[q["id"]] = q
        order.append(q["id"])

    man = read(tdir / "manifest.json", {}) or {}
    rows = []
    for lid, e in (man.get("lines") or {}).items():
        takes = []
        for t in e.get("takes", []):
            rel = str(t.get("file", ""))
            if not rel or not (tdir / rel).is_file():
                continue
            dst = out / "takes" / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(tdir / rel, dst)
            item = {"take": t.get("take"), "ogg": "takes/" + rel, "tags": t.get("tags", []), "main": bool(t.get("main"))}
            srel = str(t.get("source", ""))
            if srel and (tdir / srel).is_file():
                mdst = out / "takes" / srel
                mdst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(tdir / srel, mdst)
                item["mp3"] = "takes/" + srel
            takes.append(item)
        if not takes:
            continue
        sid = str(e.get("scene", ""))
        if sid and sid in scenes:
            sc = scenes[sid]
            where = ", ".join(locs.get(x, x) for x in sc.get("locations", []))
            group = f"{sid} · {sc.get('title', '')}"
            context, rank = where, (order.index(sid), int(e.get("index", 0)), int(e.get("then", -1) if e.get("then") is not None else -1))
        else:
            key = str(e.get("key", lid.split(":", 1)[-1]))
            room = key.split(".", 1)[0]
            group = "Осмотры и реплики в комнатах"
            context, rank = f"{locs.get(room.rstrip('d'), room)} — {key}", (10_000, 0, 0)
        rows.append({"id": lid, "speaker": e.get("speaker", ""), "speaker_name": names.get(e.get("speaker", ""), e.get("speaker", "")),
                     "group": group, "context": context, "text": e.get("text", ""), "direction": e.get("direction", {}),
                     "takes": sorted(takes, key=lambda t: t["take"]), "_rank": rank, "_id": lid})
    rows.sort(key=lambda r: (r["_rank"], r["_id"]))
    for r in rows:
        r.pop("_rank")
        r.pop("_id")
    doc = {"generated_at": man.get("updated_at", ""), "lines": rows}
    (out / "takes.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    n = sum(len(r["takes"]) for r in rows)
    print(f"[listen] {out}: строк {len(rows)}, файлов дублей {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
