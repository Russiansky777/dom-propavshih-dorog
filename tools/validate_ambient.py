#!/usr/bin/env python3
"""«Живой мир» — checks data/story/ambient/*.json (weather, wind, water, puddles, footprints, dust).

    python3 tools/validate_ambient.py [--quiet]

Exit code 0 when there are no errors (warnings do not fail). Stdlib only (runs in CI as is).

Checks:
  - every file parses, `id` == file name, `preset` exists in _index.json `presets`;
  - interiors (rooms/<LOC>.json background.kind == "interior") have no rain, water, puddles or mud
    (Director: «В помещениях — ничего этого»): only sway behind the windows and dust;
  - every polygon has 3..32 points inside the 1920x1080 frame (±10 px), no self-intersection;
    rects have a positive size; puddles lie on the room's floor (rooms/<LOC>.json walkable, centroid);
  - sway: kind tree|grass, 0 < amp_px ≤ 12, 0 < freq_hz ≤ 2, tree anchor below its top, a `layer`
    image or a `source: layer:<id>` exists; water: ≤ 4 exclude rects, ripple pair;
  - fog (Р2, партия J — туман над тем берегом): a polygon/rect, density and wisps 0..1, profile [top, core_top,
    core_bottom, bottom] not decreasing, color #rrggbb, 0 ≤ fade_s ≤ 20, flags known; counted in the overdraw;
  - dust ≤ 40 particles per emitter and ≤ 60 per room; rain intensity 0..1, |slant| ≤ 30°, ≤ 3 layers;
  - `if` / `unless` flags are known somewhere in data/story (flags.json or a room's sets/flags);
  - shader overdraw per room (regions + full-screen rain) ≤ 3 frames;
  - footfall per actor: contact frames inside the sheet, planted_foot_px 8 rows × contacts × [dx, dy],
    the sheet file exists (its contents are re-measured by game/tests/test_ambient.gd);
  - rain rings in puddles (Director 23.10, F21: «капли дождя в лужах усилить немного»): for every preset
    with rain and a puddle_style, rings per square metre per second (intensity × rings / cell² / period)
    ≥ PUDDLE_RINGS_MIN and ring_gain ≥ PUDDLE_GAIN_MIN — the old 5.5 rings/m²·s at gain 1 read as «dead»;
    and not above PUDDLE_RINGS_MAX (the same shader per pixel; more rings = busier, not dearer — a taste cap).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AMB = ROOT / "data" / "story" / "ambient"
ROOMS = ROOT / "data" / "story" / "rooms"
GAME = ROOT / "game"

W, H, MARGIN = 1920, 1080, 10
MAX_POLY = 32
TOP_KEYS = {"id", "preset", "rain", "wind", "sway_regions", "water", "puddles", "mud", "dust",
            "footfall", "water_style", "puddle_style", "fog", "wheel_water"}

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def merge(base: dict, over: dict) -> dict:
    out = json.loads(json.dumps(base))
    for k, v in over.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = merge(out[k], v)
        else:
            out[k] = v
    return out


def res_path(p: str) -> Path:
    return GAME / p[len("res://"):] if p.startswith("res://") else ROOT / p


def shape(entry: dict, where: str) -> list[tuple[float, float]] | None:
    if "polygon" in entry:
        pts = entry["polygon"]
        if not isinstance(pts, list) or not (3 <= len(pts) <= MAX_POLY):
            err(f"{where}: polygon needs 3..{MAX_POLY} points, has {len(pts) if isinstance(pts, list) else '?'}")
            return None
        out = []
        for p in pts:
            if not (isinstance(p, list) and len(p) == 2 and all(isinstance(v, (int, float)) for v in p)):
                err(f"{where}: bad point {p}")
                return None
            x, y = float(p[0]), float(p[1])
            if not (-MARGIN <= x <= W + MARGIN and -MARGIN <= y <= H + MARGIN):
                err(f"{where}: point {p} outside the 1920x1080 frame")
            out.append((x, y))
        if self_intersects(out):
            err(f"{where}: polygon crosses itself")
        return out
    if "rect" in entry:
        r = entry["rect"]
        if not (isinstance(r, list) and len(r) == 4) or r[2] <= 0 or r[3] <= 0:
            err(f"{where}: rect must be [x, y, w, h] with positive size")
            return None
        x, y, w, h = map(float, r)
        if x < -MARGIN or y < -MARGIN or x + w > W + MARGIN or y + h > H + MARGIN:
            err(f"{where}: rect {r} outside the frame")
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    return None


def _cross(o, a, b) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _segments_cross(p1, p2, p3, p4) -> bool:
    d1, d2 = _cross(p3, p4, p1), _cross(p3, p4, p2)
    d3, d4 = _cross(p1, p2, p3), _cross(p1, p2, p4)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0) and d1 * d2 < 0 and d3 * d4 < 0


def self_intersects(pts) -> bool:
    n = len(pts)
    for i in range(n):
        a1, a2 = pts[i], pts[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            if _segments_cross(a1, a2, pts[j], pts[(j + 1) % n]):
                return True
    return False


def area(pts) -> float:
    s = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2.0


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def inside(pt, pts) -> bool:
    x, y = pt
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi:
            c = not c
        j = i
    return c


def known_flags() -> set[str]:
    flags: set[str] = set()
    fj = ROOT / "data" / "story" / "flags.json"
    if fj.exists():
        doc = json.loads(fj.read_text(encoding="utf-8"))
        src = doc.get("flags", doc)
        if isinstance(src, dict):
            flags |= set(src.keys())
        elif isinstance(src, list):
            flags |= {f["id"] if isinstance(f, dict) else str(f) for f in src}
    # Any flag a room sets or declares (rooms/<LOC>.json), anywhere in its JSON.
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ("sets", "if", "unless", "requires") and isinstance(v, list):
                    flags.update(str(x) for x in v if isinstance(x, str))
                if k == "flags" and isinstance(v, dict):
                    flags.update(v.keys())
                walk(v)
        elif isinstance(o, list):
            for x in o:
                walk(x)
    for f in ROOMS.glob("*.json"):
        walk(json.loads(f.read_text(encoding="utf-8")))
    for f in (ROOT / "data" / "story" / "scenes").glob("*.json"):
        walk(json.loads(f.read_text(encoding="utf-8")))
    return flags


def check_flags(entry: dict, where: str, flags: set[str]) -> None:
    for key in ("if", "unless"):
        for f in entry.get(key, []):
            if f not in flags:
                warn(f"{where}: {key} flag '{f}' is not set or declared anywhere in data/story")


def check_room(path: Path, idx: dict, flags: set[str]) -> None:
    rid = path.stem
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        err(f"{path.name}: JSON error {e}")
        return
    if doc.get("id") != rid:
        err(f"{path.name}: id '{doc.get('id')}' must equal the file name '{rid}'")
    spec = doc
    preset = doc.get("preset")
    if preset:
        presets = idx.get("presets", {})
        if preset not in presets:
            err(f"{path.name}: unknown preset '{preset}'")
        else:
            spec = merge(presets[preset], doc)
    for k in spec:
        if not k.startswith("_") and k not in TOP_KEYS:
            err(f"{path.name}: unknown key '{k}'")
    room_file = ROOMS / f"{rid}.json"
    room = json.loads(room_file.read_text(encoding="utf-8")) if room_file.exists() else None
    if room is None:
        warn(f"{rid}: no rooms/{rid}.json yet — ambient waits for the room")
    kind = (room or {}).get("background", {}).get("kind", "exterior")
    layer_ids = {l.get("id") for l in (room or {}).get("layers", [])}
    if kind == "interior":
        for k in ("rain", "water", "puddles", "mud"):
            if spec.get(k):
                err(f"{rid}: interior room must not have '{k}' (only sway behind windows and dust)")
    overdraw = 0.0
    ids: set[str] = set()

    def uniq(e, where):
        i = e.get("id")
        if not i:
            err(f"{where}: entry without id")
        elif i in ids:
            err(f"{where}: duplicate id '{i}'")
        ids.add(i)

    def check_source(e, where):
        src = e.get("source", "background")
        if src != "background":
            if not src.startswith("layer:"):
                err(f"{where}: source must be 'background' or 'layer:<id>'")
            elif room is not None and src[6:] not in layer_ids:
                err(f"{where}: source layer '{src[6:]}' is not in rooms/{rid}.json layers")

    for i, r in enumerate(spec.get("sway_regions", [])):
        where = f"{rid}.sway_regions[{r.get('id', i)}]"
        uniq(r, where)
        check_flags(r, where, flags)
        check_source(r, where)
        pts = shape(r, where)
        if "layer" in r:
            img = r["layer"].get("image", "")
            if not res_path(img).exists():
                err(f"{where}: layer image not found: {img}")
        elif pts is None:
            err(f"{where}: needs a polygon, a rect or a layer")
        if pts:
            overdraw += area(pts)
        kind_r = r.get("kind", "tree")
        if kind_r not in ("tree", "grass"):
            err(f"{where}: kind must be tree or grass")
        amp = float(r.get("amp_px", 3.0))
        if not 0.0 < amp <= 12.0:
            err(f"{where}: amp_px {amp} outside (0, 12]")
        fq = float(r.get("freq_hz", 0.35))
        if not 0.0 < fq <= 2.0:
            err(f"{where}: freq_hz {fq} outside (0, 2]")
        if kind_r == "tree" and "anchor_y" in r and "top_y" in r and float(r["anchor_y"]) <= float(r["top_y"]):
            err(f"{where}: anchor_y must be below top_y (the root line is lower than the crown)")
        if "anchor_line" in r and not (isinstance(r["anchor_line"], list) and len(r["anchor_line"]) == 2):
            err(f"{where}: anchor_line must be [[x0, y0], [x1, y1]]")
    for key in ("water", "puddles"):
        for i, w in enumerate(spec.get(key, [])):
            where = f"{rid}.{key}[{w.get('id', i)}]"
            uniq(w, where)
            check_flags(w, where, flags)
            check_source(w, where)
            pts = shape(w, where)
            if pts is None:
                err(f"{where}: needs a polygon or a rect")
                continue
            overdraw += area(pts)
            if len(w.get("exclude", [])) > 4:
                err(f"{where}: at most 4 exclude rects")
            rp = w.get("ripple_px")
            if rp is not None and not (isinstance(rp, list) and len(rp) == 2):
                err(f"{where}: ripple_px must be [far, near]")
            # F14 (Director 23.10, «вода мёртвая»): trembling reflections, sparkles, flow lines — cheap and bounded.
            for fk, lo, hi in (("tremble_px", 0.0, 6.0), ("sparkle", 0.0, 1.0), ("streaks", 0.0, 1.0)):
                if fk in w and not (isinstance(w[fk], (int, float)) and lo <= float(w[fk]) <= hi):
                    err(f"{where}: {fk} {w[fk]} outside {lo}..{hi}")
            # J (стр. 15): lapping at the bank — only a water cut out of a layer has a bank (its alpha)
            if "lap" in w:
                if not (isinstance(w["lap"], (int, float)) and 0.0 <= float(w["lap"]) <= 1.0):
                    err(f"{where}: lap {w['lap']} outside 0..1")
                if not str(w.get("source", "")).startswith("layer:"):
                    err(f"{where}: lap needs a water layer source (\"source\": \"layer:<id>\") — its alpha is the bank")
                if not (2.0 <= float(w.get("lap_px", 10.0)) <= 30.0):
                    err(f"{where}: lap_px {w.get('lap_px')} outside 2..30")
            if float(w.get("streaks", 0.0)) > 0.0 and not w.get("flow"):
                err(f"{where}: streaks need a flow [x, y] (the direction the lines run)")
            if key == "puddles" and room is not None and room.get("walkable"):
                floor = [(float(p[0]), float(p[1])) for p in room["walkable"]]
                if not inside(centroid(pts), floor):
                    warn(f"{where}: puddle centre is off the floor (Agata never steps in it)")
    for i, m in enumerate(spec.get("mud", [])):
        where = f"{rid}.mud[{m.get('id', i)}]"
        uniq(m, where)
        if shape(m, where) is None:
            err(f"{where}: needs a polygon or a rect")
    total_dust = 0
    for i, d in enumerate(spec.get("dust", [])):
        where = f"{rid}.dust[{d.get('id', i)}]"
        uniq(d, where)
        check_flags(d, where, flags)
        if shape(d, where) is None:
            err(f"{where}: needs a polygon or a rect")
        n = int(d.get("amount", 18))
        if not 1 <= n <= 40:
            err(f"{where}: amount {n} outside 1..40 (dust is slow and sparse)")
        total_dust += n
    if total_dust > 60:
        err(f"{rid}: {total_dust} dust particles in the room (budget 60)")
    for i, w in enumerate(spec.get("wheel_water", [])):
        where = f"{rid}.wheel_water[{w.get('id', i)}]"
        uniq(w, where)
        check_flags(w, where, flags)
        wl = w.get("water_line")
        if not (isinstance(wl, list) and len(wl) == 2 and all(isinstance(p, list) and len(p) == 2 for p in wl)):
            err(f"{where}: water_line must be [[x0, y0], [x1, y1]]")
        if "pour" in w or "entry" in w:
            if not (isinstance(w.get("hub"), list) and len(w["hub"]) == 2) or float(w.get("radius_px", 0)) <= 0:
                err(f"{where}: pour/entry need the wheel: hub [x, y] and radius_px > 0")
            if not 4 <= int(w.get("paddles", 16)) <= 48:
                err(f"{where}: paddles outside 4..48")
            if "layer" not in w and float(w.get("deg_per_s", 0)) == 0:
                err(f"{where}: pour/entry need the spinning room layer (`layer`) or deg_per_s")
        if "pour" in w:
            r = float(w["pour"].get("rate", 70))
            if not 1 <= r <= 200:
                err(f"{where}: pour.rate {r} outside 1..200 drops/s per bucket")
        for j, s in enumerate(w.get("sources", [])):
            if not (isinstance(s.get("from"), list) and len(s["from"]) == 2):
                err(f"{where}.sources[{j}]: needs from [x, y]")
            if not 1 <= float(s.get("rate", 60)) <= 400:
                err(f"{where}.sources[{j}]: rate outside 1..400 drops/s")
        if not any(k in w for k in ("pour", "entry", "sources", "foam")):
            err(f"{where}: nothing to draw (pour / entry / sources / foam)")
    for i, f in enumerate(spec.get("fog", [])):
        where = f"{rid}.fog[{f.get('id', i)}]"
        uniq(f, where)
        check_flags(f, where, flags)
        pts = shape(f, where)
        if pts is None:
            err(f"{where}: needs a polygon or a rect")
            continue
        overdraw += area(pts)
        for fk in ("density", "wisps"):
            if fk in f and not (isinstance(f[fk], (int, float)) and 0.0 <= float(f[fk]) <= 1.0):
                err(f"{where}: {fk} {f[fk]} outside 0..1")
        pr = f.get("profile")
        if pr is not None and not (isinstance(pr, list) and len(pr) == 4 and all(float(pr[j]) <= float(pr[j + 1]) for j in range(3))):
            err(f"{where}: profile must be [top, core_top, core_bottom, bottom], not decreasing")
        col = str(f.get("color", "#a9afbc"))
        if not (col.startswith("#") and len(col) in (7, 9)):
            err(f"{where}: color must be #rrggbb")
        if not 0.0 <= float(f.get("fade_s", 6.0)) <= 20.0:
            err(f"{where}: fade_s outside 0..20")
    rain = spec.get("rain")
    if rain:
        it = float(rain.get("intensity", 0.5))
        if not 0.0 <= it <= 1.0:
            err(f"{rid}.rain: intensity {it} outside 0..1")
        if abs(float(rain.get("slant_deg", 10))) > 30:
            err(f"{rid}.rain: |slant_deg| > 30")
        if len(rain.get("layers", [])) > 3:
            err(f"{rid}.rain: at most 3 layers")
        overdraw += W * H
    if overdraw > 3 * W * H:
        err(f"{rid}: shader overdraw {overdraw / (W * H):.2f} frames (budget 3)")
    return None


def check_index(idx: dict) -> None:
    for actor, ff in idx.get("footfall", {}).items():
        where = f"_index.footfall.{actor}"
        sheet = ff.get("sheet", "")
        if not res_path(sheet).exists():
            err(f"{where}: sheet not found: {sheet}")
        n = int(ff.get("frames", 0))
        cf = ff.get("contact_frames", [])
        if not cf or any(not (0 <= int(f) < n) for f in cf):
            err(f"{where}: contact_frames {cf} must lie in 0..{n - 1}")
        pf = ff.get("planted_foot_px", [])
        if len(pf) != 8 or any(len(row) != len(cf) or any(len(o) != 2 for o in row) for row in pf):
            err(f"{where}: planted_foot_px must be 8 rows × {len(cf)} contacts × [dx, dy]")
    sp = idx.get("footfall_defaults", {}).get("splash", {})
    lo, hi = float(sp.get("life_min_s", 0.3)), float(sp.get("life_max_s", 0.5))
    if not (0.2 <= lo <= hi <= 0.7):
        err("_index.footfall_defaults.splash: life must be within 0.2..0.7 s (brief: 0.3–0.5)")
    fade = float(idx.get("footfall_defaults", {}).get("print_fade_s", 25))
    if not 20 <= fade <= 30:
        err(f"_index.footfall_defaults.print_fade_s {fade} outside 20..30 s (brief)")


PUDDLE_RINGS_MIN = 10.0     # rings / m² / s (F21; before: 0.55 × 0.9 / 0.3² / 1.0 = 5.5)
PUDDLE_RINGS_MAX = 30.0
PUDDLE_GAIN_MIN = 1.5


def check_puddle_rings(idx: dict) -> None:
    for name, pr in (idx.get("presets") or {}).items():
        ps, rain = pr.get("puddle_style"), pr.get("rain")
        if not isinstance(ps, dict) or not isinstance(rain, dict):
            continue
        cell = float(ps.get("ring_cell_m", 0.45))
        per = float(ps.get("ring_period_s", 1.1))
        if cell <= 0 or per <= 0:
            err(f"_index.presets.{name}.puddle_style: ring_cell_m / ring_period_s must be > 0")
            continue
        rate = min(float(rain.get("intensity", 0.5)) * float(ps.get("rings", 1.0)), 1.0) / (cell * cell) / per
        if not PUDDLE_RINGS_MIN <= rate <= PUDDLE_RINGS_MAX:
            err(f"_index.presets.{name}.puddle_style: {rate:.1f} rain rings per m²·s, want {PUDDLE_RINGS_MIN:g}..{PUDDLE_RINGS_MAX:g} (F21)")
        if float(ps.get("ring_gain", 1.0)) < PUDDLE_GAIN_MIN:
            err(f"_index.presets.{name}.puddle_style: ring_gain {ps.get('ring_gain', 1.0)} < {PUDDLE_GAIN_MIN:g} — rings too faint (F21)")
        if not 0.8 <= float(ps.get("ring_w_px", 1.4)) <= 3.0:
            err(f"_index.presets.{name}.puddle_style: ring_w_px outside 0.8..3 px")


def tod_flags() -> set[str]:
    """Виртуальные флаги времени суток (F17, game/scripts/core/time_of_day.gd): tod_<состояние>, tod_<фаза>,
    tod_day<N>, tod_dark — их отвечает GameState.has_flag, в сохранение они не пишутся."""
    p = Path(__file__).resolve().parent.parent / "data" / "story" / "time" / "_index.json"
    if not p.exists():
        return set()
    names = {"tod_dark"}
    for s in json.loads(p.read_text(encoding="utf-8")).get("states", []):
        for n in (s.get("id"), s.get("phase"), f"day{s.get('day', 0)}"):
            if n:
                names.add("tod_" + str(n))
    return names


def main() -> int:
    quiet = "--quiet" in sys.argv
    idx_path = AMB / "_index.json"
    if not idx_path.exists():
        print("validate_ambient: data/story/ambient/_index.json missing")
        return 1
    idx = json.loads(idx_path.read_text(encoding="utf-8"))
    check_index(idx)
    check_puddle_rings(idx)
    flags = known_flags() | tod_flags()   # время суток (F17): виртуальные флаги tod_*
    files = sorted(p for p in AMB.glob("*.json") if not p.name.startswith("_"))
    for p in files:
        check_room(p, idx, flags)
    for w in warnings:
        print("WARN  " + w)
    for e in errors:
        print("ERROR " + e)
    status = "OK" if not errors else "FAIL"
    if not quiet or errors:
        print(f"validate_ambient: {status} ({len(files)} rooms, {len(errors)} errors, {len(warnings)} warnings)")
    else:
        print(f"validate_ambient: {status} ({len(files)} rooms, {len(errors)} errors, {len(warnings)} warnings)")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
