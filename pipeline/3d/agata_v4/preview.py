"""preview.py glb out_prefix [zoom: z0 z1 views]  — рендер Workbench с текстурой."""
import bpy, sys, math, mathutils
argv = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else sys.argv[1:]
glb, prefix = argv[0], argv[1]
z0 = float(argv[2]) if len(argv) > 2 else None
z1 = float(argv[3]) if len(argv) > 3 else None
views = argv[4].split(",") if len(argv) > 4 else ["front", "left", "back", "right"]
bpy.ops.wm.read_factory_settings(use_empty=True)
if glb.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=glb)
else:
    bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 12; sc.cycles.use_denoising = True
sc.render.resolution_x = sc.render.resolution_y = 900
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.6, 0.65, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
sc.view_settings.view_transform = "Standard"
for nm, en, ang, rot in (("Key", 4.5, 20, (55, 0, -35)), ("Fill", 2.0, 40, (70, 0, 140)), ("Rim", 2.5, 10, (120, 0, 20))):
    L = bpy.data.lights.new(nm, "SUN"); L.energy = en; L.angle = math.radians(ang)
    ob = bpy.data.objects.new(nm, L); sc.collection.objects.link(ob); ob.rotation_euler = tuple(math.radians(v) for v in rot)
for m in bpy.data.materials:
    for n in (m.node_tree.nodes if m.node_tree else []):
        if n.type == "BSDF_PRINCIPLED":
            for l in list(m.node_tree.links):
                if l.to_socket in (n.inputs["Metallic"], n.inputs["Roughness"]): m.node_tree.links.remove(l)
            n.inputs["Metallic"].default_value = 0; n.inputs["Roughness"].default_value = 0.85
meshes = [o for o in sc.objects if o.type == "MESH"]
pts = [o.matrix_world @ mathutils.Vector(c) for o in meshes for c in o.bound_box]
mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)]); mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
if z0 is None: z0, z1 = mn.z, mx.z
cx, cy = (mn.x+mx.x)/2, (mn.y+mx.y)/2
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = (z1-z0)*1.05
ang = {"front": 0, "left": 90, "back": 180, "right": 270, "fl": 35, "fr": -35}
for v in views:
    a = math.radians(ang[v]); d = 5
    cam.location = (cx + d*math.sin(a)*-1*-1 if False else cx - d*math.sin(a), cy - d*math.cos(a), (z0+z1)/2)
    cam.rotation_euler = (math.radians(90), 0, -a)
    sc.render.filepath = f"{prefix}_{v}.png"
    bpy.ops.render.render(write_still=True)
