"""Агата v4, правки сетки после рига Meshy (T5b):
1) передний угол платка (верхний слой у ремня, под горлом справа от неё) подогнуть под ремень и соседний слой:
   вершины угла уходят назад (к телу) и чуть внутрь слоя, плавно (cos-спад), ремень не трогается;
2) сумка и ремень жёсткие: веса вершин сумки/ремня — только на корпус (Spine/Spine01/Spine02) и бёдра/таз,
   без рук и шеи.
  python v4_fix.py -- in.glb out.glb report.json [--no-weights]
"""
import bpy, bmesh, sys, json, math
import numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, rep_p = argv[:3]
do_weights = '--no-weights' not in argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
o = max(meshes, key=lambda m: len(m.data.vertices)); me = o.data
arm = next((x for x in bpy.data.objects if x.type == 'ARMATURE'), None)
M = np.array(o.matrix_world); Mi = np.linalg.inv(M)
n = len(me.vertices)
co_l = np.zeros(n * 3); me.vertices.foreach_get('co', co_l); co_l = co_l.reshape(-1, 3)
co = (M[:3, :3] @ co_l.T).T + M[:3, 3]
# цвет текстуры по вершине
uv = np.zeros(len(me.loops) * 2); me.uv_layers.active.data.foreach_get('uv', uv); uv = uv.reshape(-1, 2)
lv = np.zeros(len(me.loops), dtype=int); me.loops.foreach_get('vertex_index', lv)
vuv = np.zeros((n, 2)); vuv[lv] = uv
mat = o.active_material
img = None
for nd in mat.node_tree.nodes:
    if nd.type == 'BSDF_PRINCIPLED':
        l = nd.inputs['Base Color'].links
        if l: img = l[0].from_node.image
px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
from scipy.ndimage import gaussian_filter
px = gaussian_filter(px[..., :3], (4, 4, 0))  # кожа ремня/сумки — по размытому цвету (шум текстуры)
xi = np.clip((vuv[:, 0] % 1) * img.size[0], 0, img.size[0] - 1).astype(int)
yi = np.clip((vuv[:, 1] % 1) * img.size[1], 0, img.size[1] - 1).astype(int)
col = px[yi, xi, :3]
leather = (col[:, 1] / (col[:, 0] + 1e-4) < 0.68) & (col[:, 0] - col[:, 2] > 0.15) & (col[:, 0] > 0.2)
H = co[:, 2].max()
rep = {"height_m": float(H)}

# --- 1. угол платка ---
P = np.array([0.047, 0.0, 1.2546]) * (H / 1.65)
R = 0.032 * H / 1.65
# сетка упрощена (крупные треугольники на ровной ткани) — сначала мельче в области угла, иначе гнуть нечего;
# UV и веса делятся вместе с рёбрами (bmesh интерполирует слои)
for it in range(2):
    bm = bmesh.new(); bm.from_mesh(me)
    Mw = o.matrix_world
    faces = [f for f in bm.faces if f.calc_center_median() is not None and
             any(math.hypot((Mw @ v.co).x - P[0], (Mw @ v.co).z - P[2]) < R * 1.25 and (Mw @ v.co).y < -0.04 for v in f.verts)]
    edges = list({e for f in faces for e in f.edges})
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=2, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bm.to_mesh(me); bm.free(); me.update()
n = len(me.vertices)
co_l = np.zeros(n * 3); me.vertices.foreach_get('co', co_l); co_l = co_l.reshape(-1, 3)
co = (M[:3, :3] @ co_l.T).T + M[:3, 3]
uv = np.zeros(len(me.loops) * 2); me.uv_layers.active.data.foreach_get('uv', uv); uv = uv.reshape(-1, 2)
lv = np.zeros(len(me.loops), dtype=int); me.loops.foreach_get('vertex_index', lv)
vuv = np.zeros((n, 2)); vuv[lv] = uv
xi = np.clip((vuv[:, 0] % 1) * img.size[0], 0, img.size[0] - 1).astype(int)
yi = np.clip((vuv[:, 1] % 1) * img.size[1], 0, img.size[1] - 1).astype(int)
col = px[yi, xi, :3]
leather = (col[:, 1] / (col[:, 0] + 1e-4) < 0.68) & (col[:, 0] - col[:, 2] > 0.15) & (col[:, 0] > 0.2)
dxz = np.hypot(co[:, 0] - P[0], co[:, 2] - P[2])
near = (dxz < R) & (co[:, 1] < -0.04)
# передний слой: ближе всего к зрителю в своей колонке (±4 мм), не кожа ремня
front = np.zeros(n, bool)
idx = np.where(near)[0]
for i in idx:
    col_m = idx[np.hypot(co[idx, 0] - co[i, 0], co[idx, 2] - co[i, 2]) < 0.006]
    if co[i, 1] <= co[col_m, 1].min() + 0.008:
        front[i] = True
sel = near & ~leather   # все слои ткани в области: пространство гнётся плавно, без переворота граней
# соседи ремня (2 мм) тоже не двигаем — ремень лежит сверху
w = 0.5 * (1 + np.cos(np.pi * np.clip(dxz / R, 0, 1)))
w[~sel] = 0
# сглаживание по рёбрам: без ступеньки на краю слоя (ступенька переворачивала треугольники — тёмные точки)
ne = len(me.edges); ev = np.zeros(ne * 2, int); me.edges.foreach_get('vertices', ev); ev = ev.reshape(-1, 2)
deg = np.bincount(ev.ravel(), minlength=n).astype(float) + 1e-9
ws = w.copy()
for _ in range(12):
    acc = np.bincount(ev[:, 0], weights=ws[ev[:, 1]], minlength=n) + np.bincount(ev[:, 1], weights=ws[ev[:, 0]], minlength=n)
    ws = 0.5 * ws + 0.5 * acc / deg
    ws[leather] = 0
