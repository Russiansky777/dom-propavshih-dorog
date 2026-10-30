"""Юбка Агаты на своих костях (Директор 30.10, 19:16: «сгибы юбки не красиво»; «подумай, как сделать идеальную Агату»).

Причина: автоматическая оснастка Meshy привязала юбку к ногам — подол (0,2–0,5 м) к голеням, середину к бёдрам; при шаге
юбка делится на две «штанины» и ломается складками между ними. Здесь юбке даются свои кости: кольцо из N цепочек от
бёдер до подола (по 3 кости, родитель — Hips), вершины юбки взвешиваются на них плавно по углу и высоте (у пояса — наплыв
к прежним весам), голени и бёдра юбку больше не тянут. В игре цепочки качает SpringBoneSimulator3D (Godot 4.7) с упором
о капсулы ног (rt3d.skirt, game/scripts/actors/actor_3d.gd): колено толкает подол, при повороте юбка запаздывает.
Клипы, сетка, текстура и прежние 24 кости не меняются (проверка после экспорта: кости клипов совпадают до 1 мм).

Коса (Директор 30.10, 23:22: «так почему не делаешь?!» — коса и сумка на пружинах): цепочка Braid0..2 от затылка до
кончика (родитель — Head); вершины косы — тёмные (волосы) позади шали, узкой полосой по середине спины, с наплывом к
голове у затылка. В игре её качает свой SpringBoneSimulator3D с упором о спину (rt3d.springs).
Сумка (--bag, по умолчанию выключена): одна кость Bag0 (родитель — Hips) от верха сумки к середине дна. Пробы 30.10:
сумка и пальто в сетке Meshy — общие лоскуты, ни цвет кожи, ни лоскуты не отделяют сумку чисто — при качании на 15°
в ней дыры. Нужна отдельная сетка сумки (конвейер) или ручная разметка.

    python3.13 tools/rig_skirt.py --glb game/assets/characters/agata/rt3d/agata_v4_rt.glb --out /tmp/agata_skirt.glb \
        --report /tmp/agata_skirt.json
Нужен Python 3.13 с bpy 5.2.2 (pipeline/requirements.txt). 0 кредитов.
"""
import argparse
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

LEG = {"LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "Hips"}


FPS = 30  # клипы Meshy — 30 кадров/с (как pipeline/3d/build_rt3d_glb.py); при 24 экспорт пересэмплировал бы их


def clean() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0


def import_glb(path: Path):
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()), disable_bone_shape=True)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if any(c.name == "glTF_not_exported" for c in o.users_collection):
            bpy.data.objects.remove(o, do_unlink=True)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH"]
    acts = [a for a in bpy.data.actions if a not in acts_before]
    return arm, meshes, acts


def assign(arm, act) -> None:
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data
    ad.action = act
    if hasattr(ad, "action_slot") and ad.action_slot is None and hasattr(act, "slots") and len(act.slots):
        ad.action_slot = act.slots[0]


def sample(arm, act, bones, frames) -> dict:
    assign(arm, act)
    out = {}
    for f in frames:
        bpy.context.scene.frame_set(int(f))
        bpy.context.view_layer.update()
        out[f] = {b: tuple(arm.matrix_world @ arm.pose.bones[b].head) for b in bones if b in arm.pose.bones}
    return out


