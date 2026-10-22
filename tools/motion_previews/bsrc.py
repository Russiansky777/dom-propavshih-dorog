"""Blender (bpy) — загрузка скелетов и выборка мировых матриц костей по кадрам; позирование Агаты."""
from __future__ import annotations

import math
from pathlib import Path

import bpy
import numpy as np

import mlib


def reset(fps: float) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    sc.render.fps = int(round(fps))
    sc.render.fps_base = sc.render.fps / fps


def _new_objects(before):
    new = [o for o in bpy.context.scene.objects if o not in before]
    keep = []
    for o in new:
        if any(c.name == "glTF_not_exported" for c in o.users_collection):
            bpy.data.objects.remove(o, do_unlink=True)
        else:
            keep.append(o)
    return keep


def import_any(path: str):
    """→ (armature, meshes, actions) для .glb/.gltf/.bvh/.fbx."""
    before = set(bpy.context.scene.objects)
    acts_before = set(bpy.data.actions)
    ext = Path(path).suffix.lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(Path(path).resolve()), disable_bone_shape=True)
    elif ext == ".bvh":
        bpy.ops.import_anim.bvh(filepath=str(Path(path).resolve()), axis_forward="-Z", axis_up="Y", global_scale=1.0,
                                frame_start=0, use_fps_scale=True, update_scene_fps=False,
                                update_scene_duration=False, rotate_mode="NATIVE")
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(Path(path).resolve()))
    else:
        raise ValueError(path)
    objs = _new_objects(before)
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"]
    acts = [a for a in bpy.data.actions if a not in acts_before]
    return arm, meshes, acts


def assign(arm, act) -> None:
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    ad.action = act
    if act is not None and hasattr(ad, "action_slot") and ad.action_slot is None and hasattr(act, "slots") and len(act.slots):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


def topo_bones(arm):
    names, parents = [], []
    def walk(b):
        names.append(b.name)
        parents.append(names.index(b.parent.name) if b.parent else -1)
        for c in b.children:
            walk(c)
    for b in arm.data.bones:
        if b.parent is None:
            walk(b)
    return names, parents


def _split(n):
    return (n[:-5], True) if n.endswith("@tail") else (n, False)


def rest_world(arm, names):
    W = np.array(arm.matrix_world)
    R, P = [], []
    for n in names:
        bn, tail = _split(n)
        b = arm.data.bones[bn]
        M = W @ np.array(b.matrix_local)
        R.append(mlib.ortho(M[:3, :3]))
        P.append((W @ np.r_[np.array(b.tail_local), 1.0])[:3] if tail else M[:3, 3])
    return np.array(R), np.array(P)


def sample(arm, act, frames, names=None):
    """Мировые ориентации/позиции голов костей в заданных кадрах (дробные — через subframe).
    Имя «X@tail» — хвост кости X (у BVH это End Site: макушка, носок)."""
    sc = bpy.context.scene
    assign(arm, act)
    if names is None:
        names, _ = topo_bones(arm)
    pbs = [(arm.pose.bones[_split(n)[0]], _split(n)[1]) for n in names]
    T = len(frames)
    R = np.zeros((T, len(names), 3, 3))
    P = np.zeros((T, len(names), 3))
    for t, f in enumerate(frames):
        fi = math.floor(f)
        sc.frame_set(int(fi), subframe=float(f - fi))
        W = np.array(arm.matrix_world)
        for b, (pb, tail) in enumerate(pbs):
            M = W @ np.array(pb.matrix)
            R[t, b] = M[:3, :3]
            P[t, b] = (W @ np.r_[np.array(pb.tail), 1.0])[:3] if tail else M[:3, 3]
    return mlib.ortho(R), P


def source_motion(arm, act, frames, fps):
    names, parents = topo_bones(arm)
    for b in list(arm.data.bones):
        if not b.children:
            parents.append(names.index(b.name))
            names.append(b.name + "@tail")
    rR, rP = rest_world(arm, names)
    R, P = sample(arm, act, frames, names)
    return mlib.SourceMotion(names, parents, rR, rP, R, P, fps, np.asarray(frames, float) / fps)


# ---------------------------------------------------------------- Агата

def load_target(glb: str):
    arm, meshes, acts = import_any(glb)
    assign(arm, None)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    names, parents = topo_bones(arm)
    rR, rP = rest_world(arm, names)
    sk = mlib.Skeleton(names, parents, rR, rP)
    fg = foot_geom(sk, meshes)
    return arm, meshes, {a.name.split(".")[0]: a for a in acts}, sk, fg


def foot_geom(sk, meshes) -> mlib.FootGeom:
    dg = bpy.context.evaluated_depsgraph_get()
    V = []
    for m in meshes:
        ev = m.evaluated_get(dg)
        me = ev.to_mesh()
        mw = np.array(ev.matrix_world)
        co = np.array([v.co for v in me.vertices])
        V.append(co @ mw[:3, :3].T + mw[:3, 3])
        ev.to_mesh_clear()
    V = np.concatenate(V)
    heel, ball, tip, axis, yaw = {}, {}, {}, {}, {}
    for s, sx in (("L", 1.0), ("R", -1.0)):
        fb = sk.idx("LeftFoot" if s == "L" else "RightFoot")
        tb = sk.idx("LeftToeBase" if s == "L" else "RightToeBase")
        A, Tb = sk.rest_P[fb], sk.rest_P[tb]
        m = (V[:, 0] * sx > 0.02) & (V[:, 2] < 0.025) & (np.abs(V[:, 0] - A[0]) < 0.12)
        S = V[m]
        # ось ботинка — главная компонента подошвы на полу
        c = S[:, :2].mean(0)
        u, sv, vt = np.linalg.svd(S[:, :2] - c, full_matrices=False)
        d = vt[0]
        if d[1] > 0:
            d = -d  # носок — к −Y
        proj = (S[:, :2] - c) @ d
        h2 = np.r_[c + d * np.percentile(proj, 3), 0.0]
        t2 = np.r_[c + d * np.percentile(proj, 99), 0.0]
        b2 = np.r_[c + d * float(np.dot(Tb[:2] - c, d)), 0.0]
        Rf = sk.rest_R[fb]
        heel[s] = Rf.T @ (h2 - A)
        ball[s] = Rf.T @ (b2 - A)
        tip[s] = sk.rest_R[tb].T @ (t2 - Tb)  # носок — в системе кости пальцев (сгибается на перекате)
        ax = np.r_[d, 0.0]
        axis[s] = Rf.T @ ax
        yaw[s] = float(mlib.yaw_of_dir(ax))
    return mlib.FootGeom(heel, ball, tip, axis, yaw)


def pose_agata(arm, sk, basis_R, root_world_P):
    """basis_R (B,3,3) — matrix_basis вращений, root_world_P — мировая позиция головы таза (м)."""
    W = np.array(arm.matrix_world)
    Winv = np.linalg.inv(W)
    ir = [i for i, p in enumerate(sk.parents) if p < 0][0]
    L = np.array(arm.data.bones[sk.names[ir]].matrix_local)
    p_arm = (Winv @ np.r_[root_world_P, 1.0])[:3]
    loc = L[:3, :3].T @ (p_arm - L[:3, 3])
    for b, n in enumerate(sk.names):
        pb = arm.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        q = mlib.mat_to_quat(basis_R[b])
        pb.rotation_quaternion = (float(q[0]), float(q[1]), float(q[2]), float(q[3]))
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    pr = arm.pose.bones[sk.names[ir]]
    pr.location = (float(loc[0]), float(loc[1]), float(loc[2]))
