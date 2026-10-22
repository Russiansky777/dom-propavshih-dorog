#!/usr/bin/env python3
"""Ретаргет одного клипа на скелет Агаты + петля + чистка стоп + замеры (Blender как модуль bpy).

  python retarget_clip.py --clip <id> --clips clips.json --target agata_rt.glb --src-root _src --out out/

Источник: GLB (Mesh2Motion, Meshy) или BVH (CMU — конверсия cgspeed, 100STYLE). Шаги:
  1. проход анализа (60 Гц): ретаргет всего клипа (или frame_cut), поиск прямого участка ходьбы и двух полных циклов
     (от удара пятки левой ноги до удара через цикл), либо окна idle 6–8 с с наименьшей невязкой позы;
  2. выборка источника в моменты кадров видео (24 к/с, длина петли — целое число кадров), ретаргет;
  3. невязка петли распределяется по всей петле (вращения костей, таз), ход поворачивается к −Y;
  4. чистка: высота таза по полу (длина ног задаёт масштаб), фиксация опорной стопы (IK бедро–колено–лодыжка),
     таз опускается, где нога не дотягивается; базовая линия Meshy — как в игре: только root motion по опорной стопе;
  5. замеры до и после чистки: проскальзывание опорной стопы (мм), разворот ботинка к ходу (°), рыскание таза.
Выход: out/<id>.npz (вращения matrix_basis костей Агаты по кадрам петли, таз, смещение за петлю) и out/<id>.json.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import bsrc  # noqa: E402
import mlib  # noqa: E402

FPS_OUT = 24.0
FPS_AN = 60.0
POSE_BONES = ["Spine02", "Spine01", "Spine", "neck", "Head", "LeftArm", "LeftForeArm", "RightArm", "RightForeArm",
              "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]


def resolve_source(spec, src_root: Path, work: Path) -> Path:
    lib, rel = spec["file"].split(":", 1)
    base = src_root / lib
    if "!" in rel:
        zp, member = rel.split("!", 1)
        out = work / member
        if not out.exists():
            with zipfile.ZipFile(base / zp) as z:
                names = [n for n in z.namelist() if n.endswith(member)]
                out.write_bytes(z.read(names[0]))
        return out
    p = base / rel
    if p.suffix == ".gz":
        import gzip
        out = work / p.stem
        if not out.exists():
            out.write_bytes(gzip.decompress(p.read_bytes()))
        return out
    return p


def local_rot(sk, R):
    return mlib.basis_from_world(sk, R)


def pose_cost(sk, R, a, b):
    """Невязка позы между кадрами a и b: углы локальных вращений главных костей (°, корень суммы квадратов)
    + наклон таза без рыскания."""
    L = local_rot(sk, R[[a, b]])
    tot = 0.0
    for n in POSE_BONES:
        i = sk.idx(n)
        tot += float(mlib.rot_angle_deg(L[1, i] @ L[0, i].T)) ** 2
    ih = sk.idx("Hips")
    up_a = R[a, ih] @ (sk.rest_R[ih].T @ mlib.UP)
    up_b = R[b, ih] @ (sk.rest_R[ih].T @ mlib.UP)
    tot += math.degrees(math.acos(max(-1, min(1, float(np.dot(up_a, up_b)))))) ** 2
    return math.sqrt(tot)


def heading(v):
    return math.degrees(math.atan2(v[0], -v[1]))


def find_walk_loop(sk, R, root_P, fg, fps, cycles_pref=2):
    P = mlib.fk_positions(sk, R, root_P)
    z0 = mlib.ground_offset(sk, R, P, fg)
    P2 = P - np.array([0, 0, z0])
    con = mlib.detect_contacts(sk, R, P2, fg, fps)
    strikes = {}
    for s in ("L", "R"):
        c = con[s]["heel"] | con[s]["ball"]
        strikes[s] = [a for a, b in mlib.intervals(c) if a > 0]
    S = strikes["L"]
    best = None
    T = len(R)
    for cyc in ([cycles_pref, 1] if cycles_pref > 1 else [1]):
        for k in range(len(S) - cyc):
            a, b = S[k], S[k + cyc]
            if b >= T:
                continue
            # прямой участок: направление хода на каждой половине близко, скорость ровная
            seg = root_P[a:b + 1]
            d = seg[-1] - seg[0]
            dist = float(np.linalg.norm(d[:2]))
            dur = (b - a) / fps
            if dist / dur < 0.45:
                continue
            m = (a + b) // 2
            h1, h2 = heading(root_P[m] - root_P[a]), heading(root_P[b] - root_P[m])
            dh = abs((h2 - h1 + 180) % 360 - 180)
            hf = mlib.hips_facing(sk, R[[a, b]])
            dyaw = abs((heading(hf[1]) - heading(hf[0]) + 180) % 360 - 180)
            if dh > 12 or dyaw > 15:
                continue
            # уточнить конец петли по позе (удар пятки определяется по порогу высоты — ±1–2 кадра)
            bb = min(range(max(a + 10, b - 6), min(T - 1, b + 6) + 1), key=lambda x: pose_cost(sk, R, a, x))
            b = bb
            seg = root_P[a:b + 1]
            d = seg[-1] - seg[0]
            dist = float(np.linalg.norm(d[:2]))
            dur = (b - a) / fps
            # прямолинейность: отклонение пути от хорды
            ch = d[:2] / max(dist, 1e-6)
            dev = np.abs((seg[:, 0] - seg[0, 0]) * ch[1] - (seg[:, 1] - seg[0, 1]) * ch[0]).max()
            sp = np.linalg.norm(np.diff(seg[:, :2], axis=0), axis=1) * fps
            # поворот опорной стопы на полу за время опоры (разворот на ходу)
            piv = 0.0
            for s_ in ("L", "R"):
                ax = mlib.sole_points(sk, R[a:b + 1], P2[a:b + 1], fg, s_)[3]
                yw = np.degrees(mlib.yaw_of_dir(ax))
                for i0, i1 in mlib.intervals(con[s_]["heel"][a:b + 1] & con[s_]["ball"][a:b + 1]):
                    piv += abs((yw[i1 - 1] - yw[i0] + 180) % 360 - 180)
            cost = (pose_cost(sk, R, a, b) + dh * 3 + dyaw * 2 + dev * 300 + float(np.std(sp)) * 20 + piv * 1.5)
            # подальше от краёв записи (разгон/торможение)
            edge = min(a, T - b) / fps
            cost += max(0.0, 1.5 - edge) * 10
            strict = dev < 0.035 and dh < 5 and dyaw < 8 and piv < 12
            key = (0 if strict else 1, cost)
            if best is None or key < best[0]:
                best = (key, a, b, cyc, dh, dyaw, dev)
        if best is not None and cyc == cycles_pref and best[0][0] == 0:
            break
    if best is None:
        raise RuntimeError("не найден прямой участок ходьбы с двумя ударами пятки")
    (strict, cost), a, b, cyc, dh, dyaw, dev = best
    return {"a": a, "b": b, "cycles": cyc, "cost": round(float(cost), 2), "straight": strict == 0,
            "heading_change_deg": round(dh, 1),
            "hips_yaw_change_deg": round(dyaw, 1), "path_dev_m": round(float(dev), 3)}


def find_idle_window(sk, R, root_P, fg, fps, lo=6.0, hi=8.0):
    T = len(R)
    dur = (T - 1) / fps
    if dur < lo + 0.5:
        return {"a": 0, "b": T - 1, "whole": True, "cost": round(pose_cost(sk, R, 0, T - 1), 2)}
    P = mlib.fk_positions(sk, R, root_P)
    hf = mlib.hips_facing(sk, R)
    yaw = np.degrees(mlib.yaw_of_dir(hf))
    feet = {s: mlib.sole_points(sk, R, P, fg, s)[1] for s in ("L", "R")}
    step = int(0.25 * fps)
    best = None
    for a in range(0, T, step):
        for L in np.arange(lo, hi + 1e-6, 0.25):
            b = a + int(round(L * fps))
            if b >= T:
                break
            c = pose_cost(sk, R, a, b)
            drift = float(np.linalg.norm(root_P[b, :2] - root_P[a, :2]))
            fd = max(float(np.linalg.norm(feet[s][b, :2] - feet[s][a, :2])) for s in ("L", "R"))
            yr = float(np.ptp(yaw[a:b + 1]))
            # шаги внутри окна (стопа уходит дальше 6 см от начального места) — штраф
            walk = max(float(np.linalg.norm(feet[s][a:b + 1, :2] - feet[s][a, :2], axis=1).max()) for s in ("L", "R"))
            cost = c + drift * 200 + fd * 300 + max(0.0, yr - 20) * 2 + max(0.0, walk - 0.06) * 150
            if best is None or cost < best[0]:
                best = (cost, a, b, c, drift, fd, yr, walk)
    cost, a, b, c, drift, fd, yr, walk = best
    return {"a": a, "b": b, "whole": False, "cost": round(cost, 2), "pose_mismatch_deg": round(c, 1),
            "root_drift_m": round(drift, 3), "feet_shift_m": round(fd, 3), "hips_yaw_range_deg": round(yr, 1),
            "max_foot_travel_m": round(walk, 3)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip", required=True)
    ap.add_argument("--clips", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--src-root", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    spec = next(c for c in json.load(open(args.clips, encoding="utf-8"))["clips"] if c["id"] == args.clip)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    work = out / "_work"
    work.mkdir(exist_ok=True)

    # --- цель и источник в одной сцене, частота сцены = частота анализа
    bsrc.reset(FPS_AN)
    t_arm, t_meshes, t_acts, sk, fg = bsrc.load_target(args.target)
    src_spec = spec["source"]
    if src_spec["kind"] == "meshy":
        s_arm, s_act = t_arm, t_acts[src_spec["action"]]
    else:
        path = resolve_source(src_spec, Path(args.src_root), work)
        s_arm, _, s_acts = bsrc.import_any(str(path))
        if src_spec.get("action"):
            s_act = next(a for a in s_acts if a.name.split(".")[0] == src_spec["action"] or a.name == src_spec["action"])
        else:
            s_act = s_acts[0]
    f0, f1 = s_act.frame_range
    src_fps = src_spec.get("fps")  # кадры BVH → кадры сцены (импорт с use_fps_scale)
    if src_spec.get("frame_cut") and src_fps:
        c0, c1 = src_spec["frame_cut"]
        f0 = max(f0, c0 * FPS_AN / src_fps)
        f1 = min(f1, c1 * FPS_AN / src_fps)
    if src_spec.get("skip_first_s"):
        f0 += src_spec["skip_first_s"] * FPS_AN
    if src_spec.get("window_s"):
        w0, w1 = src_spec["window_s"]
        f0, f1 = max(f0, f0 + w0 * FPS_AN), min(f1, f0 + w1 * FPS_AN)
    frames = np.arange(f0, f1 + 1e-6, 1.0)
    print(f"[{spec['id']}] источник {src_spec.get('file', src_spec.get('action'))}: кадры сцены {f0:.1f}–{f1:.1f} "
          f"({(f1 - f0) / FPS_AN:.2f} с), костей {len(s_arm.data.bones)}", flush=True)

    src_all = bsrc.source_motion(s_arm, s_act, frames, FPS_AN)
    fam = "meshy" if src_spec["kind"] == "meshy" else mlib.detect_family(src_all.names)[0]
    mapping = mlib.FAMILY_MAPS[fam]
    missing = [v for v in mapping.values() if v not in src_all.names]
    if missing:
        print("нет костей источника:", missing, "имеются:", src_all.names, flush=True)
        return 2
    src_al, yaw0 = mlib.align_source(src_all, mapping)
    scale = mlib.leg_length(sk.rest_P, sk.names, "LeftUpLeg", "LeftLeg", "LeftFoot") / mlib.leg_length(
        src_al.rest_P, src_al.names, mapping["LeftUpLeg"], mapping["LeftLeg"], mapping["LeftFoot"])
    K = mlib.build_K(sk, src_al, mapping, tgt_foot_yaw=fg.rest_yaw if fam != "meshy" else None, fam=fam)
    R, root_P = mlib.retarget(sk, src_al, mapping, K, scale)
    head_fix = {"yaw_deg": 0.0, "roll_deg": 0.0}
    if fam != "meshy":
        # калибровка головы: постоянный за весь клип поворот головы относительно груди вбок (рыскание) и наклон к плечу
        # (крен) — у части субъектов CMU маркеры головы надеты со сдвигом (113: взгляд −40…−46° и стоя, и в ходьбе).
        # Наклон вперёд-назад не трогаем — это манера (Depressed — голова опущена).
        yaw_m, roll_m = mlib.head_offset(sk, R)
        if abs(yaw_m) > 10.0 or abs(roll_m) > 8.0:
            C = mlib.axis_angle(-mlib.FWD, math.radians(-roll_m)) @ mlib.rot_z(np.float64(math.radians(-yaw_m)))
            ihd = sk.idx("Head")
            K["Head"] = K["Head"] @ (sk.rest_R[ihd].T @ C @ sk.rest_R[ihd])
            R, root_P = mlib.retarget(sk, src_al, mapping, K, scale)
            y2, r2 = mlib.head_offset(sk, R)
            head_fix = {"yaw_deg": round(-yaw_m, 1), "roll_deg": round(-roll_m, 1), "after_yaw_deg": round(y2, 1), "after_roll_deg": round(r2, 1)}
            print("  калибровка головы:", head_fix, flush=True)
    if fam == "meshy":
        root_P = src_al.P[:, src_al.names.index("Hips")]
    # клип «на месте» (таз не уходит вперёд: Meshy, Mesh2Motion) — средняя скорость таза по пути < 0,15 м/с
    step = max(1, int(FPS_AN / 10))
    travel = float(np.linalg.norm(np.diff(root_P[::step, :2], axis=0), axis=1).sum())
    net = float(np.linalg.norm(root_P[-1, :2] - root_P[0, :2]))
    # на месте: таз почти не уходит и по пути движется медленно (качание бёдер у клипа на месте даёт до ~0,3 м/с пути,
    # у mocap-ходьбы ≥ 0,5 м/с, даже если человек вернулся к началу)
    in_place = spec["type"] == "walk" and net < 0.3 and travel / max((len(frames) - 1) / FPS_AN, 1e-6) < 0.35
    if in_place:
        root_P, _ = mlib.stance_root_motion(sk, R, root_P, fg, FPS_AN)
    print(f"  семейство {fam}, поворот к −Y {yaw0:.1f}°, масштаб {scale:.4f}, путь таза {travel:.2f} м (итог {net:.2f} м), "
          f"на месте: {in_place}", flush=True)

    # --- выбор петли
    if spec["type"] == "walk":
        if src_spec["kind"] == "meshy" or (in_place and (len(frames) - 1) / FPS_AN < 2.5):
            loop = {"a": 0, "b": len(frames) - 1, "cycles": spec.get("cycles", 1), "whole": True,
                    "cost": round(pose_cost(sk, R, 0, len(frames) - 1), 2)}
        else:
            loop = find_walk_loop(sk, R, root_P, fg, FPS_AN, spec.get("cycles", 2))
    else:
        loop = find_idle_window(sk, R, root_P, fg, FPS_AN, *spec.get("idle_len_s", [6.0, 8.0]))
    ta, tb = frames[loop["a"]], frames[loop["b"]]
    period = (tb - ta) / FPS_AN
    N = max(2, int(round(period * FPS_OUT)))
    loop.update({"t0_s": round((ta - frames[0]) / FPS_AN + spec["source"].get("skip_first_s", 0), 3),
                 "src_frame0": round(float(ta), 2), "src_frame1": round(float(tb), 2),
                 "period_s": round(period, 4), "frames_out": N, "time_scale": round(N / FPS_OUT / period, 4)})
    print("  петля:", loop, flush=True)

    # --- проход 2: моменты кадров видео
    # клип «на месте»: root motion по опорной стопе считается на частой выборке (×5), как в игре на кадрах экрана
    sub = 5 if in_place else 1
    fr2 = ta + (tb - ta) * np.arange(N * sub + 1) / (N * sub)
    src2 = bsrc.source_motion(s_arm, s_act, fr2, FPS_OUT * sub)
    src2a, _ = mlib.align_source(src2, mapping)
    R2, P2 = mlib.retarget(sk, src2a, mapping, K, scale)
    if fam == "meshy":
        P2 = src2a.P[:, src2a.names.index("Hips")]
    if in_place:
        P2, _ = mlib.stance_root_motion(sk, R2, P2, fg, FPS_OUT * sub)
    R2, P2 = R2[::sub], P2[::sub]
    ih = sk.idx("Hips")
    Lb = local_rot(sk, R2)
    disp = P2[N] - P2[0]
    disp[2] = 0.0
    if spec["type"] != "walk":
        disp = np.zeros(3)
    Ll, Pl, RRl = mlib.loop_close(Lb, P2, R2[:, ih], disp)
    # ход (или взгляд таза для idle) → −Y, начало у нуля
    if spec["type"] == "walk":
        ang = math.atan2(disp[0], -disp[1])
    else:
        hf = mlib.hips_facing(sk, R2[:N])
        mean = mlib.unit(hf.mean(0))
        ang = math.atan2(mean[0], -mean[1])
    G = mlib.rot_z(-ang)
    RRl = G @ RRl
    Pl = Pl @ G.T
    disp = G @ disp
    Pl = Pl - np.array([Pl[0, 0], Pl[0, 1], 0.0])
    Rl = mlib.world_from_local(sk, Ll, RRl)

    # --- три петли подряд: чистка с непрерывными краями, берём среднюю
    reps = 3
    Rt = np.concatenate([Rl] * reps)
    Pt = np.concatenate([Pl + k * disp for k in range(reps)])
    raw_P = Pt.copy()
    Pfk = mlib.fk_positions(sk, Rt, Pt)
    z0 = mlib.ground_offset(sk, Rt, Pfk, fg)
    do_clean = spec.get("cleanup", True)
    if do_clean:
        raw_P = Pt - np.array([0, 0, z0])
    con_raw = mlib.detect_contacts(sk, Rt, mlib.fk_positions(sk, Rt, raw_P), fg, FPS_OUT)
    td = mlib.unit(disp) if spec["type"] == "walk" else None
    facing = mlib.hips_facing(sk, Rt)
    mid = np.arange(N, 2 * N)
    met_raw = mlib.foot_metrics(sk, Rt, mlib.fk_positions(sk, Rt, raw_P), fg, mid_only(con_raw, N), FPS_OUT, td, facing, frames=mid)
    if do_clean:
        Rc, Pc, con, rep = mlib.cleanup(sk, Rt, Pt, fg, FPS_OUT)
        hip_drop, gnd = rep.hip_drop_max_m, rep.ground_offset_m
    else:
        Rc, Pc, con, hip_drop, gnd = Rt, Pt, con_raw, 0.0, 0.0
    Pfk_c = mlib.fk_positions(sk, Rc, Pc)
    con_after = mlib.detect_contacts(sk, Rc, Pfk_c, fg, FPS_OUT) if do_clean else con_raw
    met = mlib.foot_metrics(sk, Rc, Pfk_c, fg, mid_only(con, N), FPS_OUT, td, facing, frames=mid)
    sl = slice(N, 2 * N)
    if os.environ.get("MP_DEBUG"):
        np.savez_compressed(out / f"{spec['id']}_raw.npz", names=np.array(sk.names),
                            basis_quat=mlib.mat_to_quat(mlib.basis_from_world(sk, Rt[sl])).astype(np.float32),
                            root_P=(raw_P[sl] - disp).astype(np.float32), disp=disp.astype(np.float32))
    Rm, Pm = Rc[sl], Pc[sl] - disp
    basis = mlib.basis_from_world(sk, Rm)
    # отдельные замеры: высота подошвы опорной стопы, рыскание таза, наклон головы
    Pm_fk = mlib.fk_positions(sk, Rm, Pm)
    hf = mlib.hips_facing(sk, Rm)
    hy = np.degrees(mlib.yaw_of_dir(hf))
    heights = {}
    for s in ("L", "R"):
        heel, ball, tip, axis = mlib.sole_points(sk, Rm, Pm_fk, fg, s)
        low = np.minimum(np.minimum(heel[:, 2], ball[:, 2]), tip[:, 2])
        heights[s] = {"sole_min_mm": round(float(low.min()) * 1000, 1)}
        # наибольший разворот ботинка за петлю (включая перенос ноги) — на кадрах, где ось подошвы наклонена меньше
        # 30° (у круто опущенного носка рыскание проекции на пол не видно камерой и шумит)
        if td is not None:
            yaw, ok = mlib.toe_yaw_flat(axis, td, s)
            heights[s]["toe_out_max_deg"] = round(float(yaw[ok].max()), 1) if ok.any() else None
            heights[s]["toe_out_min_deg"] = round(float(yaw[ok].min()), 1) if ok.any() else None
    speed = float(np.linalg.norm(disp[:2])) / (N / FPS_OUT) if spec["type"] == "walk" else 0.0
    res = {
        "id": spec["id"], "family": fam, "scale": round(scale, 4), "source_yaw_deg": round(yaw0, 1),
        "in_place_source": bool(in_place), "head_fix": head_fix, "loop": loop, "frames": N, "fps": FPS_OUT,
        "speed_mps": round(speed, 3), "disp_per_loop_m": [round(float(x), 4) for x in disp],
        "ground_offset_m": round(float(gnd if do_clean else z0), 4), "hip_drop_max_m": round(hip_drop, 4),
        "cleanup": do_clean, "feet_raw": met_raw, "feet": met, "feet_extra": heights,
        "hips_yaw_range_deg": round(float(np.ptp(hy)), 1),
    }
    np.savez_compressed(out / f"{spec['id']}.npz", names=np.array(sk.names), parents=np.array(sk.parents),
                        basis_quat=mlib.mat_to_quat(basis).astype(np.float32), root_P=Pm.astype(np.float32),
                        disp=disp.astype(np.float32), fps=np.float32(FPS_OUT),
                        contacts_L=(con["L"]["heel"] | con["L"]["ball"])[sl], contacts_R=(con["R"]["heel"] | con["R"]["ball"])[sl])
    (out / f"{spec['id']}.json").write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({k: res[k] for k in ("frames", "speed_mps", "feet_raw", "feet", "feet_extra", "hips_yaw_range_deg", "hip_drop_max_m")}, ensure_ascii=False), flush=True)
    return 0


def mid_only(con, N):
    """Контакты только средней петли из трёх (края — для непрерывности чистки)."""
    out = {}
    for s, d in con.items():
        out[s] = {}
        for k, c in d.items():
            m = np.zeros_like(c)
            m[N:2 * N] = c[N:2 * N]
            out[s][k] = m
    return out


if __name__ == "__main__":
    sys.exit(main())
