#!/usr/bin/env python3
"""Нина в мамином зеркале (M15а): позы из 3D-модели → листы для стекла (Blender как модуль bpy, Cycles CPU).

  python3 pipeline/render/render_mirror.py --request pipeline/requests/mirror_nina.json \
      --glb pipeline/3d/out/nina/animations.glb --extra pipeline/3d/out/nina/mirror_clips.glb \
      --out assets/characters/nina_mirror [--only write,cup] [--samples 8] [--frames 6] [--report x.json]

Горница O3 нарисована одним кадром; зеркало показывает её «со своего прежнего места». Здесь та же комната
восстановлена по перспективе рисунка (поле request.room): линия горизонта, высота и фокус взгляда. Каждая поза
ставится в эту комнату там, где она стоит на рисунке (`at` — точка пола под фигурой, px холста 1672×941), и
снимается ортокамерой по лучу из точки взгляда — наклон и поворот у каждой позы свои, как у фигуры в этом месте
комнаты. Масштаб в игре: рост `height` (px холста) = 1,63 м × (at.y − горизонт) / высота взгляда.

Свет — свет горницы: свеча на столе (тёплая точка), окно (холодный прямоугольник на задней стене), тёплый
рассеянный свет комнаты. Стол, за которым сидит или стоит Нина, — «ловец теней» по линии края стола на рисунке: то,
что ниже столешницы за краем, в листе прозрачно (стол на рисунке закрывает), а тень рук и чашки ложится на стол.
Пол — тоже ловец теней (тень фигуры).

Позы (request.poses.<id>):
  clip / clip_window [доли] / hold_frame [доля]  — откуда поза (клип Meshy или перенесённый с библиотеки)
  facing_deg        — куда смотрит: 0 — на зрителя, + — к правому краю картинки, 180 — к задней стене
  frames, loop_s    — кадров в петле и длительность петли в естественном темпе (у клипа — длина окна)
  playback          — loop | pingpong
  offsets           — {кость: [x, y, z]°} добавочные повороты в локальных осях кости
  breath            — {amp_deg, period_s}: дыхание грудью (держится поза)
  ik                — {left|right: {target: [x, y, z] м в осях фигуры (x — её левая рука, −y — вперёд, z — вверх),
                       pole: [...], stroke: {...}}} руки к точкам (на столе, у зеркальца)
  look              — {target: [x, y, z], influence} куда смотрит голова
  props             — [{type: cup|hand_mirror|pen, bone, at: [x, y, z], rot: [x, y, z]°, ref_frame}] предмет в руке
  table             — {edge_px: [[x, y], [x, y]], top_m, depth_m, behind_m} стол перед фигурой: край на рисунке;
                       behind_m — на сколько таз (или носки стоя) за краем стола: глубина `at` считается отсюда
  rows              — для ходьбы: [{facing_deg, dir: [±1, 0]}] — строки листа по направлениям
Результат: <out>/<поза>.png (строки — направления, столбцы — кадры), <out>/sprites.json (как у листов
персонажей + у каждой позы at, height, px_per_m, view: наклон и поворот камеры; ходьба — ground_speed_mps).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy  # noqa: I001  (bmesh — только после bpy)
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline" / "3d"))
sys.path.insert(0, str(ROOT / "pipeline" / "render"))
import feet_fix as ff  # noqa: E402

FPS = 30  # клипы Meshy — 30 к/с


def log(m: str) -> None:
    print(m, flush=True)


# ------------------------------------------------------------------ комната по рисунку

class Room:
    """Холст рисунка (x вправо, y вниз, px) ↔ мир Blender (X вправо, Y вглубь комнаты, Z вверх, м).
    Точка взгляда — (0, 0, H); горизонт — строка yh; фокус f px; центр — столбец cx."""

    def __init__(self, spec: dict):
        self.yh = float(spec["horizon_y"])
        self.H = float(spec["camera_h_m"])
        self.f = float(spec["focal_px"])
        self.cx = float(spec.get("center_x", 836))

    def point(self, x: float, y: float, h: float = 0.0) -> Vector:
        """Точка холста на высоте h над полом → мир."""
        depth = self.f * (self.H - h) / (y - self.yh)
        return Vector(((x - self.cx) * depth / self.f, depth, h))

    def project(self, P: Vector) -> tuple[float, float]:
        return (self.cx + P.x * self.f / P.y, self.yh + (self.H - P.z) * self.f / P.y)

    def ppm(self, depth: float) -> float:
        return self.f / depth

    def eye(self) -> Vector:
        return Vector((0.0, 0.0, self.H))


# ------------------------------------------------------------------ сцена

def clean() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.render.fps_base = 1.0


def import_glb(path: str):
    before, acts0 = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(Path(path).resolve()), disable_bone_shape=True)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if any(c.name == "glTF_not_exported" for c in o.users_collection):
            bpy.data.objects.remove(o, do_unlink=True)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH"]
    acts = [a for a in bpy.data.actions if a not in acts0]
    return arm, meshes, acts, new


def load_character(glb: str, extras: list[str]):
    arm, meshes, acts, _ = import_glb(glb)
    fix_bone_lengths(arm)
    for x in extras:
        if not x or not Path(x).exists():
            log(f"  нет {x} — пропуск")
            continue
        a2, m2, acts2, objs2 = import_glb(x)
        names = {b.name for b in arm.data.bones}
        miss = [b.name for b in a2.data.bones if b.name not in names]
        if miss:
            raise SystemExit(f"{x}: другой скелет (нет костей {miss[:5]})")
        for o in objs2:
            bpy.data.objects.remove(o, do_unlink=True)
        acts += acts2
        log(f"  клипы из {Path(x).name}: {[a.name for a in acts2]}")
    return arm, meshes, acts


def fix_bone_lengths(arm) -> None:
    """Импорт glTF даёт костям длину ×100 (арматура в масштабе 0,01): хвост предплечья — в 20 м от локтя, и IK
    тянет к цели этот хвост. Длина = до головы первой дочерней кости, направление и крен — прежние (поза покоя и
    все клипы не меняются)."""
    vl = bpy.context.view_layer
    vl.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in arm.data.edit_bones:
        d = eb.tail - eb.head
        kids = list(eb.children)
        L = (kids[0].head - eb.head).length if kids else 0.0
        if L < 1.0:
            L = 8.0   # 8 см в единицах арматуры
        roll = eb.roll
        eb.tail = eb.head + d.normalized() * L
        eb.roll = roll
    bpy.ops.object.mode_set(mode="OBJECT")


def retarget_library(arm, meshes, library: str, clips: list[str], fix_walk: list[str]) -> list:
    """Клипы библиотеки (тот же скелет Meshy, другие пропорции) → на скелет персонажа (как retarget_clips.py)."""
    import retarget_clips as rc  # noqa: PLC0415
    tgt = ff.rig_from_blender(arm, meshes)
    lib_arm, lib_meshes, lib_acts, lib_objs = import_glb(library)
    for a in lib_acts:
        a.name = "_lib_" + a.name.split(".")[0]
    src = ff.rig_from_blender(lib_arm, lib_meshes)
    out = []
    for clip in clips:
        a = ff.find_action(lib_acts, "_lib_" + clip)
        if a is None:
            raise SystemExit(f"в библиотеке нет {clip}")
        fr = rc._frames(a)
        R, P = ff.sample(lib_arm, a, src, fr)
        Rt, Pt = rc.retarget_world(src, tgt, R, P)
        Pt, _fl = rc.floor_shift(arm, tgt, Rt, Pt)
        Q, loc = rc.to_basis(arm, tgt, Rt, Pt)
        act = rc.write_action(arm, tgt, clip, fr - fr[0], Q, loc)
        if clip in fix_walk:
            rep = ff.fix_action(arm, tgt, act, "walk")
            log(f"  стопы {clip}: не прошло {rep['fail']}")
        out.append(act)
        log(f"  перенос {clip}: {len(fr)} кадров")
    for o in lib_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in lib_acts:
        bpy.data.actions.remove(a)
    ff.assign(arm, None)
    return out


# ------------------------------------------------------------------ материалы и предметы

def material(name: str, color, rough=0.6, metal=0.0, holdout=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    if holdout:
        for n in list(nt.nodes):
            if n.type != "OUTPUT_MATERIAL":
                nt.nodes.remove(n)
        h = nt.nodes.new("ShaderNodeHoldout")
        nt.links.new(h.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
        return m
    b = nt.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def mesh_object(name: str, bm, mat=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if mat is not None:
        me.materials.append(mat)
    return o


def box_bm(sx, sy, sz, center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx + center[0], v.co.y * sy + center[1], v.co.z * sz + center[2]))
    return bm


def cylinder_bm(r1, r2, h, segs=24, center=(0, 0, 0), axis="Z"):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    for v in bm.verts:
        c = v.co.copy()
        if axis == "Y":
            c = Vector((c.x, c.z, c.y))
        elif axis == "X":
            c = Vector((c.z, c.y, c.x))
        v.co = c + Vector(center)
    return bm


def make_prop(kind: str):
    """Предмет в руке; начало координат — где его держит ладонь. → (объект-корень, [объекты])."""
    root = bpy.data.objects.new(f"prop_{kind}", None)
    bpy.context.scene.collection.objects.link(root)
    parts = []
    if kind == "cup":
        # глиняная кружка: кремовая глазурь, тёмный чай внутри, ручка; высота 8 см
        cer = material("ceramic", (0.82, 0.76, 0.64), rough=0.35)
        tea = material("tea", (0.16, 0.07, 0.03), rough=0.15)
        body = mesh_object("cup_body", cylinder_bm(0.04, 0.046, 0.09, center=(0, 0, 0.045)), cer)
        top = mesh_object("cup_tea", cylinder_bm(0.043, 0.043, 0.002, center=(0, 0, 0.081)), tea)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=12, radius1=0.006, radius2=0.006, depth=0.05)
        for v in bm.verts:
            v.co = Vector((v.co.x + 0.054, v.co.y, v.co.z + 0.047))
        handle = mesh_object("cup_handle", bm, cer)
        parts = [body, top, handle]
    elif kind == "hand_mirror":
        # Дунино зеркальце: деревянная рамка 13×17 см, стекло с одной стороны (−Y — к лицу)
        wood = material("frame_wood", (0.26, 0.14, 0.07), rough=0.55)
        glass = material("mirror_glass", (0.78, 0.8, 0.82), rough=0.06, metal=1.0)
        frame = mesh_object("mirror_frame", box_bm(0.13, 0.016, 0.17), wood)
        face = mesh_object("mirror_face", box_bm(0.105, 0.002, 0.145, center=(0, -0.0085, 0)), glass)
        parts = [frame, face]
    elif kind == "pen":
        # гусиное перо: светлый очин от кончика (−4 см) к опахалу — его видно над рукой, и по нему видно, что пишет
        quill = material("quill", (0.86, 0.84, 0.78), rough=0.6)
        tip = material("quill_tip", (0.12, 0.1, 0.08), rough=0.4)
        shaft = mesh_object("pen", cylinder_bm(0.0012, 0.0028, 0.2, segs=8, center=(0, 0, 0.06)), quill)
        nib = mesh_object("pen_tip", cylinder_bm(0.0003, 0.0013, 0.015, segs=8, center=(0, 0, -0.0475)), tip)
        vane = mesh_object("pen_vane", box_bm(0.024, 0.0015, 0.13, center=(0.006, 0, 0.095)), quill)
        parts = [shaft, nib, vane]
    elif kind == "paper":
        pap = material("paper", (0.86, 0.82, 0.7), rough=0.9)
        parts = [mesh_object("paper", box_bm(0.21, 0.28, 0.001), pap)]
    else:
        raise SystemExit(f"неизвестный предмет {kind}")
    for p in parts:
        p.parent = root
    return root, parts


# ------------------------------------------------------------------ свет горницы

def room_lights(room: Room, spec: dict) -> list:
    sc = bpy.context.scene
    objs = []
    w = bpy.data.worlds.new("RoomAmbient")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    amb = spec.get("ambient", {})
    bg.inputs[0].default_value = (*amb.get("color", [0.42, 0.3, 0.2]), 1.0)
    bg.inputs[1].default_value = float(amb.get("strength", 0.35))
    c = spec.get("candle")
    if c:
        L = bpy.data.lights.new("Candle", "POINT")
        L.color = c.get("color", [1.0, 0.58, 0.28])
        L.energy = float(c.get("power_w", 30))
        L.shadow_soft_size = float(c.get("radius_m", 0.03))
        o = bpy.data.objects.new("Candle", L)
        o.location = room.point(*c["flame_px"], float(c.get("height_m", 1.0)))
        sc.collection.objects.link(o)
        objs.append(o)
        log(f"  свеча: {tuple(round(v, 2) for v in o.location)}")
    wnd = spec.get("window")
    if wnd:
        L = bpy.data.lights.new("Window", "AREA")
        L.shape = "RECTANGLE"
        L.size, L.size_y = wnd.get("size_m", [1.0, 1.4])
        L.color = wnd.get("color", [0.72, 0.82, 1.0])
        L.energy = float(wnd.get("power_w", 120))
        o = bpy.data.objects.new("Window", L)
        wall = room.point(*wnd["wall_base_px"])          # пол у задней стены под окном → глубина стены
        cx, cy = wnd["center_px"]
        o.location = Vector(((cx - room.cx) * wall.y / room.f, wall.y, room.H - (cy - room.yh) * wall.y / room.f))
        o.rotation_euler = (math.radians(-90), 0, 0)   # свет площадки — по её −Z: из окна в комнату (к зрителю)
        sc.collection.objects.link(o)
        objs.append(o)
        log(f"  окно: {tuple(round(v, 2) for v in o.location)}")
    k = spec.get("room")
    if k:
        # тёплый рассеянный свет горницы со стороны зрителя (на рисунке комната освещена спереди-слева)
        L = bpy.data.lights.new("RoomKey", "AREA")
        L.shape = "DISK"
        L.size = float(k.get("size_m", 3.0))
        L.color = k.get("color", [1.0, 0.78, 0.55])
        L.energy = float(k.get("power_w", 200))
        o = bpy.data.objects.new("RoomKey", L)
        o.location = Vector(k.get("at_m", [-2.5, 1.0, 2.4]))
        sc.collection.objects.link(o)
        objs.append(o)
    return objs


def aim(o, target: Vector) -> None:
    d = target - o.location
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


# ------------------------------------------------------------------ позы

def bake_pose(arm, src_act, name: str, times_s: list[float], offsets: dict, breath: dict | None, loop_s: float):
    """Новое действие: кадр i = поза клипа в момент times_s[i] (или одна поза) + добавочные повороты + дыхание."""
    sc = bpy.context.scene
    names = [b.name for b in arm.data.bones]
    poses = []
    for i, t in enumerate(times_s):
        ff.assign(arm, src_act)
        f = t * FPS
        fi = math.floor(f)
        sc.frame_set(int(fi), subframe=float(f - fi))
        basis = {n: arm.pose.bones[n].matrix_basis.copy() for n in names}
        ph = 2 * math.pi * i / max(1, len(times_s))
        for bn, deg in offsets.items():
            if bn in basis:
                basis[bn] = basis[bn] @ Euler([math.radians(v) for v in deg], "XYZ").to_matrix().to_4x4()
        if breath:
            a = float(breath.get("amp_deg", 1.2))
            for bn, k in (("Spine01", 1.0), ("Spine", 0.6), ("neck", -0.5)):
                if bn in basis:
                    basis[bn] = basis[bn] @ Euler((math.radians(a * k * math.sin(ph)), 0, 0)).to_matrix().to_4x4()
            for bn in ("LeftShoulder", "RightShoulder"):
                if bn in basis:
                    basis[bn] = basis[bn] @ Euler((0, 0, math.radians(0.6 * a * math.sin(ph) * (1 if bn[0] == "L" else -1)))).to_matrix().to_4x4()
        poses.append(basis)
    act = bpy.data.actions.new(name)
    ff.assign(arm, act)
    for n in names:
        pb = arm.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
    for i, basis in enumerate(poses):
        for n in names:
            pb = arm.pose.bones[n]
            pb.matrix_basis = basis[n]
            pb.keyframe_insert("rotation_quaternion", frame=i)
            pb.keyframe_insert("location", frame=i)
    for fc in ff.action_fcurves(act):
        for k in fc.keyframe_points:
            k.interpolation = "LINEAR"
    return act


def clear_constraints(arm) -> None:
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)


def empty(name: str, parent=None) -> bpy.types.Object:
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


HAND_REST: dict = {}


def hand_rest_frames(arm, meshes) -> None:
    """Кисть в позе покоя (до любых поворотов фигуры): поворот кости и оси ладони по сетке — пальцы (от запястья к
    середине кисти), нормаль ладони (самая тонкая ось; у рига Meshy в покое ладонь смотрит вперёд, −Y), большой палец
    (вверх). Нужны, чтобы повернуть кисть «ладонью вниз» и вложить в неё предмет."""
    ff.assign(arm, None)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    me = meshes[0]
    co = np.array([v.co[:] for v in me.data.vertices])
    mw = np.array(me.matrix_world)
    co = co @ mw[:3, :3].T + mw[:3, 3]
    for S in ("Left", "Right"):
        b = arm.data.bones[S + "Hand"]
        M = arm.matrix_world @ b.matrix_local
        gi = me.vertex_groups[S + "Hand"].index
        idx = [v.index for v in me.data.vertices for g in v.groups if g.group == gi and g.weight > 0.5]
        Pv = co[idx]
        c = Pv.mean(0)
        _u, _s, Vt = np.linalg.svd(Pv - c)
        head = np.array(M.translation)
        f0 = Vt[0] * (1 if (c - head) @ Vt[0] > 0 else -1)
        n0 = Vt[2] * (1 if Vt[2][1] < 0 else -1)
        t0 = np.cross(n0, f0)
        t0 = t0 * (1 if t0[2] > 0 else -1)
        HAND_REST[S] = {"R": M.to_3x3().normalized(), "f": Vector(f0), "n": Vector(n0), "t": Vector(t0)}
        log(f"  кисть {S}: пальцы {np.round(f0, 2)}, ладонь {np.round(n0, 2)}, большой {np.round(t0, 2)}")


def _frame(f: Vector, n: Vector, t_hint: Vector) -> Matrix:
    f = f.normalized()
    n = (n - f * n.dot(f)).normalized()
    t = f.cross(n)
    if t.dot(t_hint) < 0:
        t = -t
    return Matrix((f, n, t)).transposed()   # столбцы f, n, t


def hand_target_rot(S: str, fingers, palm, FM: Matrix) -> Matrix:
    """Мировой поворот кости кисти, при котором пальцы и ладонь смотрят как задано (оси фигуры)."""
    h = HAND_REST[S]
    rest = _frame(h["f"], h["n"], h["t"])
    want_f, want_n = Vector(fingers), Vector(palm)
    t_rest = h["f"].cross(h["n"]).dot(h["t"])
    want = Matrix((want_f.normalized(), (want_n - want_f.normalized() * want_n.dot(want_f.normalized())).normalized(),
                   want_f.normalized().cross((want_n - want_f.normalized() * want_n.dot(want_f.normalized())).normalized()) * (1 if t_rest > 0 else -1))).transposed()
    return FM.to_3x3() @ want @ rest.transposed() @ h["R"]


def hand_frame_now(arm, S: str):
    """Кисть сейчас (мир): запястье, пальцы, ладонь, большой палец."""
    M = bone_world(arm, S + "Hand")
    Rn = M.to_3x3().normalized()
    h = HAND_REST[S]
    D = Rn @ h["R"].inverted()
    return M.translation.copy(), (D @ h["f"]).normalized(), (D @ h["n"]).normalized(), (D @ h["t"]).normalized()


def fig_matrix(origin: Vector, facing_deg: float) -> Matrix:
    """Оси фигуры в мире: модель смотрит в −Y; facing 0 — на зрителя, + — к правому краю картинки."""
    return Matrix.Translation(origin) @ Matrix.Rotation(math.radians(facing_deg), 4, "Z")


def bone_world(arm, bone: str) -> Matrix:
    return arm.matrix_world @ arm.pose.bones[bone].matrix


# ------------------------------------------------------------------ камера, кадр, рендер

def view_basis(room: Room, origin: Vector, center_h: float):
    c = Vector((origin.x, origin.y, center_h))
    d = (c - room.eye()).normalized()
    right = d.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(d).normalized()
    return d, right, up


def eval_points(meshes, extra_objs) -> np.ndarray:
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in list(meshes) + list(extra_objs):
        if o.type != "MESH" or o.hide_render:
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        mw = np.array(ev.matrix_world)
        pts.append(co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3])
        ev.to_mesh_clear()
    return np.concatenate(pts) if pts else np.zeros((0, 3))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    ap.add_argument("--glb", required=True)
    ap.add_argument("--extra", nargs="*", default=[])
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=0)
    ap.add_argument("--frames", type=int, default=0, help="кадров на позу (проба), 0 — как в запросе")
    ap.add_argument("--ppm", type=float, default=0.0, help="px на метр (проба), 0 — как в запросе")
    ap.add_argument("--report", default="")
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    R = req["render_spec"]
    room = Room(R["room"])
    ppm = args.ppm or float(R.get("px_per_m", 300))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    only = [s for s in args.only.split(",") if s]

    clean()
    arm, meshes, acts = load_character(args.glb, args.extra)
    from render_sprites import matte_materials  # noqa: PLC0415
    matte = matte_materials(meshes)
    log(f"матовые материалы: {matte}")
    lib = R.get("library", {})
    if lib.get("clips"):
        acts += retarget_library(arm, meshes, str(ROOT / lib.get("path", "pipeline/3d/motions/agata_rev10_clips.glb")),
                                 lib["clips"], lib.get("fix_walk", []))
    log("клипы: " + ", ".join(a.name for a in acts))
    V0 = eval_points(meshes, [])
    char_h = float(V0[:, 2].max() - V0[:, 2].min())
    CHAR_H[0] = char_h
    log(f"рост модели {char_h:.3f} м")
    hand_rest_frames(arm, meshes)

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = args.samples or int(R.get("samples", 48))
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.resolution_percentage = 100
    room_lights(room, R.get("lights", {}))

    # корень фигуры: двигаем и поворачиваем его, арматура — дочерняя
    root = empty("FigureRoot")
    for o in [arm] + [m for m in meshes if m.parent is None]:
        o.parent = root
    cam_data = bpy.data.cameras.new("MirrorCam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("MirrorCam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam

    poses = R["poses"]
    plan = {pid: P for pid, P in poses.items() if (not only or pid in only) and not P.get("same_as")}
    manifest = {"name": req.get("sheet_name", "nina_mirror"), "kind": "mirror_poses", "directions": 1,
                "direction_order": "строки — направления позы (у ходьбы: 0 — влево, 1 — вправо); вид — из зеркала горницы",
                "character_height_m": round(char_h, 3), "px_per_m": ppm, "room": R["room"], "actions": {},
                "qa_note": R.get("qa_note", "")}
    acts_by = {}
    for pid, P in plan.items():
        src = ff.find_action(acts, P["clip"])
        if src is None:
            raise SystemExit(f"{pid}: нет клипа {P['clip']}; есть {[a.name for a in acts]}")
        acts_by[pid] = bake(arm, src, pid, P, args.frames)
    # ---- проход 1: габарит каждой позы в её кадре (все строки, каждый 4-й кадр)
    ext, speeds = {}, {}
    for pid, P in plan.items():
        ctx = setup_pose(sc, room, arm, meshes, root, pid, P, acts_by[pid])
        e = []
        for row in ctx["rows"]:
            root.matrix_world = fig_matrix(ctx["origin"], row["facing_deg"])
            d, right, up = view_basis(room, ctx["origin"], float(P.get("center_h_m", 0.8)))
            for i in range(0, ctx["n"], max(1, ctx["n"] // 6)):
                set_frame(sc, i, ctx["n"], ctx["dyn"])
                rel = eval_points(meshes, ctx["prop_objs"]) - np.array(ctx["origin"])
                u, v = rel @ np.array(right) * ppm, rel @ np.array(up) * ppm
                e.append((float(np.abs(u).max()), float(v.max()), float(-v.min())))
        ext[pid] = (max(x[0] for x in e), max(x[1] for x in e), max(x[2] for x in e))
        if P.get("rows") and any(r.get("dir") for r in P["rows"]):
            speeds[pid] = ground_speed(sc, arm, root, ctx)
            log(f"  {pid}: скорость по полу {speeds[pid]:.3f} м/с (опорная стопа)")
        log(f"  {pid}: at {ctx['at'][0]:.1f}, {ctx['at'][1]:.1f}; рост в кадре холста {ctx['height_px']:.1f} px; габарит {ext[pid]}")
        teardown(arm, ctx)
    # ---- общий кадр: опорная точка (пол под фигурой) на одном месте у всех поз
    margin = 12
    hw = max(x[0] for x in ext.values())
    top = max(x[1] for x in ext.values())
    bot = max(x[2] for x in ext.values())
    fw = int(math.ceil((2 * hw + 2 * margin) / 16.0) * 16)
    fh = int(math.ceil((top + bot + 2 * margin) / 16.0) * 16)
    piv = (fw / 2.0, margin + top)
    manifest.update({"frame_w": fw, "frame_h": fh, "pivot": {"x": 0.5, "y": round(piv[1] / fh, 5)}})
    log(f"кадр {fw}×{fh}, опора {piv}")
    sc.render.resolution_x, sc.render.resolution_y = fw, fh
    cam_data.ortho_scale = max(fw, fh) / ppm

    from PIL import Image  # noqa: PLC0415
    grade = R.get("grade")
    for pid, P in plan.items():
        ctx = setup_pose(sc, room, arm, meshes, root, pid, P, acts_by[pid])
        n = ctx["n"]
        log(f"== рендер {pid}: {n} кадров × {len(ctx['rows'])} строк")
        sheet = Image.new("RGBA", (fw * n, fh * len(ctx["rows"])), (0, 0, 0, 0))
        for ri, row in enumerate(ctx["rows"]):
            root.matrix_world = fig_matrix(ctx["origin"], row["facing_deg"])
            d, right, up = view_basis(room, ctx["origin"], float(P.get("center_h_m", 0.8)))
            center = ctx["origin"] - right * ((piv[0] - fw / 2) / ppm) + up * ((piv[1] - fh / 2) / ppm)
            cam.location = center - d * 20.0
            cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
            for i in range(n):
                set_frame(sc, i, n, ctx["dyn"])
                tmp = out / f"_tmp_{pid}_{ri}_{i}.png"
                sc.render.filepath = str(tmp)
                bpy.ops.render.render(write_still=True)
                fr = Image.open(tmp).convert("RGBA")
                if grade:
                    fr = grade_image(fr, grade)
                sheet.paste(fr, (i * fw, ri * fh))
                tmp.unlink()
            log(f"  строка {ri + 1}/{len(ctx['rows'])} готова")
        sheet.save(out / f"{pid}.png")
        elev = math.degrees(math.asin(max(-1.0, min(1.0, -d.z))))
        yaw = math.degrees(math.atan2(d.x, d.y))
        pb = ctx["playback"]
        a = {"sheet": f"{pid}.png", "frames": n, "fps": round((n if pb == "loop" else n - 1) / ctx["loop_s"], 3),
             "playback": pb, "clip": ctx["src"], "loop_s": round(ctx["loop_s"], 3),
             "at": [round(ctx["at"][0], 1), round(ctx["at"][1], 1)], "height": round(ctx["height_px"], 1),
             "view": {"elev_deg": round(elev, 2), "yaw_deg": round(yaw, 2)}, "facing_deg": float(P.get("facing_deg", 0.0)),
             "rows": [{"facing_deg": r["facing_deg"], **({"dir": r["dir"]} if r.get("dir") else {})} for r in ctx["rows"]]}
        if pid in speeds:
            a["ground_speed_mps"] = round(speeds[pid], 4)
        for k in ("path_px", "hold"):
            if P.get(k) is not None:
                a[k] = P[k]
        manifest["actions"][pid] = a
        teardown(arm, ctx)
    for pid, P in poses.items():
        if P.get("same_as") and P["same_as"] in manifest["actions"]:
            manifest["actions"][pid] = dict(manifest["actions"][P["same_as"]], same_as=P["same_as"])
    prev = out / "sprites.json"
    if only and prev.exists():   # проба части поз — остальные из прошлого манифеста
        old = json.loads(prev.read_text(encoding="utf-8"))
        for k, v in old.get("actions", {}).items():
            manifest["actions"].setdefault(k, v)
    prev.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.report:
        Path(args.report).write_text(json.dumps({k: {"at": v["at"], "height": v["height"], "view": v["view"]} for k, v in manifest["actions"].items()},
                                                ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"готово: {out}")
    return 0


def bake(arm, src, pid: str, P: dict, frames_override: int):
    f0, f1 = src.frame_range
    n = frames_override or int(P.get("frames", 24))
    pb = P.get("playback", "loop")
    if "hold_frame" in P:
        t = (f0 + (f1 - f0) * float(P["hold_frame"])) / FPS
        times, loop_s = [t] * n, float(P.get("loop_s", 3.0))
    else:
        wa, wb = P.get("clip_window", [0.0, 1.0])
        ta, tb = (f0 + (f1 - f0) * wa) / FPS, (f0 + (f1 - f0) * wb) / FPS
        den = max(1, n - 1) if pb == "pingpong" else n
        times, loop_s = [ta + (tb - ta) * i / den for i in range(n)], (tb - ta)
    act = bake_pose(arm, src, f"mirror_{pid}", times, P.get("offsets", {}), P.get("breath"), loop_s)
    return {"act": act, "n": n, "loop_s": loop_s, "playback": pb, "src": src.name}


def setup_pose(sc, room: Room, arm, meshes, root, pid: str, P: dict, baked: dict) -> dict:
    """Поза в комнате: место (от края стола), стол-ловец теней, IK рук, взгляд, предметы. → контекст."""
    ff.assign(arm, baked["act"])
    sc.frame_set(0)
    facing = float(P.get("facing_deg", 0.0))
    at = list(P["at"])
    origin = room.point(at[0], at[1], 0.0)
    made = []
    tb = P.get("table")
    edge_y, top = None, None
    if tb:
        (ex0, ey0), (ex1, ey1) = tb["edge_px"]
        top = float(tb.get("top_m", 0.75))
        e0, e1 = room.point(ex0, ey0, top), room.point(ex1, ey1, top)
        edge_y = 0.5 * (e0.y + e1.y)
        root.matrix_world = fig_matrix(Vector((origin.x, 0, 0)), facing)
        bpy.context.view_layer.update()
        if tb.get("ref", "Hips") == "front":
            ref_y = float(eval_points(meshes, [])[:, 1].min())
        else:
            ref_y = bone_world(arm, tb.get("ref", "Hips")).translation.y
        oy = edge_y + float(tb.get("behind_m", 0.3)) - ref_y
        origin = Vector(((at[0] - room.cx) * oy / room.f, oy, 0.0))   # столбец на рисунке — прежний
        depth = float(tb.get("depth_m", 0.9))
        # с запасом по бокам: у торца стола на рисунке — стул (ближе к зрителю), край подола там тоже закрыт
        pad = float(tb.get("pad_m", 0.2))
        x0, x1 = min(e0.x, e1.x) - pad, max(e0.x, e1.x) + pad
        t_obj = mesh_object(f"Table_{pid}", box_bm(x1 - x0, depth, top, center=((x0 + x1) / 2, edge_y - depth / 2, top / 2)))
        t_obj.is_holdout = True          # стол на рисунке закрывает всё, что ниже столешницы
        t_obj.visible_shadow = False
        made.append(t_obj)
        at = list(room.project(origin))
    FM = fig_matrix(origin, facing)
    root.matrix_world = FM
    bpy.context.view_layer.update()
    # пол под фигурой — ловец теней (тень ног и подола), круг ~1,6 м: дальше рисунок сам
    if float(P.get("floor_shadow_r_m", 0.8)) > 0:   # 0 — без тени на полу (за столом ноги не видны)
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=48, radius=float(P.get("floor_shadow_r_m", 0.8)))
        fl = mesh_object(f"Floor_{pid}", bm)
        fl.location = Vector((origin.x, origin.y, 0.0))
        fl.is_shadow_catcher = True
        made.append(fl)

    def place(v, space):
        """Точка в осях фигуры (по умолчанию) или стола: x — вбок от фигуры, y — от края стола к зрителю, z — над столешницей."""
        if space == "table" and edge_y is not None:
            return Vector((origin.x + v[0], edge_y - v[1], top + v[2]))
        return FM @ Vector(v)

    dyn = []   # f(фаза 0..1) — подвижные цели на кадр
    for side, spec in (P.get("ik") or {}).items():
        S = "Left" if side == "left" else "Right"
        tgt = empty(f"ik_{pid}_{side}")
        path = spec.get("path")
        tgt.location = place(path[0][1] if path else spec["target"], spec.get("space"))
        pole = empty(f"pole_{pid}_{side}")
        pole.location = FM @ Vector(spec.get("pole", [0.5 if side == "left" else -0.5, 0.3, 1.0]))
        made += [tgt, pole]
        c = arm.pose.bones[S + "ForeArm"].constraints.new("IK")
        c.target, c.pole_target = tgt, pole
        c.pole_angle = math.radians(float(spec.get("pole_angle_deg", -90)))
        c.chain_count = 2
        c.use_tail = True
        c.influence = float(spec.get("influence", 1.0))
        hp = spec.get("hand_path")
        if spec.get("hand") or hp:
            hr = empty(f"ikrot_{pid}_{side}")
            h0 = hp[0][1] if hp else spec["hand"]
            hr.matrix_world = Matrix.Translation(tgt.location) @ hand_target_rot(S, h0["fingers"], h0["palm"], FM).to_4x4()
            made.append(hr)
            cr = arm.pose.bones[S + "Hand"].constraints.new("COPY_ROTATION")
            cr.target = hr
            cr.influence = float(h0.get("influence", 1.0))
            if hp:
                qs = [(float(k), hand_target_rot(S, h["fingers"], h["palm"], FM).to_quaternion()) for k, h in hp]
                dyn.append(lambda ph, e=hr, qs=qs: setattr(e, "rotation_quaternion", key_at(qs, ph, quat=True)) or setattr(e, "rotation_mode", "QUATERNION"))
                hr.rotation_mode = "QUATERNION"
        if path or spec.get("stroke"):
            # путь кисти по ключам (строка письма, подъём кружки) и поверх — мелкий штрих пера
            pts = [(float(k), place(v, spec.get("space"))) for k, v in path] if path else [(0.0, Vector(tgt.location))]
            st = spec.get("stroke") or {}

            def move(ph, e=tgt, pts=pts, st=st):
                off = Vector((0.0, 0.0, 0.0))
                if st:
                    a, cy = st.get("amp_m", [0.02, 0.006, 0.004]), st.get("cycles", [2, 6, 6])
                    w = 2 * math.pi * ph
                    off = FM.to_3x3() @ Vector((a[0] * math.sin(cy[0] * w), a[1] * math.sin(cy[1] * w),
                                                max(0.0, a[2] * math.sin(cy[2] * w + 1.0))))
                e.location = key_at(pts, ph) + off
            dyn.append(move)
    lk = P.get("look")
    if lk:
        t = empty(f"look_{pid}")
        lp = lk.get("path")
        t.location = place(lp[0][1] if lp else lk["target"], lk.get("space"))
        made.append(t)
        if lp:
            pts = [(float(k), place(v, lk.get("space"))) for k, v in lp]
            dyn.append(lambda ph, e=t, pts=pts: setattr(e, "location", key_at(pts, ph)))
        for bn, infl in (("Head", lk.get("influence", 0.7)), ("neck", lk.get("neck_influence", 0.0))):
            if float(infl) > 0:
                c = arm.pose.bones[bn].constraints.new("DAMPED_TRACK")
                c.target, c.track_axis, c.influence = t, "TRACK_Z", float(infl)
    prop_objs = []
    for k, pr in enumerate(P.get("props", [])):
        proot, parts = make_prop(pr["type"])
        made += [proot] + parts
        prop_objs += parts
        sc.frame_set(int(pr.get("ref_frame", 0)))
        bpy.context.view_layer.update()
        rot = Euler([math.radians(v) for v in pr.get("rot", [0, 0, 0])], "XYZ").to_matrix()
        if pr.get("space") in ("figure", "table"):
            Mw = Matrix.Translation(place(pr["at"], pr["space"])) @ (FM.to_3x3() @ rot).to_4x4()
        else:
            # в кисти: at — [вдоль пальцев, от ладони, к большому пальцу] м; axis — куда смотрит ось Z предмета
            # (в тех же осях кисти) или "up" — вертикально; spin — поворот предмета вокруг своей оси, °
            S = pr["bone"].replace("Hand", "")
            w, fh, nh, th = hand_frame_now(arm, S)
            a = pr.get("at", [0, 0, 0])
            pos = w + fh * a[0] + nh * a[1] + th * a[2]
            ax = pr.get("axis", "up")
            z = Vector((0, 0, 1)) if ax == "up" else (fh * ax[0] + nh * ax[1] + th * ax[2]).normalized()
            ya = pr.get("y_axis")
            hint = (fh * ya[0] + nh * ya[1] + th * ya[2]) if ya else (nh if abs(nh.dot(z)) < 0.9 else fh)
            y = (hint - z * hint.dot(z)).normalized()
            x = y.cross(z)
            Rm = Matrix((x, y, z)).transposed() @ Matrix.Rotation(math.radians(float(pr.get("spin", 0))), 3, "Z")
            Mw = Matrix.Translation(pos) @ Rm.to_4x4()
        if pr.get("bone"):
            proot.parent = arm
            proot.parent_type = "BONE"
            proot.parent_bone = pr["bone"]
            bpy.context.view_layer.update()
        proot.matrix_world = Mw
        bpy.context.view_layer.update()
        for side, loc in (pr.get("hands") or {}).items():
            tgt = bpy.data.objects.get(f"ik_{pid}_{side}")
            if tgt is not None:
                tgt.parent = proot
                tgt.matrix_parent_inverse = Matrix.Identity(4)
                tgt.location = Vector(loc)
    bpy.context.view_layer.update()
    # угол полюса IK зависит от крена костей в позе клипа — подбирается так, чтобы локоть смотрел на цель-полюс
    for side, spec in (P.get("ik") or {}).items():
        if "pole_angle_deg" not in spec:
            S = "Left" if side == "left" else "Right"
            pa = calibrate_pole(sc, arm, S, bpy.data.objects[f"pole_{pid}_{side}"], dyn)
            log(f"  {pid}: полюс IK {side} {pa:.1f}°")
    rows = [{"facing_deg": float(r.get("facing_deg", facing)), "dir": r.get("dir")} for r in (P.get("rows") or [{"facing_deg": facing}])]
    return {"origin": origin, "at": at, "height_px": room_char_px(room, origin, meshes), "rows": rows, "dyn": dyn,
            "made": made, "prop_objs": prop_objs, **baked}


def grade_image(im, g: dict):
    """Тон горницы: рисунок тёплый и янтарный, нейтрально-серые ткани рядом с ним читаются синеватыми —
    множитель по каналам (mul) и подъём насыщенности (sat) после рендера."""
    from PIL import Image  # noqa: PLC0415
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb = a[..., :3] * np.array(g.get("mul", [1.0, 1.0, 1.0]), np.float32)
    sat = float(g.get("sat", 1.0))
    if sat != 1.0:
        lum = (rgb @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
        rgb = lum + (rgb - lum) * sat
    a[..., :3] = np.clip(rgb, 0.0, 1.0)
    return Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGBA")


def ground_speed(sc, arm, root, ctx) -> float:
    """Ходьба на месте: с какой скоростью опорная стопа (ниже другой) уезжает назад — с этой скоростью игра
    двигает фигуру, и стопа на полу стоит. → м/с в естественном темпе клипа."""
    root.matrix_world = fig_matrix(ctx["origin"], 0.0)
    n = ctx["n"]
    pts = []
    for i in range(n):
        set_frame(sc, i, n, ctx["dyn"])
        feet = [(arm.matrix_world @ arm.pose.bones[b].matrix).translation.copy() for b in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot")]
        pts.append(feet)
    dist, cnt = 0.0, 0
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        k = 0 if a[0].z + a[2].z < a[1].z + a[3].z else 1     # левая или правая — ниже
        dist += (b[k].y - a[k].y + b[k + 2].y - a[k + 2].y) / 2.0   # назад = +Y (лицом к −Y)
        cnt += 1
    return max(0.0, dist / (cnt * ctx["loop_s"] / n))


def calibrate_pole(sc, arm, S: str, pole, dyn) -> float:
    c = next(x for x in arm.pose.bones[S + "ForeArm"].constraints if x.type == "IK")

    def dev(deg):
        c.pole_angle = math.radians(deg)
        for f in dyn:
            f(0.0)
        arm.update_tag()
        sc.frame_set(0)
        bpy.context.view_layer.update()
        sh = (arm.matrix_world @ arm.pose.bones[S + "Arm"].matrix).translation
        el = (arm.matrix_world @ arm.pose.bones[S + "ForeArm"].matrix).translation
        wr = (arm.matrix_world @ arm.pose.bones[S + "Hand"].matrix).translation
        ax = (wr - sh).normalized()
        a, b = el - sh, pole.location - sh
        a, b = a - ax * a.dot(ax), b - ax * b.dot(ax)
        return a.angle(b) if a.length > 1e-6 and b.length > 1e-6 else math.pi
    best = min(range(-180, 180, 15), key=dev)
    fine = min([best + d * 2.5 for d in range(-6, 7)], key=dev)
    dev(fine)
    return fine


def room_char_px(room: Room, origin: Vector, meshes) -> float:
    return CHAR_H[0] * room.ppm(origin.y)


CHAR_H = [1.63]


def key_at(keys: list, ph: float, quat: bool = False):
    """Значение по ключам [(фаза 0..1, значение)] в фазе ph — по кругу, плавно (smoothstep между ключами)."""
    ph %= 1.0
    k = len(keys)
    for j in range(k):
        p0, v0 = keys[j]
        p1, v1 = keys[(j + 1) % k]
        if j + 1 == k:
            p1 += 1.0
        q = ph if ph >= p0 else ph + 1.0
        if p0 <= q < p1 or k == 1:
            w = 0.0 if k == 1 else (q - p0) / (p1 - p0)
            w = w * w * (3 - 2 * w)
            return v0.slerp(v1, w) if quat else v0.lerp(v1, w)
    return keys[0][1]


def set_frame(sc, i: int, n: int, dyn: list) -> None:
    """Кадр i позы: действие + подвижные цели (путь кисти, штрихи пера, взгляд)."""
    for f in dyn:
        f(i / max(1, n))
    sc.frame_set(i)
    bpy.context.view_layer.update()


def teardown(arm, ctx) -> None:
    clear_constraints(arm)
    for o in ctx["made"]:
        try:
            bpy.data.objects.remove(o, do_unlink=True)
        except ReferenceError:
            pass


if __name__ == "__main__":
    sys.exit(main())