w = np.maximum(ws, w * 0.85)
w[leather] = 0
# у края ремня ткань не двигается (иначе из-под ремня видна щель): спад на 8 мм от ближайшей кожи
from scipy.spatial import cKDTree
lz = np.where(leather & (np.hypot(co[:, 0] - P[0], co[:, 2] - P[2]) < R * 2))[0]
if len(lz):
    dl, _ = cKDTree(co[lz]).query(co, k=1, distance_upper_bound=0.05)
    w *= np.clip((np.minimum(dl, 0.05) - 0.002) / 0.008, 0, 1) ** 2
# направление внутрь слоя: от угла вверх-влево по диагонали края (к горлу)
inward = np.array([-0.55, 0.0, 0.83]); inward /= np.linalg.norm(inward)
disp = np.zeros_like(co)
disp[:, 1] = 0.011 * w            # назад, к телу (+Y — спина)
disp += (0.004 * w)[:, None] * inward  # угол подтягивается внутрь — край подогнут, а не срезан
new = co + disp
rep["scarf"] = {"moved_vertices": int((w > 0.01).sum()), "max_shift_mm": float(np.linalg.norm(disp, axis=1).max() * 1000),
                "corner_xyz": P.round(4).tolist(), "radius_m": round(R, 4)}
# проверка: треугольники с перевёрнутой нормалью после сдвига
me.calc_loop_triangles()
T = len(me.loop_triangles); tv = np.zeros(T * 3, int); me.loop_triangles.foreach_get('vertices', tv); tv = tv.reshape(-1, 3)
moved_t = (w[tv] > 0.01).any(1)
def nrm(c):
    a, b, d = c[tv[moved_t, 0]], c[tv[moved_t, 1]], c[tv[moved_t, 2]]
    v = np.cross(b - a, d - a); return v / (np.linalg.norm(v, axis=1, keepdims=True) + 1e-12)
flip = int(((nrm(co) * nrm(new)).sum(1) < 0).sum())
rep["scarf"]["triangles_moved"] = int(moved_t.sum()); rep["scarf"]["triangles_flipped"] = flip
new_l = (Mi[:3, :3] @ new.T).T + Mi[:3, 3]
me.vertices.foreach_set('co', new_l.ravel()); me.update()

# --- 2. сумка и ремень жёсткие ---
if do_weights and arm is not None:
    names = [vg.name for vg in o.vertex_groups]
    torso = [g for g in names if g.lower() in ('spine', 'spine01', 'spine02', 'hips')]
    legs = [g for g in names if 'upleg' in g.lower() or 'thigh' in g.lower()]
    rep["groups"] = names
    # кости Meshy снизу вверх: Hips → Spine02 → Spine01 → Spine (грудь) → neck
    # сумка: кожа у правого бедра (её правая сторона — −X), без ботинок и пуговиц
    sx = H / 1.65
    bag = leather & (co[:, 2] > 0.62 * sx) & (co[:, 2] < 1.05 * sx) & (co[:, 0] < -0.05 * sx) & (co[:, 0] > -0.28 * sx)
    # ремень: кожа у прямой «левое плечо → правое бедро» в проекции на фронт (спереди и сзади)
    def dist_line(A_, B_):
        A_, B_ = np.array(A_) * sx, np.array(B_) * sx
        AB = B_ - A_; t_ = np.clip(((co[:, [0, 2]] - A_) @ AB) / (AB @ AB), 0, 1)
        return np.linalg.norm(co[:, [0, 2]] - (A_ + t_[:, None] * AB), axis=1)
    # спереди: (0.16, 1.42) → (−0.10, 0.92) по рендеру анфас; сзади: (0.13, 1.42) → (−0.14, 0.92)
    dline = np.minimum(dist_line((0.16, 1.42), (-0.10, 0.92)), dist_line((0.13, 1.42), (-0.14, 0.92)))
    braid = (co[:, 1] > 0.115 * sx) & (np.abs(co[:, 0]) < 0.06 * sx)
    strap = leather & ~bag & ~braid & (dline < 0.03 * sx) & (co[:, 2] > 0.92 * sx) & (co[:, 2] < 1.47 * sx)
    gi = {vg.name: vg.index for vg in o.vertex_groups}
    def set_w(i, ws):
        i = int(i)
        v = me.vertices[i]
        for g in [g.group for g in v.groups]:
            o.vertex_groups[g].remove([i])
        ws = {g: x for g, x in ws.items() if g in gi and x > 1e-4}
        s_ = sum(ws.values())
        for g, x in ws.items():
            o.vertex_groups[gi[g]].add([i], x / s_, 'REPLACE')
    zb = co[:, 2] / sx
    for i in np.where(strap)[0]:
        t = float(np.clip((zb[i] - 1.0) / 0.40, 0, 1))          # 0 у сумки … 1 у плеча
        set_w(i, {'Hips': 0.5 * max(0.0, 1 - 3 * t), 'Spine02': max(0.0, 1 - 1.6 * t), 'Spine01': 0.6 - abs(t - 0.6), 'Spine': max(0.0, 1.5 * t - 0.5)})
    for i in np.where(bag)[0]:
        set_w(i, {'Hips': 0.5, 'Spine02': 0.5})   # без бедра: при приседе сумку не тянет за ногу
    rep["bag"] = {"bag_vertices": int(bag.sum()), "strap_vertices": int(strap.sum())}
    np.save(dst + ".strap_co.npy", co[strap | bag])
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS')
json.dump(rep, open(rep_p, 'w'), ensure_ascii=False, indent=1)
print(json.dumps({k: v for k, v in rep.items() if k != 'groups'}, ensure_ascii=False))
