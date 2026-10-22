#!/usr/bin/env python3
"""Автопроверка листа персонажа по sprites.json конвейера (F16 23.10: «у Агаты будто бы мало fps»).

- ходьба: не меньше 20 кадров на цикл, темп листа (fps) совпадает с собственным темпом клипа (кадры / длительность
  цикла) с точностью 10 % — иначе ноги в игре идут быстрее или медленнее, чем шагает клип;
- у каждого действия есть лист, кадры и темп; кадров не меньше, чем в запросе.

  python pipeline/render/check_sprites.py --sprites assets/characters/<name>/sprites.json [--request pipeline/requests/<name>.json]
Код 1 — порок; числа печатаются.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

WALK_MIN_FRAMES = 20
FPS_TOL = 0.10


def check(sprites: dict, req: dict | None) -> list:
    bad = []
    want = (req or {}).get("frames", {})
    for a, act in sprites.get("actions", {}).items():
        n, fps = int(act.get("frames", 0)), float(act.get("fps", 0))
        if n <= 0 or fps <= 0:
            bad.append(f"{a}: кадров {n}, темп {fps}")
            continue
        if a in want and n < int(want[a]):
            bad.append(f"{a}: кадров {n} меньше запрошенных {want[a]}")
        if a == "walk" or a.startswith("walk"):
            if n < WALK_MIN_FRAMES:
                bad.append(f"{a}: {n} кадров на цикл < {WALK_MIN_FRAMES}")
            nat = act.get("natural_fps")
            if nat is None:
                bad.append(f"{a}: нет natural_fps (лист не из нынешнего render_sprites)")
            elif abs(fps - float(nat)) > FPS_TOL * float(nat):
                bad.append(f"{a}: темп листа {fps} ≠ темп клипа {nat} (±{FPS_TOL * 100:.0f} %)")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sprites", required=True)
    ap.add_argument("--request", default="")
    args = ap.parse_args()
    sp = json.loads(Path(args.sprites).read_text(encoding="utf-8"))
    req = json.loads(Path(args.request).read_text(encoding="utf-8")) if args.request else None
    for a, act in sp.get("actions", {}).items():
        print(f"{sp.get('name')}/{a}: {act.get('frames')} кадров, {act.get('fps')} к/с, клип {act.get('clip_seconds')} с, "
              f"свой темп {act.get('natural_fps')} к/с", flush=True)
    bad = check(sp, req)
    print(f"лист {sp.get('name')}: " + ("ок" if not bad else "НЕ ПРОШЛО: " + "; ".join(bad)), flush=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
