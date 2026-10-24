"""T5c — sit: сидячая фигура в середине кадра. Клип стула сдвигает таз назад (сиденье за опорной точкой), и рендер
листа — общий кадр всех действий с осью по стойке — уводит фигуру к краю (d7 обрезана). Сдвигаем таз во всём клипе
так, чтобы середина силуэта сидя по полу (X, Y) совпала с серединой стойки; колени чуть сводим — меньше провисает
ткань юбки между ними."""
import bpy, numpy as np
from mathutils import Vector, Quaternion
import math, os
KNEE_AXIS = tuple(float(x) for x in os.environ.get('KNEE_AXIS', '0,0,1').split(','))
def _bbox(o):
    dg = bpy.context.evaluated_depsgraph_get(); e = o.evaluated_get(dg); m = e.to_mesh()
    a = np.zeros(len(m.vertices) * 3); m.vertices.foreach_get("co", a); e.to_mesh_clear()
    a = a.reshape(-1, 3); M = np.array(o.matrix_world)
    w = a @ M[:3, :3].T + M[:3, 3]
    return w.min(0), w.max(0)
def center_sit(arm, o, sit_name, ref_name, knee_in_deg=0.0):
    sc = bpy.context.scene
    arm.animation_data.action = bpy.data.actions[ref_name]; sc.frame_set(int(bpy.data.actions[ref_name].frame_range[0]))
    lo, hi = _bbox(o); ref = (lo + hi) / 2
    act = bpy.data.actions[sit_name]; arm.animation_data.action = act; sc.frame_set(int(act.frame_range[0]))
    lo, hi = _bbox(o); cur = (lo + hi) / 2
    d = Vector((ref[0] - cur[0], ref[1] - cur[1], 0.0))
    hb = arm.pose.bones["Hips"]
    Ml = (arm.matrix_world @ hb.bone.matrix_local).to_3x3().inverted()
    dl = Ml @ d
    # все ключи location таза + сведение коленей (поворот бедра вокруг оси вперёд — в локальных осях кости)
    f0, f1 = map(int, act.frame_range)
    poses = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f); poses.append({b.name: (b.rotation_quaternion.copy(), b.location.copy()) for b in arm.pose.bones})
    arm.animation_data.action = None
    new = bpy.data.actions.new(sit_name + "_c")
    arm.animation_data.action = new
    for i, p in enumerate(poses):
        for b in arm.pose.bones:
            q, l = p[b.name]
            if b.name == "Hips":
                l = l + dl
            if knee_in_deg and b.name in ("LeftUpLeg", "RightUpLeg"):
                sgn = 1 if b.name.startswith("Left") else -1
                q = q @ Quaternion(Vector(KNEE_AXIS), math.radians(sgn * knee_in_deg))
            if knee_in_deg and b.name in ("LeftLeg", "RightLeg"):
                sgn = 1 if b.name.startswith("Left") else -1
                q = q @ Quaternion(Vector(KNEE_AXIS), math.radians(-sgn * knee_in_deg))
            b.rotation_mode = "QUATERNION"; b.rotation_quaternion = q; b.location = l
            b.keyframe_insert("rotation_quaternion", frame=f0 + i); b.keyframe_insert("location", frame=f0 + i)
    name = act.name; bpy.data.actions.remove(act); new.name = name
    arm.animation_data.action = new; sc.frame_set(f0)
    lo, hi = _bbox(o)
    P = lambda n: arm.matrix_world @ arm.pose.bones[n].head
    knees = round((P("LeftLeg") - P("RightLeg")).length, 3)
    return {"knee_gap_m": knees, "knee_in_deg": knee_in_deg, "shift_m": [round(float(d.x), 4), round(float(d.y), 4)], "center_after": [round(float((lo[0] + hi[0]) / 2 - ref[0]), 4), round(float((lo[1] + hi[1]) / 2 - ref[1]), 4)]}
