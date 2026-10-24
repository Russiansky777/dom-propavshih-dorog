"""Исходная модель v4 + текстура лица/волос → упрощение до 290 тыс. треугольников (UV сохраняются) → GLB для рига Meshy."""
import bpy, sys
argv = sys.argv[sys.argv.index('--')+1:]
src, tex, out = argv[:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
img = bpy.data.images['Image_0']; new = bpy.data.images.load(tex); img.user_remap(new); new.name = 'basecolor_v4'
o = [o for o in bpy.data.objects if o.type == 'MESH'][0]
n0 = len(o.data.polygons)
m = o.modifiers.new('dec', 'DECIMATE'); m.ratio = 290000 / n0; m.use_collapse_triangulate = True
bpy.context.view_layer.objects.active = o; o.select_set(True)
bpy.ops.object.modifier_apply(modifier='dec')
print('faces', n0, '->', len(o.data.polygons))
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=False, export_image_format='AUTO')
