"""Проверка жёсткой сумки и ремня по всем клипам: растяжение рёбер ремня/сумки (≤ 3 % — «не ломается»)
и зазор кисть ↔ сумка (кисть не входит в клапан)."""
import bpy, sys, json, numpy as np
from scipy.spatial import cKDTree
argv = sys.argv[sys.argv.index('--') + 1:]
glb, strap_co_p, out_p = argv[0], argv[1], argv[2]
step = int(argv[3]) if len(argv) > 3 else 3
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb, disable_bone_shape=True)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
o = max([o for o in bpy.data.objects if o.type == 'MESH'], key=lambda m: len(m.data.vertices)); me = o.data
sc = bpy.context.scene; dg = bpy.context.evaluated_depsgraph_get()
def coords():
    dg.update(); ev = o.evaluated_get(dg); m = ev.to_mesh()
    a = np.zeros(len(m.vertices) * 3); m.vertices.foreach_get('co', a); ev.to_mesh_clear()
    a = a.reshape(-1, 3); M = np.array(o.matrix_world); return a @ M[:3, :3].T + M[:3, 3]
arm.animation_data_create(); arm.animation_data.action = None
for pb in arm.pose.bones: pb.matrix_basis.identity()
rest = coords()
sco = np.load(strap_co_p)
d, idx = cKDTree(rest).query(sco, k=1)
rig = np.unique(idx[d < 0.002])
gi = {g.index: g.name for g in o.vertex_groups}
hand = {'RightHand': [], 'LeftHand': []}
for v in me.vertices:
    if v.groups:
        g = max(v.groups, key=lambda g: g.weight)
        if gi[g.group] in hand and g.weight > 0.5: hand[gi[g.group]].append(v.index)
ne = len(me.edges); ev_ = np.zeros(ne * 2, int); me.edges.foreach_get('vertices', ev_); ev_ = ev_.reshape(-1, 2)
inset = np.zeros(len(me.vertices), bool); inset[rig] = True
E = ev_[inset[ev_[:, 0]] & inset[ev_[:, 1]]]
L0 = np.linalg.norm(rest[E[:, 0]] - rest[E[:, 1]], axis=1) + 1e-9
bag_rest_z = rest[rig, 2]; bag_only = rig[bag_rest_z < 1.05]
rep = {"rigid_vertices": int(len(rig)), "edges": int(len(E)), "clips": {}}
for act in bpy.data.actions:
    arm.animation_data.action = act
    f0, f1 = [int(round(x)) for x in act.frame_range]
    worst = 0.0; gap = {k: 9.0 for k in hand}
    for f in range(f0, f1 + 1, step):
        sc.frame_set(f); c = coords()
        L = np.linalg.norm(c[E[:, 0]] - c[E[:, 1]], axis=1)
        worst = max(worst, float(np.percentile(np.abs(L / L0 - 1), 99.5)))
        tree = cKDTree(c[bag_only])
        for k, vs in hand.items():
            if vs:
                gap[k] = min(gap[k], float(tree.query(c[vs], k=1)[0].min()))
    rep["clips"][act.name] = {"strap_bag_stretch_p995": round(worst, 4), "hand_bag_gap_m": {k: round(v, 4) for k, v in gap.items()}}
    print(act.name, rep["clips"][act.name], flush=True)
json.dump(rep, open(out_p, 'w'), ensure_ascii=False, indent=1)
