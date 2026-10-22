#!/usr/bin/env python3
"""Пересчёт замеров стоп по готовым retargeted/<id>.npz (Blender как модуль bpy) и обновление previews/manifest.json:
наибольший разворот ботинка в переносе ноги — только на кадрах, где ось подошвы наклонена < 30°, и вердикт
«вывернутая стопа» (collect.toe_verdict). Нужен, чтобы уточнить замер без перерендера роликов.

  python remeasure.py --target agata_rt.glb --manifest previews/manifest.json --npz retargeted
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import bsrc  # noqa: E402
import collect  # noqa: E402
import mlib  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--npz", required=True)
    args = ap.parse_args()
    bsrc.reset(24.0)
    _, _, _, sk, fg = bsrc.load_target(args.target)
    man = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    ih = sk.idx("Hips")
    for it in man["items"]:
        f = Path(args.npz) / f"{it['id']}.npz"
        if it["type"] != "walk" or not f.exists() or "feet" not in it:
            continue
        d = np.load(f)
        disp = d["disp"].astype(float)
        td = mlib.unit(np.array([disp[0], disp[1], 0.0]))
        B = mlib.quat_to_mat(d["basis_quat"].astype(float))
        R = mlib.world_from_local(sk, B, sk.rest_R[ih] @ B[:, ih])
        P = mlib.fk_positions(sk, R, d["root_P"].astype(float))
        fx = it.setdefault("feet_extra", {})
        for s in ("L", "R"):
            axis = mlib.sole_points(sk, R, P, fg, s)[3]
            yaw, ok = mlib.toe_yaw_flat(axis, td, s)
            fx.setdefault(s, {})
            fx[s]["toe_out_max_deg_all_frames"] = round(float(yaw.max()), 1)
            fx[s]["toe_out_max_deg"] = round(float(yaw[ok].max()), 1) if ok.any() else None
            fx[s]["toe_out_min_deg"] = round(float(yaw[ok].min()), 1) if ok.any() else None
        it["foot_turn_check"] = collect.toe_verdict({"feet": it["feet"], "feet_extra": fx})
        print(it["id"], it["foot_turn_check"].get("note"), flush=True)
    man["metrics"]["swing_toe_out_max_deg"] = ("наибольший разворот ботинка наружу за петлю, включая перенос ноги, на кадрах, "
                                              "где ось подошвы наклонена меньше 30° (круто опущенный носок камера видит "
                                              "вертикальным); без этого фильтра — toe_out_max_deg_all_frames")
    Path(args.manifest).write_text(json.dumps(man, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
