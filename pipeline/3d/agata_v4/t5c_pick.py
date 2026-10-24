"""T5c — мельче присед pick: поза кадра f = slerp(поза кадра 0, поза f, w) — низ (таз, ноги) с весом w_low, верх с w_up;
плюс дополнительный наклон спины (spine_deg, по глубине приседа), таз по высоте — подошвы на полу как в кадре 0."""
import bpy, math
from mathutils import Quaternion, Vector, Matrix
LOW = {"Hips","LeftUpLeg","LeftLeg","LeftFoot","LeftToeBase","RightUpLeg","RightLeg","RightFoot","RightToeBase"}
FEET = ("LeftToeBase","RightToeBase","LeftFoot","RightFoot")
def foot_z(arm):
    # только головки костей: хвосты концевых костей glTF смотрят куда угодно
    return min((arm.matrix_world @ arm.pose.bones[n].head).z for n in FEET)
def build(arm, src_name, dst_name, w_low, w_up, spine_deg=0.0, arm_deg=0.0, axis="X"):
    src = bpy.data.actions[src_name]
    f0, f1 = map(int, src.frame_range)
    sc = bpy.context.scene
    arm.animation_data.action = src
    poses, hz = [], []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        poses.append({b.name: (b.rotation_quaternion.copy(), b.location.copy()) for b in arm.pose.bones})
        hz.append((arm.matrix_world @ arm.pose.bones["Hips"].head).z)
    drop = max(hz[0] - min(hz), 1e-6)
    base = poses[0]
    arm.animation_data.action = None
    for b in arm.pose.bones:
        b.rotation_mode = "QUATERNION"
        q, l = base[b.name]; b.rotation_quaternion = q; b.location = l
    bpy.context.view_layer.update()
    fz0 = foot_z(arm)
    out = []
    for i, p in enumerate(poses):
        t = max(0.0, (hz[0] - hz[i]) / drop)
        t = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t))
        for b in arm.pose.bones:
            q0, l0 = base[b.name]; q1, l1 = p[b.name]
            w = w_low if b.name in LOW else w_up
            q = q0.slerp(q1, w)
            if spine_deg and b.name in ("Spine01", "Spine"):
                q = q @ Quaternion(Vector((1,0,0)) if axis=="X" else Vector((0,0,1)), math.radians(spine_deg / 2 * t))
            if arm_deg and b.name in ("LeftArm", "RightArm"):
                q = q @ Quaternion(Vector((1,0,0)), math.radians(arm_deg * t))
            b.rotation_quaternion = q
            b.location = l0.lerp(l1, w)
        bpy.context.view_layer.update()
        # подошвы на полу: таз вниз/вверх на разницу (глобальная Z → локальная таза через матрицу)
        dz = fz0 - foot_z(arm)
        if abs(dz) > 1e-5 and i not in (0,):
            hb = arm.pose.bones["Hips"]
            M = (arm.matrix_world @ hb.bone.matrix_local).to_3x3()
            hb.location = hb.location + (M.inverted() @ Vector((0, 0, dz))) * 1.0
            bpy.context.view_layer.update()
        out.append({b.name: (b.rotation_quaternion.copy(), b.location.copy()) for b in arm.pose.bones})
    dst = bpy.data.actions.get(dst_name) or bpy.data.actions.new(dst_name)
    arm.animation_data.action = dst
    for i, p in enumerate(out):
        for b in arm.pose.bones:
            b.rotation_quaternion, b.location = p[b.name]
            b.keyframe_insert("rotation_quaternion", frame=f0 + i); b.keyframe_insert("location", frame=f0 + i)
    return dst