def smooth(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def texture_colours(mesh) -> dict:
    """Цвет текстуры (base color) в каждой вершине — по её первой развёртке."""
    img = None
    for mat in mesh.data.materials:
        if mat is None or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None and (img is None or "Base" in n.image.name):
                img = n.image
    if img is None:
        return {}
    w, h = img.size
    px = img.pixels[:]
    uv = mesh.data.uv_layers.active.data
    out = {}
    for poly in mesh.data.polygons:
        for li in poly.loop_indices:
            vi = mesh.data.loops[li].vertex_index
            if vi in out:
                continue
            u, v = uv[li].uv
            x = min(max(int(u * w), 0), w - 1)
            y = min(max(int(v * h), 0), h - 1)
            i = (y * w + x) * 4
            out[vi] = (px[i], px[i + 1], px[i + 2])
    return out


def islands(mesh) -> list:
    """Связные куски сетки (по рёбрам)."""
    n = len(mesh.data.vertices)
    par = list(range(n))

    def find(a: int) -> int:
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a

    for e in mesh.data.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            par[a] = b
    out: dict = {}
    for i in range(n):
        out.setdefault(find(i), []).append(i)
    return list(out.values())


def rig_braid(arm, mesh, args, report: dict) -> None:
    """Коса: цепочка Braid0..N-1 (родитель Head) по середине косы; вершины косы — на ней, у затылка — наплыв к голове."""
    levels = [float(x) for x in args.braid.split(",")]
    b0, b1 = [float(x) for x in args.braid_fade.split(",")]
    neck = arm.matrix_world @ arm.data.bones["neck"].head_local
    col = texture_colours(mesh)
    mw = mesh.matrix_world
    names = {g.index: g.name for g in mesh.vertex_groups}
    sel = []
    for v in mesh.data.vertices:
        p = mw @ v.co
        if p.z < levels[-1] - 0.03 or p.z > b1:
            continue
        if abs(p.x - neck.x) > args.braid_half or p.y - neck.y < args.braid_back - 0.02:
            continue
        c = col.get(v.index, (1.0, 1.0, 1.0))
        if 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] > args.braid_lum:
            continue
        sel.append(v.index)
    # сетка Meshy — из лоскутов (отдельных кусков поверхности): лоскут, который в основном коса, идёт целиком — иначе
    # светлые пряди и кончик оставались на шали тёмными клиньями; лоскут, где косы мало, — не коса
    isl = islands(mesh)
    chosen = set(sel)
    full = []
    for vs in isl:
        k = sum(1 for i in vs if i in chosen)
        if k and k >= 0.4 * len(vs):
            full.extend(vs)
    sel = full
    # середина косы на каждом уровне
    joints = []
    for z in levels:
        pts = [mw @ mesh.data.vertices[i].co for i in sel if abs((mw @ mesh.data.vertices[i].co).z - z) < 0.015]
        if not pts:
            pts = [mw @ mesh.data.vertices[i].co for i in sel]
        joints.append(Vector((sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), z)))
    report["braid_vertices"] = len(sel)
    report["braid_joints"] = [[round(x, 3) for x in j] for j in joints]
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    inv = arm.matrix_world.inverted()
    parent = eb["Head"]
    for k in range(len(levels) - 1):
        b = eb.new(f"Braid{k}")
        b.head = inv @ joints[k]
        b.tail = inv @ joints[k + 1]
        b.roll = 0.0
        b.parent = parent
        b.use_connect = k > 0
        b.use_deform = True
        parent = b
    bpy.ops.object.mode_set(mode="OBJECT")
    mids = [(levels[k] + levels[k + 1]) * 0.5 for k in range(len(levels) - 1)]
    for idx in sel:
        v = mesh.data.vertices[idx]
        p = mw @ v.co
        if p.z >= mids[0]:
            vert_w = {0: 1.0}
        elif p.z <= mids[-1]:
            vert_w = {len(mids) - 1: 1.0}
        else:
            vert_w = {}
            for k in range(len(mids) - 1):
                if mids[k + 1] <= p.z <= mids[k]:
                    u = (mids[k] - p.z) / (mids[k] - mids[k + 1])
                    vert_w = {k: 1.0 - u, k + 1: u}
                    break
        s = 1.0 - smooth(b0, b1, p.z)          # 1 — только кости косы, 0 — прежние веса (голова)
        old = {names[g.group]: g.weight for g in v.groups}
        tot_old = sum(old.values()) or 1.0
        new = {nm: (1.0 - s) * w / tot_old for nm, w in old.items()}
        if s < 1.0:
            # у затылка коса уходит в волосы головы: прежняя часть — голове (не плечам), чтобы коса шла с головой
            hold = sum(new.values())
            new = {"Head": hold}
        for k, wk in vert_w.items():
            nm = f"Braid{k}"
            new[nm] = new.get(nm, 0.0) + s * wk
        top = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tw = sum(w for _, w in top) or 1.0
        keep = {nm: w / tw for nm, w in top if w / tw > 0.002}
        for g in list(v.groups):
            mesh.vertex_groups[g.group].remove([idx])
        for nm, w in keep.items():
            vg = mesh.vertex_groups.get(nm) or mesh.vertex_groups.new(name=nm)
            vg.add([idx], w, "REPLACE")


