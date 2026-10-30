"""Юбка Агаты на своих костях (Директор 30.10, 19:16: «сгибы юбки не красиво»; «подумай, как сделать идеальную Агату»).

Причина: автоматическая оснастка Meshy привязала юбку к ногам — подол (0,2–0,5 м) к голеням, середину к бёдрам; при шаге
юбка делится на две «штанины» и ломается складками между ними. Здесь юбке даются свои кости: кольцо из N цепочек от
бёдер до подола (по 3 кости, родитель — Hips), вершины юбки взвешиваются на них плавно по углу и высоте (у пояса — наплыв
к прежним весам), голени и бёдра юбку больше не тянут. В игре цепочки качает SpringBoneSimulator3D (Godot 4.7) с упором
о капсулы ног (rt3d.skirt, game/scripts/actors/actor_3d.gd): колено толкает подол, при повороте юбка запаздывает.
Клипы, сетка, текстура и прежние 24 кости не меняются (проверка после экспорта: кости клипов совпадают до 1 мм).

    python3.13 tools/rig_skirt.py --glb game/assets/characters/agata/rt3d/agata_v4_rt.glb --out /tmp/agata_skirt.glb \
        --report /tmp/agata_skirt.json
Нужен Python 3.13 с bpy 5.2.2 (pipeline/requirements.txt). 0 кредитов.
"""
import argparse
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

LEG = {"LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "Hips"}


FPS = 30  # клипы Meshy — 30 кадров/с (как pipeline/3d/build_rt3d_glb.py); при 24 экспорт пересэмплировал бы их


def clean() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0


def import_glb(path: Path):
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()), disable_bone_shape=True)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if any(c.name == "glTF_not_exported" for c in o.users_collection):
            bpy.data.objects.remove(o, do_unlink=True)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH"]
    acts = [a for a in bpy.data.actions if a not in acts_before]
    return arm, meshes, acts


def assign(arm, act) -> None:
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    ad.action = act
    if hasattr(ad, "action_slot") and ad.action_slot is None and hasattr(act, "slots") and len(act.slots):
        ad.action_slot = act.slots[0]


def sample(arm, act, bones, frames) -> dict:
    assign(arm, act)
    out = {}
    for f in frames:
        bpy.context.scene.frame_set(int(f))
        bpy.context.view_layer.update()
        out[f] = {b: tuple(arm.matrix_world @ arm.pose.bones[b].head) for b in bones if b in arm.pose.bones}
    return out


