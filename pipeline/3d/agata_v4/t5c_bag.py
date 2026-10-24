"""Сумка: веса без разрывов (T5c). Сетка Meshy — ~2000 отдельных кусков; T5b делал жёсткими (Hips/Spine02 по 0,5)
вершины по цвету кожи, и в кусках сумки оставались вершины с весами ног/рук → вытянутые треугольники («солома»
из клапана). Здесь жёсткость — поле по расстоянию до вершин кожи сумки (в позе покоя): ≤ r0 — жёстко, дальше плавный
спад до нуля на r0 + R. Поле непрерывно в пространстве, поэтому соседние куски сетки (у которых общие края лежат
в одной точке, но не связаны рёбрами) двигаются одинаково и щелей нет; руки, кисти и голова не трогаются."""
import numpy as np
from scipy.spatial import cKDTree
def fix_bag(o, r0=1.5, R=8.0):
    me = o.data; n = len(me.vertices)
    gi = {g.name: g.index for g in o.vertex_groups}; G = len(gi)
    W = np.zeros((n, G))
    for v in me.vertices:
        for g in v.groups: W[v.index, g.group] = g.weight
    bagw = np.zeros(G); bagw[gi["Hips"]] = 0.5; bagw[gi["Spine02"]] = 0.5
    bag = (np.abs(W[:, gi["Hips"]] - 0.5) < 1e-3) & (np.abs(W[:, gi["Spine02"]] - 0.5) < 1e-3) & (np.abs(W.sum(1) - 1) < 1e-3)
    co = np.zeros(n * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    unit = 100.0 if co[:, 2].max() > 10 else 1.0          # сетка в см (масштаб объекта 0,01) или в м
    d, _ = cKDTree(co[bag]).query(co, distance_upper_bound=(r0 + R) * unit / 100 * 1.01)
    t = np.clip(1 - (np.nan_to_num(d, posinf=1e9) - r0 * unit / 100) / (R * unit / 100), 0, 1)
    t = t * t * (3 - 2 * t)
    armg = [gi[g] for g in gi if any(k in g for k in ("Arm", "Hand", "Shoulder", "neck", "Head", "head"))]
    t = t * np.clip(1 - 2 * W[:, armg].sum(1), 0, 1)
    ch = np.where((t > 1e-3) & ~bag)[0]
    Wn = W.copy(); Wn[ch] = (1 - t[ch, None]) * W[ch] + t[ch, None] * bagw
    for i in ch:                                          # не больше 4 костей на вершину (glTF), сумма 1
        r = Wn[i]; r[np.argsort(-r)[4:]] = 0
    Wn[ch] /= Wn[ch].sum(1, keepdims=True)
    for i in ch:
        i = int(i)
        for g in [g.group for g in me.vertices[i].groups]:
            o.vertex_groups[g].remove([i])
        for k in np.where(Wn[i] > 1e-4)[0]:
            o.vertex_groups[int(k)].add([i], float(Wn[i, k]), "REPLACE")
    return {"bag_vertices": int(bag.sum()), "rigid_added": int(((t > 0.999) & ~bag).sum()),
            "blended": int(((t > 1e-3) & (t <= 0.999) & ~bag).sum()), "r0_cm": r0, "falloff_cm": R}
