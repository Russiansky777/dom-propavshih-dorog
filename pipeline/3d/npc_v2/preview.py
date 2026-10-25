"""Превью игрового GLB жителя для проверки глазами: по каждому клипу кадры анфас и сбоку + лицо крупно (рот).
  python3.13 preview.py -- <glb> <out.jpg> [кадров на клип=5] [клипы через запятую]"""
import bpy, sys, math, os, tempfile
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
glb, out = argv[0], argv[1]
nf = int(argv[2]) if len(argv) > 2 else 5
only = argv[3].split(',') if len(argv) > 3 else None
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb, disable_bone_shape=True)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) < 100]:
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 6; sc.cycles.use_denoising = False
sc.render.resolution_x = 240; sc.render.resolution_y = 320; sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.75, 0.78, 1)
for nm, en, rot in (("Key", 4.0, (55, 0, -35)), ("Fill", 2.0, (70, 0, 140))):
    L = bpy.data.lights.new(nm, "SUN"); L.energy = en
    ob = bpy.data.objects.new(nm, L); sc.collection.objects.link(ob); ob.rotation_euler = tuple(math.radians(v) for v in rot)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
if arm.animation_data is None:
    arm.animation_data_create()
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
H = max((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
tmp = tempfile.mkdtemp()
tiles = []


def shot(yaw, look_z, scale, path):
    yaw = math.radians(yaw); d = 6; e = math.radians(10)
    cam.data.ortho_scale = scale
    cam.location = (-d * math.sin(yaw) * math.cos(e), -d * math.cos(yaw) * math.cos(e), look_z + d * math.sin(e))
    cam.rotation_euler = (Vector((0, 0, look_z)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


acts = [a for a in bpy.data.actions if not only or a.name in only]
for a in acts:
    arm.animation_data.action = a
    f0, f1 = a.frame_range
    row = []
    for i in range(nf):
        f = f0 + (f1 - f0) * i / max(1, nf - 1)
        sc.frame_set(int(f), subframe=f - int(f))
        for yaw in (0, 90):
            p = f"{tmp}/{a.name}_{i}_{yaw}.png"; shot(yaw, H * 0.5, H * 1.1, p); row.append(p)
    # лицо крупно — два соседних кадра (рот закрыт / приоткрыт в «говорит»)
    picks = [f0 + (f1 - f0) * 0.3, f0 + (f1 - f0) * 0.32]
    jb = arm.pose.bones.get('Jaw')
    if jb is not None:
        ang = []
        for f in range(int(f0), int(f1) + 1):
            sc.frame_set(f); ang.append((jb.rotation_quaternion.angle, f))
        picks = [min(ang)[1], max(ang)[1]]
    for i, f in enumerate(picks):
        sc.frame_set(int(f), subframe=f - int(f))
        for yaw in (0, 90):
            p = f"{tmp}/{a.name}_face{i}_{yaw}.png"; shot(yaw, H * 0.89, 0.3, p); row.append(p)
    tiles.append((a.name, row))
from PIL import Image, ImageDraw
W = max(len(r) for _, r in tiles) * 240
img = Image.new("RGB", (W, 340 * len(tiles)), "white")
d = ImageDraw.Draw(img)
for y, (name, row) in enumerate(tiles):
    for x, p in enumerate(row):
        img.paste(Image.open(p).convert("RGB"), (x * 240, y * 340 + 20))
    d.text((4, y * 340 + 4), name, fill="black")
img.save(out, quality=85)
print("preview", out, [n for n, _ in tiles])
