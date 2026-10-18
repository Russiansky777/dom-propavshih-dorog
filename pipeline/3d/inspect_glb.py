#!/usr/bin/env python3
"""Отчёт по анимированному GLB персонажа (Blender как модуль bpy): сетка, материалы, скелет, клипы,
траектории ключевых костей — чтобы игра (реальное 3D, Godot) и выбор клипов опирались на числа.

  python3 pipeline/3d/inspect_glb.py --glb assets/characters/agata/rt3d/agata.glb --out pipeline/3d/state/agata_glb_report.json \
      [--strips Docs/evidence/M1/agata_v2/clips] [--strip-frames 8]

Что в отчёте (метры модели, оси Blender: Z вверх, анфас смотрит в −Y):
  mesh: вершины, треугольники; materials: текстуры и их размеры; bones: имя, родитель, голова в покое;
  actions: длительность (с), fps сцены; по клипу — смещение Hips от начала к концу (есть ли root motion),
  размах Hips/Head по осям, поворот Hips вокруг Z (рыскание: «поворот на 90°» в idle виден сразу),
  ступни: минимум высоты, доля кадров в опоре, скорость опорной ступни (м/с) — для подгонки шага;
  samples: позиции Hips/Head/ступней с шагом 1/30 с (для автопроверок скольжения и рывков).
--strips: на каждый клип полоса кадров Cycles (вид 3/4, мало сэмплов) — посмотреть клип на нашей модели.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

KEY_BONES = {
    "hips": ["hips", "pelvis", "root"],
    "head": ["head"],
    "neck": ["neck"],
    "spine2": ["spine02", "spine2", "chest", "spine01", "spine1"],
    "l_foot": ["leftfoot", "l_foot", "foot_l", "leftankle"],
    "r_foot": ["rightfoot", "r_foot", "foot_r", "rightankle"],
    "l_toe": ["lefttoebase", "lefttoe", "l_toe", "toe_l"],
    "r_toe": ["righttoebase", "righttoe", "r_toe", "toe_r"],
    "l_hand": ["lefthand", "l_hand", "hand_l"],
    "r_hand": ["righthand", "r_hand", "hand_r"],
}


def norm(s: str) -> str:
    return s.lower().replace("_", "").replace(".", "").replace(" ", "").replace("mixamorig:", "")


def find_bone(arm, keys: list[str]):
    names = {norm(b.name): b.name for b in arm.pose.bones}
    for k in keys:
        k2 = norm(k)
        if k2 in names:
            return names[k2]
    for k in keys:
        k2 = norm(k)
        for n, orig in names.items():
            if n.endswith(k2) or n.startswith(k2):
                return orig
    return None


def r(v, n=4):
    return [round(float(x), n) for x in v]


def assign_action(arm, act) -> None:
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    # Blender 4.4+: слоты действий — берём первый подходящий, если он не выбран сам
    ad = arm.animation_data
    if hasattr(ad, "action_slot") and ad.action_slot is None and hasattr(act, "slots") and len(act.slots):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


def yaw_of(arm, pb) -> float:
    """Рыскание кости вокруг Z мира: направление её локальной оси Z (вперёд у Hips в ригах Meshy/Mixamo
    смотрит туда же, что и лицо) в проекции на пол."""
    m = arm.matrix_world @ pb.matrix
    fwd = m.to_3x3() @ Vector((0, 0, 1))
    return math.degrees(math.atan2(fwd.x, -fwd.y))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--strips", default="")
    ap.add_argument("--strip-frames", type=int, default=8)
    ap.add_argument("--strip-size", type=int, default=256)
    ap.add_argument("--hz", type=float, default=30.0)
    args = ap.parse_args()

    report = {"files": []}
    for glb in args.glb:
        glb = Path(glb)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        for o in list(bpy.context.scene.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.import_scene.gltf(filepath=str(glb.resolve()), disable_bone_shape=True)
        objs = [o for o in bpy.context.scene.objects if not any(c.name == "glTF_not_exported" for c in o.users_collection)]
        arm = next((o for o in objs if o.type == "ARMATURE"), None)
        meshes = [o for o in objs if o.type == "MESH"]
        scene = bpy.context.scene
        fps = scene.render.fps / scene.render.fps_base
        entry = {"file": glb.name, "bytes": glb.stat().st_size, "scene_fps": fps, "objects": [{"name": o.name, "type": o.type, "parent": o.parent.name if o.parent else None, "location": r(o.location), "rotation": r(o.rotation_euler), "scale": r(o.scale)} for o in objs]}
        tris = verts = 0
        for m in meshes:
            me = m.data
            me.calc_loop_triangles()
            tris += len(me.loop_triangles)
            verts += len(me.vertices)
        entry["mesh"] = {"objects": len(meshes), "vertices": verts, "triangles": tris}
        mats = []
        for mat in bpy.data.materials:
            texs = []
            if mat.use_nodes and mat.node_tree:
                for n in mat.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image is not None:
                        im = n.image
                        links = [l.to_socket.name for l in n.outputs[0].links] if n.outputs else []
                        texs.append({"image": im.name, "size": list(im.size), "packed_bytes": len(im.packed_file.data) if im.packed_file else None, "to": links})
            mats.append({"name": mat.name, "textures": texs, "blend": getattr(mat, "blend_method", None)})
        entry["materials"] = mats
        if arm is None:
            entry["error"] = "нет скелета"
            report["files"].append(entry)
            continue
        entry["armature"] = {"name": arm.name, "bones": len(arm.data.bones)}
        entry["bones"] = [{"name": b.name, "parent": b.parent.name if b.parent else None, "head": r(arm.matrix_world @ b.head_local, 3)} for b in arm.data.bones]
        key = {k: find_bone(arm, v) for k, v in KEY_BONES.items()}
        entry["key_bones"] = key
        acts = []
        for act in list(bpy.data.actions):
            assign_action(arm, act)
            f0, f1 = act.frame_range
            dur = (f1 - f0) / fps
            n = max(2, int(round(dur * args.hz)) + 1)
            samples = {k: [] for k in key if key[k]}
            yaws = []
            for i in range(n):
                f = f0 + (f1 - f0) * i / (n - 1)
                scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
                bpy.context.view_layer.update()
                for k, bn in key.items():
                    if not bn:
                        continue
                    pb = arm.pose.bones[bn]
                    samples[k].append(r(arm.matrix_world @ pb.head, 4))
                if key.get("hips"):
                    yaws.append(yaw_of(arm, arm.pose.bones[key["hips"]]))
            a = {"name": act.name, "frames": [f0, f1], "seconds": round(dur, 3), "samples_hz": args.hz, "n": n}
            if "hips" in samples:
                h = samples["hips"]
                a["hips_delta_m"] = r([h[-1][j] - h[0][j] for j in range(3)], 3)
                a["hips_range_m"] = r([max(p[j] for p in h) - min(p[j] for p in h) for j in range(3)], 3)
            if "head" in samples:
                hd = samples["head"]
                a["head_range_m"] = r([max(p[j] for p in hd) - min(p[j] for p in hd) for j in range(3)], 3)
            if yaws:
                unwrapped = [yaws[0]]
                for y in yaws[1:]:
                    d = (y - unwrapped[-1] + 180) % 360 - 180
                    unwrapped.append(unwrapped[-1] + d)
                a["hips_yaw_deg"] = {"start": round(unwrapped[0], 1), "end": round(unwrapped[-1], 1), "min": round(min(unwrapped), 1), "max": round(max(unwrapped), 1)}
            feet = {}
            for side in ("l_foot", "r_foot"):
                if side not in samples:
                    continue
                p = samples[side]
                zmin = min(q[2] for q in p)
                stance = [i for i, q in enumerate(p) if q[2] < zmin + 0.025]
                vel = []
                for i in stance:
                    if i + 1 < len(p) and (i + 1) in stance:
                        dx, dy = p[i + 1][0] - p[i][0], p[i + 1][1] - p[i][1]
                        vel.append(math.hypot(dx, dy) * args.hz)
                feet[side] = {"z_min": round(zmin, 4), "stance_fraction": round(len(stance) / len(p), 3), "stance_speed_mps_median": round(sorted(vel)[len(vel) // 2], 3) if vel else None, "travel_m": r([p[-1][j] - p[0][j] for j in range(3)], 3)}
            a["feet"] = feet
            a["samples"] = samples
            acts.append(a)
            print(f"  {glb.name}: {act.name} {dur:.2f} с, hips Δ {a.get('hips_delta_m')}, yaw {a.get('hips_yaw_deg')}", flush=True)
        entry["actions"] = acts
        report["files"].append(entry)

        if args.strips:
            out = Path(args.strips) / glb.stem
            out.mkdir(parents=True, exist_ok=True)
            render_strips(arm, meshes, out, args.strip_frames, args.strip_size)

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print("отчёт:", args.out)
    return 0


def render_strips(arm, meshes, out: Path, nframes: int, size: int) -> None:
    """Полоса кадров клипа на нашей модели: вид 3/4 спереди (−35°), Cycles 8 сэмплов, прозрачный фон → JPG на сером."""
    from PIL import Image
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("C"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 2.4
    cam = bpy.data.objects.new("C", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    ang = math.radians(-35)
    cam.location = Vector((8 * math.sin(ang), -8 * math.cos(ang), 0.9 + 8 * math.sin(math.radians(14))))
    cam.rotation_euler = (Vector((0, 0, 0.85)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    for nm, en, rot in (("Key", 4.5, (55, 0, -35)), ("Fill", 2.0, (70, 0, 140)), ("Rim", 2.5, (120, 0, 20))):
        l = bpy.data.lights.new(nm, "SUN"); l.energy = en
        lo = bpy.data.objects.new(nm, l); scene.collection.objects.link(lo); lo.rotation_euler = tuple(math.radians(x) for x in rot)
    scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"; scene.cycles.samples = 8; scene.cycles.use_denoising = False
    scene.render.film_transparent = True
    scene.render.resolution_y = size; scene.render.resolution_x = int(size * 0.75); scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    for act in list(bpy.data.actions):
        assign_action(arm, act)
        f0, f1 = act.frame_range
        strip = Image.new("RGB", (scene.render.resolution_x * nframes, size), (150, 150, 158))
        for i in range(nframes):
            scene.frame_set(int(round(f0 + (f1 - f0) * i / max(nframes - 1, 1))))
            tmp = out / "_tmp.png"
            scene.render.filepath = str(tmp)
            bpy.ops.render.render(write_still=True)
            im = Image.open(tmp).convert("RGBA")
            strip.paste(im, (i * scene.render.resolution_x, 0), im)
            tmp.unlink()
        safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in act.name)
        strip.save(out / f"{safe}.jpg", quality=85)
        print(f"  полоса: {out / (safe + '.jpg')}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
