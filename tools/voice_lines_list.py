#!/usr/bin/env python3
"""Список всех озвученных строк для проверки на слух: Docs/voice_lines_<дата>.md.

Каждая строка: id (по нему Директор называет строку с неверным ударением или подачей), кто говорит, где звучит
(сцена/задание или комната ключа текста), текст субтитров. Порядок — по дням и сценам, как в игре; осмотры и
мысли — по комнатам. Источник — assets/voice/ru/manifest.json (актуальные записи) и данные сюжета.

  python3 tools/voice_lines_list.py [--date 2026-10-23]
"""
from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
MANIFEST = ROOT / "assets" / "voice" / "ru" / "manifest.json"


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def main() -> int:
    date = sys.argv[sys.argv.index("--date") + 1] if "--date" in sys.argv else dt.date.today().isoformat()
    man = load(MANIFEST).get("lines", {})
    names = {c["id"]: c.get("name") or c["id"] for c in load(STORY / "characters.json")["characters"]}
    names["narrator"] = "Рассказчик"
    scene_info: dict[str, tuple[int, int, str, str]] = {}   # id → (порядок эпизода, порядок сцены, эпизод, название)
    order = 0
    for f in sorted((STORY / "scenes").glob("E*.json")):
        d = load(f)
        for sc in d.get("scenes", []):
            order += 1
            scene_info[sc["id"]] = (int(d.get("episode", 0)), order, f"E{d.get('episode', 0)} {d.get('title', '')}", sc.get("title", ""))
    for q in load(STORY / "quests.json").get("quests", []):
        order += 1
        scene_info[q["id"]] = (9, order, "Необязательные истории", q.get("title", ""))
    rooms = {}
    for f in sorted((STORY / "rooms").glob("*.json")):
        d = load(f)
        rooms[f.stem] = d.get("title") or d.get("name") or f.stem
    day_of_text = {"ru_E0_E1": "День первый", "ru_bag": "Сумка (строки предметов)", "ru_E2_E3": "День второй",
                   "ru_mechanics": "Крупные планы предметов и механик", "ru_E4_E5": "Дни третий–четвёртый, эпилог"}

    sys.path.insert(0, str(ROOT / "tools"))
    import voice_coverage as vc   # noqa: E402
    rows = vc.coverage()["rows"]
    playing = {r["id"] for r in rows if r["status"] == "записана"}   # звучит в игре: назначенный голос, текст совпал
    scene_rows, narr_rows = [], []
    for lid, e in man.items():
        if "stale" in e or lid not in playing:
            continue   # устаревшие и запасные записи другого голоса не звучат
        who = names.get(str(e.get("speaker", "")), str(e.get("speaker", "")))
        text = " ".join(str(e.get("text", "")).split())
        if e.get("kind") == "narration":
            key = str(e.get("key", lid))
            room = key.split(".")[0]
            src = str(e.get("source_text", ""))
            narr_rows.append((day_of_text.get(src, src), room, lid, who, text, rooms.get(room, "")))
        else:
            sc = str(e.get("scene", ""))
            ep, so, ep_title, sc_title = scene_info.get(sc, (99, 9999, "?", ""))
            opt = f" (вариант «{e['option']}»)" if e.get("option") else ""
            scene_rows.append((ep, so, int(e.get("index", 0)), lid, who, text + opt, ep_title, sc, sc_title))
    scene_rows.sort()
    narr_rows.sort(key=lambda r: (list(day_of_text.values()).index(r[0]) if r[0] in day_of_text.values() else 99, r[1], r[2]))

    out = [f"# Озвученные строки — {date}", "",
           "Для проверки на слух: если ударение или подача не те — напиши **id** строки (первая колонка) и что не так "
           "(«M09_2: ударение в «затвор»», «agata:H3.school_door.use: слишком громко»). Перезаписываются только названные строки.",
           f"Всего: {len(scene_rows)} реплик в сценах и историях, {len(narr_rows)} осмотров, мыслей и слов персонажей в комнатах. "
           "Строки, которые в игре только субтитрами, — в конце файла (раздел «Без голоса»).", ""]
    cur_ep = None
    for ep, so, idx, lid, who, text, ep_title, sc, sc_title in scene_rows:
        if ep_title != cur_ep:
            out += ["", f"## {ep_title}", "", "| id | кто | сцена | текст |", "|---|---|---|---|"]
            cur_ep = ep_title
        out.append(f"| `{lid}` | {who} | {sc} {sc_title} | {text.replace('|', '/')} |")
    cur = None
    for day, room, lid, who, text, room_title in narr_rows:
        if day != cur:
            out += ["", f"## Осмотры, мысли, слова в комнатах — {day}", "", "| id | кто | где | текст |", "|---|---|---|---|"]
            cur = day
        out.append(f"| `{lid}` | {who} | {room}{(' ' + room_title) if room_title and room_title != room else ''} | {text.replace('|', '/')} |")
    # без голоса
    silent = [r for r in rows if r["status"].startswith("не звучит") or r["status"] in ("нет записи", "устарела", "нет файла", "теги изменены")]
    out += ["", "## Без голоса (только субтитры)", ""]
    if not silent:
        out.append("Нет.")
    for st in sorted({r["status"] for r in silent}):
        ids = [r["id"] for r in silent if r["status"] == st]
        out.append(f"- **{st}** ({len(ids)}): " + ", ".join(f"`{i}`" for i in ids))
    path = ROOT / "Docs" / f"voice_lines_{date}.md"
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{path.relative_to(ROOT)}: {len(scene_rows)} реплик, {len(narr_rows)} фраз в комнатах, без голоса {len(silent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
