#!/usr/bin/env python3
"""Действия Агаты у предметов и сидячая поза в кадрах — автопроверка (партия G, 23.10).

G1 (Директор: «странные взмахи руками»): действие «reach» было клипом Meshy «сорвать яблоко и положить в корзину»
(6,2 с) — три взмаха обеими руками, сжатые в 1,3 с. Теперь «reach» — взять или положить у пояса (open_door:
протянуть руку и вернуть), «pick» — наклон и подъём без «осмотра» у лица. Проверки по листам игры
(game/assets/characters/<id>/sprites.json, упакованные атласы) и данным актёра (game/data/actors/<id>.json):
  1. одноразовое действие (loop false) короткое: кадры / темп ≤ max_s из данных актёра (actions.<a>.max_s),
     по умолчанию ≤ 1,7 с; ключевой кадр внутри клипа;
  2. начинается и кончается в позе стойки: силуэт первого и последнего кадра каждой строки совпадает с первым
     кадром стойки (IoU ≥ 0,85) — переход стойка ↔ действие без скачка;
  3. без размаха: силуэт в каждой строке не шире стойки больше чем в max_width_ratio раз (actions.<a>.
     max_width_ratio в данных актёра; прежний «reach» — руки в стороны, в анфас ×1,9).
G53 (Директор: «Агата стоит у края стола») — кадры с персонажем из листа (поле compose слоя в rooms/*.json):
  4. compose.action есть в листе персонажа (assets/characters/<набор>/sprites.json), compose.dir — строка листа,
     compose.frame — кадр;
  5. сидячая поза за столом (compose.action == "sit"): у слоя есть hide (что на картине перед ней) и
     слой стоит раньше слоя с семьёй (если он указан в compose.below) — нарисованные руки и посуда поверх;
  6. картинки слоёв совпадают с данными (tools/make_frame_layers.py --check для этих кадров).

  python3 tools/validate_actor_actions.py [--quiet]
Код 1 — порок (числа печатаются).
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
    Image.MAX_IMAGE_PIXELS = None  # листы Агаты 2,25× (G56): сетка pick 34 560 × 6 912 px
except ImportError:  # CI без Pillow: проверка листов — в локальном tools/run_tests.sh (Pillow есть у конвейера и агентов)
    Image = None

ROOT = Path(__file__).resolve().parent.parent
ACTORS = ROOT / "game" / "data" / "actors"
ROOMS = ROOT / "data" / "story" / "rooms"
DEFAULT_MAX_S = 1.7
IOU_MIN = 0.85
ALPHA = 128


def res_path(res: str) -> Path:
    return ROOT / "game" / res[len("res://"):] if res.startswith("res://") else ROOT / res


def frame_mask(sheet, act: dict, fw: int, fh: int, d: int, i: int):
    """sheet — картинка листа или список страниц атласа (седьмое число куска — номер страницы)."""
    n = int(act["frames"])
    rects = (act.get("atlas") or {}).get("rects")
    if rects:
        x, y, w, h, ox, oy = rects[d * n + i][:6]
        pg = rects[d * n + i][6] if len(rects[d * n + i]) > 6 else 0
        page = sheet[pg] if isinstance(sheet, list) else sheet
        fr = Image.new("L", (fw, fh), 0)
        fr.paste(page.crop((x, y, x + w, y + h)).getchannel("A"), (ox, oy))
    else:
        sheet = sheet[0] if isinstance(sheet, list) else sheet
        fr = sheet.crop((i * fw, d * fh, (i + 1) * fw, (d + 1) * fh)).getchannel("A")
    return fr.point(lambda v: 255 if v >= ALPHA else 0)


def _count(m) -> int:
    return m.histogram()[255]


def iou(a, b) -> float:
    u = _count(ImageChops.lighter(a, b))
    return _count(ImageChops.darker(a, b)) / u if u else 1.0


def width(m) -> int:
    bb = m.getbbox()
    return (bb[2] - bb[0]) if bb else 0


def check_actor(path: Path, quiet: bool) -> list:
    spec = json.loads(path.read_text(encoding="utf-8"))
    sdir = res_path(str(spec.get("sheet_dir", f"res://assets/characters/{spec.get('id', path.stem)}")))
    sp_path = sdir / str(spec.get("sprites", "sprites.json"))
    if not sp_path.exists():
        return []
    sp = json.loads(sp_path.read_text(encoding="utf-8"))
    fw, fh, dirs = int(sp["frame_w"]), int(sp["frame_h"]), int(sp.get("directions", 8))
    over = {k: v for k, v in (spec.get("actions") or {}).items() if isinstance(v, dict)}
    skip = set(spec.get("skip_actions", []))
    keyf = {k: v for k, v in (spec.get("action_key_frame") or {}).items() if not k.startswith("_")}
    idle_name = str(spec.get("idle_action", "idle"))
    acts = sp.get("actions", {})
    bad = []
    if idle_name not in acts:
        return bad
    idle = acts[idle_name]
    idle_img = Image.open(sdir / idle["sheet"]).convert("RGBA")
    idle0 = [frame_mask(idle_img, idle, fw, fh, d, 0) for d in range(dirs)]
    idle_w = [max(1, width(m)) for m in idle0]
    for a, o in over.items():
        if a in skip or a not in acts or o.get("loop", True):
            continue
        act = dict(acts[a])
        act.update(o)
        n, fps = int(act["frames"]), float(act.get("fps", 24))
        dur = n / fps
        cap = float(o.get("max_s", DEFAULT_MAX_S))
        if dur > cap + 1e-6:
            bad.append(f"{path.stem}/{a}: {n} кадров / {fps:g} к/с = {dur:.2f} с > {cap:g} с")
        if a in keyf and not (0 < int(keyf[a]) < n):
            bad.append(f"{path.stem}/{a}: ключевой кадр {keyf[a]} вне 1..{n - 1}")
        img = [Image.open(sdir / act["sheet"]).convert("RGBA")] + [
            Image.open(sdir / name).convert("RGBA") for name in (act.get("atlas") or {}).get("pages", [])[1:]]
        worst_io, worst_w = 1.0, 0.0
        for d in range(dirs):
            first, last = frame_mask(img, act, fw, fh, d, 0), frame_mask(img, act, fw, fh, d, n - 1)
            io = min(iou(first, idle0[d]), iou(last, idle0[d]))
            worst_io = min(worst_io, io)
            if io < IOU_MIN:
                bad.append(f"{path.stem}/{a} строка {d}: первый/последний кадр не в позе стойки (IoU {io:.2f} < {IOU_MIN})")
            wr = max(width(frame_mask(img, act, fw, fh, d, i)) for i in range(n)) / idle_w[d]
            worst_w = max(worst_w, wr)
            cap_w = o.get("max_width_ratio")
            if cap_w is not None and wr > float(cap_w):
                bad.append(f"{path.stem}/{a} строка {d}: силуэт шире стойки в {wr:.2f} раза > {cap_w} (размах рук)")
        if not quiet:
            print(f"  {path.stem}/{a}: {n} кадров, {dur:.2f} с (≤ {cap:g}); начало/конец ↔ стойка IoU ≥ {worst_io:.2f}; "
                  f"ширина ≤ ×{worst_w:.2f} стойки" + (f" (≤ ×{o['max_width_ratio']})" if "max_width_ratio" in o else ""))
    return bad


def check_frames(quiet: bool) -> list:
    bad, ids = [], []
    for rf in sorted(ROOMS.glob("*.json")):
        if rf.name.startswith("_"):
            continue
        room = json.loads(rf.read_text(encoding="utf-8"))
        layers = room.get("layers", [])
        order = [l.get("id") for l in layers]
        for li, l in enumerate(layers):
            c = l.get("compose") or {}
            if "char" not in c:
                continue
            cset = {"tamara": "tamara_v3"}.get(c["char"], c["char"])
            sp_path = ROOT / "assets" / "characters" / cset / "sprites.json"
            if not sp_path.exists():
                continue
            sp = json.loads(sp_path.read_text(encoding="utf-8"))
            a = c.get("action", "idle")
            where = f"{room['id']}.{l.get('id')}"
            if a not in sp.get("actions", {}):
                bad.append(f"{where}: действия «{a}» нет в листе {cset}")
                continue
            if not (0 <= int(c.get("dir", 0)) < int(sp.get("directions", 8))):
                bad.append(f"{where}: строка {c.get('dir')} вне листа")
            if not (0 <= int(c.get("frame", 0)) < int(sp["actions"][a]["frames"])):
                bad.append(f"{where}: кадр {c.get('frame')} вне листа {a}")
            if a == "sit":
                ids.append(room["id"])
                if not c.get("hide"):
                    bad.append(f"{where}: сидит за столом, но нет hide — стол и посуда не перед ней")
                below = c.get("below")
                if below and (below not in order or order.index(below) < li):
                    bad.append(f"{where}: слой должен стоять раньше «{below}» (нарисованные руки и посуда поверх)")
                if not quiet:
                    print(f"  {where}: сидит (лист {cset}/{a}, строка {c.get('dir')}), скрыто {len(c['hide'])} многоугольников, под слоем «{below}»")
    if ids:
        r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "make_frame_layers.py"), "--check", *sorted(set(ids))],
                           capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if line.startswith("DIFF"):
                bad.append(f"слой кадра не совпадает с данными: {line[5:]} — tools/make_frame_layers.py")
        if r.returncode not in (0, 1):
            bad.append(f"make_frame_layers --check: код {r.returncode}: {r.stderr.strip()[-300:]}")
    return bad


def main() -> int:
    quiet = "--quiet" in sys.argv
    if Image is None:
        print("validate_actor_actions: SKIP — нет Pillow (python3 -m pip install pillow)")
        return 0
    bad = []
    for p in sorted(ACTORS.glob("*.json")):
        bad += check_actor(p, quiet)
    bad += check_frames(quiet)
    for b in bad:
        print("FAIL", b)
    print("validate_actor_actions: " + ("OK" if not bad else f"{len(bad)} порок(ов)"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
