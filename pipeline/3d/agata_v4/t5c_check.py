"""T5c — проверка GLB по всем клипам (каждый 3-й кадр): у сумки (≤ 10 см от кожи сумки в покое) нет вытянутых
рёбер («солома»: ребро длиннее, чем в покое, в 1,5+ раза), кисть не входит в сумку (зазор кисть ↔ кожа сумки).
  python3.13 pipeline/3d/agata_v4/t5c_check.py <glb> <отчёт.json> [шаг]"""
import bpy, sys, json, numpy as np
from scipy.spatial import cKDTree
glb, out_p = sys.argv[1], sys.argv[2]; step = int(sys.argv[3]) if len(sys.argv) > 3 else 3
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb, disable_bone_shape=True)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
o = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda m: len(m.data.vertices)); me = o.data
sc = bpy.context.scene
def coords():
    dg = bpy.context.evaluated_depsgraph_get(); ev = o.evaluated_get(dg); m = ev.to_mesh()
    a = np.zeros(len(m.vertices) * 3); m.vertices.foreach_get("co", a); ev.to_mesh_clear()
    a = a.reshape(-1, 3); M = np.array(o.matrix_world); return a @ M[:3, :3].T + M[:3, 3]
n = len(me.vertices); gi = {g.name: g.index for g in o.vertex_groups}
W = np.zeros((n, len(gi)))
for v in me.vertices:
    for g in v.groups: W[v.index, g.group] = g.weight
arm.data.pose_position = "REST"; bpy.context.view_layer.update(); rest = coords(); arm.data.pose_position = "POSE"
# кожа сумки в покое: вершины, жёсткие на Hips/Spine02 поровну (как назначил v4_fix), ниже пояса
bag = (np.abs(W[:, gi["Hips"]] - 0.5) < 0.02) & (np.abs(W[:, gi["Spine02"]] - 0.5) < 0.02) & (rest[:, 2] < 1.08)
d, _ = cKDTree(rest[bag]).query(rest, distance_upper_bound=0.11)
zone = d < 0.10
ed = np.zeros(len(me.edges) * 2, dtype=int); me.edges.foreach_get("vertices", ed); ed = ed.reshape(-1, 2)
ez = zone[ed[:, 0]] & zone[ed[:, 1]]
L0 = np.linalg.norm(rest[ed[:, 0]] - rest[ed[:, 1]], axis=1); ez &= L0 > 1e-4
hand = (W[:, [gi["LeftHand"], gi["RightHand"]]].sum(1) > 0.5)
rep = {"glb": glb.split("/")[-1], "bag_vertices": int(bag.sum()), "zone_edges": int(ez.sum()), "clips": {}}
for act in bpy.data.actions:
    if act.name.endswith("_T5b"): continue
    arm.animation_data.action = act; f0, f1 = map(int, act.frame_range)
    worst, gap = 0.0, 1e9; cnt = 0
    for f in range(f0, f1 + 1, step):
        sc.frame_set(f); c = coords()
        r = np.linalg.norm(c[ed[ez, 0]] - c[ed[ez, 1]], axis=1) / L0[ez]
        cnt = max(cnt, int((r > 1.5).sum())); worst = max(worst, float(np.percentile(r, 99.9)))
        g, _ = cKDTree(c[bag]).query(c[hand]); gap = min(gap, float(g.min()))
    rep["clips"][act.name] = {"edges_over_1_5x_max": cnt, "stretch_p99_9": round(worst, 2), "hand_bag_gap_mm": round(gap * 1000, 1)}
    print(act.name, rep["clips"][act.name], flush=True)
json.dump(rep, open(out_p, "w"), ensure_ascii=False, indent=1)
