#!/usr/bin/env python3
"""Автопроверка стоп персонажа (правило проекта: каждый дефект — автопроверка). Дефект 22.10: ботинки Агаты
развёрнуты наружу (в опоре 15–17°, в переносе до 38–46°; на экране под камерой 14° — ≈50° и ≈75°), носок в опоре
поднят на 3–5 см, у стойки правая стопа развёрнута на 25–80°.

По GLB персонажа и запросу конвейера меряет каждый клип листа (pipeline/3d/feet_fix.py: measure) — так же, как он
будет нарисован: у ходьбы и стойки с исправлением стоп (feet_fix.fix_action, по умолчанию включено; "feet_fix":
false в запросе — выключить, список — только эти действия), у остальных действий — как есть (только отчёт).
Пороги (THRESHOLDS в feet_fix.py): ходьба — носок в опоре 0…+6°, в переносе |носок| ≤ 10°, подошва в середине
опоры не выше 1 см над полом, проскальзывание опорной стопы ≤ 5 мм; стойка — |носок| ≤ 8°, проскальзывание ≤ 3 мм.
Числа — в pipeline/3d/state/<name>_feet.json; код выхода 1, если порог превышен.

  python pipeline/3d/check_feet.py --glb pipeline/3d/out/agata/animations.glb --request pipeline/requests/agata.json \\
      [--state pipeline/3d/state/agata.json] [--out pipeline/3d/state/agata_feet.json]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import feet_fix  # noqa: E402


def roles_to_fix(req: dict) -> list:
    v = req.get("feet_fix", True)
    acts = req.get("actions", ["idle", "walk"])
    if v is True:
        return [a for a in acts if feet_fix.kind_of(a)]
    if isinstance(v, list):
        return [a for a in acts if a in v]
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--request", required=True)
    ap.add_argument("--state", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--clips", nargs="*", default=[], help="роль=клип, если нет состояния конвейера")
    ap.add_argument("--print-roles", action="store_true", help="только напечатать действия, которым положено исправление")
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    fix = roles_to_fix(req)
    if args.print_roles:
        print(" ".join(fix))
        return 0
    name = req.get("character", Path(args.request).stem)
    state = Path(args.state or f"pipeline/3d/state/{name}.json")
    keys = {}
    if state.exists():
        keys = {k: v.get("key") for k, v in json.loads(state.read_text(encoding="utf-8")).get("actions", {}).items() if v.get("key")}
    keys.update(dict(c.split("=", 1) for c in args.clips))
    windows = {k: tuple(v) for k, v in req.get("clip_window", {}).items()}

    bpy = feet_fix._bpy()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    acts0 = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.glb).resolve()), disable_bone_shape=True)
    objs = [o for o in sc.objects if not any(c.name == "glTF_not_exported" for c in o.users_collection)]
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"]
    acts = [a for a in bpy.data.actions if a not in acts0]
    rig = feet_fix.rig_from_blender(arm, meshes)
    out = {"name": name, "glb": str(args.glb), "thresholds": feet_fix.THRESHOLDS, "params": feet_fix.PARAMS,
           "rest_toe_out_deg": {k: round(v, 1) for k, v in rig.rest_yaw.items()}, "roles": {}, "ok": True}
    order = req.get("actions", ["idle", "walk"])
    for i, role in enumerate(order):
        key = keys.get(role)
        act = feet_fix.find_action(acts, key) if key else feet_fix.find_action(acts, role)
        if act is None and len(acts) == len(order):
            act = acts[i]
        if act is None:
            out["roles"][role] = {"error": "клип не найден"}
            continue
        kind = feet_fix.kind_of(role) or feet_fix.kind_of(act.name) or ("idle" if role in fix else None)
        win = windows.get(role)
        if role in fix and kind:
            rep = feet_fix.fix_action(arm, rig, act, kind, window=win)
            entry = {"clip": act.name, "kind": kind, "window": win, "fixed": True, "before": rep["before"],
                     "after": rep["after"], "hip_drop_max_m": rep.get("hip_drop_max_m"),
                     "upper_body_max_rot_diff_deg": rep.get("upper_body_max_rot_diff_deg"), "legs": rep.get("legs"),
                     "fail": rep["fail"]}
        else:
            # действия (открыть, поднять…) и клипы без исправления — только отчёт
            bones = [n for s in ("L", "R") for n in (feet_fix.SIDES[s] + "UpLeg", feet_fix.SIDES[s] + "Leg", feet_fix.SIDES[s] + "Foot")]
            frames = feet_fix.key_times(act, bones)
            if win:
                f0, f1 = frames[0], frames[-1]
                frames = frames[(frames >= f0 + (f1 - f0) * win[0] - 1e-6) & (frames <= f0 + (f1 - f0) * win[1] + 1e-6)]
            R, P = feet_fix.sample(arm, act, rig, frames)
            m = feet_fix.measure(rig, R, P, kind or "idle", in_place=(kind == "walk"))
            entry = {"clip": act.name, "kind": kind or "action", "window": win, "fixed": False, "after": m,
                     "fail": feet_fix.verdict(m, kind) if kind else [], "enforced": bool(kind)}
        if entry["fail"]:
            out["ok"] = False
        out["roles"][role] = entry
        a = entry["after"]
        print(f"{name}/{role} ({act.name}{', исправлено' if entry['fixed'] else ''}): " + "; ".join(
            f"{s}: носок в опоре {v['stance_toe_out_deg']}°, |носок| ≤ {v['toe_abs_max_deg']}°, вне опоры ≤ {v['swing_toe_abs_max_deg']}°, "
            f"подошва {v['sole_lift_mid_stance_max_m']} м, скольжение {v['slide_max_mm']} мм" for s, v in a.items())
            + (f" — НЕ ПРОШЛО: {entry['fail']}" if entry["fail"] else " — ок"), flush=True)
    dst = Path(args.out or f"pipeline/3d/state/{name}_feet.json")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"стопы {name}: {'ок' if out['ok'] else 'ПОРОГ ПРЕВЫШЕН'} → {dst}", flush=True)
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
