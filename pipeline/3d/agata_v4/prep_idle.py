"""motion.glb (риг Meshy + клип Text to Motion) → стойка Idle_T2M: амплитуда покачивания ×k вокруг средней позы окна
(«лёгкий перенос веса»: в клипе голова ходит на 20 см, таз на 14 см), лишний Icosphere убран."""
import bpy, sys
from mathutils import Quaternion, Vector
argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, f0, f1, k = argv[0], argv[1], int(argv[2]), int(argv[3]), float(argv[4])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and len(o.data.vertices) < 100:
        bpy.data.objects.remove(o, do_unlink=True)
act = bpy.data.actions[0]; act.name = 'Idle_T2M'
fcs = {}
for fc in (act.fcurves if hasattr(act, 'fcurves') else []):
    fcs.setdefault(fc.data_path, {})[fc.array_index] = fc
if not fcs:  # Blender 5: слои/каналы действия
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    fcs.setdefault(fc.data_path, {})[fc.array_index] = fc
n = 0
for path, comp in fcs.items():
    if path.endswith('rotation_quaternion') and len(comp) == 4:
        keys = len(comp[0].keyframe_points)
        qs = [Quaternion([comp[i].keyframe_points[j].co[1] for i in range(4)]) for j in range(keys)]
        fr = [comp[0].keyframe_points[j].co[0] for j in range(keys)]
        win = [q for q, f in zip(qs, fr) if f0 <= f <= f1] or qs
        m = Quaternion((0, 0, 0, 0))
        for q in win:
            m = Quaternion([a + (b if win[0].dot(q) >= 0 else -b) for a, b in zip(m, q)])
        m.normalize()
        for j, q in enumerate(qs):
            if m.dot(q) < 0: q = -q
            r = m.slerp(q, k)
            for i in range(4):
                comp[i].keyframe_points[j].co[1] = r[i]
        n += 1
    elif path.endswith('location') and len(comp) == 3:
        keys = len(comp[0].keyframe_points)
        for i in range(3):
            kp = comp[i].keyframe_points
            vals = [kp[j].co[1] for j in range(keys) if f0 <= kp[j].co[0] <= f1] or [p.co[1] for p in kp]
            mean = sum(vals) / len(vals)
            for j in range(keys):
                kp[j].co[1] = mean + (kp[j].co[1] - mean) * k
        n += 1
for comp in fcs.values():
    for fc in comp.values():
        for p in fc.keyframe_points: p.interpolation = 'LINEAR'
        fc.update()
print('damped channels', n)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS')
