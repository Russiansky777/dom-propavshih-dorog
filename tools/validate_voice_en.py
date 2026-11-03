#!/usr/bin/env python3
"""Проверка английского голоса: assets/voice/en (запросы pipeline/requests/voice_EN_full_*.json, Директор 03.11).

    python3 -I tools/validate_voice_en.py [--quiet] [--strict]

1. Каждая запись манифеста assets/voice/en/manifest.json — строка английской копии данных game/data/story_en с тем же
   текстом (sha1, как сверяет игра — VoiceDirector при голосе и субтитрах на одном языке); файл на месте.
2. Копия игры game/assets/voice/en совпадает с assets/voice/en побайтно (tools/sync_voice.sh).
3. Покрытие: строки, что звучат по-русски (актуальные записи assets/voice/ru), без английской записи — предупреждение
   (--strict: ошибка) — английский голос экспериментальный, без записи строка идёт субтитрами.
Набора ещё нет — код 0 и сообщение.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EN = ROOT / "assets" / "voice" / "en"
RU = ROOT / "assets" / "voice" / "ru"
GAME_EN = ROOT / "game" / "assets" / "voice" / "en"


def _voice_module():
    spec = importlib.util.spec_from_file_location("eleven_voice", ROOT / "pipeline" / "voice" / "eleven_voice.py")
    m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(ROOT / "pipeline" / "voice"))
    spec.loader.exec_module(m)
    return m


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()
    man_p = EN / "manifest.json"
    if not man_p.is_file():
        print("[voice_en] набора assets/voice/en ещё нет — проверять нечего")
        return 0
    ev = _voice_module()
    ev.use_language("en")
    lines = ev.all_lines()
    man = json.loads(man_p.read_text(encoding="utf-8")).get("lines", {})
    errors: list[str] = []
    warns: list[str] = []
    for lid, e in sorted(man.items()):
        if "stale" in e:
            warns.append(f"{lid}: stale ({e['stale']}) — игра не играет, нужна перезапись")
            continue
        cur = lines.get(lid)
        if cur is None:
            errors.append(f"{lid}: нет такой строки в game/data/story_en")
            continue
        if hashlib.sha1(cur["text"].encode("utf-8")).hexdigest() != e.get("text_sha1"):
            errors.append(f"{lid}: текст изменился после записи (sha1) — пометить stale запросом или перезаписать")
        f = EN / str(e.get("file", ""))
        if not f.is_file():
            errors.append(f"{lid}: нет файла {f.relative_to(ROOT)}")
            continue
        g = GAME_EN / str(e.get("file", ""))
        if not g.is_file() or g.read_bytes() != f.read_bytes():
            errors.append(f"{lid}: копия игры {g.relative_to(ROOT)} не совпадает (tools/sync_voice.sh)")
    gm = GAME_EN / "manifest.json"
    if not gm.is_file() or gm.read_bytes() != man_p.read_bytes():
        errors.append("game/assets/voice/en/manifest.json не совпадает с assets/voice/en (tools/sync_voice.sh)")
    ru = json.loads((RU / "manifest.json").read_text(encoding="utf-8")).get("lines", {}) if (RU / "manifest.json").is_file() else {}
    missing = sorted(lid for lid, e in ru.items() if "stale" not in e and lid not in man)
    if missing:
        msg = f"без английской записи {len(missing)} строк (звучат по-русски): {', '.join(missing[:12])}{' …' if len(missing) > 12 else ''}"
        (errors if a.strict else warns).append(msg)
    ok = sum(1 for e in man.values() if "stale" not in e)
    print(f"[voice_en] записей {len(man)} (актуальных {ok}), ошибок {len(errors)}, предупреждений {len(warns)}")
    for w in warns[: (5 if a.quiet else 200)]:
        print(f"  предупреждение: {w}")
    for x in errors:
        print(f"  ОШИБКА: {x}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
