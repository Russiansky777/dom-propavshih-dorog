#!/usr/bin/env python3
"""Клипы с другого рига Meshy на персонажа — без кредитов (тот же скелет из 24 костей, другие пропорции).

Зачем (22.10): стойка Meshy «action 0» у NPC читается как широкий застывший шаг, при переходе к реплике поза
прыгает; Агата v3 получает все игровые клипы прежней Агаты (Walking_Woman, Idle_4, open_door, наклон, «тянется»)
без новых задач Meshy. Библиотека клипов — pipeline/3d/motions/agata_rev10_clips.glb (игровой GLB Агаты rev 10:
15 клипов Meshy на её риге).

Перенос — по мировым поворотам: для каждой кости поворот относительно позы покоя источника (Δ = R·R₀ᵀ) переносится
на позу покоя цели (R' = Δ·R₀'); если направление кости в покое у источника и цели расходится больше чем на 10°
(A-поза против T-позы), кость дополнительно доворачивается в то же мировое направление, что у источника. Таз —
поворот так же, смещение масштабируется ростом таза цели. Пол клипа приводится к нулю модели (клипы Meshy стоят на
разной высоте: Idle_4 — на 5 см ниже). Стопы потом правит feet_fix (render_sprites --feet-fix, check_feet).

Склейка со стойкой (blend_from): начало и конец клипа плавно выходят из позы стойки (кадр начала окна стойки) и
возвращаются в неё — переход «стоит ↔ говорит/тянется» без скачка. legs_from: таз и ноги на весь клип — из той же
позы стойки (стопы не сдвигаются при реплике).

Запрос (pipeline/requests/<name>.json), поле "retarget" (нет поля — по умолчанию стойка Idle_4 и склейка реплики со
стойкой; false — выключить):
  "retarget": {
    "library": "pipeline/3d/motions/agata_rev10_clips.glb",          # по умолчанию
    "roles": {"idle": {"clip": "Idle_4"},
              "talk": {"own": true, "blend_from": "idle", "legs_from": "idle", "blend_s": 0.5},
              "reach": {"clip": "Female_Stand_Pick_Fruit_Basket", "blend_from": "idle", "blend_s": 0.6}},
    "extra_clips": ["Idle_3", "Idle_9"]                                # ещё клипы библиотеки (для GLB игры в 3D)
  }
  Поля роли (кроме clip/own/blend_from/legs_from/blend_s):
    "library": "pipeline/3d/motions/<другой>.glb" — клип из другой библиотеки (тот же скелет Meshy; G53: сидя —
               Chair_Sit_Idle_F с рига Нины);
    "segments": [[t0, t1], …] — секунды исходного клипа: только эти отрезки, подряд, стык — плавный наплыв
               "join_s" (по умолчанию 0,1 с); затем склейка со стойкой (G1: «взять» — протянуть руку и вернуть
               из open_door без долгой задержки у двери);
    "name": "…" — имя клипа в GLB (по умолчанию <клип>_<роль>); имя без walk/idle — check_feet не судит клип
               порогами стойки (сидя стопы стоят как у сидящей).

  python pipeline/3d/retarget_clips.py --glb pipeline/3d/out/<name>/animations.glb --request pipeline/requests/<name>.json \
      [--state pipeline/3d/state/<name>.json] --out pipeline/3d/out/<name>/animations.glb --clips-out pipeline/3d/out/<name>/clips.txt
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import feet_fix as ff  # noqa: E402

DEFAULT_LIBRARY = "pipeline/3d/motions/agata_rev10_clips.glb"
DEFAULT_SPEC = {"roles": {"idle": {"clip": "Idle_4"},
                          "talk": {"own": True, "blend_from": "idle", "legs_from": "idle", "blend_s": 0.5}}}
FPS = 30


def spec_for(req: dict) -> dict | None:
    v = req.get("retarget", None)
    if v is False:
        return None
    spec = json.loads(json.dumps(DEFAULT_SPEC)) if v is None or v is True else dict(v)
    spec.setdefault("library", DEFAULT_LIBRARY)
    acts = req.get("actions", ["idle", "walk"])
    spec["roles"] = {r: c for r, c in spec.get("roles", {}).items() if r in acts}
    return spec


def _import(path):
    bpy = ff._bpy()
    sc = bpy.context.scene
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
    sc.render.fps = FPS
    return arm, meshes, acts, new


def _frames(act):
    f0, f1 = act.frame_range
    return np.arange(round(f0), round(f1) + 1, 1.0)


def retarget_world(src: ff.Rig, tgt: ff.Rig, R, P):
    """R, P (T,B,3,3)/(T,B,3) — мировые позы источника (по именам костей источника) → позы цели (по костям цели)."""
    T = len(R)
    Rt = np.zeros((T, len(tgt.names), 3, 3))
    Pt = np.zeros((T, len(tgt.names), 3))
    hs, ht = src.rest_P[src.idx("Hips")], tgt.rest_P[tgt.idx("Hips")]
    k = ht[2] / max(hs[2], 1e-6)
    for b, n in enumerate(tgt.names):
        if n not in src.names:
            Rt[:, b] = tgt.rest_R[b]
            continue
        sb = src.idx(n)
        D = np.einsum("tij,kj->tik", R[:, sb], src.rest_R[sb])          # Δ = R·R₀ᵀ
        Rt[:, b] = np.einsum("tij,jk->tik", D, tgt.rest_R[b])
        ys, yt = src.rest_R[sb][:, 1], tgt.rest_R[b][:, 1]
        if math.degrees(math.acos(max(-1.0, min(1.0, float(ys @ yt))))) > 10.0:
            for t in range(T):
                C = ff.rot_between(Rt[t, b][:, 1], R[t, sb][:, 1])
                Rt[t, b] = C @ Rt[t, b]
    # головы костей: таз — смещение источника × k, остальные — по цепочке от таза
    hi_t, hi_s = tgt.idx("Hips"), src.idx("Hips")
    Pt[:, hi_t] = ht + k * (P[:, hi_s] - hs)
    for b, n in enumerate(tgt.names):
        pb = tgt.parents[b]
        if pb < 0:
            continue
        off = tgt.rest_R[pb].T @ (tgt.rest_P[b] - tgt.rest_P[pb])       # голова в системе родителя (покой)
        Pt[:, b] = Pt[:, pb] + np.einsum("tij,j->ti", Rt[:, pb], off)
    return ff.ortho(Rt), Pt


def to_basis(arm, rig: ff.Rig, R, P):
    """Мировые позы → (кватернионы matrix_basis (T,B,4), location таза (T,3))."""
    W = np.array(arm.matrix_world)
    Q = np.zeros((len(R), len(rig.names), 4))
    for b in range(len(rig.names)):
        pb = rig.parents[b]
        if pb < 0:
            Bm = np.einsum("ij,tjk->tik", rig.rest_R[b].T, R[:, b])
        else:
            Bm = np.einsum("ij,jk,tlk,tlm->tim", rig.rest_R[b].T, rig.rest_R[pb], R[:, pb], R[:, b])
        prev = None
        for t in range(len(R)):
            q = ff.mat_to_quat(ff.ortho(Bm[t]))
            if prev is not None and float(q @ prev) < 0:
                q = -q
            Q[t, b] = q
            prev = q
    hb = rig.names[0]
    L = np.array(arm.data.bones[hb].matrix_local)
    Winv = np.linalg.inv(W)
    p_arm = (Winv[:3, :3] @ P[:, 0].T).T + Winv[:3, 3]
    loc = (L[:3, :3].T @ (p_arm - L[:3, 3]).T).T
    return Q, loc


def write_action(arm, rig: ff.Rig, name, frames, Q, loc):
    bpy = ff._bpy()
    old = bpy.data.actions.get(name)
    if old is not None:  # свой клип персонажа с тем же именем заменяется перенесённым
        old.name = "_old_" + name
    act = bpy.data.actions.new(name)
    ff.assign(arm, act)
    # ключ, чтобы у действия появились слот и каналы (Blender 4.4+: слои/слоты), затем значения — массивами
    # все каналы всех костей (location/scale — покой): иначе при смене клипа кости без ключей держали бы значения
    # предыдущего клипа (в рендере листов и в игре)
    for n in rig.names:
        pb = arm.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        pb.matrix_basis.identity()
        for path in ("rotation_quaternion", "location", "scale"):
            pb.keyframe_insert(path, frame=float(frames[0]))
    fcs = {(fc.data_path, fc.array_index): fc for fc in ff.action_fcurves(act)}
    one = np.ones(len(frames))
    for b, n in enumerate(rig.names):
        for i in range(4):
            _fill(fcs[(f'pose.bones["{n}"].rotation_quaternion', i)], frames, Q[:, b, i])
        for i in range(3):
            _fill(fcs[(f'pose.bones["{n}"].location', i)], frames, loc[:, i] if b == 0 else 0 * one)
            _fill(fcs[(f'pose.bones["{n}"].scale', i)], frames, one)
    act.use_fake_user = True
    return act


def _fill(fc, frames, vals):
    kp = fc.keyframe_points
    while len(kp):
        kp.remove(kp[0], fast=True)
    kp.add(len(frames))
    co = np.empty(2 * len(frames))
    co[0::2], co[1::2] = frames, vals
    kp.foreach_set("co", co)
    kp.foreach_set("interpolation", [1] * len(frames))  # LINEAR
    fc.update()


def pose_at(arm, rig: ff.Rig, act, frame):
    """Поза клипа в кадре: кватернионы matrix_basis всех костей и location таза (как в to_basis)."""
    bpy = ff._bpy()
    ff.assign(arm, act)
    fi = math.floor(frame)
    bpy.context.scene.frame_set(int(fi), subframe=float(frame - fi))
    Q = np.array([list(arm.pose.bones[n].rotation_quaternion) for n in rig.names])
    return Q, np.array(arm.pose.bones[rig.names[0]].location)


def slerp(q0, q1, w):
    d = float(q0 @ q1)
    if d < 0:
        q1, d = -q1, -d
    if d > 0.9995:
        q = q0 + w * (q1 - q0)
        return q / np.linalg.norm(q)
    th = math.acos(d)
    return (math.sin((1 - w) * th) * q0 + math.sin(w * th) * q1) / math.sin(th)


def bookend(rig: ff.Rig, Q, loc, q_ref, loc_ref, blend_n, legs=False):
    """Начало и конец клипа — из позы q_ref и обратно (косинусный вес на blend_n кадров); legs — таз и ноги
    на весь клип из q_ref (стопы стоят как в стойке)."""
    T = len(Q)
    Q, loc = Q.copy(), loc.copy()
    if legs:
        for b, n in enumerate(rig.names):
            if b == 0 or any(k in n for k in ("UpLeg", "Leg", "Foot", "ToeBase")):
                Q[:, b] = q_ref[b]
        loc[:] = loc_ref
    if blend_n > 0:
        for t in range(T):
            x = min(t, T - 1 - t)
            if x >= blend_n:
                continue
            w = 0.5 - 0.5 * math.cos(math.pi * x / blend_n)
            for b in range(len(rig.names)):
                Q[t, b] = slerp(q_ref[b], Q[t, b], w)
            loc[t] = loc_ref + w * (loc[t] - loc_ref)
    return Q, loc


def cut_segments(Q, loc, segs, join_n):
    """Отрезки клипа (секунды → кадры FPS) подряд; на стыке join_n кадров конец прошлого отрезка плавно
    переходит в начало следующего (отрезки перекрываются на join_n кадров)."""
    T = len(Q)
    outQ, outL = None, None
    for a, b in segs:
        i0 = max(0, min(T - 1, int(round(float(a) * FPS))))
        i1 = max(i0, min(T - 1, int(round(float(b) * FPS))))
        q, l = Q[i0:i1 + 1].copy(), loc[i0:i1 + 1].copy()
        if outQ is None:
            outQ, outL = q, l
            continue
        n = max(0, min(join_n, len(outQ) - 1, len(q) - 1))
        for k in range(n):
            w = 0.5 - 0.5 * math.cos(math.pi * (k + 1) / (n + 1))
            t = len(outQ) - n + k
            for bi in range(Q.shape[1]):
                q[k, bi] = slerp(outQ[t, bi], q[k, bi], w)
            l[k] = outL[t] + w * (l[k] - outL[t])
        outQ = np.concatenate([outQ[:len(outQ) - n], q])
        outL = np.concatenate([outL[:len(outL) - n], l])
    return outQ, outL


def floor_shift(arm, rig, R, P):
    """Сдвиг по Z, чтобы пол клипа (feet_fix.clip_floor) стал нулём модели."""
    fl = ff.clip_floor(rig, R, P)
    P = P.copy()
    P[:, :, 2] -= fl
    return P, fl


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--request", required=True)
    ap.add_argument("--state", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--clips-out", default="")
    ap.add_argument("--report", default="")
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    spec = spec_for(req)
    if not spec or not (spec["roles"] or spec.get("extra_clips")):
        print("retarget: нечего переносить")
        return 0
    name = req.get("character", Path(args.request).stem)
    state = Path(args.state or f"pipeline/3d/state/{name}.json")
    keys = {}
    if state.exists():
        keys = {k: v.get("key") for k, v in json.loads(state.read_text(encoding="utf-8")).get("actions", {}).items() if v.get("key")}
    windows = {k: tuple(v) for k, v in req.get("clip_window", {}).items()}

    bpy = ff._bpy()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.context.scene.render.fps = FPS
    arm, meshes, own_acts, _ = _import(args.glb)
    tgt = ff.rig_from_blender(arm, meshes)
    libs = {}  # путь библиотеки → её арматура, клипы (с приставкой), объекты, скелет

    def lib(path):
        if path not in libs:
            la, lm, lacts, lobjs = _import(path)
            pre = f"_lib{len(libs)}_"
            for a in lacts:  # имена клипов библиотеки освобождаются для перенесённых
                a.name = pre + a.name.split(".")[0]
            libs[path] = {"arm": la, "acts": lacts, "objs": lobjs, "rig": ff.rig_from_blender(la, lm), "pre": pre}
        return libs[path]

    lib(spec["library"])
    rep = {"name": name, "library": spec["library"], "roles": {}, "extra": []}

    made = {}  # (библиотека, клип) → (Q, loc, frames, пол)

    def make(clip, path=None):
        path = path or spec["library"]
        if (path, clip) in made:
            return made[(path, clip)]
        L = lib(path)
        a = ff.find_action(L["acts"], L["pre"] + clip)
        if a is None:
            raise SystemExit(f"retarget: в библиотеке {path} нет клипа {clip}; есть {[x.name for x in L['acts']]}")
        fr = _frames(a)
        R, P = ff.sample(L["arm"], a, L["rig"], fr)
        Rt, Pt = retarget_world(L["rig"], tgt, R, P)
        Pt, fl = floor_shift(arm, tgt, Rt, Pt)
        Q, loc = to_basis(arm, tgt, Rt, Pt)
        made[(path, clip)] = (Q, loc, fr - fr[0], fl)
        return made[(path, clip)]

    roles = spec["roles"]
    from check_feet import roles_to_fix  # noqa: PLC0415
    fix_roles = set(roles_to_fix(req))
    out_clips = {}
    # сначала роли без склейки (стойка — опора для остальных)
    order = sorted(roles, key=lambda r: 1 if roles[r].get("blend_from") or roles[r].get("legs_from") else 0)
    pose_of = {}
    for role in order:
        c = roles[role]
        if c.get("own"):
            key = keys.get(role)
            a = ff.find_action(own_acts, key) if key else ff.find_action(own_acts, role)
            if a is None:
                print(f"retarget: у персонажа нет клипа роли {role} — пропуск", flush=True)
                continue
            fr = _frames(a)
            R, P = ff.sample(arm, a, tgt, fr)
            P, fl = floor_shift(arm, tgt, R, P)
            Q, loc = to_basis(arm, tgt, R, P)
            src_name, fr = a.name, fr - fr[0]
        else:
            Q, loc, fr, fl = make(c["clip"], c.get("library"))
            src_name = c["clip"]
        if c.get("segments"):
            Q, loc = cut_segments(Q, loc, c["segments"], int(round(float(c.get("join_s", 0.1)) * FPS)))
            fr = np.arange(len(Q), dtype=float)
        ref = c.get("blend_from") or c.get("legs_from")
        if ref:
            if ref not in pose_of:
                raise SystemExit(f"retarget: роль {role} склеивается с {ref}, но {ref} не перенесена")
            qr, lr = pose_of[ref]
            n = int(round(float(c.get("blend_s", 0.5)) * FPS))
            Q, loc = bookend(tgt, Q, loc, qr, lr, n, legs=bool(c.get("legs_from")))
        new_name = c.get("name") or (f"{src_name}_{role}" if (ref or c.get("own")) else src_name)
        act = write_action(arm, tgt, new_name, fr, Q, loc)
        out_clips[role] = act.name
        # стопы — здесь же (а не только перед рендером): склейка реплики и действий берёт позу уже исправленной
        # стойки, иначе при смене стойка → реплика ботинки поворачивались бы наружу
        fixed = None
        if role in fix_roles:
            kind = ff.kind_of(role) or ff.kind_of(act.name) or "idle"
            fixed = ff.fix_action(arm, tgt, act, kind, window=windows.get(role))
        # поза начала окна роли — опора склейки
        w0 = windows.get(role, (0.0, 1.0))[0]
        i0 = int(round(w0 * (len(fr) - 1)))
        pose_of[role] = pose_at(arm, tgt, act, float(fr[i0])) if fixed else (Q[i0].copy(), loc[i0].copy())
        rep["roles"][role] = {"clip": act.name, "from": "own" if c.get("own") else (c.get("library") or spec["library"]),
                              "source_clip": src_name, "segments": c.get("segments"), "frames": len(fr),
                              "floor_shift_m": round(-fl, 4), "blend_from": ref, "legs_from": c.get("legs_from"),
                              "feet": {k: fixed[k] for k in ("after", "fail")} if fixed else None}
        print(f"retarget {name}/{role}: {src_name} → {act.name} ({len(fr)} кадров, пол {fl * 100:+.1f} см → 0)", flush=True)
    for clip in spec.get("extra_clips", []):
        if any(v == clip for v in out_clips.values()):
            continue
        Q, loc, fr, fl = make(clip)
        act = write_action(arm, tgt, clip, fr, Q, loc)
        rep["extra"].append(act.name)
    # библиотеку — из сцены и из данных (иначе её клипы уйдут в экспорт)
    for L in libs.values():
        for o in L["objs"]:
            bpy.data.objects.remove(o, do_unlink=True)
        for a in L["acts"]:
            bpy.data.actions.remove(a)
    drop = set(spec.get("drop_own", []))
    for a in list(bpy.data.actions):
        if a.name.startswith("_old_") or a.name in drop or a.name.split(".")[0] in drop:
            bpy.data.actions.remove(a)
    ff.assign(arm, None)
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.ops.export_scene.gltf(filepath=str(Path(args.out).resolve()), export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True)
    if args.clips_out:
        Path(args.clips_out).write_text(" ".join(f"{r}={k}" for r, k in out_clips.items()) + "\n", encoding="utf-8")
    if args.report:
        Path(args.report).write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"retarget {name}: {out_clips} → {args.out}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
