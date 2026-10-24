"""base.glb + клипы других GLB того же рига Meshy (те же кости) → один GLB."""
import bpy, sys
argv = sys.argv[sys.argv.index('--') + 1:]
base, out, others = argv[0], argv[1], argv[2:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=base)
keep = set(bpy.data.objects)
for spec in others:
    path, name = spec.split('=')
    acts0 = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [a for a in bpy.data.actions if a not in acts0]
    new[0].name = name; new[0].use_fake_user = True
    for a in new[1:]: bpy.data.actions.remove(a)
    for o in [o for o in bpy.data.objects if o not in keep]:
        bpy.data.objects.remove(o, do_unlink=True)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) < 100]:
    bpy.data.objects.remove(o, do_unlink=True)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
print('actions', [a.name for a in bpy.data.actions])
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS')
