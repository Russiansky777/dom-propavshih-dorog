import bpy, sys, math, mathutils
argv = sys.argv[sys.argv.index('--') + 1:]
glb, prefix, specs = argv[0], argv[1], argv[2:]   # spec: action@frac@yaw
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb, disable_bone_shape=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 10; sc.cycles.use_denoising = True
sc.render.resolution_x = 450; sc.render.resolution_y = 600; sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.6, 0.65, 1)
for nm, en, ang, rot in (("Key", 4.5, 20, (55, 0, -35)), ("Fill", 2.0, 40, (70, 0, 140)), ("Rim", 2.5, 10, (120, 0, 20))):
    L = bpy.data.lights.new(nm, "SUN"); L.energy = en; L.angle = math.radians(ang)
    ob = bpy.data.objects.new(nm, L); sc.collection.objects.link(ob); ob.rotation_euler = tuple(math.radians(v) for v in rot)
for m in bpy.data.materials:
    for n in (m.node_tree.nodes if m.node_tree else []):
        if n.type == "BSDF_PRINCIPLED":
            for l in list(m.node_tree.links):
                if l.to_socket in (n.inputs["Metallic"], n.inputs["Roughness"]): m.node_tree.links.remove(l)
            n.inputs["Metallic"].default_value = 0; n.inputs["Roughness"].default_value = 0.85
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.9
for sp in specs:
    an, frac, yaw = sp.split('@'); frac = float(frac); yaw = math.radians(float(yaw))
    act = bpy.data.actions[an]; arm.animation_data.action = act
    f0, f1 = act.frame_range; sc.frame_set(int(round(f0 + (f1 - f0) * frac)))
    d = 6; e = math.radians(14)
    cam.location = (-d * math.sin(yaw) * math.cos(e), -d * math.cos(yaw) * math.cos(e), 0.85 + d * math.sin(e))
    cam.rotation_euler = (mathutils.Vector((0, 0, 0.85)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{prefix}_{an}_{frac}_{int(math.degrees(yaw))}.png"
    bpy.ops.render.render(write_still=True)
