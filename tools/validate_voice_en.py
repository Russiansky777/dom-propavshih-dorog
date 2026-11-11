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




def _voice_trim_module():
    """tools/voice_trim.py (09.11): lines shortened for the game — the game's copy and manifest differ on purpose."""
    import importlib.util as _u
    sp = _u.spec_from_file_location("voice_trim", str(ROOT / "tools" / "voice_trim.py"))
    mod = _u.module_from_spec(sp)
    sp.loader.exec_module(mod)
    return mod

# 09.11: lines shortened for the game (data/story/voice_trim.json, tools/voice_trim.py)
try:
    TRIMS = json.loads((ROOT / "data/story/voice_trim.json").read_text(encoding="utf-8")).get("trims", {})
except (OSError, ValueError):
    TRIMS = {}


def trimmed_copy_ok(src, game) -> bool:
    mark = game.with_name(game.name + ".trim.json")
    if not game.is_file() or not mark.is_file():
        return False
    try:
        m = json.loads(mark.read_text(encoding="utf-8"))
    except ValueError:
        return False
    return m.get("src_md5") == hashlib.md5(src.read_bytes()).hexdigest()

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
        # 11.11 (run 42924844288): a line shortened for the game the pipeline marks stale against its full recording —
        # the game's copy plays it trimmed (voice_trim.py lifts the mark); checked below as a trimmed line
        trimmed_stale = "stale" in e and str(e["stale"]).startswith("текст изменён") and ("en/" + str(e.get("file", ""))) in TRIMS
        if "stale" in e and not trimmed_stale:
            warns.append(f"{lid}: stale ({e['stale']}) — игра не играет, нужна перезапись")
            continue
        cur = lines.get(lid)
        if cur is None:
            errors.append(f"{lid}: нет такой строки в game/data/story_en")
            continue
        trim = TRIMS.get("en/" + str(e.get("file", "")))
        if trim is not None:
            # 09.11: a line shortened for the game (data/story/voice_trim.json): its text now is the trimmed one
            if cur["text"] != trim.get("text"):
                errors.append(f"{lid}: обрезка голоса (voice_trim.json) звучит «{trim.get('text')}», а текст строки «{cur['text']}»")
        elif hashlib.sha1(cur["text"].encode("utf-8")).hexdigest() != e.get("text_sha1"):
            errors.append(f"{lid}: текст изменился после записи (sha1) — пометить stale запросом или перезаписать")
        f = EN / str(e.get("file", ""))
        if not f.is_file():
            errors.append(f"{lid}: нет файла {f.relative_to(ROOT)}")
            continue
        g = GAME_EN / str(e.get("file", ""))
        if trim is not None:
            if not trimmed_copy_ok(f, g):
                errors.append(f"{lid}: обрезанной копии игры {g.relative_to(ROOT)} нет или она не из этого исходника (tools/sync_voice.sh)")
        elif not g.is_file() or g.read_bytes() != f.read_bytes():
            errors.append(f"{lid}: копия игры {g.relative_to(ROOT)} не совпадает (tools/sync_voice.sh)")
    gm = GAME_EN / "manifest.json"
    if not gm.is_file() or gm.read_text(encoding="utf-8") != _voice_trim_module().expected_manifest(man_p.read_text(encoding="utf-8"), "en"):
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
