#!/usr/bin/env python3
"""Автопроверка листа персонажа по sprites.json конвейера (F16 23.10: «у Агаты будто бы мало fps»).

- ходьба: не меньше 20 кадров на цикл, темп листа (fps) совпадает с собственным темпом клипа (кадры / длительность
  цикла) с точностью 10 % — иначе ноги в игре идут быстрее или медленнее, чем шагает клип;
- у каждого действия есть лист, кадры и темп; кадров не меньше, чем в запросе;
- стойка (F16/F22, 23.10: «будто бы 4–5 кадров меняются и всё»): соседние кадры не совпадают попиксельно,
  в цикле не меньше 20 разных кадров (по каждой строке листа).

  python pipeline/render/check_sprites.py --sprites assets/characters/<name>/sprites.json [--request pipeline/requests/<name>.json]
Код 1 — порок; числа печатаются.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

WALK_MIN_FRAMES = 20
IDLE_MIN_DISTINCT = 20
FPS_TOL = 0.10
SAME_PX = 0.5  # средняя разница каналов (0..255) по фигуре — кадры «одинаковые»


def idle_frames(sheet_path: Path, n: int, fw: int, fh: int, dirs: int) -> list:
    """По строкам листа: число разных кадров и пары одинаковых соседей."""
    import numpy as np  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415
    A = np.asarray(Image.open(sheet_path).convert("RGBA")).astype(np.int16)
    out = []
    for d in range(dirs):
        fr = [A[d * fh:(d + 1) * fh, i * fw:(i + 1) * fw] for i in range(n)]
        same = []
        distinct = 1
        for i in range(1, n):
            m = (fr[i][:, :, 3] > 0) | (fr[i - 1][:, :, 3] > 0)
            diff = float(np.abs(fr[i] - fr[i - 1])[m].mean()) if m.any() else 0.0
            if diff < SAME_PX:
                same.append(i)
            else:
                distinct += 1
        out.append((distinct, same))
    return out


def check(sprites: dict, req: dict | None, base: Path | None = None) -> list:
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
        if (a == "idle" or a.startswith("idle")) and base is not None and (base / act.get("sheet", a + ".png")).exists():
            rows = idle_frames(base / act.get("sheet", a + ".png"), n, int(sprites["frame_w"]), int(sprites["frame_h"]),
                               int(sprites.get("directions", 8)))
            worst = min(r[0] for r in rows)
            same = [(d, r[1]) for d, r in enumerate(rows) if r[1]]
            print(f"{sprites.get('name')}/{a}: разных кадров в цикле не меньше {worst} из {n} по строкам; одинаковые соседи: {same or 'нет'}", flush=True)
            if worst < IDLE_MIN_DISTINCT:
                bad.append(f"{a}: разных кадров {worst} < {IDLE_MIN_DISTINCT}")
            if same:
                bad.append(f"{a}: соседние кадры совпадают {same}")
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
    bad = check(sp, req, Path(args.sprites).parent)
    print(f"лист {sp.get('name')}: " + ("ок" if not bad else "НЕ ПРОШЛО: " + "; ".join(bad)), flush=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
