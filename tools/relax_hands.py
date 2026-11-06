#!/usr/bin/env python3
"""Кисти и плечи жителей v3 (Директор 06.11, 23:0x: «пальцы-грабли и массивные плечи — да, кисти и плечи»).

Модели Meshy без костей пальцев: кисть отлита растопыренной, пальцы торчат «граблями»; плечо и предплечье толстые.
Правится сама сетка в позе покоя (кости и клипы не трогаются — перенос клипов и проверки build_rt3d_glb остаются
верны):
  1. пальцы: всё, что дальше костяшек (доля `knuckle` длины кисти от запястья), сгибается к ладони плавной дугой
     до `curl` градусов на кончиках, и пальцы сводятся друг к другу (боковой разброс × (1 − `close` на кончиках));
     нормали этих вершин поворачиваются вместе с ними;
  2. плечо: вершины кости плеча (верх руки) сжимаются к её оси на `slim` (по весу кости) — тоньше дельта и плечо.
Ладонь — сторона наименьшего разброса вершин кисти (кисть плоская), к телу.

  python3 tools/relax_hands.py in_game.glb out_game.glb [--curl 38] [--close 0.3] [--knuckle 0.46] [--slim 0.12]
"""
from __future__ import annotations

import argparse
import math
import sys

import bpy
import mathutils
from mathutils import Matrix, Vector


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--curl", type=float, default=38.0)
    ap.add_argument("--close", type=float, default=0.3)
    ap.add_argument("--knuckle", type=float, default=0.46)
    ap.add_argument("--slim", type=float, default=0.12)
    a = ap.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=a.inp)
    arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
    W = arm.matrix_world
    head = {b.name: W @ b.head_local for b in arm.data.bones}
    report = {}
    for ob in [o for o in bpy.context.scene.objects if o.type == "MESH" and len(o.vertex_groups) > 0]:
        me = ob.data
        MW = ob.matrix_world
        MWi = MW.inverted()
        gi = {g.name: g.index for g in ob.vertex_groups}
        has_custom = me.has_custom_normals
        loop_n = [Vector(n.vector) for n in me.corner_normals] if has_custom else None
        rot_of_vert = {}   # vertex → rotation matrix (world) applied to its normals
        moved = 0
        for side in ("Left", "Right"):
            hand, fore, up = side + "Hand", side + "ForeArm", side + "Arm"
            if hand not in gi or fore not in gi:
                continue
            H, F = head[hand], head[fore]
            ax = (H - F).normalized()
            # the hand's vertices (its bone the strongest)
            hv = []
            for v in me.vertices:
                best, bw = None, 0.0
                for g in v.groups:
                    if g.weight > bw:
                        best, bw = g.group, g.weight
                if best == gi[hand]:
                    hv.append(v.index)
            if len(hv) < 50:
                continue
            P = [MW @ me.vertices[i].co for i in hv]
            # the palm's normal: the hand's flattest direction (PCA)
            c = sum(P, Vector()) / len(P)
            cov = Matrix(((0.0,) * 3,) * 3)
            for p in P:
                d = p - c
                for r in range(3):
                    for q in range(3):
                        cov[r][q] += d[r] * d[q]
            # power iteration for the largest axes, the smallest = cross of the two largest
            def top(m, skip=None):
                v = Vector((0.3, 0.5, 0.8))
                for _ in range(60):
                    v = m @ v
                    if skip is not None:
                        v -= skip * v.dot(skip)
                    v.normalize()
                return v
            e1 = top(cov)
            e2 = top(cov, e1)
            n = e1.cross(e2).normalized()
            # palm toward the body (the hand's own side is +x for Left in Blender's import of these rigs)
            out_x = 1.0 if side == "Left" else -1.0
            if n.x * out_x > 0:
                n = -n
            n = (n - ax * n.dot(ax)).normalized()
            b = ax.cross(n).normalized()
            ts = [(p - H).dot(ax) for p in P]
            L = max(ts)
            t0 = a.knuckle * L
            K = H + ax * t0
            R = max((L - t0) / max(math.radians(a.curl), 1e-3), 1e-4)
            for idx, p in zip(hv, P):
                d = p - K
                r = d.dot(ax)
                if r <= 0.0:
                    continue
                h = d.dot(n)
                w = d.dot(b)
                u = min(r / max(L - t0, 1e-6), 1.0)
                phi = r / R
                rho = R - h
                C = K + n * R
                newp = C - n * (rho * math.cos(phi)) + ax * (rho * math.sin(phi)) + b * (w * (1.0 - a.close * u))
                me.vertices[idx].co = MWi @ newp
                rot_of_vert[idx] = Matrix.Rotation(phi, 3, b)
                moved += 1
            # the upper arm thinner (its bone's weight)
            if up in gi:
                A0, A1 = head[up], head[fore]
                aa = (A1 - A0).normalized()
                for v in me.vertices:
                    wa = 0.0
                    for g in v.groups:
                        if g.group == gi[up]:
                            wa = g.weight
                    if wa <= 0.0:
                        continue
                    p = MW @ v.co
                    t = (p - A0).dot(aa)
                    if t < -0.03 or t > (A1 - A0).length + 0.02:
                        continue
                    q = A0 + aa * t
                    v.co = MWi @ (q + (p - q) * (1.0 - a.slim * wa))
        if has_custom and rot_of_vert:
            # the curled fingers' normals turned with them (the rest as they were)
            new_n = []
            for li, loop in enumerate(me.loops):
                nv = loop_n[li]
                if loop.vertex_index in rot_of_vert:
                    nv = (rot_of_vert[loop.vertex_index] @ nv).normalized()
                new_n.append(nv)
            me.normals_split_custom_set(new_n)
        me.update()
        report[ob.name] = {"finger_vertices": moved, "custom_normals": has_custom}
    print("relax_hands:", report)
    bpy.ops.export_scene.gltf(filepath=a.out, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
