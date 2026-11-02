"""Юбка Агаты: перевес полос подола, привязанных к голеням (Директор 01.11, стр. 3: «при шагании ноги выпирают будто штаны
из-под юбки»).

tools/rig_skirt.py привязывал низ юбки у самых голеней частично к ногам (--leg_reach 0.15 --leg_top 0.40), чтобы между
подолом и сапогом не тянулись серые клинья: юбка тогда висела на пружинах неподвижно, и эти полосы за голенью и были
«штанами». С 01.11 подол несут ноги (rt3d.skirt.drive, SkirtDrive) — полосы можно сузить. Этот скрипт меняет в готовом
GLB только веса вершин юбки (JOINTS_0 / WEIGHTS_0 той же длины, на месте) по той же формуле rig_skirt.py с новыми
leg_reach / leg_top; всё остальное — сетка, кости, клипы, текстуры — побайтно то же (проверка в конце). Blender не нужен.

    python3 tools/reweight_skirt_glb.py --glb game/assets/characters/agata/rt3d/agata_v4_rt.glb --out /tmp/a.glb \\
        --leg_reach 0.06 --leg_top 0.26 [--report /tmp/a.json]

Формула (rig_skirt.py): s = (1 − smooth(fade0, fade1, z)) · (1 − k), k = clamp((leg_reach − d) / (leg_reach − 0.05)) ·
clamp((leg_top − z) / leg_band), d — расстояние до отрезка голени (LeftLeg→LeftFoot, RightLeg→RightFoot); вес вершины =
(1 − s) · прежние (не юбочные) веса + s · веса костей юбки (две соседние цепочки по углу, две кости по высоте); не больше
4 влияний, по убыванию, нормировано. Прежние не юбочные веса — нынешние без костей юбки (нормированные); вершины, у
которых их нет (s было 1), не меняются: новые k не больше прежних.
"""
import argparse
import json
import math
import struct
from pathlib import Path

