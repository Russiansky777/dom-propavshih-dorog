"""Правая рука чуть в сторону во всех клипах (кисть не входит в сумку): поворот плеча RightArm в мире
вокруг оси «вперёд» на θ°, одинаково во всех клипах — переходы между клипами без скачка."""
import bpy, sys, math
from mathutils import Matrix
argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, theta = argv[0], argv[1], float(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src, disable_bone_shape=True)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]; sc = bpy.context.scene
pb = arm.pose.bones['RightArm']
# правая сторона Агаты — −X; рука наружу = поворот вокруг оси Y (вперёд −Y), конец руки уходит к −X
for act in list(bpy.data.actions):
    arm.animation_data.action = act
    f0, f1 = [int(round(x)) for x in act.frame_range]
    mats = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        head = (arm.matrix_world @ pb.matrix).translation
        R = Matrix.Translation(head) @ Matrix.Rotation(math.radians(theta), 4, 'Y') @ Matrix.Translation(-head)
        mats[f] = arm.matrix_world.inverted() @ R @ arm.matrix_world @ pb.matrix
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        pb.matrix = mats[f]
        bpy.context.view_layer.update()
        pb.keyframe_insert('rotation_quaternion', frame=f)
print('ok', [a.name for a in bpy.data.actions])
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True)
