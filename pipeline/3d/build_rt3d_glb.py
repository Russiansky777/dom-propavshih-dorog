#!/usr/bin/env python3
"""GLB Агаты для игры в реальном 3D (Blender как модуль bpy): та же модель и текстура, сетка упрощена до
бюджета веба, все клипы (основа + дополнительные задачи Meshy на том же риге) — в одном файле.

  python3 pipeline/3d/build_rt3d_glb.py --base assets/characters/agata/rt3d/agata.glb \
      [--extra assets/characters/agata/rt3d/agata_extra_r4.glb ...] --tris 50000 \
      --out assets/characters/agata/rt3d/agata_rt.glb --check-out pipeline/3d/state/agata_rt_check.json

Что делается:
  1. импорт основы (сетка 907 тыс. треугольников, 2K baseColor, скелет 24 кости, клипы Meshy);
  2. Decimate (collapse) до ~--tris треугольников ДО модификатора Armature — веса костей и UV сохраняются;
  3. клипы дополнительных GLB переносятся на скелет основы покадрово (matrix_basis каждой кости: позы покоя у
     всех файлов одного рига одинаковые), имена клипов — как у Meshy;
  4. экспорт GLB (все действия, текстура JPEG 90);
  5. проверка: файл снова импортируется, для каждого клипа и каждой ключевой кости — расхождение мировых позиций
     с исходником (метры) в 9 моментах клипа; больше 2 мм — ошибка (код 3). Внешность не меняется — только число
     треугольников; отчёт с числами — --check-out.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy

KEY = ["Hips", "Spine02", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]


def clean() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def import_glb(path: Path) -> tuple:
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()), disable_bone_shape=True)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
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
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


def sample(arm, act, n: int = 9) -> dict:
    scene = bpy.context.scene
    assign(arm, act)
    f0, f1 = act.frame_range
    out = {}
    for i in range(n):
        f = f0 + (f1 - f0) * i / (n - 1)
        scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        for b in KEY:
            pb = arm.pose.bones.get(b)
            if pb is not None:
                out.setdefault(b, []).append(list(arm.matrix_world @ pb.head))
    return out


def decimate(mesh, tris: int) -> dict:
    me = mesh.data
    me.calc_loop_triangles()
    before = len(me.loop_triangles)
    ratio = min(1.0, tris / max(before, 1))
    mod = mesh.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=mesh, active_object=mesh, selected_objects=[mesh]):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    me.calc_loop_triangles()
    return {"before": before, "after": len(me.loop_triangles), "ratio": round(ratio, 5), "vertices": len(me.vertices)}


def transfer(src_arm, src_act, dst_arm, name: str):
    """Покадровый перенос клипа: matrix_basis каждой кости src → dst, ключи на каждый кадр сцены."""
    scene = bpy.context.scene
    assign(src_arm, src_act)
    f0, f1 = (int(math.floor(src_act.frame_range[0])), int(math.ceil(src_act.frame_range[1])))
    if dst_arm.animation_data is None:
        dst_arm.animation_data_create()
    new = bpy.data.actions.new(name)
    dst_arm.animation_data.action = new
    for pb in dst_arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        for pb in dst_arm.pose.bones:
            spb = src_arm.pose.bones.get(pb.name)
            if spb is None:
                continue
            pb.matrix_basis = spb.matrix_basis.copy()
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)
    return new


def push_all_to_nla(arm, acts) -> None:
    """Каждое действие — своя дорожка NLA: экспорт в режиме ACTIONS берёт их все по именам."""
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    for act in acts:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(act.frame_range[0]), act)
        st.name = act.name
        tr.mute = True
    ad.action = None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--extra", nargs="*", default=[])
    ap.add_argument("--tris", type=int, default=50000)
    ap.add_argument("--out", required=True)
    ap.add_argument("--check-out", required=True)
    ap.add_argument("--rename", nargs="*", default=[], help="старое=новое имя клипа")
    ap.add_argument("--drop", nargs="*", default=[], help="клипы, которые не нужны игре (дубли)")
    args = ap.parse_args()
    rename = dict(x.split("=", 1) for x in args.rename)

    clean()
    arm, meshes, acts = import_glb(Path(args.base))
    report = {"base": args.base, "extra": args.extra, "tris_target": args.tris, "decimate": {}, "clips": {}}
    reference = {a.name.split(".")[0]: sample(arm, a) for a in acts}
    for m in meshes:
        report["decimate"][m.name] = decimate(m, args.tris)
    keep = list(acts)
    for ex in args.extra:
        earm, emeshes, eacts = import_glb(Path(ex))
        for a in eacts:
            nm = a.name.split(".")[0]
            if any(k.name.split(".")[0] == nm for k in keep):
                print(f"клип {nm} уже есть — пропускаю дубль из {ex}", flush=True)
                continue
            reference[nm] = sample(earm, a)
            keep.append(transfer(earm, a, arm, nm))
            print(f"перенесён клип {nm} из {Path(ex).name}", flush=True)
        for o in [earm] + emeshes:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(keep):
        if a.name.split(".")[0] in args.drop:
            keep.remove(a)
            reference.pop(a.name.split(".")[0], None)
    for a in keep:
        base = a.name.split(".")[0]
        a.name = rename.get(base, base)
        if a.name != base:
            reference[a.name] = reference.pop(base)
    # всё лишнее (дубли действий от второго импорта) — вон, чтобы экспорт не захватил чужие клипы
    for a in list(bpy.data.actions):
        if a not in keep:
            bpy.data.actions.remove(a)
    push_all_to_nla(arm, keep)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kw = dict(filepath=str(out.resolve()), export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
              export_force_sampling=True, export_skins=True, export_morph=False, export_apply=False, export_yup=True,
              export_image_format="JPEG", export_jpeg_quality=90, export_optimize_animation_size=True,
              export_reset_pose_bones=True, export_def_bones=False, export_extras=False)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError as e:  # имена параметров экспортёра меняются между версиями Blender
        print("экспортёр отклонил параметр:", e, flush=True)
        for k in ("export_jpeg_quality", "export_optimize_animation_size", "export_reset_pose_bones", "export_def_bones", "export_extras"):
            kw.pop(k, None)
        bpy.ops.export_scene.gltf(**kw)
    report["out_bytes"] = out.stat().st_size
    print(f"экспорт: {out} {out.stat().st_size} байт", flush=True)

    # проверка: импорт результата, сравнение костей с исходником
    clean()
    rarm, rmeshes, racts = import_glb(out)
    worst = 0.0
    for a in racts:
        nm = a.name.split(".")[0]
        ref = reference.get(nm)
        if ref is None:
            report["clips"][nm] = {"error": "нет в исходнике"}
            continue
        got = sample(rarm, a)
        dev = 0.0
        for b, pts in ref.items():
            for p, q in zip(pts, got.get(b, [])):
                dev = max(dev, math.dist(p, q))
        worst = max(worst, dev)
        report["clips"][nm] = {"frames": list(a.frame_range), "max_dev_m": round(dev, 5)}
    missing = sorted(set(reference) - {a.name.split(".")[0] for a in racts})
    tri = 0
    for m in rmeshes:
        m.data.calc_loop_triangles()
        tri += len(m.data.loop_triangles)
    report["result"] = {"triangles": tri, "clips": len(racts), "missing": missing, "max_dev_m": round(worst, 5)}
    Path(args.check_out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.check_out).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(report["result"], ensure_ascii=False), flush=True)
    if missing or worst > 0.002:
        print(f"ПРОВЕРКА НЕ ПРОШЛА: пропали {missing}, расхождение {worst:.4f} м", flush=True)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