def smooth(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--report", default="")
    ap.add_argument("--chains", type=int, default=8)
    ap.add_argument("--levels", default="0.80,0.62,0.44,0.26", help="высоты суставов цепочки сверху вниз, м (последняя — низ третьей кости)")
    ap.add_argument("--hem", type=float, default=0.19, help="ниже — сапоги, не юбка")
    ap.add_argument("--leg_reach", type=float, default=0.15, help="ближе к голени — низ юбки частично идёт за ногой (м)")
    ap.add_argument("--leg_top", type=float, default=0.40, help="выше — юбка совсем не идёт за голенью (м)")
    ap.add_argument("--fade", default="0.72,0.86", help="наплыв к прежним весам у пояса: полностью кости юбки ниже первой, прежние — выше второй")
    ap.add_argument("--inset", type=float, default=0.85, help="сустав внутри юбки: доля её радиуса")
    args = ap.parse_args()
    levels = [float(x) for x in args.levels.split(",")]
    f0, f1 = [float(x) for x in args.fade.split(",")]
    report: dict = {"glb": args.glb}

    clean()
    arm, meshes, acts = import_glb(Path(args.glb))
    mesh = max(meshes, key=lambda o: len(o.data.vertices))
    report["clips"] = sorted(a.name for a in acts)
    hips = arm.matrix_world @ arm.data.bones["Hips"].head_local
    cx, cy = hips.x, hips.y
    shins = []
    for side in ("Left", "Right"):
        a = arm.matrix_world @ arm.data.bones[side + "Leg"].head_local
        b = arm.matrix_world @ arm.data.bones[side + "Foot"].head_local
        shins.append((a, b))

    def shin_dist(p: Vector) -> float:
        best = 9.0
        for a, b in shins:
            ab = b - a
            t = min(max((p - a).dot(ab) / max(ab.length_squared, 1e-9), 0.0), 1.0)
            best = min(best, (a + ab * t - p).length)
        return best

    names = {g.index: g.name for g in mesh.vertex_groups}
    mw = mesh.matrix_world
    # вершины юбки: от сапог до пояса, ведущая кость — нога или таз, не сапог
    sel = []
    for v in mesh.data.vertices:
        p = mw @ v.co
        if p.z < args.hem or p.z > f1:
            continue
        ws = [(g.weight, names[g.group]) for g in v.groups if g.weight > 0.0]
        if not ws:
            continue
        dom = max(ws)[1]
        if dom not in LEG:
            continue
        sel.append(v.index)
    report["skirt_vertices"] = len(sel)

    # радиус юбки по углу и высоте (для суставов)
    n = args.chains
    step = 2.0 * math.pi / n
    rad = {}
    for idx in sel:
        p = mw @ mesh.data.vertices[idx].co
        ang = math.atan2(p.x - cx, p.y - cy) % (2.0 * math.pi)
        c = int(round(ang / step)) % n
        k = min(range(len(levels)), key=lambda i: abs(levels[i] - p.z))
        if abs(levels[k] - p.z) < 0.05:
            r = math.hypot(p.x - cx, p.y - cy)
            rad[(c, k)] = max(rad.get((c, k), 0.0), r)
    joints = {}
    for c in range(n):
        ang = c * step
        for k, z in enumerate(levels):
            r = rad.get((c, k)) or rad.get((c, k - 1)) or 0.15
            r *= args.inset
            joints[(c, k)] = Vector((cx + r * math.sin(ang), cy + r * math.cos(ang), z))
    report["joints"] = {f"{c}_{k}": [round(x, 3) for x in joints[(c, k)]] for (c, k) in joints}

    # кости: Skirt<c>_<k>, k = 0..2, от сустава k к k+1; первая — дочь Hips
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    inv = arm.matrix_world.inverted()
    for c in range(n):
        parent = eb["Hips"]
        for k in range(len(levels) - 1):
            b = eb.new(f"Skirt{c}_{k}")
            b.head = inv @ joints[(c, k)]
            b.tail = inv @ joints[(c, k + 1)]
            b.roll = 0.0
            b.parent = parent
            b.use_connect = k > 0
            b.use_deform = True
            parent = b
    bpy.ops.object.mode_set(mode="OBJECT")

    # веса: по углу — две соседние цепочки, по высоте — кости между серединами; у пояса — наплыв к прежним
    groups = {}
    for c in range(n):
        for k in range(len(levels) - 1):
            nm = f"Skirt{c}_{k}"
            groups[nm] = mesh.vertex_groups.get(nm) or mesh.vertex_groups.new(name=nm)
    mids = [(levels[k] + levels[k + 1]) * 0.5 for k in range(len(levels) - 1)]
    for idx in sel:
        v = mesh.data.vertices[idx]
        p = mw @ v.co
        ang = math.atan2(p.x - cx, p.y - cy) % (2.0 * math.pi)
        a = int(math.floor(ang / step)) % n
        t = (ang - a * step) / step
        chain_w = {a: 1.0 - t, (a + 1) % n: t}
        # по высоте
        if p.z >= mids[0]:
            vert_w = {0: 1.0}
        elif p.z <= mids[-1]:
            vert_w = {len(mids) - 1: 1.0}
        else:
            vert_w = {}
            for k in range(len(mids) - 1):
                if mids[k + 1] <= p.z <= mids[k]:
                    u = (mids[k] - p.z) / (mids[k] - mids[k + 1])
                    vert_w = {k: 1.0 - u, k + 1: u}
                    break
        s = 1.0 - smooth(f0, f1, p.z)        # 1 — только кости юбки, 0 — прежние веса
        # у самых голеней низ юбки и голенища идут за ногой, как прежде: переход к костям юбки — полосой, без шва
        # (иначе ткань между подолом и сапогом растягивается серыми клиньями)
        d_shin = shin_dist(p)
        k = min(max((args.leg_reach - d_shin) / (args.leg_reach - 0.05), 0.0), 1.0) * min(max((args.leg_top - p.z) / 0.14, 0.0), 1.0)
        s *= 1.0 - k
        old = {names[g.group]: g.weight for g in v.groups}
        tot_old = sum(old.values()) or 1.0
        new = {}
        for nm, w in old.items():
            new[nm] = (1.0 - s) * w / tot_old
        for c, wc in chain_w.items():
            for k, wk in vert_w.items():
                nm = f"Skirt{c}_{k}"
                new[nm] = new.get(nm, 0.0) + s * wc * wk
        # не больше 4 влияний (как в игре): самые сильные, нормированные
        top = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tw = sum(w for _, w in top) or 1.0
        keep = {nm: w / tw for nm, w in top if w / tw > 0.002}
        for g in list(v.groups):
            mesh.vertex_groups[g.group].remove([idx])
        for nm, w in keep.items():
            vg = mesh.vertex_groups.get(nm) or mesh.vertex_groups.new(name=nm)
            vg.add([idx], w, "REPLACE")

    # клипы: каждое действие — дорожка NLA (экспорт ACTIONS берёт все по именам, как build_rt3d_glb.py)
    ranges = {a.name: tuple(a.frame_range) for a in acts}
    ref_bones = ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
    reference = {}
    for act in acts:
        fr = act.frame_range
        frames = [fr[0], (fr[0] + fr[1]) * 0.5, fr[1]]
        reference[act.name] = sample(arm, act, ref_bones, frames)
    ad = arm.animation_data
    ad.action = None
    for act in acts:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(act.frame_range[0]), act)
        st.name = act.name
        tr.mute = True

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kw = dict(filepath=str(out.resolve()), export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
              export_force_sampling=True, export_skins=True, export_morph=False, export_apply=False, export_yup=True,
              export_image_format="JPEG", export_jpeg_quality=90, export_optimize_animation_size=True,
              export_reset_pose_bones=True, export_def_bones=False, export_extras=False)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError as e:
        print("экспортёр отклонил параметр:", e, flush=True)
        for k in ("export_jpeg_quality", "export_optimize_animation_size", "export_reset_pose_bones", "export_def_bones", "export_extras"):
            kw.pop(k, None)
        bpy.ops.export_scene.gltf(**kw)
    report["out_bytes"] = out.stat().st_size

    # проверка: клипы и прежние кости те же
    clean()
    rarm, rmeshes, racts = import_glb(out)
    report["bones"] = len(rarm.data.bones)
    report["clips_out"] = sorted(a.name for a in racts)
    worst = 0.0
    for a in racts:
        nm = a.name
        if nm not in reference:
            continue
        got = sample(rarm, a, ref_bones, list(reference[nm].keys()))
        for f, bones in reference[nm].items():
            for b, pos in bones.items():
                worst = max(worst, (Vector(pos) - Vector(got[f][b])).length)
    report["worst_bone_mm"] = round(worst * 1000.0, 3)
    report["frame_ranges_same"] = all(tuple(a.frame_range) == ranges.get(a.name, tuple(a.frame_range)) for a in racts)
    print(json.dumps({k: v for k, v in report.items() if k != "joints"}, ensure_ascii=False), flush=True)
    if args.report:
        Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = report["clips_out"] == report["clips"] and worst < 0.001 and report["frame_ranges_same"]
    return 0 if ok else 3


if __name__ == "__main__":
    raise SystemExit(main())