LEG = {"LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "Hips"}


def smooth(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def read_glb(path: Path):
    b = path.read_bytes()
    magic, ver, length = struct.unpack_from("<III", b, 0)
    assert magic == 0x46546C67, "not a GLB"
    jl, jt = struct.unpack_from("<II", b, 12)
    js = json.loads(b[20:20 + jl])
    bl, bt = struct.unpack_from("<II", b, 20 + jl)
    bin_off = 28 + jl
    return b, js, bin_off


def accessor(b: bytes, js: dict, bin_off: int, i: int):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    fmt = {5126: "f", 5121: "B", 5123: "H", 5125: "I"}[a["componentType"]]
    size = struct.calcsize(fmt)
    stride = bv.get("byteStride", n * size)
    start = bin_off + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = []
    for k in range(a["count"]):
        out.append(struct.unpack_from("<" + fmt * n, b, start + k * stride))
    return out, start, stride, fmt, n


def mat4_inv_translation(m) -> tuple:
    """Joint origin in mesh space from an inverse bind matrix (column-major, rigid × uniform scale)."""
    # m maps mesh → joint; its inverse's translation is −R⁻¹·t, R⁻¹ = Rᵀ / s²
    r = [[m[0], m[4], m[8]], [m[1], m[5], m[9]], [m[2], m[6], m[10]]]
    t = [m[12], m[13], m[14]]
    s2 = r[0][0] ** 2 + r[1][0] ** 2 + r[2][0] ** 2
    return tuple(-(r[0][c] * t[0] + r[1][c] * t[1] + r[2][c] * t[2]) / s2 for c in range(3))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--report", default="")
    ap.add_argument("--leg_reach", type=float, default=0.06)
    ap.add_argument("--leg_top", type=float, default=0.26)
    ap.add_argument("--leg_band", type=float, default=0.14, help="высота перехода над leg_top (м), как в rig_skirt.py")
    ap.add_argument("--levels", default="0.80,0.62,0.44,0.26")
    ap.add_argument("--hem", type=float, default=0.19)
    ap.add_argument("--fade", default="0.72,0.86")
    ap.add_argument("--old_reach", type=float, default=0.15)
    ap.add_argument("--old_top", type=float, default=0.40)
    args = ap.parse_args()
    levels = [float(x) for x in args.levels.split(",")]
    mids = [(levels[k] + levels[k + 1]) * 0.5 for k in range(len(levels) - 1)]
    f0, f1 = [float(x) for x in args.fade.split(",")]

    src = Path(args.glb)
    b, js, bin_off = read_glb(src)
    prim = js["meshes"][0]["primitives"][0]["attributes"]
    pos, *_ = accessor(b, js, bin_off, prim["POSITION"])
    joints, j_start, j_stride, j_fmt, _ = accessor(b, js, bin_off, prim["JOINTS_0"])
    weights, w_start, w_stride, w_fmt, _ = accessor(b, js, bin_off, prim["WEIGHTS_0"])
    skin = js["skins"][0]
    names = [js["nodes"][j]["name"] for j in skin["joints"]]
    ibm, *_ = accessor(b, js, bin_off, skin["inverseBindMatrices"])
    origin = {names[i]: mat4_inv_translation(ibm[i]) for i in range(len(names))}
    idx = {n: i for i, n in enumerate(names)}
    n_chain = 0
    while f"Skirt{n_chain}_0" in idx:
        n_chain += 1
    step = 2.0 * math.pi / n_chain

    # glTF is Y-up; rig_skirt.py worked in Blender's Z-up world: (x, y, z)_blender = (x, −z, y)_gltf
    def bl(p):
        return (p[0], -p[2], p[1])

    hx, hy, _ = bl(origin["Hips"])
    shins = [(bl(origin[s + "Leg"]), bl(origin[s + "Foot"])) for s in ("Left", "Right")]

    def shin_dist(p) -> float:
        best = 9.0
        for a, c in shins:
            ab = [c[i] - a[i] for i in range(3)]
            ll = sum(x * x for x in ab) or 1e-9
            t = min(max(sum((p[i] - a[i]) * ab[i] for i in range(3)) / ll, 0.0), 1.0)
            best = min(best, math.dist(p, [a[i] + ab[i] * t for i in range(3)]))
        return best

    def k_leg(p, reach, top) -> float:
        return min(max((reach - shin_dist(p)) / (reach - 0.05), 0.0), 1.0) * min(max((top - p[2]) / args.leg_band, 0.0), 1.0)

    def skirt_w(p) -> dict:
        ang = math.atan2(p[0] - hx, p[1] - hy) % (2.0 * math.pi)
        a = int(math.floor(ang / step)) % n_chain
        t = (ang - a * step) / step
        chain_w = {a: 1.0 - t, (a + 1) % n_chain: t}
        if p[2] >= mids[0]:
            vert_w = {0: 1.0}
        elif p[2] <= mids[-1]:
            vert_w = {len(mids) - 1: 1.0}
        else:
            vert_w = {}
            for k in range(len(mids) - 1):
                if mids[k + 1] <= p[2] <= mids[k]:
                    u = (mids[k] - p[2]) / (mids[k] - mids[k + 1])
                    vert_w = {k: 1.0 - u, k + 1: u}
                    break
        out = {}
        for c, wc in chain_w.items():
            for k, wk in vert_w.items():
                out[f"Skirt{c}_{k}"] = out.get(f"Skirt{c}_{k}", 0.0) + wc * wk
        return out

    out = bytearray(b)
    rep = {"glb": str(src), "leg_reach": args.leg_reach, "leg_top": args.leg_top, "chains": n_chain}
    changed = 0
    selected = 0
    check_dev = 0.0
    check_n = 0
    s_dev = 0.0
    s_sum = 0.0
    s_cnt = 0
    leg_w_before = 0.0
    leg_w_after = 0.0
    legs4 = {"LeftLeg", "RightLeg", "LeftUpLeg", "RightUpLeg"}
    for vi, pg in enumerate(pos):
        p = bl(pg)
        if p[2] < args.hem or p[2] > f1:
            continue
        cur = {}
        for j, w in zip(joints[vi], weights[vi]):
            if w > 0.0:
                cur[names[j]] = cur.get(names[j], 0.0) + w
        if not cur:
            continue
        sk_now = sum(w for n, w in cur.items() if n.startswith("Skirt"))
        dom = max(cur.items(), key=lambda kv: kv[1])[0]
        if sk_now <= 0.0 and dom not in LEG:
            continue
        selected += 1
        old = {n: w for n, w in cur.items() if not n.startswith("Skirt")}
        tot_old = sum(old.values())
        s_fade = 1.0 - smooth(f0, f1, p[2])
        s_old = s_fade * (1.0 - k_leg(p, args.old_reach, args.old_top))
        s_new = s_fade * (1.0 - k_leg(p, args.leg_reach, args.leg_top))
        sw = skirt_w(p)
        if sk_now > 0.999 and tot_old <= 1e-6:
            # the formula against what rig_skirt.py wrote (pure skirt vertices): the same chains and bones
            tot = sum(sw.values())
            top = dict(sorted(sw.items(), key=lambda kv: kv[1], reverse=True)[:4])
            tt = sum(top.values()) or 1.0
            dev = max(abs(top.get(n, 0.0) / tt - cur.get(n, 0.0)) for n in set(top) | set(cur))
            check_dev = max(check_dev, dev)
            check_n += 1
            continue
        if sk_now > 0.0:
            s_dev = max(s_dev, abs(sk_now - s_old))   # the skirt share rig_skirt.py gave this vertex, as the formula has it
            s_sum += abs(sk_now - s_old)
            s_cnt += 1
        if tot_old <= 1e-6 or s_new <= s_old + 1e-4:
            continue
        leg_w_before += sum(w for n, w in cur.items() if n in legs4)
        new = {n: (1.0 - s_new) * w / tot_old for n, w in old.items()}
        for n, w in sw.items():
            new[n] = new.get(n, 0.0) + s_new * w
        top = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tw = sum(w for _, w in top) or 1.0
        keep = [(n, w / tw) for n, w in top if w / tw > 0.002]
        tk = sum(w for _, w in keep) or 1.0
        keep = [(n, w / tk) for n, w in keep]
        leg_w_after += sum(w for n, w in keep if n in legs4)
        jj = [idx[n] for n, _ in keep] + [0] * (4 - len(keep))
        ww = [w for _, w in keep] + [0.0] * (4 - len(keep))
        struct.pack_into("<" + j_fmt * 4, out, j_start + vi * j_stride, *jj)
        struct.pack_into("<" + w_fmt * 4, out, w_start + vi * w_stride, *ww)
        changed += 1
    rep.update({"skirt_vertices": selected, "changed": changed, "formula_check_vertices": check_n,
                "formula_check_max_dev": round(check_dev, 4), "skirt_share_max_dev": round(s_dev, 4), "skirt_share_mean_dev": round(s_sum / max(s_cnt, 1), 4), "leg_weight_sum_before": round(leg_w_before, 1),
                "leg_weight_sum_after": round(leg_w_after, 1)})
    # everything but the two attribute views is byte for byte the same
    spans = []
    for a in (prim["JOINTS_0"], prim["WEIGHTS_0"]):
        bv = js["bufferViews"][js["accessors"][a]["bufferView"]]
        s0 = bin_off + bv.get("byteOffset", 0)
        spans.append((s0, s0 + bv["byteLength"]))
    diff_out = 0
    for i in range(0, len(b), 4096):
        if b[i:i + 4096] != out[i:i + 4096]:
            for k in range(i, min(i + 4096, len(b))):
                if b[k] != out[k] and not any(s0 <= k < s1 for s0, s1 in spans):
                    diff_out += 1
    rep["bytes_changed_outside_weights"] = diff_out
    rep["size_same"] = len(out) == len(b)
    Path(args.out).write_bytes(bytes(out))
    print(json.dumps(rep, ensure_ascii=False))
    if args.report:
        Path(args.report).write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = diff_out == 0 and len(out) == len(b) and check_dev < 0.02 and s_sum / max(s_cnt, 1) < 0.01 and s_dev < 0.15
    return 0 if ok else 3


if __name__ == "__main__":
    raise SystemExit(main())
