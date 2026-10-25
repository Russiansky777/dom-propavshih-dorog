#!/usr/bin/env python3
"""Вставка выбранных Директором дублей озвучки на место основной записи (I-T5 / I-T3; pipeline/voice/README → «Дубли»).

    python3 -I tools/apply_takes.py pipeline/requests/takes_I.json [--except ID ...] [--dry-run]

Файл выбора — выгрузка страницы прослушивания (`takes_choice.json`): choices.<id манифеста> = {take, speaker, text}.
Для take ≠ 1: `assets/voice/ru_takes/<файл>/take<k>.ogg` и `src/<файл>/take<k>.mp3` копируются на место основной записи
(`assets/voice/ru/<файл>.ogg`, `ru/src/<файл>.mp3`); в записи манифеста — `seed_salt` дубля (100 + k), `duration_s`, `lufs`
из `ru_takes/manifest.json` и `chosen_take`. text_sha1/voice_sha1 не трогаются (их сверяют игра и only_changed конвейера);
выравнивание основной записи (`alignment`) к дублю не относится — поле снимается.

Не вставляется (печатается почему): строка, чей текст с прослушивания уже не совпадает с текстом основной записи (текст
сменился — Директор слушает новые дубли); строка из --except (перезапись по замечаниям — выбор больше не действует);
дубль, которого нет в ru_takes. Повторный запуск ничего не меняет (chosen_take уже стоит).
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RU = ROOT / "assets" / "voice" / "ru"
TAKES = ROOT / "assets" / "voice" / "ru_takes"
TAKE_SALT = 100


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("choice")
    ap.add_argument("--except", dest="skip", nargs="*", default=[])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    choices = json.loads(Path(a.choice).read_text(encoding="utf-8"))["choices"]
    man_path = RU / "manifest.json"
    man = json.loads(man_path.read_text(encoding="utf-8"))
    tman = json.loads((TAKES / "manifest.json").read_text(encoding="utf-8"))["lines"]
    skip = set(a.skip)
    applied, kept = [], []
    for lid, ch in choices.items():
        k = int(ch.get("take", 1))
        if k == 1:
            continue
        e = man["lines"].get(lid)
        te = tman.get(lid)
        why = ""
        if lid in skip:
            why = "перезапись по замечаниям — выбор не действует"
        elif e is None or te is None:
            why = "нет в манифесте основной записи или дублей"
        elif e.get("chosen_take") == k:
            why = "уже вставлен"
        elif str(ch.get("text", "")) != str(e.get("text", "")) or te.get("text_sha1") != e.get("text_sha1"):
            why = "текст сменился после прослушивания"
        take = next((t for t in (te or {}).get("takes", []) if int(t.get("take", 0)) == k), None) if not why else None
        if not why and take is None:
            why = f"дубля {k} нет в ru_takes"
        if why:
            kept.append((lid, k, why))
            continue
        src_ogg, src_mp3 = TAKES / take["file"], TAKES / take["source"]
        dst_ogg, dst_mp3 = RU / e["file"], RU / e["source"]
        if not src_ogg.is_file():
            kept.append((lid, k, f"нет файла {src_ogg.relative_to(ROOT)}"))
            continue
        if not a.dry_run:
            shutil.copyfile(src_ogg, dst_ogg)
            if src_mp3.is_file():
                shutil.copyfile(src_mp3, dst_mp3)
            e["seed_salt"] = TAKE_SALT + k
            for f in ("duration_s", "lufs"):
                if f in take:
                    e[f] = take[f]
            e["chosen_take"] = k
            e["chosen_by"] = Path(a.choice).name
            e.pop("alignment", None)
        applied.append((lid, k))
    if applied and not a.dry_run:
        man_path.write_text(json.dumps(man, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for lid, k in applied:
        print(f"  вставлен  {lid:34} дубль {k}")
    for lid, k, why in kept:
        print(f"  оставлен  {lid:34} дубль {k}: {why}")
    print(f"apply_takes: вставлено {len(applied)}, не вставлено {len(kept)}" + (" (dry-run)" if a.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
