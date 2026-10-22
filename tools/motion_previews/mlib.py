"""Математика превью движений (numpy, без Blender): ретаргет на скелет Агаты, петля, контакты стоп, IK ног, замеры.

Соглашения: мир — метры, Z вверх, Агата в покое смотрит в −Y (её левая рука — +X). Вращения — матрицы 3×3
(мировая ориентация кадра кости), позиции — головы костей (суставы). Кадры по времени: массивы (T, …).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

UP = np.array([0.0, 0.0, 1.0])
FWD = np.array([0.0, -1.0, 0.0])
LEFT = np.array([1.0, 0.0, 0.0])


# ---------------------------------------------------------------- вращения

def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def ortho(R):
    """Ближайшая ортонормированная матрица (полярное разложение) — убирает масштаб и шум."""
    U, _, Vt = np.linalg.svd(R)
    d = np.sign(np.linalg.det(U @ Vt))
    U = U.copy()
    U[..., :, -1] *= d[..., None]
    return U @ Vt


def axis_angle(axis, ang):
    axis = unit(axis)
    ang = np.asarray(ang, float)
    x, y, z = axis[..., 0], axis[..., 1], axis[..., 2]
    c, s = np.cos(ang), np.sin(ang)
    C = 1 - c
    R = np.stack([
        np.stack([c + x * x * C, x * y * C - z * s, x * z * C + y * s], -1),
        np.stack([y * x * C + z * s, c + y * y * C, y * z * C - x * s], -1),
        np.stack([z * x * C - y * s, z * y * C + x * s, c + z * z * C], -1)], -2)
    return R


def rot_z(ang):
    return axis_angle(np.broadcast_to(UP, np.shape(ang) + (3,)), ang)


def rot_between(a, b):
    """Минимальное вращение, переводящее направление a в b (векторизовано)."""
    a, b = unit(a), unit(b)
    v = np.cross(a, b)
    c = np.sum(a * b, -1)
    s = np.linalg.norm(v, axis=-1)
    ang = np.arctan2(s, c)
    # почти противоположные — любая перпендикулярная ось
    alt = np.cross(a, np.array([1.0, 0, 0]))
    alt = np.where(np.linalg.norm(alt, axis=-1, keepdims=True) < 1e-6, np.cross(a, np.array([0, 1.0, 0])), alt)
    axis = np.where((s < 1e-9)[..., None], alt, v)
    return axis_angle(axis, ang)


def mat_to_quat(R):
    R = np.asarray(R, float)
    shp = R.shape[:-2]
    R = R.reshape(-1, 3, 3)
    q = np.empty((len(R), 4))
    for i, m in enumerate(R):
        t = np.trace(m)
        if t > 0:
            s = math.sqrt(t + 1.0) * 2
            q[i] = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
        elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
            s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
            q[i] = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
        elif m[1, 1] > m[2, 2]:
            s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
            q[i] = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
        else:
            s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
            q[i] = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    q /= np.linalg.norm(q, axis=1, keepdims=True)
    return q.reshape(shp + (4,))


def quat_to_mat(q):
    q = unit(q)
    w, x, y, z = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    return np.stack([
        np.stack([1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], -1),
        np.stack([2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], -1),
        np.stack([2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)], -1)], -2)


def rot_log(R):
    """Вектор поворота (ось × угол) матрицы R."""
    R = np.asarray(R, float)
    c = np.clip((np.trace(R, axis1=-2, axis2=-1) - 1) / 2, -1, 1)
    ang = np.arccos(c)
    v = np.stack([R[..., 2, 1] - R[..., 1, 2], R[..., 0, 2] - R[..., 2, 0], R[..., 1, 0] - R[..., 0, 1]], -1)
    s = np.sin(ang)
    k = np.where(s > 1e-6, ang / np.maximum(2 * s, 1e-12), 0.5)
    return v * k[..., None]


def rot_exp(w):
    w = np.asarray(w, float)
    ang = np.linalg.norm(w, axis=-1)
    return axis_angle(np.where(ang[..., None] > 1e-12, w, np.array([0, 0, 1.0])), ang)


def rot_angle_deg(R):
    return np.degrees(np.linalg.norm(rot_log(R), axis=-1))


def yaw_of_dir(v):
    """Угол направления на полу (рад) от −Y (вперёд Агаты) к +X: 0 = вперёд, +90° = влево Агаты."""
    return np.arctan2(v[..., 0], -v[..., 1])


# ---------------------------------------------------------------- скелет и FK

@dataclass
class Skeleton:
    names: list
    parents: list           # индекс родителя или -1
    rest_R: np.ndarray      # (B,3,3) мировые ориентации костей в покое
    rest_P: np.ndarray      # (B,3) мировые головы костей в покое, м
    offsets: np.ndarray = field(default=None)  # (B,3) голова кости в системе родителя (покой)

    def __post_init__(self):
        if self.offsets is None:
            off = np.zeros((len(self.names), 3))
            for b, p in enumerate(self.parents):
                if p >= 0:
                    off[b] = self.rest_R[p].T @ (self.rest_P[b] - self.rest_P[p])
            self.offsets = off

    def idx(self, n):
        return self.names.index(n)


def fk_positions(sk: Skeleton, R, root_P):
    """R: (T,B,3,3) мировые ориентации; root_P: (T,3). → (T,B,3) позиции голов костей."""
    T, B = R.shape[:2]
    P = np.zeros((T, B, 3))
    for b, p in enumerate(sk.parents):
        if p < 0:
            P[:, b] = root_P
        else:
            P[:, b] = P[:, p] + np.einsum("tij,j->ti", R[:, p], sk.offsets[b])
    return P


def world_from_local(sk: Skeleton, L, root_R):
    """L: (T,B,3,3) локальные вращения относительно покоя (как matrix_basis Blender), root — мировое."""
    T, B = L.shape[:2]
    R = np.zeros((T, B, 3, 3))
    for b, p in enumerate(sk.parents):
        if p < 0:
            R[:, b] = root_R
        else:
            rel = sk.rest_R[p].T @ sk.rest_R[b]
            R[:, b] = R[:, p] @ rel @ L[:, b]
    return R


def basis_from_world(sk: Skeleton, R):
    """Мировые ориентации → matrix_basis (вращение) каждой кости: B = Rrest_b^T Rrest_p R_p^T R_b."""
    T, B = R.shape[:2]
    out = np.zeros_like(R)
    for b, p in enumerate(sk.parents):
        if p < 0:
            out[:, b] = sk.rest_R[b].T @ R[:, b]
        else:
            out[:, b] = sk.rest_R[b].T @ sk.rest_R[p] @ np.swapaxes(R[:, p], -1, -2) @ R[:, b]
    return out


# ---------------------------------------------------------------- ретаргет

# Тип переноса по кости цели:
#   delta — мировое вращение относительно покоя переносится как есть (позы покоя считаются равносильными:
#           таз, позвоночник, шея, голова, ключицы);
#   aim   — кадр кости строится по направлению на дочерний сустав + «вперёд» (руки и ноги: покой T/A-поза разный);
#   yaw   — стопа и пальцы: кадр по направлению носка на полу + «вверх» (покой — стопа плоско на полу).
TARGET_KIND = {
    "Hips": "hips", "Spine02": "aim", "Spine01": "aim", "Spine": "aim", "neck": "aim", "Head": "aim",
    "LeftShoulder": "delta", "RightShoulder": "delta",
    "LeftArm": "aim", "LeftForeArm": "aim", "LeftHand": "aim",
    "RightArm": "aim", "RightForeArm": "aim", "RightHand": "aim",
    "LeftUpLeg": "aim", "LeftLeg": "aim", "RightUpLeg": "aim", "RightLeg": "aim",
    "LeftFoot": "yaw", "LeftToeBase": "yaw", "RightFoot": "yaw", "RightToeBase": "yaw",
}
# Прицел кости цели: (откуда, куда) — суставы Агаты. Для таза: (правое бедро, левое бедро) + «вверх» (таз → Spine01).
# Позвоночник, шея и голова — тоже по направлениям сегментов: у источников поза покоя не всегда прямая
# (в CMU шея и голова в покое наклонены на 10–20°) — перенос «как есть» наклонил бы голову Агаты.
TARGET_AIMS = {
    "Hips": (("RightUpLeg", "LeftUpLeg"), ("Hips", "Spine01")),
    "Spine02": ("Spine02", "Spine01"), "Spine01": ("Spine01", "Spine"), "Spine": ("Spine", "neck"),
    "neck": ("neck", "Head"), "Head": ("Head", "head_end"),
    "LeftArm": ("LeftArm", "LeftForeArm"), "LeftForeArm": ("LeftForeArm", "LeftHand"), "LeftHand": ("LeftForeArm", "LeftHand"),
    "RightArm": ("RightArm", "RightForeArm"), "RightForeArm": ("RightForeArm", "RightHand"), "RightHand": ("RightForeArm", "RightHand"),
    "LeftUpLeg": ("LeftUpLeg", "LeftLeg"), "LeftLeg": ("LeftLeg", "LeftFoot"),
    "RightUpLeg": ("RightUpLeg", "RightLeg"), "RightLeg": ("RightLeg", "RightFoot"),
    "LeftFoot": ("LeftFoot", "LeftToeBase"), "LeftToeBase": ("LeftFoot", "LeftToeBase"),
    "RightFoot": ("RightFoot", "RightToeBase"), "RightToeBase": ("RightFoot", "RightToeBase"),
}
# Прицелы источника по семействам там, где они не выводятся из соответствия костей (позвоночник, голова, таз).
FAMILY_AIMS = {
    "m2m": {"Hips": (("thigh_r", "thigh_l"), ("pelvis", "spine_02")), "Spine02": ("spine_01", "spine_02"),
            "Spine01": ("spine_02", "spine_03"), "Spine": ("spine_03", "neck_01"), "neck": ("neck_01", "head"),
            "Head": ("head", "head_leaf")},
    "cmu": {"Hips": (("RightUpLeg", "LeftUpLeg"), ("Hips", "Spine1")), "Spine02": ("LowerBack", "Spine"),
            "Spine01": ("Spine", "Spine1"), "Spine": ("Spine", "Spine1"), "neck": ("Neck1", "Head"),
            "Head": ("Head", "Head@tail")},
    "100style": {"Hips": (("RightHip", "LeftHip"), ("Hips", "Chest2")), "Spine02": ("Chest", "Chest2"),
                 "Spine01": ("Chest2", "Chest3"), "Spine": ("Chest4", "Neck"), "neck": ("Neck", "Head"),
                 "Head": ("Head", "Head@tail")},
}

# Соответствие костей Агаты (Meshy, 24 кости) костям источника — по семействам скелетов.
FAMILY_MAPS = {
    "meshy": {k: k for k in TARGET_KIND},
    "m2m": {"Hips": "pelvis", "Spine02": "spine_01", "Spine01": "spine_02", "Spine": "spine_03", "neck": "neck_01",
            "Head": "head", "LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l",
            "LeftHand": "hand_l", "RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r",
            "RightHand": "hand_r", "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l",
            "LeftToeBase": "ball_l", "RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r",
            "RightToeBase": "ball_r"},
    "cmu": {"Hips": "Hips", "Spine02": "LowerBack", "Spine01": "Spine", "Spine": "Spine1", "neck": "Neck1",
            "Head": "Head", "LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm",
            "LeftHand": "LeftHand", "RightShoulder": "RightShoulder", "RightArm": "RightArm",
            "RightForeArm": "RightForeArm", "RightHand": "RightHand", "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg",
            "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase", "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg",
            "RightFoot": "RightFoot", "RightToeBase": "RightToeBase"},
    # 100STYLE: имена проверяются по заголовку BVH (sources/100style/skeleton_header.txt)
    "100style": {"Hips": "Hips", "Spine02": "Chest", "Spine01": "Chest2", "Spine": "Chest4", "neck": "Neck",
                 "Head": "Head", "LeftShoulder": "LeftCollar", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftElbow",
                 "LeftHand": "LeftWrist", "RightShoulder": "RightCollar", "RightArm": "RightShoulder",
                 "RightForeArm": "RightElbow", "RightHand": "RightWrist", "LeftUpLeg": "LeftHip",
                 "LeftLeg": "LeftKnee", "LeftFoot": "LeftAnkle", "LeftToeBase": "LeftToe", "RightUpLeg": "RightHip",
                 "RightLeg": "RightKnee", "RightFoot": "RightAnkle", "RightToeBase": "RightToe"},
}


def detect_family(src_names):
    s = set(src_names)
    best, score = None, -1
    for fam, m in FAMILY_MAPS.items():
        if fam == "meshy":
            continue
        sc = sum(1 for v in m.values() if v in s)
        if sc > score:
            best, score = fam, sc
    return best, score


def facing_from_rest(P, names, lhip, rhip, hips, up_child):
    """Направление «вперёд» скелета в покое: левая сторона × вверх."""
    left = P[names.index(lhip)] - P[names.index(rhip)]
    left[2] = 0
    left = unit(left)
    fwd = np.cross(left, UP)
    return unit(fwd)


def aim_frame(aim, ref):
    x = unit(aim)
    z = unit(ref - np.sum(ref * x, -1, keepdims=True) * x)
    y = np.cross(z, x)
    return np.stack([x, y, z], -1)


def yaw_frame(aim):
    h = aim.copy()
    h[..., 2] = 0
    x = unit(h)
    z = np.broadcast_to(UP, x.shape)
    y = np.cross(z, x)
    return np.stack([x, y, z], -1)


@dataclass
class SourceMotion:
    names: list
    parents: list
    rest_R: np.ndarray      # (S,3,3)
    rest_P: np.ndarray      # (S,3)
    R: np.ndarray           # (T,S,3,3)
    P: np.ndarray           # (T,S,3)
    fps: float
    times: np.ndarray       # (T,) секунды источника


def align_source(src: SourceMotion, mapping):
    """Поворот источника вокруг Z: «вперёд» его покоя → −Y; масштаб позиций по длине ног."""
    n = src.names
    fwd = facing_from_rest(src.rest_P, n, mapping["LeftUpLeg"], mapping["RightUpLeg"], mapping["Hips"], mapping["Spine02"])
    ang = math.atan2(fwd[0], -fwd[1])  # yaw источника относительно −Y
    G = rot_z(-ang)
    out = SourceMotion(src.names, src.parents, G @ src.rest_R, src.rest_P @ G.T,
                       np.einsum("ij,tsjk->tsik", G, src.R), np.einsum("ij,tsj->tsi", G, src.P), src.fps, src.times)
    return out, math.degrees(ang)


def leg_length(P, names, up, knee, ankle):
    a, b, c = P[names.index(up)], P[names.index(knee)], P[names.index(ankle)]
    return np.linalg.norm(b - a) + np.linalg.norm(c - b)


def hips_frame(lat, up):
    x = unit(lat)
    z = unit(up - np.sum(up * x, -1, keepdims=True) * x)
    y = np.cross(z, x)
    return np.stack([x, y, z], -1)


def _src_aim(fam, mapping, tb):
    fa = FAMILY_AIMS.get(fam, {})
    if tb in fa:
        return fa[tb]
    a0, a1 = TARGET_AIMS[tb]
    if isinstance(a0, tuple):
        return tuple(tuple(mapping[x] for x in pair) for pair in (a0, a1))
    return mapping[a0], mapping[a1]


def build_K(tgt: Skeleton, src: SourceMotion, mapping, tgt_foot_yaw=None, fam="meshy"):
    """Постоянная поправка K по кости: R_tgt(t) = R_src(t) · K.
    K = R_src_rest^T · A_src · A_tgt^T · R_tgt_rest, где A — анатомический кадр кости в покое (по прицелу)."""
    K = {}
    sn, tn = src.names, tgt.names
    def sp(n):
        return src.rest_P[sn.index(n)]
    def tp(n):
        return tgt.rest_P[tn.index(n)]
    for tb, kind in TARGET_KIND.items():
        sb = mapping.get(tb)
        if sb is None or sb not in sn or tb not in tn:
            continue
        Rs, Rt = src.rest_R[sn.index(sb)], tgt.rest_R[tn.index(tb)]
        if kind == "delta" or fam == "meshy":
            K[tb] = Rs.T @ Rt
            continue
        ta0, ta1 = TARGET_AIMS[tb]
        sa0, sa1 = _src_aim(fam, mapping, tb)
        if kind == "hips":
            At = hips_frame(tp(ta0[1]) - tp(ta0[0]), tp(ta1[1]) - tp(ta1[0]))
            As = hips_frame(sp(sa0[1]) - sp(sa0[0]), sp(sa1[1]) - sp(sa1[0]))
        else:
            ta = tp(ta1) - tp(ta0)
            sa = sp(sa1) - sp(sa0)
            if kind == "yaw":
                if tgt_foot_yaw is not None:
                    y = tgt_foot_yaw["L" if tb.startswith("Left") else "R"]
                    ta = np.array([math.sin(y), -math.cos(y), 0.0])
                At, As = yaw_frame(ta), yaw_frame(sa)
            else:
                At, As = aim_frame(ta, FWD), aim_frame(sa, FWD)
        K[tb] = Rs.T @ As @ At.T @ Rt
    return K


def retarget(tgt: Skeleton, src: SourceMotion, mapping, K, scale):
    """→ R (T,B,3,3) мировые ориентации костей Агаты, root_P (T,3)."""
    T = src.R.shape[0]
    B = len(tgt.names)
    R = np.zeros((T, B, 3, 3))
    sn = src.names
    for b, name in enumerate(tgt.names):
        p = tgt.parents[b]
        if name in K:
            R[:, b] = src.R[:, sn.index(mapping[name])] @ K[name]
        elif p >= 0:
            R[:, b] = R[:, p] @ (tgt.rest_R[p].T @ tgt.rest_R[b])
        else:
            R[:, b] = tgt.rest_R[b]
    R = ortho(R)
    root_P = src.P[:, sn.index(mapping["Hips"])] * scale
    return R, root_P


# ---------------------------------------------------------------- стопы: подошва, контакты, IK

@dataclass
class FootGeom:
    """Точки подошвы в системе кости стопы (покой): пятка и подушечка (под суставом пальцев), носок; ось ботинка."""
    heel: dict
    ball: dict
    tip: dict
    shoe_axis: dict      # единичный вектор «пятка→носок» ботинка в системе кости стопы
    rest_yaw: dict       # рыскание ботинка в покое (рад, 0 = −Y, + = к +X)


def sole_points(sk: Skeleton, R, P, fg: FootGeom, side):
    fb = sk.idx("LeftFoot" if side == "L" else "RightFoot")
    tb = sk.idx("LeftToeBase" if side == "L" else "RightToeBase")
    Rf, Pf = R[:, fb], P[:, fb]
    heel = Pf + np.einsum("tij,j->ti", Rf, fg.heel[side])
    ball = Pf + np.einsum("tij,j->ti", Rf, fg.ball[side])
    tip = P[:, tb] + np.einsum("tij,j->ti", R[:, tb], fg.tip[side])
    axis = np.einsum("tij,j->ti", Rf, fg.shoe_axis[side])
    return heel, ball, tip, axis


def hspeed(X, fps):
    v = np.zeros(len(X))
    if len(X) > 2:
        d = np.linalg.norm(X[2:, :2] - X[:-2, :2], axis=1) * fps / 2
        v[1:-1] = d
        v[0], v[-1] = d[0], d[-1]
    return v


def contacts(Z, V, h_thr, v_thr, min_len=3):
    c = (Z < h_thr) & (V < v_thr)
    # убрать дырки и короткие касания
    c = c.copy()
    n = len(c)
    i = 0
    while i < n:
        if not c[i]:
            j = i
            while j < n and not c[j]:
                j += 1
            if 0 < i and j < n and j - i <= 2:
                c[i:j] = True
            i = j
        else:
            i += 1
    i = 0
    while i < n:
        if c[i]:
            j = i
            while j < n and c[j]:
                j += 1
            if j - i < min_len:
                c[i:j] = False
            i = j
        else:
            i += 1
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


def two_bone_ik(Ph, Pk, Pa, target, pole_hint):
    """Аналитический IK бедро–колено–лодыжка: новые колено/лодыжка, плоскость сгиба — по прежнему колену."""
    l1 = np.linalg.norm(Pk - Ph)
    l2 = np.linalg.norm(Pa - Pk)
    d = target - Ph
    L = np.linalg.norm(d)
    L = min(max(L, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dn = d / max(np.linalg.norm(d), 1e-9)
    cosA = (l1 * l1 + L * L - l2 * l2) / (2 * l1 * L)
    cosA = min(max(cosA, -1.0), 1.0)
    sinA = math.sqrt(1 - cosA * cosA)
    pole = pole_hint - Ph
    pole = pole - np.dot(pole, dn) * dn
    if np.linalg.norm(pole) < 1e-6:
        pole = np.array([0, -1.0, 0]) - np.dot(np.array([0, -1.0, 0]), dn) * dn
    pole = pole / np.linalg.norm(pole)
    knee = Ph + dn * (l1 * cosA) + pole * (l1 * sinA)
    ankle = Ph + dn * L
    return knee, ankle


@dataclass
class CleanupReport:
    contacts: dict
    hip_drop_max_m: float
    ground_offset_m: float
    pitch_fix_deg: dict


def ground_offset(sk, R, P, fg):
    zs = []
    for s in ("L", "R"):
        heel, ball, tip, _ = sole_points(sk, R, P, fg, s)
        zs.append(np.minimum(np.minimum(heel[:, 2], ball[:, 2]), tip[:, 2]))
    z = np.minimum(zs[0], zs[1])
    return float(np.percentile(z, 10))


def detect_contacts(sk, R, P, fg, fps, h_thr=0.03, v_thr=0.30, h_max=0.09):
    """Касание точки подошвы: низко и почти неподвижна. Порог высоты — от собственного минимума точки
    (у ретаргета одна стопа может «висеть» на 3–5 см выше другой из-за наклона таза источника), но не выше h_max."""
    out = {}
    for s in ("L", "R"):
        heel, ball, tip, _ = sole_points(sk, R, P, fg, s)
        zb = np.minimum(ball[:, 2], tip[:, 2])
        th = min(h_max, max(h_thr, float(np.percentile(heel[:, 2], 5)) + h_thr))
        tb = min(h_max, max(h_thr, float(np.percentile(zb, 5)) + h_thr))
        out[s] = {"heel": contacts(heel[:, 2], hspeed(heel, fps), th, v_thr),
                  "ball": contacts(zb, hspeed(ball, fps), tb, v_thr)}
    return out


def leg_ids(sk, s):
    p = "Left" if s == "L" else "Right"
    return sk.idx(p + "UpLeg"), sk.idx(p + "Leg"), sk.idx(p + "Foot")


def apply_leg_ik(sk, R, P, s, ankle_target):
    """Поставить лодыжку ноги s в ankle_target (T,3), ориентацию стопы сохранить. Меняет R на месте."""
    iu, ik, ia = leg_ids(sk, s)
    T = len(R)
    for t in range(T):
        Ph, Pk, Pa = P[t, iu], P[t, ik], P[t, ia]
        if np.linalg.norm(ankle_target[t] - Pa) < 1e-6:
            continue
        knee, ankle = two_bone_ik(Ph, Pk, Pa, ankle_target[t], Pk + (Pk - (Ph + Pa) / 2) * 2.0)
        Rf = R[t, ia].copy()
        d1 = rot_between(Pk - Ph, knee - Ph)
        R[t, iu] = d1 @ R[t, iu]
        Pk2 = Ph + d1 @ (Pk - Ph)
        R[t, ik] = d1 @ R[t, ik]
        d2 = rot_between(d1 @ (Pa - Pk), ankle - Pk2)
        R[t, ik] = d2 @ R[t, ik]
        R[t, ia] = Rf  # мировая ориентация стопы — прежняя
    return R


def solve_foot_targets(sk, R, P, fg, con, fps, blend_out_s=0.18, hyst=0.003):
    """Фиксация опорной стопы. Пока стопа в контакте (пятка или подушечка), держится самая низкая точка подошвы
    (пятка → подушечка → носок — перекат жёсткого сапога): она запоминается там, где стоит с учётом текущей
    поправки, и дальше не двигается и стоит на полу. Поправка лодыжки c(t) непрерывна; после отрыва затухает
    за blend_out_s. Плюс подошва не ниже пола."""
    targets = {}
    for s in ("L", "R"):
        heel, ball, tip, _ = sole_points(sk, R, P, fg, s)
        pts = (heel, ball, tip)
        ia = leg_ids(sk, s)[2]
        A = P[:, ia]
        T = len(A)
        c = np.zeros((T, 3))
        cur = np.zeros(3)
        anchor, mode = None, None
        decay = math.exp(-1.0 / (blend_out_s * fps / 3.0))
        inc = con[s]["heel"] | con[s]["ball"]
        for t in range(T):
            if inc[t]:
                z = [pts[k][t, 2] + cur[2] for k in range(3)]
                k = int(np.argmin(z))
                if mode is None or (k != mode and z[k] < z[mode] - hyst):
                    anchor = pts[k][t] + cur
                    anchor[2] = 0.0
                    mode = k
                cur = anchor - pts[mode][t]
            else:
                mode = None
                cur = cur * decay
            c[t] = cur
        low = np.minimum(np.minimum(heel[:, 2], ball[:, 2]), tip[:, 2]) + c[:, 2]
        c[:, 2] += np.maximum(0.0, -low)
        targets[s] = A + c
    return targets


def rigid_toes(sk, R):
    """Пальцы — в покое относительно стопы: сапог почти не гнётся, а маркеры пальцев у mocap шумят."""
    R = R.copy()
    for s in ("Left", "Right"):
        fb, tb = sk.idx(s + "Foot"), sk.idx(s + "ToeBase")
        R[:, tb] = R[:, fb] @ (sk.rest_R[fb].T @ sk.rest_R[tb])
    return R


def lock_foot_yaw(sk, R, P, fg, con, fps, blend_out_s=0.17):
    """Пока стопа стоит плоско (пятка и подушечка на полу), её поворот вокруг вертикали не меняется:
    без этого стопа «вертится» на подушечке на 2–5° и пятка уезжает на 1–2 см. После отрыва поправка затухает."""
    R = R.copy()
    decay = math.exp(-1.0 / (blend_out_s * fps / 3.0))
    for s in ("L", "R"):
        fb = sk.idx("LeftFoot" if s == "L" else "RightFoot")
        tb = sk.idx("LeftToeBase" if s == "L" else "RightToeBase")
        axis = np.einsum("tij,j->ti", R[:, fb], fg.shoe_axis[s])
        yaw = yaw_of_dir(axis)
        flat = con[s]["heel"] & con[s]["ball"]
        cur, y0, on = 0.0, None, False
        for t in range(len(R)):
            if flat[t]:
                if not on:
                    y0 = yaw[t] + cur
                    on = True
                cur = float(np.angle(np.exp(1j * (y0 - yaw[t]))))
            else:
                on = False
                cur *= decay
            if abs(cur) > 1e-6:
                Rz = rot_z(np.float64(cur))
                R[t, fb] = Rz @ R[t, fb]
                R[t, tb] = Rz @ R[t, tb]
    return R


def cleanup(sk, R, root_P, fg, fps, con=None, iters=2):
    """Высота таза → контакты → IK ног (2 прохода: после первого таз опускается там, где нога не дотягивается)."""
    P = fk_positions(sk, R, root_P)
    z0 = ground_offset(sk, R, P, fg)
    root_P = root_P - np.array([0, 0, z0])
    P = fk_positions(sk, R, root_P)
    if con is None:
        con = detect_contacts(sk, R, P, fg, fps)
    R = rigid_toes(sk, R)
    R = lock_foot_yaw(sk, R, P, fg, con, fps)
    P = fk_positions(sk, R, root_P)
    drop_max = 0.0
    for it in range(iters):
        targets = solve_foot_targets(sk, R, P, fg, con, fps)
        # недостижимо — опустить таз (сглаженно)
        need = np.zeros(len(R))
        for s in ("L", "R"):
            iu, ik, ia = leg_ids(sk, s)
            lmax = (np.linalg.norm(sk.offsets[ik]) + np.linalg.norm(sk.offsets[ia])) * 0.995
            d = targets[s] - P[:, iu]
            dist = np.linalg.norm(d, axis=1)
            # насколько опустить бедро по вертикали, чтобы дотянуться
            h2 = np.maximum(lmax ** 2 - np.sum(d[:, :2] ** 2, axis=1), 0)
            dz_ok = -np.sqrt(h2)  # допустимая вертикаль d_z ≥ -sqrt(...)
            need = np.maximum(need, np.where(dist > lmax, np.maximum(0, dz_ok - d[:, 2]), 0))
        if need.max() > 1e-4:
            k = max(1, int(0.12 * fps))
            ker = np.hanning(2 * k + 1)
            ker /= ker.sum()
            pad = np.pad(need, k, mode="edge")
            sm = np.convolve(pad, ker, mode="valid")
            sm = np.maximum(sm, need * 0.98)
            root_P = root_P - np.stack([np.zeros_like(sm), np.zeros_like(sm), sm], 1)
            drop_max = max(drop_max, float(sm.max()))
            P = fk_positions(sk, R, root_P)
            targets = solve_foot_targets(sk, R, P, fg, con, fps)
        R = R.copy()
        for s in ("L", "R"):
            R = apply_leg_ik(sk, R, P, s, targets[s])
        P = fk_positions(sk, R, root_P)
        break
    return R, root_P, con, CleanupReport(contacts={}, hip_drop_max_m=drop_max, ground_offset_m=z0, pitch_fix_deg={})


# ---------------------------------------------------------------- замеры

def foot_metrics(sk, R, P, fg, con, fps, travel_dir=None, facing=None, eps=0.012, frames=None):
    """Проскальзывание опорной стопы (мм) и разворот ботинка (°) относительно хода (или взгляда таза для idle).
    Скольжение: точки подошвы (пятка, подушечка, носок), пока точка на полу (не выше своего минимума + eps = 1 см):
    наибольший уход по полу от места, где она встала, за одно касание. Перекат с пятки на носок скольжением не
    считается — пятка, поднявшись на 1 см, из замера выходит. Угол: кадры, где стопа стоит плоско
    (пятка и подушечка в контакте); + = носок наружу."""
    out = {}
    sel = np.zeros(len(R), bool)
    if frames is None:
        sel[:] = True
    else:
        sel[frames] = True
    pts = {s: sole_points(sk, R, P, fg, s) for s in ("L", "R")}
    allmin = np.minimum.reduce([np.minimum(np.minimum(pts[s][0][:, 2], pts[s][1][:, 2]), pts[s][2][:, 2]) for s in ("L", "R")])
    floor = float(np.percentile(allmin, 2))
    for s in ("L", "R"):
        heel, ball, tip, axis = pts[s]
        slides = []
        Z = np.stack([heel[:, 2], ball[:, 2], tip[:, 2]], 1)
        X = np.stack([heel, ball, tip], 1)
        k = np.argmin(Z, 1)
        inc = (con[s]["heel"] | con[s]["ball"]) & (Z.min(1) < floor + eps) & sel
        for a, b in intervals(inc):
            if b - a < 2:
                continue
            # опорная точка (самая низкая) не должна ехать: наибольший уход по полу от места, где она стала опорной
            worst, t0 = 0.0, a
            for t in range(a + 1, b + 1):
                if t == b or k[t] != k[t0]:
                    run = X[t0:t, k[t0], :2]
                    worst = max(worst, float(np.linalg.norm(run - run[0], axis=1).max()))
                    t0 = t
            slides.append(worst * 1000)
        flat = con[s]["heel"] & con[s]["ball"] & sel
        if flat.sum() < 2:
            flat = (con[s]["heel"] | con[s]["ball"]) & sel
        ang = None
        if flat.any():
            yaw = yaw_of_dir(axis[flat])
            if travel_dir is not None:
                ref = math.atan2(travel_dir[0], -travel_dir[1])
            else:
                ref = yaw_of_dir(facing[flat])
            rel = np.degrees(np.angle(np.exp(1j * (yaw - ref))))
            # yaw > 0 — носок к +X (влево Агаты): для левой ноги это наружу, для правой — внутрь
            sign = 1.0 if s == "L" else -1.0
            ang = float(np.median(rel) * sign)
        out[s] = {"slide_mm_max": round(max(slides), 1) if slides else None,
                  "slide_mm_median": round(float(np.median(slides)), 1) if slides else None,
                  "contacts": len(slides), "toe_out_deg": None if ang is None else round(ang, 1)}
    return out


def hips_facing(sk, R):
    """Направление взгляда таза на полу: ось кости, переходящая в −Y в покое."""
    ih = sk.idx("Hips")
    loc = sk.rest_R[ih].T @ FWD
    f = np.einsum("tij,j->ti", R[:, ih], loc)
    f[:, 2] = 0
    return unit(f)


# ---------------------------------------------------------------- петля

def loop_close(R_local, root_P, root_R, disp):
    """Распределить невязку цикла по всей петле. R_local: (N+1,B,3,3) локальные вращения (кадр N — начало следующего
    цикла), root_P (N+1,3), root_R (N+1,3,3), disp — смещение за цикл (горизонталь) → петля длиной N кадров."""
    N = len(root_P) - 1
    j = np.arange(N) / N
    out_L = np.empty((N,) + R_local.shape[1:])
    for b in range(R_local.shape[1]):
        D = R_local[N, b] @ R_local[0, b].T
        w = rot_log(D)
        out_L[:, b] = rot_exp(-j[:, None] * w) @ R_local[:N, b]
    D = root_R[N] @ root_R[0].T
    w = rot_log(D)
    out_RR = rot_exp(-j[:, None] * w) @ root_R[:N]
    lin = root_P[0] + j[:, None] * disp
    e = root_P[:N + 1] - (root_P[0] + np.arange(N + 1)[:, None] / N * disp)
    e_corr = e[:N] - j[:, None] * (e[N] - e[0])
    out_P = lin + e_corr
    return out_L, out_P, out_RR


def stance_root_motion(sk, R, root_P, fg, fps):
    """Root motion по опорной стопе (как в игре, actor_3d/player.gd): опорная — нога с более низкой точкой подошвы;
    её смещение по полу между кадрами вычитается из таза. → новый root_P и индекс опорной ноги по кадрам."""
    P = fk_positions(sk, R, root_P)
    pts = {}
    for s in ("L", "R"):
        heel, ball, tip, _ = sole_points(sk, R, P, fg, s)
        low = np.where((heel[:, 2] < ball[:, 2])[:, None], heel, ball)
        pts[s] = (low, np.minimum(heel[:, 2], ball[:, 2]))
    stance = np.where(pts["L"][1] <= pts["R"][1], 0, 1)
    acc = np.zeros(3)
    out = root_P.copy()
    for t in range(1, len(R)):
        s = "L" if stance[t] == 0 else "R"
        d = pts[s][0][t] - pts[s][0][t - 1]
        d[2] = 0
        acc = acc - d
        out[t] = root_P[t] + acc
    return out, stance


def head_hips_yaw(sk, R):
    """Рыскание головы относительно таза по кадрам (°): ось «вперёд» покоя у каждой кости."""
    def yaw(bn):
        i = sk.idx(bn)
        loc = sk.rest_R[i].T @ FWD
        f = np.einsum("tij,j->ti", R[:, i], loc)
        return np.degrees(np.arctan2(f[:, 0], -f[:, 1]))
    return (yaw("Head") - yaw("Hips") + 180) % 360 - 180


def head_offset(sk, R):
    """Средний поворот головы относительно груди (Spine) в осях покоя: рыскание (+ к +X) и крен (макушка к +X), °."""
    ic, ih = sk.idx("Spine"), sk.idx("Head")
    E = R[:, ic] @ sk.rest_R[ic].T
    F = R[:, ih] @ sk.rest_R[ih].T
    G = np.swapaxes(E, -1, -2) @ F
    Gm = rot_exp(np.median(rot_log(G), axis=0))
    f = Gm @ FWD
    u = Gm @ UP
    return math.degrees(math.atan2(f[0], -f[1])), math.degrees(math.atan2(u[0], u[2]))
