#!/usr/bin/env python3
"""Сборка результатов прогона: ролики → previews/<библиотека>/<id>.mp4, ретаргет → retargeted/<id>.npz,
манифест previews/manifest.json, журналы previews/logs/, листы кадров previews/contact_<библиотека>.jpg.

  python3 collect.py --clips clips.json --in _pv --run <run_id> --sha <sha>
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
from pathlib import Path

LIB_DIR = {"baseline": "baseline", "mesh2motion": "mesh2motion", "cmu": "cmu", "100style": "100style"}
SRC_URL = {
    "m2m": "https://github.com/Mesh2Motion/mesh2motion-app/blob/{sha}/{path}",
    "cmu": "https://github.com/Shriinivas/cmubvh/blob/{sha}/{path}",
}
RETARGET_FORMAT = ("npz: names (кости Агаты, agata_rt.glb), parents, basis_quat (кадры×кости×4, wxyz — matrix_basis "
                   "Blender относительно покоя), root_P (кадры×3, мировая позиция головы кости Hips, м, Z вверх, ход к −Y), "
                   "disp (смещение таза за петлю, м), fps 24, contacts_L/R (опорная стопа на кадре). Петля бесшовная: "
                   "кадр k-й петли = кадр j + k·disp.")


def screen_angle(theta_deg: float | None, elev=14.0) -> float | None:
    """Как выглядит разворот носка θ при ходьбе к зрителю под ортокамерой elev°: глубина сжата в sin(elev) раз."""
    if theta_deg is None:
        return None
    t = math.radians(abs(theta_deg))
    return round(math.copysign(math.degrees(math.atan2(math.tan(t), math.sin(math.radians(elev)))), theta_deg), 1)


def toe_verdict(rt: dict) -> dict:
    """Есть ли «вывернутая стопа при ходьбе вниз» (как у Meshy Walking_Woman: опора 15–17° наружу, в переносе до 38–46°)."""
    if rt is None:
        return {}
    f, fx = rt["feet"], rt.get("feet_extra", {})
    st = [f[s]["toe_out_deg"] for s in ("L", "R") if f[s]["toe_out_deg"] is not None]
    sw = [fx[s].get("toe_out_max_deg") for s in ("L", "R") if fx.get(s, {}).get("toe_out_max_deg") is not None]
    out = {"stance_toe_out_deg": {s: f[s]["toe_out_deg"] for s in ("L", "R")},
           "stance_on_screen_deg_14": {s: screen_angle(f[s]["toe_out_deg"]) for s in ("L", "R")}}
    if sw:
        out["swing_toe_out_max_deg"] = {s: fx[s].get("toe_out_max_deg") for s in ("L", "R")}
    if st:
        out_st = max(st) > 12.0
        in_st = min(st) < -12.0
        bad_sw = bool(sw) and max(sw) > 25.0
        out["has_turned_foot"] = bool(out_st or in_st or bad_sw)
        notes = []
        if out_st:
            notes.append("носок наружу в опоре > 12°")
        if in_st:
            notes.append("носок внутрь в опоре > 12°")
        if bad_sw:
            notes.append("в переносе ноги носок уходит наружу > 25°")
        out["note"] = "; ".join(notes) if notes else "нет: в опоре |носок| ≤ 12°, в переносе ≤ 25° наружу"
    return out


def thumbs(mp4: Path, dst: Path, fracs=(0.3, 0.6)) -> list[Path]:
    out = []
    try:
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(mp4)],
                                   capture_output=True, text=True, check=True).stdout.strip())
    except Exception:  # noqa: BLE001
        return out
    for k, fr in enumerate(fracs):
        p = dst.with_name(f"{dst.stem}_{k}.jpg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{dur * fr:.3f}", "-i", str(mp4), "-frames:v", "1",
                        "-vf", "scale=640:360", str(p)], check=False)
        if p.exists():
            out.append(p)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", required=True)
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--run", default="")
    ap.add_argument("--sha", default="")
    args = ap.parse_args()
    cfg = json.load(open(args.clips, encoding="utf-8"))
    src = Path(args.inp)
    prev, rtd, logs = Path("previews"), Path("retargeted"), Path("previews/logs")
    for d in (prev, rtd, logs):
        d.mkdir(parents=True, exist_ok=True)
    tmp = Path("_thumbs")
    tmp.mkdir(exist_ok=True)
    items, sheets = [], {}
    for c in cfg["clips"]:
        cid, lib = c["id"], c["library"]
        rt_p = next(iter(src.rglob(f"{cid}.json")), None)
        rnd_p = next(iter(src.rglob(f"{cid}.render.json")), None)
        mp4 = next(iter(src.rglob(f"{cid}.mp4")), None)
        npz = next(iter(src.rglob(f"{cid}.npz")), None)
        log = next(iter(src.rglob(f"log_{cid}.txt")), None)
        rt = json.loads(rt_p.read_text(encoding="utf-8")) if rt_p else None
        rnd = json.loads(rnd_p.read_text(encoding="utf-8")) if rnd_p else None
        if log:
            shutil.copy(log, logs / f"{cid}.txt")
        entry = {"id": cid, "library": cfg["libraries"][lib]["title"], "type": c["type"], "clip": c["title"],
                 "license": cfg["libraries"][lib]["license"], "library_url": cfg["libraries"][lib]["url"],
                 "why": c.get("why", ""), "status": "ok" if (mp4 and rt) else "нет результата"}
        s = c["source"]
        if s.get("file"):
            lk, rel = s["file"].split(":", 1)
            relz = rel.split("!", 1)[0]
            if lk in SRC_URL:
                entry["source_url"] = SRC_URL[lk].format(sha=cfg["pins"][lk], path=relz)
            elif lk == "100style":
                entry["source_url"] = "https://zenodo.org/records/8127870 (100STYLE.zip → " + rel + ")"
            if lk == "cmu":
                subj = relz.split("/")[1]
                entry["official_page"] = f"http://mocap.cs.cmu.edu/search.php?subjectnumber={subj}"
            entry["source_file"] = rel
            if s.get("frame_cut"):
                entry["frame_cut"] = s["frame_cut"]
        else:
            entry["source_url"] = "assets/characters/agata/rt3d/agata_rt.glb (клип " + s["action"] + ")"
        if rt:
            entry.update({
                "loop": rt["loop"], "loop_frames": rt["frames"], "speed_mps": rt["speed_mps"], "cleanup": rt["cleanup"],
                "head_fix": rt.get("head_fix"), "hips_yaw_range_deg": rt["hips_yaw_range_deg"],
                "hip_drop_max_m": rt["hip_drop_max_m"], "ground_offset_m": rt["ground_offset_m"], "scale": rt["scale"],
                "feet_before_cleanup": rt["feet_raw"], "feet": rt["feet"], "feet_extra": rt.get("feet_extra"),
                "foot_turn_check": toe_verdict(rt) if c["type"] == "walk" else {
                    "stance_toe_out_vs_hips_deg": {k: rt["feet"][k]["toe_out_deg"] for k in ("L", "R")}},
            })
            entry["slide_mm_max"] = max([rt["feet"][k]["slide_mm_max"] or 0.0 for k in ("L", "R")])
            entry["slide_mm_max_before_cleanup"] = max([rt["feet_raw"][k]["slide_mm_max"] or 0.0 for k in ("L", "R")])
        if rnd and mp4:
            d = prev / LIB_DIR[lib]
            d.mkdir(parents=True, exist_ok=True)
            shutil.copy(mp4, d / f"{cid}.mp4")
            entry.update({"mp4": f"previews/{LIB_DIR[lib]}/{cid}.mp4", "duration_s": rnd["duration_s"],
                          "bytes": rnd["bytes"], "loops_in_video": rnd["loops"], "size_ok": rnd["size_ok"]})
            for t in thumbs(d / f"{cid}.mp4", tmp / f"{cid}.jpg"):
                sheets.setdefault(LIB_DIR[lib], []).append(t)
        if npz:
            shutil.copy(npz, rtd / f"{cid}.npz")
            entry["retargeted"] = f"retargeted/{cid}.npz"
        items.append(entry)
    fl = next(iter(src.rglob("fetch.log")), None)
    if fl:
        shutil.copy(fl, logs / "fetch_sources.txt")
    try:
        from PIL import Image
        for lib, ims in sheets.items():
            cols = 2
            rows = math.ceil(len(ims) / cols)
            sheet = Image.new("RGB", (640 * cols, 360 * rows), (20, 20, 20))
            for k, p in enumerate(ims):
                sheet.paste(Image.open(p).convert("RGB"), ((k % cols) * 640, (k // cols) * 360))
            sheet.save(prev / f"contact_{lib}.jpg", quality=82)
    except Exception as e:  # noqa: BLE001
        print("листы кадров не собраны:", e)
    man = {"run": args.run, "commit": args.sha, "fps": 24, "size": "1280x720", "camera_elev_deg": 14,
           "views": {"walk": ["к зрителю (вниз по экрану)", "профиль (вправо)", "по диагонали"], "idle": ["3/4 спереди", "профиль"]},
           "floor": "шкала: линии 10 см, толще 50 см, ещё толще 1 м",
           "metrics": {
               "slide_mm": "проскальзывание опорной стопы: наибольший уход по полу самой низкой точки подошвы (пятка/подушечка/носок) от места, где она стала опорной, за одно касание; мм; до и после чистки",
               "toe_out_deg": "разворот ботинка (ось подошвы по сетке модели) к направлению хода на кадрах, где стопа стоит плоско; + наружу; для idle — к взгляду таза",
               "swing_toe_out_max_deg": "наибольший разворот наружу за петлю, включая перенос ноги",
               "stance_on_screen_deg_14": "как этот угол выглядит на экране при ходьбе к зрителю под камерой 14° (глубина сжата ×0,24)"},
           "cleanup": "масштаб по длине ног; высота таза — подошва на полу; пальцы сапога жёсткие; поворот опорной стопы на полу зафиксирован; самая низкая точка подошвы держится на месте (IK бедро–колено–лодыжка); таз опускается, где нога не дотягивается. Базовая линия Meshy — без чистки, как в игре.",
           "retargeted_format": RETARGET_FORMAT, "items": items}
    (prev / "manifest.json").write_text(json.dumps(man, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"манифест: {len(items)} клипов, роликов {sum(1 for i in items if i.get('mp4'))}")
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
