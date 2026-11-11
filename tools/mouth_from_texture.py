#!/usr/bin/env python3
"""Линия губ модели по рисунку лица — для моделей без кости челюсти (Агата), где tests/bake_mouth.gd не находит разреза.

Тёмная полоса между губами на текстуре модели: вершины лица (вес кости Head/Jaw > 0,3, не дальше 3,5 см от середины,
не глубже 4 см от переда лица) в полосе высот [lo, hi] см над костью головы, яркость цвета текстуры в их UV < lum.
По ним — середина, полуширина, изгиб (как в bake_mouth: y = a + c·x², z так же); запись в формате
data/actors_rest/mouth_<id>.json (точка и оси в системе кости головы, единицы скелета).

  python3 -I tools/mouth_from_texture.py <model.glb> <lo_cm> <hi_cm> <lum>      — JSON в stdout
  python3 -I tools/mouth_from_texture.py --selfcheck                            — пересчёт запечённой точки Нины
"""
import io, json, struct, sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CT = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(p):
    b = Path(p).read_bytes()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    bl = struct.unpack("<I", b[off:off + 4])[0]
    blob = b[off + 8:off + 8 + bl]

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        dt = CT[a["componentType"]]
        k = NC[a["type"]]
        st = bv.get("byteStride")
        if st and st != k * np.dtype(dt).itemsize:
            arr = np.array([np.frombuffer(blob, dtype=dt, count=k, offset=o + r * st) for r in range(a["count"])])
        else:
            arr = np.frombuffer(blob, dtype=dt, count=a["count"] * k, offset=o).reshape(a["count"], k)
        if a.get("normalized"):
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        return arr

    def img(i):
        bv = j["bufferViews"][j["images"][i]["bufferView"]]
        o = bv.get("byteOffset", 0)
        return Image.open(io.BytesIO(blob[o:o + bv["byteLength"]])).convert("RGB")

    return j, acc, img


def frame(j, acc):
    skin = j["skins"][0]
    names = [j["nodes"][n].get("name") for n in skin["joints"]]
    ibm = acc(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    hi = names.index("Head")
    la = names.index("LeftArm")
    hp = np.linalg.inv(ibm[hi])[:3, 3]
    up = np.array([0.0, 1.0, 0.0])
    out_l = np.array([1.0, 0.0, 0.0]) * (1 if np.linalg.inv(ibm[la])[0, 3] >= 0 else -1)
    right = -out_l
    fwd = np.cross(out_l, up)
    return names, ibm, hi, hp, right, up, fwd


def to_head(ibm_h, hp, right, up, fwd, off_cm):
    """Точка (вправо, вверх, вперёд в см от кости головы, оси модели) → система кости головы (единицы скелета)."""
    mid = hp + (right * off_cm[0] + up * off_cm[1] + fwd * off_cm[2]) * 0.01
    return (ibm_h @ np.append(mid, 1.0))[:3]


def measure(path, lo, hi_cm, lum):
    j, acc, img = load(path)
    prim = j["meshes"][0]["primitives"][0]
    P = acc(prim["attributes"]["POSITION"]).astype(np.float64)
    UV = acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    J = acc(prim["attributes"]["JOINTS_0"]).astype(int)
    W = acc(prim["attributes"]["WEIGHTS_0"]).astype(np.float64)
    names, ibm, hi, hp, right, up, fwd = frame(j, acc)
    ji = names.index("Jaw") if "Jaw" in names else -9
    hw = sum(np.where((J[:, c] == hi) | (J[:, c] == ji), W[:, c], 0.0) for c in range(J.shape[1]))
    mat = j["materials"][prim["material"]]
    tex = img(j["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"])
    ta = np.asarray(tex).astype(float)
    tw, th = tex.size
    col = ta[np.clip((UV[:, 1] * th).astype(int), 0, th - 1), np.clip((UV[:, 0] * tw).astype(int), 0, tw - 1)]
    q = P - hp
    v = np.stack([q @ right, q @ up, q @ fwd], 1) * 100.0          # mesh space is metres (skin bind), → cm
    face = (hw > 0.3) & (np.abs(v[:, 0]) < 3.5)
    fmax = v[face & (np.abs(v[:, 0]) < 1.0), 2].max()
    sel = face & (v[:, 1] > lo) & (v[:, 1] < hi_cm) & (v[:, 2] > fmax - 4.0) & (col.mean(1) < lum)
    L = v[sel]
    if len(L) < 6:
        return {}
    xc = (L[:, 0].min() + L[:, 0].max()) / 2
    hwid = (L[:, 0].max() - L[:, 0].min()) / 2
    x = (L[:, 0] - xc) / hwid
    A = np.stack([np.ones_like(x), x * x], 1)
    ya, yc2 = np.linalg.lstsq(A, L[:, 1], rcond=None)[0]
    za, zc2 = np.linalg.lstsq(A, L[:, 2], rcond=None)[0]
    at = to_head(ibm[hi], hp, right, up, fwd, (xc, ya, za))
    s = np.linalg.norm(ibm[hi][:3, :3] @ right) * 0.01                 # skeleton units per cm
    nb = lambda w: (ibm[hi][:3, :3] @ w) / np.linalg.norm(ibm[hi][:3, :3] @ w)
    r4 = lambda a: [round(float(t), 4) for t in a]
    return {"at": r4(at), "back": round(float(-zc2 * s), 4), "fwd": r4(nb(fwd)), "half_w": round(float(hwid * s), 4),
            "line_pts": int(len(L)), "right": r4(nb(right)), "sag": round(float(yc2 * s), 4), "tris": 0,
            "unit_per_m": round(float(s * 100.0), 2), "up": r4(nb(up)), "from": "lip_colour",
            "_cm": [round(float(xc), 2), round(float(ya), 2), round(float(za), 2)]}


def selfcheck():
    """Запечённая точка Нины (bake_mouth, Godot) → см в осях модели → обратно этим пересчётом: до 0,01 единицы."""
    j, acc, _ = load(ROOT / "game/assets/characters/nina_v3/rt3d/nina_rt.glb")
    names, ibm, hi, hp, right, up, fwd = frame(j, acc)
    b = json.loads((ROOT / "game/data/actors_rest/mouth_nina.json").read_text())
    at = np.array(b["at"])
    off = [at @ np.array(b["right"]), at @ np.array(b["up"]), at @ np.array(b["fwd"])]
    back = to_head(ibm[hi], hp, right, up, fwd, off)
    err = float(np.abs(back - at).max())
    print("selfcheck: Nina's baked lip point re-derived, max error %.4f units" % err)
    return 0 if err < 0.01 else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--selfcheck"]:
        sys.exit(selfcheck())
    r = measure(sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]))
    print(json.dumps(r, ensure_ascii=False))
    sys.exit(0 if r else 1)