def rig_bag(arm, mesh, args, report: dict) -> None:
    """Сумка: кость Bag0 (родитель Hips) от верха сумки к середине дна; сумка на ней целиком, у верха — наплыв."""
    z0, z1 = [float(x) for x in args.bag.split(",")]
    hips = arm.matrix_world @ arm.data.bones["Hips"].head_local
    col = texture_colours(mesh)
    mw = mesh.matrix_world
    names = {g.index: g.name for g in mesh.vertex_groups}
    side = args.bag_side
    sel = []
    for v in mesh.data.vertices:
        p = mw @ v.co
        if not (z0 < p.z < z1):
            continue
        if (p.x - hips.x) * (1.0 if side > 0 else -1.0) < abs(side):
            continue
        dom = max(((g.weight, names[g.group]) for g in v.groups), default=(0.0, "-"))[1]
        if "Arm" in dom or "Hand" in dom:
            continue
        c = col.get(v.index, (0.0, 0.0, 0.0))
        if c[0] - c[2] < args.bag_warm:
            continue
        sel.append(v.index)
    # уверенные вершины сумки задают её коробку (2–98 % по каждой оси — без случайных пятен на пальто); сумка —
    # лоскуты сетки, лежащие в коробке почти целиком, с кожей теплее пальто (пальто у бедра — 0,09–0,10, кожа сумки
    # темнее в тени, но теплее). Цвет по вершине оставлял на сумке дыры (тёмная кожа клапана), лоскуты — нет.
    seeds = [mw @ mesh.data.vertices[i].co for i in sel]

    def pct(vals, q):
        vals = sorted(vals)
        return vals[min(max(int(q * (len(vals) - 1)), 0), len(vals) - 1)]

    lo = Vector((pct([p.x for p in seeds], 0.02), pct([p.y for p in seeds], 0.02), pct([p.z for p in seeds], 0.02))) - Vector((0.01, 0.01, 0.01))
    hi = Vector((pct([p.x for p in seeds], 0.98), pct([p.y for p in seeds], 0.98), pct([p.z for p in seeds], 0.98))) + Vector((0.01, 0.01, 0.01))
    report["bag_box"] = [[round(x, 3) for x in lo], [round(x, 3) for x in hi]]
    full = []
    for vs in islands(mesh):
        inside = 0
        warm = 0.0
        for i in vs:
            p = mw @ mesh.data.vertices[i].co
            if lo.x <= p.x <= hi.x and lo.y <= p.y <= hi.y and lo.z <= p.z <= hi.z:
                inside += 1
            c = col.get(i, (0.0, 0.0, 0.0))
            warm += c[0] - c[2]
        if inside >= 0.9 * len(vs) and warm / len(vs) > args.bag_island_warm:
            full.extend(vs)
    sel = full
    pts = [mw @ mesh.data.vertices[i].co for i in sel]
    top = max(p.z for p in pts)
    bot = min(p.z for p in pts)
    up = [p for p in pts if p.z > top - 0.03]
    dn = [p for p in pts if p.z < bot + 0.03]
    head = Vector((sum(p.x for p in up) / len(up), sum(p.y for p in up) / len(up), top - 0.01))
    tail = Vector((sum(p.x for p in dn) / len(dn), sum(p.y for p in dn) / len(dn), bot + 0.01))
    report["bag_vertices"] = len(sel)
    report["bag_bone"] = [[round(x, 3) for x in head], [round(x, 3) for x in tail]]
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    inv = arm.matrix_world.inverted()
    b = eb.new("Bag0")
    b.head = inv @ head
    b.tail = inv @ tail
    b.roll = 0.0
    b.parent = eb["Hips"]
    b.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    vg = mesh.vertex_groups.get("Bag0") or mesh.vertex_groups.new(name="Bag0")
    for idx in sel:
        v = mesh.data.vertices[idx]
        p = mw @ v.co
        s = 1.0 - smooth(top - args.bag_fade, top, p.z)       # 1 — только сумка, 0 — прежние веса (ремень, таз)
        old = {names[g.group]: g.weight for g in v.groups}
        tot_old = sum(old.values()) or 1.0
        new = {nm: (1.0 - s) * w / tot_old for nm, w in old.items()}
        new["Bag0"] = new.get("Bag0", 0.0) + s
        top4 = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tw = sum(w for _, w in top4) or 1.0
        keep = {nm: w / tw for nm, w in top4 if w / tw > 0.002}
        for g in list(v.groups):
            mesh.vertex_groups[g.group].remove([idx])
        for nm, w in keep.items():
            g = mesh.vertex_groups.get(nm) or mesh.vertex_groups.new(name=nm)
            g.add([idx], w, "REPLACE")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--report", default="")
    ap.add_argument("--chains", type=int, default=8)
    ap.add_argument("--levels", default="0.80,0.62,0.44,0.26", help="высоты суставов цепочки сверху вниз, м (последняя — низ третьей кости)")
    ap.add_argument("--hem", type=float, default=0.19, help="ниже — сапоги, не юбка")
    ap.add_argument("--leg_reach", type=float, default=0.15, help="ближе к голени — низ юбки частично идёт за ногой (м)")
    ap.add_argument("--leg_top", type=float, default=0.40, help="выше — юбка совсем не идёт за голенью (м)")
    ap.add_argument("--fade", default="0.72,0.86", help="наплыв к прежним весам у пояса: полностью кости юбки ниже первой, прежние — выше второй")
    ap.add_argument("--inset", type=float, default=0.85, help="сустав внутри юбки: доля её радиуса")
    ap.add_argument("--braid", default="1.36,1.30,1.25,1.20", help="суставы косы сверху вниз, м (пусто — без косы)")
    ap.add_argument("--braid_fade", default="1.34,1.39", help="наплыв косы к голове: ниже первой — только кости косы, выше второй — голова")
    ap.add_argument("--braid_half", type=float, default=0.05, help="коса — не дальше этого от середины спины по ширине, м")
    ap.add_argument("--braid_back", type=float, default=0.14, help="коса — дальше этого назад от оси, м (шаль ближе)")
    ap.add_argument("--braid_lum", type=float, default=0.22, help="коса — темнее этого (волосы; шаль светлая)")
    ap.add_argument("--bag", default="", help="сумка — по высоте от и до, м, например 0.70,1.0 (пусто — без сумки; пока выключена: "
                    "в сетке Meshy сумка и пальто — общие лоскуты, ни цвет, ни лоскуты не отделяют её чисто — при качании дыры, "
                    "кадры 30.10 в Docs/DECISIONS.md)")
    ap.add_argument("--bag_side", type=float, default=-0.11, help="сумка — дальше этого вбок от середины таза, м (знак — сторона: − правая)")
    ap.add_argument("--bag_warm", type=float, default=0.17, help="сумка — красно-коричневая кожа: красный минус синий больше этого")
    ap.add_argument("--bag_island_warm", type=float, default=0.12, help="лоскут сумки — в среднем теплее этого (пальто 0,09–0,10)")
    ap.add_argument("--bag_fade", type=float, default=0.03, help="у верха сумки столько метров — наплыв к прежним весам (ремень)")
    args = ap.parse_args()
    levels = [float(x) for x in args.levels.split(",")]
    f0, f1 = [float(x) for x in args.fade.split(",")]
    report: dict = {"glb": args.glb}

    clean()
    arm, meshes, acts = import_glb(Path(args.glb))
    mesh = max(meshes, key=lambda o: len(o.data.vertices))
    report["clips"] = sorted(a.name for a in acts)
    hips = arm.matrix_world @ arm.data.bones["Hips"].head_local
    cx, cy = hips.x, hips.y
    shins = []
    for side in ("Left", "Right"):
        a = arm.matrix_world @ arm.data.bones[side + "Leg"].head_local
        b = arm.matrix_world @ arm.data.bones[side + "Foot"].head_local
        shins.append((a, b))

    def shin_dist(p: Vector) -> float:
        best = 9.0
        for a, b in shins:
            ab = b - a
            t = min(max((p - a).dot(ab) / max(ab.length_squared, 1e-9), 0.0), 1.0)
            best = min(best, (a + ab * t - p).length)
        return best

    names = {g.index: g.name for g in mesh.vertex_groups}
    mw = mesh.matrix_world
    # вершины юбки: от сапог до пояса, ведущая кость — нога или таз, не сапог
    sel = []
    for v in mesh.data.vertices:
        p = mw @ v.co
        if p.z < args.hem or p.z > f1:
            continue
        ws = [(g.weight, names[g.group]) for g in v.groups if g.weight > 0.0]
        if not ws:
            continue
        dom = max(ws)[1]
        if dom not in LEG:
            continue
        sel.append(v.index)
    report["skirt_vertices"] = len(sel)

    # радиус юбки по углу и высоте (для суставов)
    n = args.chains
    step = 2.0 * math.pi / n
    rad = {}
    for idx in sel:
        p = mw @ mesh.data.vertices[idx].co
        ang = math.atan2(p.x - cx, p.y - cy) % (2.0 * math.pi)
        c = int(round(ang / step)) % n
        k = min(range(len(levels)), key=lambda i: abs(levels[i] - p.z))
        if abs(levels[k] - p.z) < 0.05:
            r = math.hypot(p.x - cx, p.y - cy)
            rad[(c, k)] = max(rad.get((c, k), 0.0), r)
    joints = {}
    for c in range(n):
        ang = c * step
        for k, z in enumerate(levels):
            r = rad.get((c, k)) or rad.get((c, k - 1)) or 0.15
            r *= args.inset
            joints[(c, k)] = Vector((cx + r * math.sin(ang), cy + r * math.cos(ang), z))
    report["joints"] = {f"{c}_{k}": [round(x, 3) for x in joints[(c, k)]] for (c, k) in joints}

    # кости: Skirt<c>_<k>, k = 0..2, от сустава k к k+1; первая — дочь Hips
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    inv = arm.matrix_world.inverted()
    for c in range(n):
        parent = eb["Hips"]
        for k in range(len(levels) - 1):
            b = eb.new(f"Skirt{c}_{k}")
            b.head = inv @ joints[(c, k)]
            b.tail = inv @ joints[(c, k + 1)]
            b.roll = 0.0
            b.parent = parent
            b.use_connect = k > 0
            b.use_deform = True
            parent = b
    bpy.ops.object.mode_set(mode="OBJECT")

    # веса: по углу — две соседние цепочки, по высоте — кости между серединами; у пояса — наплыв к прежним
    groups = {}
    for c in range(n):
        for k in range(len(levels) - 1):
            nm = f"Skirt{c}_{k}"
            groups[nm] = mesh.vertex_groups.get(nm) or mesh.vertex_groups.new(name=nm)
    mids = [(levels[k] + levels[k + 1]) * 0.5 for k in range(len(levels) - 1)]
    for idx in sel:
        v = mesh.data.vertices[idx]
        p = mw @ v.co
        ang = math.atan2(p.x - cx, p.y - cy) % (2.0 * math.pi)
        a = int(math.floor(ang / step)) % n
        t = (ang - a * step) / step
        chain_w = {a: 1.0 - t, (a + 1) % n: t}
        # по высоте
        if p.z >= mids[0]:
            vert_w = {0: 1.0}
        elif p.z <= mids[-1]:
            vert_w = {len(mids) - 1: 1.0}
        else:
            vert_w = {}
            for k in range(len(mids) - 1):
                if mids[k + 1] <= p.z <= mids[k]:
                    u = (mids[k] - p.z) / (mids[k] - mids[k + 1])
                    vert_w = {k: 1.0 - u, k + 1: u}
                    break
        s = 1.0 - smooth(f0, f1, p.z)        # 1 — только кости юбки, 0 — прежние веса
        # у самых голеней низ юбки и голенища идут за ногой, как прежде: переход к костям юбки — полосой, без шва
        # (иначе ткань между подолом и сапогом растягивается серыми клиньями)
        d_shin = shin_dist(p)
        k = min(max((args.leg_reach - d_shin) / (args.leg_reach - 0.05), 0.0), 1.0) * min(max((args.leg_top - p.z) / 0.14, 0.0), 1.0)
        s *= 1.0 - k
        old = {names[g.group]: g.weight for g in v.groups}
        tot_old = sum(old.values()) or 1.0
        new = {}
        for nm, w in old.items():
            new[nm] = (1.0 - s) * w / tot_old
        for c, wc in chain_w.items():
            for k, wk in vert_w.items():
                nm = f"Skirt{c}_{k}"
                new[nm] = new.get(nm, 0.0) + s * wc * wk
        # не больше 4 влияний (как в игре): самые сильные, нормированные
        top = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tw = sum(w for _, w in top) or 1.0
        keep = {nm: w / tw for nm, w in top if w / tw > 0.002}
        for g in list(v.groups):
            mesh.vertex_groups[g.group].remove([idx])
        for nm, w in keep.items():
            vg = mesh.vertex_groups.get(nm) or mesh.vertex_groups.new(name=nm)
            vg.add([idx], w, "REPLACE")

    if args.braid.strip():
        rig_braid(arm, mesh, args, report)
    if args.bag.strip():
        rig_bag(arm, mesh, args, report)

    # клипы: каждое действие — дорожка NLA (экспорт ACTIONS берёт все по именам, как build_rt3d_glb.py)
    ranges = {a.name: tuple(a.frame_range) for a in acts}
    ref_bones = ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
    reference = {}
    for act in acts:
        fr = act.frame_range
        frames = [fr[0], (fr[0] + fr[1]) * 0.5, fr[1]]
        reference[act.name] = sample(arm, act, ref_bones, frames)
    ad = arm.animation_data
    ad.action = None
    for act in acts:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(act.frame_range[0]), act)
        st.name = act.name
        tr.mute = True

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kw = dict(filepath=str(out.resolve()), export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
              export_force_sampling=True, export_skins=True, export_morph=False, export_apply=False, export_yup=True,
              export_image_format="JPEG", export_jpeg_quality=90, export_optimize_animation_size=True,
              export_reset_pose_bones=True, export_def_bones=False, export_extras=False)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError as e:
        print("экспортёр отклонил параметр:", e, flush=True)
        for k in ("export_jpeg_quality", "export_optimize_animation_size", "export_reset_pose_bones", "export_def_bones", "export_extras"):
            kw.pop(k, None)
        bpy.ops.export_scene.gltf(**kw)
    report["out_bytes"] = out.stat().st_size

    # проверка: клипы и прежние кости те же
    clean()
    rarm, rmeshes, racts = import_glb(out)
    report["bones"] = len(rarm.data.bones)
    report["clips_out"] = sorted(a.name for a in racts)
    worst = 0.0
    for a in racts:
        nm = a.name
        if nm not in reference:
            continue
        got = sample(rarm, a, ref_bones, list(reference[nm].keys()))
        for f, bones in reference[nm].items():
            for b, pos in bones.items():
                worst = max(worst, (Vector(pos) - Vector(got[f][b])).length)
    report["worst_bone_mm"] = round(worst * 1000.0, 3)
    report["frame_ranges_same"] = all(tuple(a.frame_range) == ranges.get(a.name, tuple(a.frame_range)) for a in racts)
    print(json.dumps({k: v for k, v in report.items() if k != "joints"}, ensure_ascii=False), flush=True)
    if args.report:
        Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = report["clips_out"] == report["clips"] and worst < 0.001 and report["frame_ranges_same"]
    return 0 if ok else 3


if __name__ == "__main__":
    raise SystemExit(main())
