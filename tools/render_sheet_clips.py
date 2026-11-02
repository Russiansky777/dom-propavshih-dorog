#!/usr/bin/env python3
"""Новые клипы листа персонажа рендером на месте (python3.13 + bpy 5.2.2), камера и свет — как у листа.

Зачем (Директор 01.11, стр. 61, 68; Docs/tasks/frame_talk_sheets.json): фигуры кадров играют клипы листов (покой и жест
реплики, tools/make_frame_layers.py). Клип talk листов v2 стоит иначе, чем listen (ноги на 10–12 см вперёд, подошвы
выше, корпус откинут) — на наплыве «слушает → говорит» ноги переступают растворением; у Агаты клипа реплики в листе
нет. Здесь из клипов GLB собирается производный клип (ноги и таз — поза стойки, спина — доля клипа, руки, шея и
голова — клип целиком, начало и конец — в позе стойки) и рендерится тем же кадрированием, что лист.

Кадрирование, камера, свет и материалы — те же шаги, что pipeline/render/render_sprites.py (функции оттуда же:
matte_materials, scene_bounds, screen_extent): первое действие --frames — стойка кадрирования (с исправлением стоп
feet_fix, как в рендере листа), её кадр — начало окна; пол каждого клипа сводится к полу стойки. Совпадение
проверяется ключом --probe: кадр уже готового действия рендерится заново и сравнивается попиксельно с листом
(assets/characters/<набор>/<действие>.png или копией игры) — отчёт в JSON.

Выход — копия игры, как у tools/pack_sheets.py: game/assets/characters/<набор>/<действие>.png — атлас (кадры обрезаны
по фигуре, полки, max_side 8192), в game/…/sprites.json у действия — описание, atlas.rects и "game_only": true
(сетки в assets/ нет — assets/ ведёт Codex; make_frame_layers берёт такие действия из копии игры).

  python3.13 tools/render_sheet_clips.py --glb nina_v2_game_r4.glb --set nina_v2 --frames idle=24 listen=24 talk=36 \
      --window idle=0.1:0.5 listen=0.1:0.6 --feet-fix idle --size 864 --samples 16 \
      --derive talk_steady=talk --stance listen --keep Spine02=0.3 Spine01=0.3 Spine=0.3 --bookend-s 0.5 \
      --render talk_steady=36 --fps talk_steady=9 --work /tmp/w [--probe idle:0:0 listen:2:0] [--dirs 0 1 …]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "pipeline" / "render"))
sys.path.insert(0, str(ROOT / "pipeline" / "3d"))
sys.path.insert(0, str(ROOT / "tools"))
import render_sprites as rs  # noqa: E402
import feet_fix  # noqa: E402

LEGS = ("UpLeg", "Leg", "Foot", "ToeBase")


def kv(items, cast=str):
    out = {}
    for it in items:
        k, v = it.split("=", 1)
        out[k] = cast(v)
    return out


def frame_at(scene, f):
    fi = math.floor(f)
    scene.frame_set(int(fi), subframe=float(f - fi))


def pose_now(arm):
    return {pb.name: (Quaternion(pb.rotation_quaternion), Vector(pb.location), Vector(pb.scale)) for pb in arm.pose.bones}


def torso_tilt_deg(scene, arm, act, frames, ref) -> float:
    """Наибольший наклон корпуса клипа от стойки, градусы: угол вектора таз → шея (мировые головы костей Hips и neck)
    с тем же вектором позы стойки ref (02.11: сырой talk жителей откидывает корпус на 5° и уводит таз)."""
    feet_fix.assign(arm, act)
    worst = 0.0
    for f in frames:
        frame_at(scene, float(f))
        v = torso_vec(arm)
        worst = max(worst, math.degrees(v.angle(ref)))
    return worst


def feet_drift_m(scene, arm, act, frames, ref) -> float:
    """Наибольший сдвиг стоп (мировые головы LeftFoot/RightFoot) от позы стойки ref, м."""
    feet_fix.assign(arm, act)
    worst = 0.0
    for f in frames:
        frame_at(scene, float(f))
        for k, v in feet_now(arm).items():
            worst = max(worst, (v - ref[k]).length)
    return worst


def feet_now(arm):
    W = arm.matrix_world
    return {b: W @ arm.pose.bones[b].head for b in ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase") if b in arm.pose.bones}


def torso_vec(arm):
    W = arm.matrix_world
    neck = next((b for b in ("neck", "Neck", "Head") if b in arm.pose.bones), None)
    return (W @ arm.pose.bones[neck].head) - (W @ arm.pose.bones["Hips"].head)


def derive_action(scene, arm, src, stance_pose, name, keep, bookend_n, fixed_names):
    """Производный клип: кости из keep — slerp(стойка, клип, доля) (таз, спина: 0,3 — как rt3d.act_body живых жителей);
    кости fixed_names (ноги, корень) — поза стойки; остальные (руки, шея, голова) — клип. Если таз берёт долю клипа,
    бёдра (UpLeg) доворачиваются так, что их мировой поворот — как в стойке: ноги и стопы стоят на месте. Таз не
    смещается (location — стойки). Начало и конец — плавно (косинус, bookend_n кадров) из позы стойки и обратно:
    реплика начинается и кончается в стойке. Ключи — в каждом целом кадре клипа, интерполяция линейная."""
    feet_fix.assign(arm, src)
    f0, f1 = src.frame_range
    frames = np.arange(round(f0), round(f1) + 1, 1.0)
    T = len(frames)
    poses = []
    for f in frames:
        frame_at(scene, float(f))
        poses.append(pose_now(arm))
    out = {}
    for pb in arm.pose.bones:
        n = pb.name
        q_st, l_st, s_st = stance_pose[n]
        rows = []
        for t in range(T):
            q, l, s = poses[t][n]
            w = float(keep[n]) if n in keep else (0.0 if n in fixed_names else 1.0)
            x = min(t, T - 1 - t)
            if bookend_n > 0 and x < bookend_n:
                w *= 0.5 - 0.5 * math.cos(math.pi * x / bookend_n)
            wl = 0.0 if n == "Hips" else w     # таз не уходит вбок и вперёд: смещение — стойки
            rows.append([q_st.slerp(q, w), l_st.lerp(l, wl), s_st.lerp(s, w)])
        out[n] = rows
    hips = arm.pose.bones.get("Hips")
    if hips is not None and "Hips" in keep:
        R_h = hips.bone.matrix_local.to_quaternion()
        q_hs = stance_pose["Hips"][0]
        ups = [pb for pb in arm.pose.bones if pb.parent is not None and pb.parent.name == "Hips" and pb.name.endswith("UpLeg")]
        # поворот таза уводит головы бёдер (вместе со стопами) — таз сдвигается обратно: середина головок бёдер на месте
        if ups:
            Linv = hips.bone.matrix_local.inverted()
            mid = sum(((Linv @ pb.bone.head_local) for pb in ups), Vector()) / len(ups)
            l_hs = stance_pose["Hips"][1]
            for t in range(T):
                out["Hips"][t][1] = l_hs + (q_hs @ mid) - (out["Hips"][t][0] @ mid)
        for pb in ups:
            R_rel = R_h.inverted() @ pb.bone.matrix_local.to_quaternion()
            q_st = stance_pose[pb.name][0]
            for t in range(T):
                q_hn = out["Hips"][t][0]
                out[pb.name][t][0] = R_rel.inverted() @ (q_hn.inverted() @ q_hs) @ R_rel @ q_st
    act = bpy.data.actions.new(name)
    feet_fix.assign(arm, act)
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        for path in ("rotation_quaternion", "location", "scale"):
            pb.keyframe_insert(path, frame=float(frames[0]))
    fcs = {(fc.data_path, fc.array_index): fc for fc in feet_fix.action_fcurves(act)}
    for pb in arm.pose.bones:
        n = pb.name
        qs, ls, ss = np.zeros((T, 4)), np.zeros((T, 3)), np.zeros((T, 3))
        prev = None
        for t in range(T):
            qq, l, sc = out[n][t]
            qq = qq.normalized()
            if prev is not None and qq.dot(prev) < 0:
                qq = -qq
            prev = qq
            qs[t], ls[t], ss[t] = list(qq), list(l), list(sc)
        for i in range(4):
            fill(fcs[(f'pose.bones["{n}"].rotation_quaternion', i)], frames, qs[:, i])
        for i in range(3):
            fill(fcs[(f'pose.bones["{n}"].location', i)], frames, ls[:, i])
            fill(fcs[(f'pose.bones["{n}"].scale', i)], frames, ss[:, i])
    act.use_fake_user = True
    return act


def fill(fc, frames, vals):
    kp = fc.keyframe_points
    while len(kp):
        kp.remove(kp[0], fast=True)
    kp.add(len(frames))
    co = np.empty(2 * len(frames))
    co[0::2], co[1::2] = frames, vals
    kp.foreach_set("co", co)
    kp.foreach_set("interpolation", [1] * len(frames))
    fc.update()


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--set", required=True, help="набор листов: game/assets/characters/<набор>")
    ap.add_argument("--frames", nargs="+", required=True, help="действия листа (первое — стойка кадрирования) и кадры")
    ap.add_argument("--clips", nargs="*", default=[], help="действие=клип GLB (иначе имя действия)")
    ap.add_argument("--window", nargs="*", default=[])
    ap.add_argument("--feet-fix", nargs="*", default=[])
    ap.add_argument("--size", type=int, default=864)
    ap.add_argument("--frame-w", type=int, default=0, help="ширина кадра листа (проверка: кадр не расширился)")
    ap.add_argument("--elev", type=float, default=14.0)
    ap.add_argument("--front-yaw", type=float, default=0.0)
    ap.add_argument("--samples", type=int, default=16)
    ap.add_argument("--margin", type=float, default=1.12)
    ap.add_argument("--derive", nargs="*", default=[], help="новое=клип-источник (действие из --frames или клип GLB)")
    ap.add_argument("--stance", default="", help="действие-стойка производных клипов (кадр начала окна)")
    ap.add_argument("--keep", nargs="*", default=[], help="кость=доля клипа (остальные, кроме таза и ног, — 1)")
    ap.add_argument("--bookend-s", type=float, default=0.5)
    ap.add_argument("--render", nargs="*", default=[], help="действие=кадров — что рендерить")
    ap.add_argument("--fps", nargs="*", default=[])
    ap.add_argument("--dirs", nargs="*", type=int, default=list(range(8)))
    ap.add_argument("--work", required=True, help="папка кадров (кадры уже есть — не рендерятся заново)")
    ap.add_argument("--probe", nargs="*", default=[], help="действие:направление:кадр — отрендерить для сверки")
    ap.add_argument("--manifest-extra", default="", help="JSON: поля в описание действий (_source и т. п.)")
    ap.add_argument("--patch-game", action="store_true", help="без рендера: обновить у действий копии игры поле derived (замеры)")
    args = ap.parse_args(argv)

    work = Path(args.work); work.mkdir(parents=True, exist_ok=True)
    frames_by = {k: int(v) for k, v in kv(args.frames).items()}
    clip_of = kv(args.clips)
    windows = {k: tuple(float(x) for x in v.split(":")) for k, v in kv(args.window).items()}
    keep = kv(args.keep, float)
    derive = kv(args.derive)
    render = {k: int(v) for k, v in kv(args.render).items()}
    fps_of = kv(args.fps, float)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.glb).resolve()), disable_bone_shape=True)
    objs = []
    for o in bpy.context.scene.objects:
        if o in before:
            continue
        if any(c.name == "glTF_not_exported" for c in o.users_collection):
            o.hide_render = True
            continue
        objs.append(o)
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"]
    scene = bpy.context.scene
    actions = list(bpy.data.actions)

    def find(key):
        return next((a for a in actions if a.name == key or a.name.split(".")[0] == key), None)

    def act_of(name):
        a = find(clip_of.get(name, name))
        if a is None:
            raise SystemExit(f"нет клипа {clip_of.get(name, name)}; в GLB: {[x.name for x in actions]}")
        return a

    # стопы стойки — как рендер листа (render_sprites --feet-fix), до кадрирования
    if args.feet_fix:
        rig = feet_fix.rig_from_blender(arm, meshes)
        for name in args.feet_fix:
            a = act_of(name)
            kind = feet_fix.kind_of(name) or feet_fix.kind_of(a.name) or "idle"
            rep = feet_fix.fix_action(arm, rig, a, kind, window=windows.get(name))
            print(f"  стопы {name} ({a.name}): не прошло {rep['fail']}", flush=True)

    def window_frames(name, a, n):
        f0, f1 = a.frame_range
        if name in windows:
            wa, wb = windows[name]
            f0, f1 = f0 + (f1 - f0) * wa, f0 + (f1 - f0) * wb
        den = max(1, n - 1) if name in windows else n
        return [f0 + (f1 - f0) * i / den for i in range(n)], f0, f1, den

    # производные клипы — из позы стойки (кадр начала окна, после исправления стоп)
    derived = {}
    tilts = {}
    if derive:
        st = act_of(args.stance)
        feet_fix.assign(arm, st)
        frame_at(scene, window_frames(args.stance, st, 2)[0][0])
        stance_pose = pose_now(arm)
        bpy.context.view_layer.update()
        stance_torso = torso_vec(arm)
        stance_feet = feet_now(arm)
        fixed = {pb.name for pb in arm.pose.bones if pb.parent is None or any(k in pb.name for k in LEGS)}
        fixed |= {"Hips"}
        for new, src in derive.items():
            sa = act_of(src)
            bn = int(round(args.bookend_s * scene.render.fps / scene.render.fps_base))
            derived[new] = derive_action(scene, arm, sa, stance_pose, new, keep, bn, fixed)
            fr_all = np.arange(round(sa.frame_range[0]), round(sa.frame_range[1]) + 1, 1.0)
            tilts[new] = (round(torso_tilt_deg(scene, arm, derived[new], fr_all, stance_torso), 2),
                          round(torso_tilt_deg(scene, arm, sa, fr_all, stance_torso), 2),
                          round(feet_drift_m(scene, arm, derived[new], fr_all, stance_feet), 4))
            print(f"  {new}: наклон корпуса от стойки до {tilts[new][0]}° (клип {sa.name} как есть — до {tilts[new][1]}°), "
                  f"стопы сдвигаются до {tilts[new][2] * 100:.2f} см", flush=True)
            print(f"  {new}: из {sa.name} (таз и ноги — {args.stance}, доли {keep}, склейка {bn} кадров)", flush=True)

    def act_any(name):
        return derived.get(name) or act_of(name)

    # кадрирование — как render_sprites: первое действие в начале окна
    first = next(iter(frames_by))
    a0 = act_of(first)
    feet_fix.assign(arm, a0)
    g0, g1 = a0.frame_range
    if first in windows:
        g0 = g0 + (g1 - g0) * windows[first][0]
    scene.frame_set(int(round(g0)))
    matte = rs.matte_materials(meshes)
    roots = [o for o in objs if o.parent is None]
    pivot = bpy.data.objects.new("SpritePivot", None)
    scene.collection.objects.link(pivot)
    for r in roots:
        r.parent = pivot
    bpy.context.view_layer.update()
    mins, maxs = rs.scene_bounds(meshes)
    height = maxs.z - mins.z
    center = Vector(((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, mins.z))
    for r in roots:
        r.location -= Vector((center.x, center.y, mins.z))
    bpy.context.view_layer.update()
    cam_data = bpy.data.cameras.new("SpriteCam"); cam_data.type = "ORTHO"
    extent = height * args.margin
    cam = bpy.data.objects.new("SpriteCam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    dist = extent * 4
    elev = math.radians(args.elev)
    cam.location = Vector((0, -dist * math.cos(elev), height / 2 + dist * math.sin(elev)))
    look = Vector((0, 0, height / 2))
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun = bpy.data.lights.new("Key", "SUN"); sun.energy = 4.5; sun.angle = math.radians(20)
    so = bpy.data.objects.new("Key", sun); scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(55), 0, math.radians(-35))
    fill_l = bpy.data.lights.new("Fill", "SUN"); fill_l.energy = 2.0; fill_l.angle = math.radians(40)
    fo = bpy.data.objects.new("Fill", fill_l); scene.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(70), 0, math.radians(140))
    rim = bpy.data.lights.new("Rim", "SUN"); rim.energy = 2.5; rim.angle = math.radians(10)
    ro = bpy.data.objects.new("Rim", rim); scene.collection.objects.link(ro)
    ro.rotation_euler = (math.radians(120), 0, math.radians(20))
    world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.6, 0.6, 0.65, 1); bg.inputs[1].default_value = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"; scene.cycles.samples = args.samples; scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_y = args.size; scene.render.resolution_x = int(args.size * 0.75)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"; scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    cam_data.ortho_scale = height * args.margin
    print(f"  кадрирование: рост {height:.3f} м, центр {tuple(round(v, 4) for v in center)}", flush=True)

    # пол клипов → пол стойки; ширина кадра — проверка (кадр листа не меняется)
    def set_frame(act, f):
        feet_fix.assign(arm, act)
        frame_at(scene, f)
    names = list(frames_by) + [n for n in render if n not in frames_by]
    todo = []
    for n in names:
        nf = render.get(n, frames_by.get(n))
        a = act_any(n)
        todo.append((a, window_frames(n, a, nf)[0]))
    yaws = [args.front_yaw + d * 360.0 / 8 for d in range(8)]
    k0 = len(frames_by)
    # ширина кадра — по действиям листа (как render_sprites --fit); новые клипы проверяются, кадр не меняют
    hx, top, floors = rs.screen_extent(meshes, todo[:k0], set_frame, yaws, args.elev, height / 2)
    if len(todo) > k0:
        hx_new, _, floors_new = rs.screen_extent(meshes, todo[k0:], set_frame, yaws, args.elev, height / 2)
        floors = floors + floors_new
    else:
        hx_new = 0.0
    floor_shift = {n: floors[0] - fl for n, fl in zip(names, floors)}
    # производный клип стоит ногами и тазом в позе стойки — и на её полу (пол клипа по кадрам у стойки с
    # покачиванием — среднее окна, у производного — один кадр: иначе подошвы реплики на 0,5–1 см ниже кадра покоя)
    for n in derived:
        if args.stance in floor_shift:
            floor_shift[n] = floor_shift[args.stance]
    print("  пол клипов → пол стойки (см): " + ", ".join(f"{n} {v * 100:+.2f}" for n, v in floor_shift.items()), flush=True)
    m_per_px = extent / scene.render.resolution_y
    need = int(math.ceil(2 * hx * 1.03 / m_per_px / 16.0) * 16)
    if need > scene.render.resolution_x:
        print(f"  кадр шире: {scene.render.resolution_x} → {need} px (как у листа)", flush=True)
        scene.render.resolution_x = need
        cam_data.ortho_scale = extent * max(need, scene.render.resolution_y) / scene.render.resolution_y
    need_new = int(math.ceil(2 * hx_new * 1.03 / m_per_px / 16.0) * 16)
    if need_new > scene.render.resolution_x:
        print(f"  ВНИМАНИЕ: новый клип шире кадра ({need_new} > {scene.render.resolution_x} px) — край обрежется", file=sys.stderr, flush=True)
    if args.frame_w and args.frame_w != scene.render.resolution_x:
        raise SystemExit(f"ширина кадра {scene.render.resolution_x} ≠ листа {args.frame_w}")

    def render_one(name, d, i, n, path):
        a = act_any(name)
        fr, f0, f1, den = window_frames(name, a, n)
        feet_fix.assign(arm, a)
        dz = floor_shift.get(name, 0.0)
        for r in roots:
            r.location.z += dz
        pivot.rotation_euler = (0, 0, math.radians(args.front_yaw + d * 360.0 / 8))
        frame_at(scene, fr[i])
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        for r in roots:
            r.location.z -= dz
        return a, f0, f1, den

    rep = {"set": args.set, "glb": str(args.glb), "height_m": round(height, 4), "floor_shift_m": {k: round(v, 4) for k, v in floor_shift.items()},
           "probe": []}
    for p in args.probe:
        name, d, i = p.split(":")
        n = frames_by.get(name) or render[name]
        out = work / f"probe_{name}_{d}_{i}.png"
        t0 = time.time()
        render_one(name, int(d), int(i), n, out)
        rep["probe"].append({"action": name, "dir": int(d), "frame": int(i), "png": str(out), "seconds": round(time.time() - t0, 1)})
        print(f"  проба {p}: {time.time() - t0:.1f} с", flush=True)

    meta_extra = json.loads(args.manifest_extra) if args.manifest_extra else {}
    for name, n in render.items():
        t0 = time.time()
        a = None
        for d in args.dirs:
            for i in range(n):
                path = work / name / f"{d}_{i:03d}.png"
                if path.exists():
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                a, f0, f1, den = render_one(name, d, i, n, path)
            print(f"  {name}: направление {d} готово ({time.time() - t0:.0f} с)", flush=True)
        a = act_any(name)
        fr, f0, f1, den = window_frames(name, a, n)
        clip_s = (f1 - f0) * scene.render.fps_base / scene.render.fps
        m = {"sheet": f"{name}.png", "frames": n, "fps": fps_of.get(name, 24.0), "clip": a.name,
             "clip_seconds": round(clip_s, 4), "natural_fps": round(den / max(clip_s, 1e-6), 2)}
        if abs(floor_shift.get(name, 0.0)) > 1e-5:
            m["floor_shift_m"] = round(floor_shift[name], 4)
        if name in windows:
            m["window"] = list(windows[name]); m["playback"] = "pingpong"
        if name in derived:
            m["derived"] = {"from": derive[name], "stance": args.stance, "stance_frame": "начало окна",
                            "fixed": "ноги (мировой поворот бёдер — стойки), смещение таза", "keep": keep, "bookend_s": args.bookend_s,
                            "torso_tilt_max_deg": tilts[name][0], "source_torso_tilt_max_deg": tilts[name][1],
                            "feet_drift_max_m": tilts[name][2]}
        m.update(meta_extra.get(name, {}))
        (work / name).mkdir(parents=True, exist_ok=True)
        (work / name / "action.json").write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
        if args.patch_game and name in derived:
            gp = ROOT / "game" / "assets" / "characters" / args.set / "sprites.json"
            gm = json.loads(gp.read_text(encoding="utf-8"))
            if name in gm.get("actions", {}):
                gm["actions"][name]["derived"] = m["derived"]
                gp.write_text(json.dumps(gm, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                print(f"  {args.set}/{name}: derived обновлено в копии игры", flush=True)
    rep["matte"] = bool(matte)
    rep["frame_w"], rep["frame_h"] = scene.render.resolution_x, scene.render.resolution_y
    (work / "render_report.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    print("готово", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
