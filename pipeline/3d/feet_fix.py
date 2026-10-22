#!/usr/bin/env python3
"""Стопы персонажей Meshy: разворот ботинок наружу и «носок вверх» в опоре — шаг конвейера и замер.

Почему (замер 22.10, ветка motion-previews, Docs/MOTION_LIBRARIES.md): у моделей Meshy ботинок в сетке развёрнут
наружу относительно костей стопы (у Агаты ≈10,5°); клипы Meshy (Walking_Woman, Idle…) держат носок наружу 15–17°
в опоре и до 38–46° в переносе, в опоре носок поднят на 3–5 см. Камера 14° сжимает глубину ×0,24 — на экране это
≈50° и ≈75°: «ботинок вбок».

Что делает исправление (только кости ног; таз и всё выше — без изменений, кроме опускания таза на миллиметры там,
где без этого стопа не встаёт на пол):
  1. рыскание подошвы (по поперечной оси ботинка — не зависит от наклона носка) приводится к цели: в опоре
     медиана → +3° наружу, всё остальное мягко ограничено ±7,5° (tanh); постоянная часть — поворотом всей ноги вокруг
     оси бедро–лодыжка (внутренняя ротация в тазобедренном: лодыжка остаётся на месте, колено идёт за носком),
     переменная часть (перенос ноги) — поворотом стопы вокруг оси голени, не больше 14°; у стойки «прямо» — куда
     смотрит таз (не ось модели), нога поворачивается не больше 6° (юбка Meshy привязана к голеням и заламывается),
     остальное — стопой в голеностопе (до 24°, подол и колено под ним на месте);
  2. в середине опоры подошва ложится плоско (поворот стопы в голеностопе вокруг поперечной оси);
  3. опорная подошва ставится на пол клипа (IK бедро–колено–лодыжка при неподвижном бедре; если нога не дотягивается —
     таз опускается ровно на недостающее, со сглаживанием); в переносе подошва не уходит под пол. Пол — свой у каждого
     клипа (clip_floor): Idle_4 Агаты стоит на 5 см ниже нуля модели. У стойки опорная точка подошвы стоит на месте.

Ядро — numpy (мировые матрицы костей по кадрам), обвязка Blender (bpy) — чтение/запись клипа в действие.
Замер (measure) — то же, что проверяет check_feet.py: угол носка в опоре и в переносе, высота подошвы в опоре,
проскальзывание опорной стопы (root motion по опорной стопе, как в игре), поворот стопы относительно голени.

  python pipeline/3d/feet_fix.py --glb in.glb --clips walk=Walking_Woman idle=Idle [--out-glb out.glb] [--report r.json]
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

UP = np.array([0.0, 0.0, 1.0])
FWD = np.array([0.0, -1.0, 0.0])  # Meshy/Blender: персонаж смотрит в −Y, его левая сторона — +X

PARAMS = {
    "stance_target_deg": 3.0,     # медиана разворота ботинка в опоре после исправления (+ наружу)
    "soft_limit_deg": 7.5,        # мягкий предел |разворота| в любой фазе (tanh)
    "ankle_max_deg": 14.0,        # предел поворота стопы относительно голени (переменная часть)
    "hip_extra_max_deg": 12.0,    # добор разворота в переносе ротацией в бедре (колено в переносе — до ~2 см внутрь)
    # стойка: юбка Meshy привязана к голеням (вес Leg 0,4–0,55 на высоте 20–50 см) — ротация всей ноги больше ~8°
    # заламывает подол на месте; поэтому у стойки нога поворачивается не больше чем на idle_hip_max_deg, остальное —
    # стопой относительно голени (подол и колено под ним не двигаются, сапог поворачивается целиком ниже голенища)
    "idle_hip_max_deg": 6.0,
    "idle_ankle_max_deg": 24.0,
    "flat_ramp": 0.12,            # доля опоры на выход в плоскую подошву в начале и в конце касания
    "contact_pitch_max_deg": 12.0,  # в касании подошва не круче 12° (удар пятки без задранного на 10+ см носка)
    "floor_z": 0.002,             # высота опорной подошвы над полом (м) — пол = низ сетки в позе покоя
    "contact_h": 0.03,            # касание: самая низкая точка подошвы ниже своего минимума + 3 см…
    "hip_drop_max": 0.016,        # …таз опускается не больше чем на 1,6 см (иначе подошва ложится не до конца)
}
THRESHOLDS = {
    "walk": {"stance_toe_out_min": 0.0, "stance_toe_out_max": 6.0, "swing_abs_max": 10.0, "sole_lift_max_m": 0.01,
             "slide_max_mm": 5.0},
    "idle": {"toe_abs_max": 8.0, "slide_max_mm": 3.0},  # подъём пятки у стойки — поза (перенос веса), не порок
}


# ---------------------------------------------------------------- вращения

def unit(v):
    v = np.asarray(v, float)
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def ortho(R):
    U, _, Vt = np.linalg.svd(R)
    d = np.sign(np.linalg.det(U @ Vt))
    U = U.copy()
    U[..., :, -1] *= d[..., None]
    return U @ Vt


def axis_angle(axis, ang):
    x, y, z = unit(axis)
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def rot_between(a, b):
    a, b = unit(a), unit(b)
    v = np.cross(a, b)
    s, c = np.linalg.norm(v), float(np.dot(a, b))
    if s < 1e-9:
        return np.eye(3)
    return axis_angle(v, math.atan2(s, c))


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def wrap_deg(a):
    return (np.asarray(a) + 180.0) % 360.0 - 180.0


# ---------------------------------------------------------------- скелет и стопа

@dataclass
class Rig:
    names: list
    parents: list
    rest_R: np.ndarray          # (B,3,3) мировые ориентации в покое
    rest_P: np.ndarray          # (B,3) мировые головы костей в покое
    heel: dict = field(default_factory=dict)   # точки подошвы в системе кости стопы (носок — в системе пальцев)
    ball: dict = field(default_factory=dict)
    tip: dict = field(default_factory=dict)
    lat: dict = field(default_factory=dict)    # поперечная ось ботинка (к +X в покое) в системе кости стопы
    rest_yaw: dict = field(default_factory=dict)

    def idx(self, n):
        return self.names.index(n)


SIDES = {"L": "Left", "R": "Right"}


def leg(rig, s):
    p = SIDES[s]
    return rig.idx(p + "UpLeg"), rig.idx(p + "Leg"), rig.idx(p + "Foot"), rig.idx(p + "ToeBase")


def foot_geometry(rig: Rig, V: np.ndarray) -> None:
    """V — вершины сетки в позе покоя (мир). Ось ботинка — главная компонента подошвы (вершины ниже 2,5 см)."""
    for s, sx in (("L", 1.0), ("R", -1.0)):
        iu, ik, ia, it = leg(rig, s)
        A, Tb = rig.rest_P[ia], rig.rest_P[it]
        m = (V[:, 0] * sx > 0.02) & (V[:, 2] < 0.025) & (np.abs(V[:, 0] - A[0]) < 0.12)
        S = V[m]
        c = S[:, :2].mean(0)
        _, _, vt = np.linalg.svd(S[:, :2] - c, full_matrices=False)
        d = vt[0] if vt[0][1] < 0 else -vt[0]  # носок — к −Y
        proj = (S[:, :2] - c) @ d
        heel = np.r_[c + d * np.percentile(proj, 3), 0.0]
        tip = np.r_[c + d * np.percentile(proj, 99), 0.0]
        ball = np.r_[c + d * float(np.dot(Tb[:2] - c, d)), 0.0]
        Rf, Rt = rig.rest_R[ia], rig.rest_R[it]
        rig.heel[s] = Rf.T @ (heel - A)
        rig.ball[s] = Rf.T @ (ball - A)
        rig.tip[s] = Rt.T @ (tip - Tb)
        ax = np.r_[d, 0.0]
        rig.lat[s] = Rf.T @ unit(np.cross(UP, ax))
        rig.rest_yaw[s] = math.degrees(math.atan2(ax[0], -ax[1]))


def sole(rig, R, P, s):
    """Пятка, подушечка, носок подошвы (T,3) — жёстко по кости стопы (пятка, подушечка) и пальцев (носок)."""
    iu, ik, ia, it = leg(rig, s)
    heel = P[:, ia] + np.einsum("tij,j->ti", R[:, ia], rig.heel[s])
    ball = P[:, ia] + np.einsum("tij,j->ti", R[:, ia], rig.ball[s])
    tip = P[:, it] + np.einsum("tij,j->ti", R[:, it], rig.tip[s])
    return heel, ball, tip


def clip_floor(rig, R, P):
    """Пол клипа: клипы Meshy стоят на разной высоте (Idle_4 Агаты — на 5 см ниже нуля модели; без этого стойку
    «ставили на пол» подъёмом лодыжки на 6 см — колени сгибались, юбка ломалась). Пол — 5-й перцентиль самой низкой
    точки подошв по кадрам (в стойке и в опоре ходьбы на полу всегда стоит хоть одна точка)."""
    z = np.min(np.stack([x[:, 2] for s in ("L", "R") for x in sole(rig, R, P, s)], 1), 1)
    return float(np.percentile(z, 5))


def toe_out(rig, Rfoot, s, ref=0.0):
    """Разворот ботинка наружу (°) по поперечной оси подошвы: не зависит от наклона носка вверх-вниз.
    ref — рыскание корпуса (°, + — против часовой сверху), от которого считается «прямо»: у ходьбы 0 (направление
    хода), у стойки — куда смотрит таз (body_yaw)."""
    l = Rfoot @ rig.lat[s] if Rfoot.ndim == 2 else np.einsum("tij,j->ti", Rfoot, rig.lat[s])
    yaw = np.degrees(np.arctan2(l[..., 1], l[..., 0])) - ref  # + = носок к +X
    return yaw if s == "L" else -yaw


def body_yaw(rig, R):
    """Куда смотрит таз (медиана по кадрам, ° от −Y, + — против часовой сверху). Стойки Meshy бывают развёрнуты
    корпусом (Idle Агаты — на −43°, голова к зрителю): носок стойки меряется от таза, а не от оси модели."""
    hi = rig.idx("Hips")
    f = np.einsum("tij,j->ti", R[:, hi], rig.rest_R[hi].T @ FWD)
    return float(np.median(np.degrees(np.arctan2(f[:, 0], -f[:, 1]))))


def contacts(rig, R, P, kind="walk"):
    """Касание по кадрам: самая низкая точка подошвы ниже своего 5-го перцентиля + contact_h. У ходьбы (клип на
    месте: опорная стопа едет назад, как по дорожке) — ещё и стопа не летит вперёд (иначе это нога, которая только
    опускается) и она нижняя из двух (4 мм допуска — двойная опора). У стойки — только высота."""
    low, vel = {}, {}
    T = len(R)
    for s in ("L", "R"):
        h, b, t = sole(rig, R, P, s)
        X = np.stack([h, b, t], 1)
        k = np.argmin(X[:, :, 2], 1)
        low[s] = X[np.arange(T), k, 2]
        ia = leg(rig, s)[2]
        A = P[:, ia]
        v = np.zeros(T)
        if T > 2:
            v[1:-1] = ((A[2:] - A[:-2]) @ FWD) / 2.0
            v[0], v[-1] = v[1], v[-2]
        vel[s] = v  # смещение лодыжки вперёд за кадр (м)
    out = {}
    for s, o in (("L", "R"), ("R", "L")):
        z = low[s]
        near = z < np.percentile(z, 5) + PARAMS["contact_h"]
        if kind == "walk":
            fwd_ok = vel[s] < 0.004  # не летит вперёд быстрее ~0,1 м/с
            out[s] = _drop_short(near & fwd_ok & (z <= low[o] + 0.004), 3)
        else:
            out[s] = near
    return out, low


def _drop_short(c, n_min):
    """Касания короче n_min кадров — не опора (стопа на миг ниже другой при отрыве; Агата v3, 23.10: кадр 7 правой
    ноги — «опора» с пяткой на 4,8 см). Касание, переходящее через край массива, считается целиком."""
    c = c.copy()
    iv = intervals(c)
    n = len(c)
    for k, (a, b) in enumerate(iv):
        ln = b - a
        if len(iv) > 1 and ((k == 0 and a == 0 and iv[-1][1] == n) or (k == len(iv) - 1 and b == n and iv[0][0] == 0)):
            ln = (iv[0][1] - iv[0][0]) + (iv[-1][1] - iv[-1][0])
        if ln < n_min:
            c[a:b] = False
    return c


def intervals(c):
    out, i, n = [], 0, len(c)
    while i < n:
        if c[i]:
            j = i
            while j < n and c[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def cyc_intervals(c, cyclic):
    """Интервалы касания; у петли касание, переходящее через шов, склеивается (возвращает (a, len))."""
    n = len(c)
    iv = [(a, b - a) for a, b in intervals(c)]
    if cyclic and len(iv) >= 2 and iv[0][0] == 0 and iv[-1][0] + iv[-1][1] == n:
        a0, l0 = iv[-1]
        iv = [(a0, l0 + iv[0][1])] + iv[1:-1]
    return iv


# ---------------------------------------------------------------- исправление

def _solve_angle(f, target, guess):
    """Подбор угла θ: f(θ) = target (секущие, 6 шагов)."""
    t0, t1 = 0.0, guess
    f0, f1 = f(t0) - target, f(t1) - target
    for _ in range(6):
        if abs(f1 - f0) < 1e-9:
            break
        t2 = t1 - f1 * (t1 - t0) / (f1 - f0)
        t0, f0, t1, f1 = t1, f1, t2, f(t2) - target
        if abs(f1) < 1e-4:
            break
    return t1


def two_bone(Ph, Pk, Pa, target):
    l1, l2 = np.linalg.norm(Pk - Ph), np.linalg.norm(Pa - Pk)
    d = target - Ph
    L = min(max(np.linalg.norm(d), abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = unit(d)
    cosA = min(max((l1 * l1 + L * L - l2 * l2) / (2 * l1 * L), -1.0), 1.0)
    pole = Pk - Ph
    pole = pole - np.dot(pole, dn) * dn
    if np.linalg.norm(pole) < 1e-6:
        pole = FWD - np.dot(FWD, dn) * dn
    pole = unit(pole)
    knee = Ph + dn * (l1 * cosA) + pole * (l1 * math.sqrt(max(0.0, 1 - cosA * cosA)))
    return knee, Ph + dn * L


def fix_clip(rig: Rig, R: np.ndarray, P: np.ndarray, kind: str, cyclic: bool, params=None):
    """R (T,B,3,3), P (T,B,3) — мировые ориентации и головы костей (клип «на месте»). → R', P', отчёт.
    Меняются только кости ног (бедро, голень, стопа, пальцы); таз — только по высоте и только если надо."""
    p = dict(PARAMS, **(params or {}))
    T = len(R)
    R, P = R.copy(), P.copy()
    con, _ = contacts(rig, R, P, kind)
    p["_floor"] = clip_floor(rig, R, P) + p["floor_z"]
    ref = body_yaw(rig, R) if kind != "walk" else 0.0
    rep = {"kind": kind, "frames": T, "cyclic": bool(cyclic), "body_yaw_deg": round(ref, 1),
           "floor_m": round(p["_floor"] - p["floor_z"], 4), "legs": {}}
    Lt = p["soft_limit_deg"]
    hip_cap = 180.0 if kind == "walk" else p["idle_hip_max_deg"]
    ank_cap = p["ankle_max_deg"] if kind == "walk" else p["idle_ankle_max_deg"]
    for s in ("L", "R"):
        iu, ik, ia, it = leg(rig, s)
        to = toe_out(rig, R[:, ia], s, ref)
        st = con[s] if con[s].any() else np.ones(T, bool)
        off = float(np.median(to[st])) - p["stance_target_deg"]
        want = Lt * np.tanh((to - off) / Lt)
        # в опоре разворот стопы держится постоянным (цель): стопа не вертится на полу и не проскальзывает
        cs = _soft_edges(st.astype(float), cyclic)
        want = cs * p["stance_target_deg"] + (1 - cs) * want
        d_total = want - to                      # нужная поправка разворота (+ наружу)
        d_const = float(np.clip(-off, -hip_cap, hip_cap))  # постоянная часть — вся нога (ротация в бедре)
        d_var = np.clip(d_total - d_const, -ank_cap, ank_cap)
        sgn = 1.0 if s == "L" else -1.0         # разворот наружу → рыскание по +Z для левой, по −Z для правой
        sw_deg, an_deg = np.zeros(T), np.zeros(T)
        for t in range(T):
            hip, ankle = P[t, iu].copy(), P[t, ia].copy()
            # 1) ротация всей ноги вокруг оси бедро–лодыжка: лодыжка на месте, колено идёт за носком
            u = unit(ankle - hip)
            Rf0 = R[t, ia]
            y0 = float(toe_out(rig, Rf0, s))
            th = _solve_angle(lambda a: float(toe_out(rig, axis_angle(u, a) @ Rf0, s)), y0 + d_const,
                              math.radians(d_const * sgn) * (-1.0 if u[2] < 0 else 1.0))
            Q = axis_angle(u, th)
            for b in (iu, ik, ia, it):
                R[t, b] = Q @ R[t, b]
            for b in (ik, ia, it):
                P[t, b] = hip + Q @ (P[t, b] - hip)
            sw_deg[t] = math.degrees(th)
            # 2) переменная часть — стопа вокруг оси голени (≤ ankle_max)
            if abs(d_var[t]) > 1e-3:
                v = unit(P[t, ia] - P[t, ik])
                Rf1 = R[t, ia]
                y1 = float(toe_out(rig, Rf1, s))
                ph = _solve_angle(lambda a: float(toe_out(rig, axis_angle(v, a) @ Rf1, s)), y1 + d_var[t],
                                  math.radians(d_var[t] * sgn) * (-1.0 if v[2] < 0 else 1.0))
                cap = math.radians(ank_cap)
                ph = max(-cap, min(cap, ph))
                A = axis_angle(v, ph)
                R[t, ia] = A @ R[t, ia]
                R[t, it] = A @ R[t, it]
                P[t, it] = P[t, ia] + A @ (P[t, it] - P[t, ia])
                an_deg[t] = math.degrees(ph)
            # 3) что не добрал голеностоп (перенос ноги с сильным разворотом) — ещё немного ротацией в бедре
            y2 = float(toe_out(rig, R[t, ia], s, ref))
            res = float(want[t]) - y2
            if abs(res) > 0.3:
                u = unit(P[t, ia] - hip)
                Rf2 = R[t, ia]
                th2 = _solve_angle(lambda a: float(toe_out(rig, axis_angle(u, a) @ Rf2, s)), y2 + res,
                                   math.radians(res * sgn) * (-1.0 if u[2] < 0 else 1.0))
                cap2 = math.radians(p["hip_extra_max_deg"])
                th2 = max(-cap2, min(cap2, th2))
                Q = axis_angle(u, th2)
                for b in (iu, ik, ia, it):
                    R[t, b] = Q @ R[t, b]
                for b in (ik, ia, it):
                    P[t, b] = hip + Q @ (P[t, b] - hip)
                sw_deg[t] += math.degrees(th2)
        rep["legs"][s] = {"stance_toe_out_before_deg": round(float(np.median(to[st])), 1),
                          "hip_rotation_deg": round(float(np.median(np.abs(sw_deg))), 1),
                          "ankle_twist_max_deg": round(float(np.abs(an_deg).max()), 1)}
    # 3)–4) опора: у ходьбы — плоская подошва в середине опоры и подошва на полу; у стойки — стопы стоят на месте
    con, _ = contacts(rig, R, P, kind)
    if kind == "walk":
        R, P, drop = _walk_stance(rig, R, P, con, cyclic, p)
    else:
        R, P, drop = _idle_plant(rig, R, P, con, p)
    rep["hip_drop_max_m"] = round(float(drop.max()), 4)
    return ortho(R), P, rep



def _ramp(con, cyclic, frac):
    """Вес по кадрам касания: 0 на краях, 1 в середине (косинус на долю frac длины касания)."""
    T = len(con)
    w = np.zeros(T)
    for a, n in cyc_intervals(con, cyclic):
        r = max(1, int(round(n * frac)))
        for k in range(n):
            x = min(k, n - 1 - k)
            w[(a + k) % T] = 0.5 - 0.5 * math.cos(math.pi * min(1.0, x / r))
    return w


def _inner_edges(con, cyclic, r=2):
    T = len(con)
    w = np.zeros(T)
    for a, n in cyc_intervals(con, cyclic):
        for k in range(n):
            x = min(k, n - 1 - k)
            w[(a + k) % T] = min(1.0, (x + 1) / (r + 1))
    return w


def _soft_edges(c, cyclic, k=3):
    ker = np.r_[np.linspace(0.25, 1.0, k + 1), np.linspace(1.0, 0.25, k + 1)[1:]]
    pad = np.r_[c[-k:], c, c[:k]] if cyclic else np.r_[np.repeat(c[0], k), c, np.repeat(c[-1], k)]
    return np.clip(np.maximum(np.convolve(pad, ker / ker.max(), mode="valid"), c), 0, 1)


def _smooth_max(x, cyclic, r=4):
    ker = np.hanning(2 * r + 1)
    ker /= ker.sum()
    pad = np.r_[x[-r:], x, x[:r]] if cyclic else np.r_[np.repeat(x[0], r), x, np.repeat(x[-1], r)]
    return np.maximum(np.convolve(pad, ker, mode="valid"), x)


def _flatten(rig, R, P, s, w, cap=None):
    """Поворот стопы (и пальцев) в голеностопе вокруг поперечной оси: наклон подошвы пятка→подушечка ×(1−w),
    но не круче cap (° — там, где cap задан: в касании носок не задирается выше); пальцы сапога — к позе покоя
    относительно стопы с тем же весом (сапог не гнётся носком в пол)."""
    R, P = R.copy(), P.copy()
    iu, ik, ia, it = leg(rig, s)
    rel = rig.rest_R[ia].T @ rig.rest_R[it]
    for t in range(len(R)):
        if w[t] > 1e-3:
            Rt_rest = R[t, ia] @ rel
            dR = Rt_rest @ R[t, it].T
            ang = math.acos(max(-1.0, min(1.0, (np.trace(dR) - 1) / 2)))
            if ang > 1e-6:
                ax = np.array([dR[2, 1] - dR[1, 2], dR[0, 2] - dR[2, 0], dR[1, 0] - dR[0, 1]])
                R[t, it] = axis_angle(ax, ang * w[t]) @ R[t, it]
    for t in range(len(R)):
        if w[t] <= 1e-3 and (cap is None or cap[t] is None):
            continue
        lat = R[t, ia] @ rig.lat[s]
        Rt0, Pt0 = R[t], P[t]

        def pitch_after(a):
            Ra = axis_angle(lat, a)
            Rt, Pt = Rt0.copy(), Pt0.copy()
            Rt[ia], Rt[it] = Ra @ Rt[ia], Ra @ Rt[it]
            Pt[it] = Pt[ia] + Ra @ (Pt[it] - Pt[ia])
            h, b, _ = sole(rig, Rt[None], Pt[None], s)
            h, b = h[0], b[0]
            return math.degrees(math.atan2(b[2] - h[2], np.linalg.norm((b - h)[:2])))
        pit = pitch_after(0.0)
        goal = pit * (1 - w[t])
        if cap is not None and cap[t] is not None:
            goal = max(-cap[t], min(cap[t], goal))
        if abs(goal - pit) < 1e-3:
            continue
        a = _solve_angle(pitch_after, goal, math.radians(pit - goal))
        Ra = axis_angle(lat, a)
        R[t, ia] = Ra @ R[t, ia]
        R[t, it] = Ra @ R[t, it]
        P[t, it] = P[t, ia] + Ra @ (P[t, it] - P[t, ia])
    return R, P


def _apply_ik(rig, R, P, s, target):
    """Лодыжка ноги s → target (T,3), бедро на месте, ориентация стопы и пальцев сохраняется."""
    iu, ik, ia, it = leg(rig, s)
    for t in range(len(R)):
        Ph, Pk, Pa = P[t, iu], P[t, ik], P[t, ia]
        if np.linalg.norm(target[t] - Pa) < 1e-7:
            continue
        knee, ankle = two_bone(Ph, Pk, Pa, target[t])
        Rf, Rtoe = R[t, ia].copy(), R[t, it].copy()
        d1 = rot_between(Pk - Ph, knee - Ph)
        R[t, iu] = d1 @ R[t, iu]
        R[t, ik] = d1 @ R[t, ik]
        d2 = rot_between(d1 @ (Pa - Pk), ankle - knee)
        R[t, ik] = d2 @ R[t, ik]
        R[t, ia], R[t, it] = Rf, Rtoe
        toe_off = P[t, it] - Pa
        P[t, ik], P[t, ia] = knee, ankle
        P[t, it] = ankle + toe_off


def _walk_stance(rig, R, P, con, cyclic, p):
    """Ходьба: в середине опоры подошва плоская (сколько позволяет длина ноги: таз опускается не больше
    hip_drop_max), опорная подошва — на полу, в переносе — не под полом. Горизонталь лодыжек не меняется:
    шаг и root motion остаются клиповыми."""
    T = len(R)
    w0 = {s: _ramp(con[s], cyclic, p["flat_ramp"]) for s in ("L", "R")}
    # притяжение к полу — только внутри касания (нога уже не летит вперёд), с мягким входом и выходом по 2 кадра:
    # раньше касания опускающаяся стопа задевала бы пол на ходу
    cs = {s: _inner_edges(con[s], cyclic) for s in ("L", "R")}
    scale = {s: np.ones(T) for s in ("L", "R")}
    for _ in range(4):
        Rf, Pf = R, P
        need, deficit = {}, np.zeros(T)
        for s in ("L", "R"):
            cap = [p["contact_pitch_max_deg"] if c else None for c in con[s]]
            Rf, Pf = _flatten(rig, Rf, Pf, s, w0[s] * scale[s], cap)
        for s in ("L", "R"):
            iu, ik, ia, it = leg(rig, s)
            h, b, tp = sole(rig, Rf, Pf, s)
            z = np.minimum(np.minimum(h[:, 2], b[:, 2]), tp[:, 2])
            fl = p["_floor"]
            dz = cs[s] * (fl - z)
            dz = np.maximum(dz, fl - z)
            dz = np.where(cs[s] > 0, dz, np.maximum(0.0, fl - z))
            need[s] = dz
            l1 = np.linalg.norm(Pf[:, ik] - Pf[:, iu], axis=1)
            l2 = np.linalg.norm(Pf[:, ia] - Pf[:, ik], axis=1)
            dist = np.linalg.norm(Pf[:, ia] + dz[:, None] * UP - Pf[:, iu], axis=1)
            short = np.maximum(0.0, dist - (l1 + l2) * 0.998) * cs[s]
            deficit = np.maximum(deficit, short)
            over = short > p["hip_drop_max"]
            scale[s] = np.where(over, scale[s] * np.clip(p["hip_drop_max"] / np.maximum(short, 1e-9), 0.3, 1.0), scale[s])
        if deficit.max() <= p["hip_drop_max"] + 1e-4:
            break
    drop = np.minimum(_smooth_max(deficit, cyclic), p["hip_drop_max"]) if deficit.max() > 0 else np.zeros(T)
    Pf = Pf - drop[:, None, None] * UP[None, None, :]
    for s in ("L", "R"):
        iu, ik, ia, it = leg(rig, s)
        _apply_ik(rig, Rf, Pf, s, Pf[:, ia] + (need[s] + drop)[:, None] * UP)
    return Rf, Pf, drop


def _idle_plant(rig, R, P, con, p, hyst=0.003):
    """Стойка: на всё касание опорная точка подошвы (самая низкая: пятка → подушечка → носок — перекат при
    переносе веса) стоит на месте; поправка лодыжки непрерывна; высота — как в клипе, но не под полом."""
    T = len(R)
    R, P = R.copy(), P.copy()
    for s in ("L", "R"):
        iu, ik, ia, it = leg(rig, s)
        pts = sole(rig, R, P, s)
        tgt = P[:, ia].copy()
        cur = np.zeros(3)
        anchor, mode = None, None
        decay = math.exp(-1.0 / 3.0)
        for t in range(T):
            if con[s][t]:
                z = [pts[k][t, 2] for k in range(3)]
                k = int(np.argmin(z))
                if mode is None or (k != mode and z[k] < z[mode] - hyst):
                    anchor = pts[k][t, :2] + cur[:2]
                    mode = k
                cur[:2] = anchor - pts[mode][t, :2]
            else:
                mode = None
                cur *= decay
            tgt[t, :2] += cur[:2]
        h, bl, tp = pts
        z = np.minimum(np.minimum(h[:, 2], bl[:, 2]), tp[:, 2])
        tgt[:, 2] += np.maximum(0.0, p["_floor"] - z)
        _apply_ik(rig, R, P, s, tgt)
    return R, P, np.zeros(T)

# ---------------------------------------------------------------- замер

def stance_root_motion(rig, R, P, con=None):
    """Root motion по опорной стопе (как в игре): точка подошвы, стоящая ниже всех (пятка/подушечка/носок любой
    стопы), не двигается. Опорная точка «липкая»: меняется, только когда другая ниже на 2 мм — иначе равные по
    высоте точки (плоская подошва) перебрасывали бы отсчёт от кадра к кадру. Смещение — по одной точке в соседних
    кадрах."""
    X = np.stack([np.stack(sole(rig, R, P, s), 1) for s in ("L", "R")], 1)  # (T, стопа, точка, 3)
    T = len(R)
    Z = X[:, :, :, 2].reshape(T, 6)
    off = np.zeros((T, 3))
    acc = np.zeros(3)
    cur = int(np.argmin(Z[0]))
    for t in range(1, T):
        k = int(np.argmin(Z[t]))
        if Z[t, k] < Z[t, cur] - 0.002:
            cur = k
        f, j = divmod(cur, 3)
        d = X[t, f, j] - X[t - 1, f, j]
        d[2] = 0
        acc -= d
        off[t] = acc
    return off


def measure(rig: Rig, R, P, kind: str, in_place=True, cyclic=None):
    """Числа для check_feet: разворот ботинка в опоре (медиана) и вне опоры (наибольший по модулю), подъём подошвы
    в середине опоры, проскальзывание пятки и подушечки за касание (у ходьбы на месте — после root motion по
    опорной стопе, как в игре: насколько уходят по полу точки подошвы, пока они на полу).
    Петля меряется на двух периодах подряд (касание через шов — целиком), считаются касания, начатые в первом."""
    if cyclic is None:
        cyclic = is_cyclic(rig, R, P)
    T0 = len(R)
    ref = body_yaw(rig, R) if kind != "walk" else 0.0
    if cyclic:
        R = np.concatenate([R, R[1:]])
        P = np.concatenate([P, P[1:]])
    T = len(R)
    con, low = contacts(rig, R, P, kind)
    off = stance_root_motion(rig, R, P) if (kind == "walk" and in_place) else np.zeros((T, 3))
    out = {}
    floor = clip_floor(rig, R, P)
    for s in ("L", "R"):
        iu, ik, ia, it = leg(rig, s)
        to = toe_out(rig, R[:, ia], s, ref)
        st = con[s]
        h, b, tp = sole(rig, R, P, s)
        lift, slide = [], []
        hm, bm = h + off, b + off
        for a, c in intervals(st):
            if cyclic:
                if a >= T0 or (a == 0 and c < T0 - 1):
                    continue  # хвост касания через шов — оно меряется целиком, начиная с его начала в конце петли
                c = min(c, a + T0)
            n = c - a
            mid = slice(a + n // 4, a + max(n // 4 + 1, 3 * n // 4))
            lift.append(float(max(np.abs(h[mid, 2] - floor).max(), np.abs(b[mid, 2] - floor).max())))
            for X in (hm, bm):
                on = X[a:c, 2] < floor + 0.012
                for a2, c2 in intervals(on):
                    seg = X[a + a2:a + c2, :2]
                    if len(seg) > 1:
                        slide.append(float(np.linalg.norm(seg - seg[0], axis=1).max()))
        to, st = to[:T0], st[:T0]
        out[s] = {
            "stance_toe_out_deg": round(float(np.median(to[st])), 1) if st.any() else None,
            "stance_toe_out_range_deg": [round(float(to[st].min()), 1), round(float(to[st].max()), 1)] if st.any() else None,
            "swing_toe_abs_max_deg": round(float(np.abs(to[~st]).max()), 1) if (~st).any() else 0.0,
            "toe_abs_max_deg": round(float(np.abs(to).max()), 1),
            "sole_lift_mid_stance_max_m": round(max(lift), 4) if lift else None,
            "slide_max_mm": round(max(slide) * 1000, 1) if slide else 0.0,
            "contact_frames": int(st.sum()),
        }
        out[s]["floor_m"] = round(floor, 4)
        if kind != "walk":
            out[s]["body_yaw_deg"] = round(ref, 1)
    return out


def verdict(m: dict, kind: str) -> list:
    th = THRESHOLDS["walk" if kind == "walk" else "idle"]
    bad = []
    for s, v in m.items():
        if kind == "walk":
            if v["stance_toe_out_deg"] is None or not (th["stance_toe_out_min"] <= v["stance_toe_out_deg"] <= th["stance_toe_out_max"]):
                bad.append(f"{s}: носок в опоре {v['stance_toe_out_deg']}° вне {th['stance_toe_out_min']}…{th['stance_toe_out_max']}°")
            if v["swing_toe_abs_max_deg"] > th["swing_abs_max"]:
                bad.append(f"{s}: в переносе |носок| {v['swing_toe_abs_max_deg']}° > {th['swing_abs_max']}°")
        else:
            if v["toe_abs_max_deg"] > th["toe_abs_max"]:
                bad.append(f"{s}: |носок| {v['toe_abs_max_deg']}° > {th['toe_abs_max']}°")
        if kind == "walk" and v["sole_lift_mid_stance_max_m"] is not None and v["sole_lift_mid_stance_max_m"] > th["sole_lift_max_m"]:
            bad.append(f"{s}: подошва в опоре над полом {v['sole_lift_mid_stance_max_m'] * 100:.1f} см > {th['sole_lift_max_m'] * 100:.0f} см")
        if v["slide_max_mm"] > th["slide_max_mm"]:
            bad.append(f"{s}: проскальзывание {v['slide_max_mm']} мм > {th['slide_max_mm']} мм")
    return bad


def kind_of(role: str) -> str | None:
    r = role.lower()
    if r.startswith("walk") or "walk" in r:
        return "walk"
    if r.startswith("idle") or "idle" in r or "breathe" in r:
        return "idle"
    return None


# ---------------------------------------------------------------- Blender

def _bpy():
    import bpy  # noqa: PLC0415
    return bpy


def rig_from_blender(arm, meshes) -> Rig:
    bpy = _bpy()
    names, parents = [], []

    def walk(b):
        names.append(b.name)
        parents.append(names.index(b.parent.name) if b.parent else -1)
        for c in b.children:
            walk(c)
    for b in arm.data.bones:
        if b.parent is None:
            walk(b)
    W = np.array(arm.matrix_world)
    rR, rP = [], []
    for n in names:
        M = W @ np.array(arm.data.bones[n].matrix_local)
        rR.append(ortho(M[:3, :3]))
        rP.append(M[:3, 3])
    rig = Rig(names, parents, np.array(rR), np.array(rP))
    # сетка в позе покоя (без действия): вершины в мире
    ad = arm.animation_data
    keep = (ad.action, getattr(ad, "action_slot", None)) if ad else (None, None)
    if ad:
        ad.action = None
    saved = {pb.name: pb.matrix_basis.copy() for pb in arm.pose.bones}
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    V = []
    for m in meshes:
        ev = m.evaluated_get(dg)
        me = ev.to_mesh()
        mw = np.array(ev.matrix_world)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        V.append(co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3])
        ev.to_mesh_clear()

    for pb in arm.pose.bones:
        pb.matrix_basis = saved[pb.name]
    if ad and keep[0] is not None:
        assign(arm, keep[0])
    foot_geometry(rig, np.concatenate(V))
    return rig


def assign(arm, act):
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    ad.action = act
    if act is not None and hasattr(ad, "action_slot") and ad.action_slot is None and len(getattr(act, "slots", [])):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


def action_fcurves(act):
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def key_times(act, bones):
    xs = set()
    for fc in action_fcurves(act):
        for bn in bones:
            if fc.data_path == f'pose.bones["{bn}"].rotation_quaternion':
                xs.update(round(k.co[0], 4) for k in fc.keyframe_points)
    if not xs:
        f0, f1 = act.frame_range
        xs = set(np.arange(f0, f1 + 1e-6, 1.0).round(4))
    return np.array(sorted(xs))


def sample(arm, act, rig: Rig, frames):
    bpy = _bpy()
    sc = bpy.context.scene
    assign(arm, act)
    pbs = [arm.pose.bones[n] for n in rig.names]
    T = len(frames)
    R = np.zeros((T, len(pbs), 3, 3))
    P = np.zeros((T, len(pbs), 3))
    for t, f in enumerate(frames):
        fi = math.floor(f)
        sc.frame_set(int(fi), subframe=float(f - fi))
        W = np.array(arm.matrix_world)
        for b, pb in enumerate(pbs):
            M = W @ np.array(pb.matrix)
            R[t, b], P[t, b] = M[:3, :3], M[:3, 3]
    return ortho(R), P


def is_cyclic(rig, R, P, tol_deg=4.0, tol_m=0.01):
    """Петля: первый и последний кадры совпадают по ногам и тазу (клипы Meshy зациклены)."""
    worst = 0.0
    for b in [rig.idx(n) for n in ("Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot")]:
        d = R[0, b].T @ R[-1, b]
        worst = max(worst, math.degrees(math.acos(min(1.0, max(-1.0, (np.trace(d) - 1) / 2)))))
    return worst < tol_deg and np.linalg.norm(P[0, 0] - P[-1, 0]) < tol_m


def write_back(arm, act, rig: Rig, frames, R, P, P_old):
    """Новые вращения костей ног и высота таза → ключи действия (в тех же моментах, интерполяция прежняя)."""
    bones = [n for s in ("L", "R") for n in (SIDES[s] + "UpLeg", SIDES[s] + "Leg", SIDES[s] + "Foot", SIDES[s] + "ToeBase")]
    fcs = {}
    for fc in action_fcurves(act):
        fcs[(fc.data_path, fc.array_index)] = fc
    W = np.array(arm.matrix_world)
    Winv = np.linalg.inv(W)
    for bn in bones:
        b = rig.idx(bn)
        pidx = rig.parents[b]
        Q = []
        for t in range(len(frames)):
            Bm = rig.rest_R[b].T @ rig.rest_R[pidx] @ R[t, pidx].T @ R[t, b]
            q = mat_to_quat(ortho(Bm))
            if Q and float(np.dot(q, Q[-1])) < 0:
                q = -q
            Q.append(q)
        Q = np.array(Q)
        path = f'pose.bones["{bn}"].rotation_quaternion'
        for i in range(4):
            fc = fcs.get((path, i))
            if fc is None:
                fc = _new_fcurve(act, path, i, bn)
            _set_keys(fc, frames, Q[:, i])
    # таз: только высота (если опускали)
    dz = P[:, 0, 2] - P_old[:, 0, 2]
    if np.abs(dz).max() > 1e-6:
        hb = rig.names[0]
        bone = arm.data.bones[hb]
        L = np.array(bone.matrix_local)
        path = f'pose.bones["{hb}"].location'
        pb = arm.pose.bones[hb]
        cur = []
        bpy = _bpy()
        sc = bpy.context.scene
        assign(arm, act)
        for f in frames:
            fi = math.floor(f)
            sc.frame_set(int(fi), subframe=float(f - fi))
            cur.append(np.array(pb.location))
        cur = np.array(cur)
        # мировой сдвиг по Z → сдвиг в системе кости покоя (armature space / масштаб объекта)
        dv = (Winv[:3, :3] @ np.stack([np.zeros_like(dz), np.zeros_like(dz), dz], 0)).T
        dloc = (L[:3, :3].T @ dv.T).T
        new = cur + dloc
        for i in range(3):
            fc = fcs.get((path, i)) or _new_fcurve(act, path, i, hb)
            _set_keys(fc, frames, new[:, i])


def _new_fcurve(act, path, i, group):
    if hasattr(act, "fcurves"):
        return act.fcurves.new(path, index=i, action_group=group)
    cb = act.layers[0].strips[0].channelbags[0]
    return cb.fcurves.new(path, index=i)


def _set_keys(fc, frames, vals):
    """Заменить значения ключей в моментах frames (есть — правим, нет — добавляем), интерполяция — как была."""
    kp = fc.keyframe_points
    existing = {round(k.co[0], 4): k for k in kp}
    interp = kp[0].interpolation if len(kp) else "LINEAR"
    for f, v in zip(frames, vals):
        k = existing.get(round(float(f), 4))
        if k is None:
            k = kp.insert(float(f), float(v), options={"FAST"})
            k.interpolation = interp
        else:
            k.co[1] = float(v)
            k.handle_left[1] = float(v)
            k.handle_right[1] = float(v)
    fc.update()


def fix_action(arm, rig: Rig, act, kind: str, params=None, window=None) -> dict:
    """Исправить один клип на месте (ключи действия). window=(a, b) — доля клипа (как clip_window у листов):
    правится и меряется только этот отрезок. → отчёт с замерами до и после."""
    bones = [n for s in ("L", "R") for n in (SIDES[s] + "UpLeg", SIDES[s] + "Leg", SIDES[s] + "Foot")]
    frames = key_times(act, bones)
    if window:
        f0, f1 = frames[0], frames[-1]
        lo, hi = f0 + (f1 - f0) * window[0], f0 + (f1 - f0) * window[1]
        frames = frames[(frames >= lo - 1e-6) & (frames <= hi + 1e-6)]
    R, P = sample(arm, act, rig, frames)
    cyc = is_cyclic(rig, R, P) and not window
    before = measure(rig, R, P, kind, cyclic=cyc)
    R2, P2, rep = fix_clip(rig, R, P, kind, cyc, params)
    write_back(arm, act, rig, frames, R2, P2, P)
    R3, P3 = sample(arm, act, rig, frames)
    after = measure(rig, R3, P3, kind, cyclic=cyc)
    # кости выше таза не тронуты: наибольшее расхождение мировых вращений (°)
    upper = [i for i, n in enumerate(rig.names) if not any(k in n for k in ("UpLeg", "Leg", "Foot", "ToeBase", "Hips"))]
    du = 0.0
    for b in upper:
        d = np.einsum("tji,tjk->tik", R[:, b], R3[:, b])
        du = max(du, float(np.degrees(np.arccos(np.clip((np.trace(d, axis1=1, axis2=2) - 1) / 2, -1, 1))).max()))
    rep.update({"clip": act.name, "window": list(window) if window else None, "before": before, "after": after, "upper_body_max_rot_diff_deg": round(du, 3),
                "fail": verdict(after, kind)})
    return rep


def find_action(acts, key):
    for a in acts:
        if a.name == key or a.name.split(".")[0] == key:
            return a
    for a in acts:
        if key.lower() in a.name.lower():
            return a
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--clips", nargs="*", default=[], help="роль=клип[@a:b], напр. walk=Walking_Woman idle=Idle@0:0.2")
    ap.add_argument("--auto", action="store_true", help="все клипы, чьё имя — ходьба или стойка (GLB для игры в 3D)")
    ap.add_argument("--out-glb", default="")
    ap.add_argument("--report", default="")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--params", default="", help="JSON поверх PARAMS (опыты)")
    args = ap.parse_args()
    prm = json.loads(args.params) if args.params else None
    bpy = _bpy()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = int(args.fps)
    acts0 = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.glb).resolve()), disable_bone_shape=True)
    objs = [o for o in sc.objects if not any(c.name == "glTF_not_exported" for c in o.users_collection)]
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"]
    acts = [a for a in bpy.data.actions if a not in acts0]
    rig = rig_from_blender(arm, meshes)
    reports = []
    specs = list(args.clips)
    if args.auto:
        specs += [f"{a.name}={a.name}" for a in acts if kind_of(a.name) and not any(x.split("=", 1)[1].split("@")[0] == a.name for x in specs)]
    for spec in specs:
        role, key = spec.split("=", 1)
        win = None
        if "@" in key:
            key, w = key.split("@", 1)
            win = tuple(float(x) for x in w.split(":"))
        act = find_action(acts, key)
        kind = kind_of(role) or kind_of(key)
        if act is None or kind is None:
            print(f"пропуск {spec}: клип не найден или не ходьба/стойка", flush=True)
            continue
        r = fix_action(arm, rig, act, kind, params=prm, window=win)
        r["role"] = role
        reports.append(r)
        print(json.dumps({k: r[k] for k in ("role", "clip", "before", "after", "fail", "hip_drop_max_m")}, ensure_ascii=False), flush=True)
    if args.report:
        Path(args.report).write_text(json.dumps({"rest_toe_out_deg": rig.rest_yaw, "clips": reports}, ensure_ascii=False, indent=1), encoding="utf-8")
    if args.out_glb:
        bpy.ops.export_scene.gltf(filepath=str(Path(args.out_glb).resolve()), export_format="GLB", export_animations=True,
                                  export_animation_mode="ACTIONS", export_force_sampling=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
