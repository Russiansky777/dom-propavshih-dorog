"""Agata v5 candidate GLB → rig input: one mesh, decimated (collapse) to ~N triangles, UV and texture kept, GLB.
  python3 tools/v5_rig_input.py -- <src.glb> <out.glb> <tris>   (bpy; used by workflow meshy-agata-v5, mode rig)"""
import bpy, sys
args = sys.argv[sys.argv.index('--') + 1:]
src, out, tris = args[0], args[1], int(args[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
total = sum(len(o.data.polygons) for o in meshes)
print('SRC polys', total, 'meshes', len(meshes))
for o in meshes:
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    m = o.modifiers.new('dec', 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = min(1.0, tris / max(total, 1))
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='dec')
print('OUT polys', sum(len(o.data.polygons) for o in meshes))
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=92)
