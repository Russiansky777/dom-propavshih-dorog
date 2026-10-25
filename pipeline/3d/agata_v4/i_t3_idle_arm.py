"""I-T3 (карта Директора 25.10, стр. 33): в стойке (idle) при взгляде с направлений 6–7 правая кисть уходила в пальто/сумку.
Только клип стойки: плечо RightArm дополнительно поворачивается наружу на θ° (вокруг оси «вперёд», как arm_offset.py T5b,
там 12° во всех клипах) и предплечье RightForeArm — вперёд на φ°, чтобы кисть легла перед сумкой, а не в неё.
Остальные клипы не меняются — перерендер только idle (0 кредитов Meshy).
  python pipeline/3d/agata_v4/i_t3_idle_arm.py -- in.glb out.glb <клип-подстрока> θ φ
"""
import bpy, sys, math
from mathutils import Matrix
argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, key, theta, phi = argv[0], argv[1], argv[2], float(argv[3]), float(argv[4])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src, disable_bone_shape=True)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]; sc = bpy.context.scene
acts = [a for a in bpy.data.actions if key in a.name]
assert acts, [a.name for a in bpy.data.actions]


def turn(pb, axis, deg, f0, f1):
    mats = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        head = (arm.matrix_world @ pb.matrix).translation
        R = Matrix.Translation(head) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-head)
        mats[f] = arm.matrix_world.inverted() @ R @ arm.matrix_world @ pb.matrix
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        pb.matrix = mats[f]
        bpy.context.view_layer.update()
        pb.keyframe_insert('rotation_quaternion', frame=f)


for act in acts:
    arm.animation_data.action = act
    f0, f1 = [int(round(x)) for x in act.frame_range]
    turn(arm.pose.bones['RightArm'], 'Y', theta, f0, f1)          # правая сторона — −X: рука наружу
    if phi:
        turn(arm.pose.bones['RightForeArm'], 'X', -phi, f0, f1)   # вперёд — −Y: кисть перед сумкой
print('ok', [a.name for a in acts])
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True)
