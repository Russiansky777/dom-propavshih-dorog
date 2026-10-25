"""I-T4 (25.10): игровой GLB жителя из задач Meshy — по полю "blender" запроса pipeline/requests/npc_<имя>.json.
Всё, что Директор может захотеть поменять (амплитуды, окна, поворот плеч, рот), — параметры запроса: правка = перерендер.

  python3.13 build_npc.py -- <запрос.json> <папка с GLB прогона> <выход.glb> [отчёт.json]

Вход (артефакт glb-<run> pipeline-character): animations.glb (риг + пресеты), motion_<роль>.glb (Text to Motion на риг).
Шаги:
  1. клипы по ролям: пресеты из animations.glb ("clips": {роль: имя клипа Meshy}), Text to Motion — motion_<роль>.glb;
  2. "damp": {роль: k} — амплитуда покачивания ×k вокруг средней позы (как стойка Агаты v4, prep_idle.py);
  3. "arms_in_deg": {роль: θ} — плечи к телу на θ° (листы в полу-А-позе; в стойке руки опущены и близко к телу);
  4. "jaw": кость челюсти (у рига Meshy лицевых костей нет): вершины подбородка и нижней губы — на кость Jaw с плавным спадом,
     в клипе "role" рот чередуется «приоткрыт / закрыт» точно по кадрам листа (frames, окно) — в игре он идёт, пока звучит реплика;
  5. "rigid": [{"bone", "box": [x0,y0,z0,x1,y1,z1]}] — жёсткие предметы (очки на шнурке, сумка, рукавицы): вершины в коробке
     (поза покоя, метры) целиком на одну кость — не тянутся с руками.
"""
import bpy, sys, json, math
from mathutils import Quaternion, Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
req_path, src_dir, out_path = argv[0], argv[1], argv[2]
rep_path = argv[3] if len(argv) > 3 else None
req = json.load(open(req_path, encoding='utf-8'))
cfg = req['blender']
report = {}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f"{src_dir}/animations.glb", disable_bone_shape=True)
keep = set(bpy.data.objects)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) >= 100]
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) < 100]:
    bpy.data.objects.remove(o, do_unlink=True)
report['meshy_clips'] = [a.name for a in bpy.data.actions]


def fcurves(act):
    out = list(getattr(act, 'fcurves', []) or [])
    if not out:  # Blender 5: слои/каналы действия
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
    return out


# 1. клипы по ролям
roles = {}
for role, clip in cfg.get('clips', {}).items():
    act = next((a for a in bpy.data.actions if a.name == clip or a.name.startswith(clip)), None)
    if act is None:
        act = next((a for a in bpy.data.actions if clip.lower() in a.name.lower()), None)
    if act is None:
        raise SystemExit(f"нет клипа {clip} в animations.glb: {report['meshy_clips']}")
    roles[role] = act
for role in cfg.get('text_motion_roles', []):
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=f"{src_dir}/motion_{role}.glb", disable_bone_shape=True)
    new = [a for a in bpy.data.actions if a not in before]
    new.sort(key=lambda a: -(a.frame_range[1] - a.frame_range[0]))
    roles[role] = new[0]
    new[0].name = f"{role}_clip"      # сразу: следующий импорт клипа с тем же именем не должен его задеть
    new[0].use_fake_user = True
    for a in new[1:]:
        bpy.data.actions.remove(a)
    for o in [o for o in bpy.data.objects if o not in keep]:
        bpy.data.objects.remove(o, do_unlink=True)
for role, act in roles.items():
    act.name = f"{role}_clip"
    act.use_fake_user = True
for a in [a for a in bpy.data.actions if a not in roles.values()]:
    bpy.data.actions.remove(a)
report['roles'] = {r: [a.name, list(a.frame_range)] for r, a in roles.items()}

# 2. амплитуда покачивания
for role, k in cfg.get('damp', {}).items():
    act = roles[role]
    fcs = {}
    for fc in fcurves(act):
        fcs.setdefault(fc.data_path, {})[fc.array_index] = fc
    for path, comp in fcs.items():
        if path.endswith('rotation_quaternion') and len(comp) == 4:
            n = len(comp[0].keyframe_points)
            qs = [Quaternion([comp[i].keyframe_points[j].co[1] for i in range(4)]) for j in range(n)]
            m = Quaternion((0, 0, 0, 0))
            for q in qs:
                m = Quaternion([a + (b if qs[0].dot(q) >= 0 else -b) for a, b in zip(m, q)])
            m.normalize()
            for j, q in enumerate(qs):
                if m.dot(q) < 0:
                    q = -q
                r = m.slerp(q, k)
                for i in range(4):
                    comp[i].keyframe_points[j].co[1] = r[i]
        elif path.endswith('location') and len(comp) == 3 and 'Hips' in path:
            for fc in comp.values():
                kp = fc.keyframe_points
                mean = sum(p.co[1] for p in kp) / max(1, len(kp))
                for p in kp:
                    p.co[1] = mean + (p.co[1] - mean) * k
        for fc in comp.values():
            fc.update()

sc = bpy.context.scene
if arm.animation_data is None:
    arm.animation_data_create()


def use(act):
    """Клип на риг. Blender 5: у действия из другого GLB свой слот — берём его же, иначе ключи пишутся в новый пустой
    слот и при экспорте клип раздваивается («listen» и «listen-Armature» в позе покоя)."""
    arm.animation_data.action = act
    if act is not None and getattr(act, 'slots', None) and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]


def frames_of(act):
    f0, f1 = act.frame_range
    return int(math.floor(f0)), int(math.ceil(f1))


# 2б. "straighten": {роль: {"legs": k, "hips": k}} — Text to Motion на риге Meshy сажает фигуру (колени согнуты,
#     таз назад, «полуприсед» сбоку): повороты ног и таза к позе покоя (прямые ноги) на долю k; стопы — обратно на пол
LEGS = ('LeftUpLeg', 'LeftLeg', 'LeftFoot', 'RightUpLeg', 'RightLeg', 'RightFoot')
for role, spec in cfg.get('straighten', {}).items():
    act = roles[role]
    for fc_group in [{}]:
        for fc in fcurves(act):
            fc_group.setdefault(fc.data_path, {})[fc.array_index] = fc
        for path, comp in fc_group.items():
            if not path.endswith('rotation_quaternion') or len(comp) != 4:
                continue
            bone = path.split('"')[1]
            k = spec.get('legs', 0.0) if bone in LEGS else spec.get('hips', 0.0) if bone == 'Hips' else 0.0
            if not k:
                continue
            for j in range(len(comp[0].keyframe_points)):
                q = Quaternion([comp[i].keyframe_points[j].co[1] for i in range(4)])
                r = q.slerp(Quaternion(), k)
                for i in range(4):
                    comp[i].keyframe_points[j].co[1] = r[i]
            for fc in comp.values():
                fc.update()
    # стопы на пол позы покоя: нижняя из пяток (головы костей Foot) по каждому кадру
    use(None)
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    foot = lambda: min((arm.matrix_world @ arm.pose.bones[b].matrix).translation.z for b in ('LeftFoot', 'RightFoot'))
    rest_z = foot()
    use(act)
    hb = arm.pose.bones['Hips']
    f0, f1 = frames_of(act)
    shift = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        shift[f] = rest_z - foot()
    inv = arm.matrix_world.inverted().to_3x3()
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        m = hb.matrix.copy()
        m.translation += inv @ Vector((0, 0, shift[f]))
        hb.matrix = m
        bpy.context.view_layer.update()
        hb.keyframe_insert('location', frame=f)
    report.setdefault('straighten', {})[role] = {'floor_shift_cm': [round(min(shift.values()) * 100, 1), round(max(shift.values()) * 100, 1)]}


# 3. плечи к телу: поворот плеча в мире вокруг оси «вперёд» (Y), одинаково по всему клипу
for role, theta in cfg.get('arms_in_deg', {}).items():
    if not theta:
        continue
    act = roles[role]
    use(act)
    f0, f1 = frames_of(act)
    for side, sign in (('Left', -1.0), ('Right', 1.0)):
        pb = arm.pose.bones.get(f'{side}Arm')
        if pb is None:
            continue
        # левая рука персонажа — +X: к телу = конец руки к −X; правая — наоборот
        mats = {}
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            head = (arm.matrix_world @ pb.matrix).translation
            R = Matrix.Translation(head) @ Matrix.Rotation(math.radians(sign * theta), 4, 'Y') @ Matrix.Translation(-head)
            mats[f] = arm.matrix_world.inverted() @ R @ arm.matrix_world @ pb.matrix
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            pb.matrix = mats[f]
            bpy.context.view_layer.update()
            pb.keyframe_insert('rotation_quaternion', frame=f)

# 5. жёсткие предметы (до челюсти: веса предметов не трогаются ею)
for item in cfg.get('rigid', []):
    lo, hi = Vector(item['box'][:3]), Vector(item['box'][3:])
    n = 0
    for ob in meshes:
        vg = ob.vertex_groups.get(item['bone']) or ob.vertex_groups.new(name=item['bone'])
        mw = ob.matrix_world
        idx = [v.index for v in ob.data.vertices if all(lo[i] <= (mw @ v.co)[i] <= hi[i] for i in range(3))]
        for g in ob.vertex_groups:
            if g != vg:
                g.remove(idx)
        vg.add(idx, 1.0, 'REPLACE')
        n += len(idx)
    report.setdefault('rigid', []).append({**item, 'vertices': n})

# 4. челюсть
jaw = cfg.get('jaw')
if jaw:
    rest = {}
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    head_b = arm.data.bones['Head']
    hz = (arm.matrix_world @ head_b.head_local).z
    # голова — вершины с весом Head ≥ 0,5; профиль лица — передний край (−Y) по срезам высоты
    pts = []
    for ob in meshes:
        g = ob.vertex_groups.get('Head')
        if g is None:
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            for ge in v.groups:
                if ge.group == g.index and ge.weight >= 0.5:
                    pts.append(mw @ v.co)
    top = max(p.z for p in pts)
    cx = sum(p.x for p in pts) / len(pts)
    face = [p for p in pts if abs(p.x - cx) < 0.02]
    # срезы по 4 мм; кончик носа — самый передний срез на 4–12 см выше сустава головы (не поля шапки, не борода);
    # линия рта — между суставом головы (≈ низ подбородка у рига Meshy) и носом, доля mouth_frac (Нина: 0,57 → губы)
    sl = {}
    for p in face:
        b = int((p.z - hz) / 0.004)
        sl[b] = min(sl.get(b, 9), p.y)
    mid = [b for b in sl if 10 <= b <= 30]
    nose = min(mid, key=lambda b: sl[b])
    nose_z = hz + (nose + 0.5) * 0.004
    chin_z = hz
    mouth_z = hz + jaw.get('mouth_frac', 0.57) * (nose_z - hz) + jaw.get('mouth_dz', 0.0)   # mouth_dz — поправка по кадрам проверки, м
    front_y = sl[nose]
    back_y = max(p.y for p in pts)
    pivot = Vector((cx, front_y + jaw.get('pivot_depth', 0.4) * (back_y - front_y), mouth_z + 0.005))
    report['jaw_geom'] = {'neck_z': hz, 'top': top, 'nose_z': nose_z, 'chin_z': chin_z, 'mouth_z': mouth_z, 'pivot': list(pivot)}
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones.new('Jaw')
    inv = arm.matrix_world.inverted()
    eb.head = inv @ pivot
    eb.tail = inv @ (pivot + Vector((0, -0.06, -0.02)))
    eb.parent = arm.data.edit_bones['Head']
    bpy.ops.object.mode_set(mode='OBJECT')
    soft = jaw.get('soft_m', 0.006)
    width = jaw.get('half_width_m', 0.045)
    lowest = chin_z - jaw.get('below_chin_m', 0.03)
    # разрез рта: у сетки Meshy губы — одна поверхность, без щели рот при опускании челюсти только тянется.
    # Грани у линии рта (ширина губ, передний слой) делятся на верхние и нижние, общие рёбра разрезаются;
    # за щелью — тёмная полость (сплюснутая сфера на кости Head)
    import bmesh
    lip_hw = jaw.get('lip_half_width_m', 0.024)
    lip_front = min((p.y for p in face if abs(p.z - mouth_z) < 0.004), default=front_y)
    side = {}
    nslit = 0
    for ob in meshes:
        mw = ob.matrix_world
        bm = bmesh.new(); bm.from_mesh(ob.data)
        reg = {}
        for f in bm.faces:
            c = mw @ f.calc_center_median()
            if abs(c.x - cx) < lip_hw and c.y < lip_front + 0.012 and abs(c.z - mouth_z) < 0.01:
                reg[f] = c.z >= mouth_z
        cut = [e for e in bm.edges if len(e.link_faces) == 2 and all(f in reg for f in e.link_faces)
               and reg[e.link_faces[0]] != reg[e.link_faces[1]]]
        nslit += len(cut)
        if cut:
            bmesh.ops.split_edges(bm, edges=cut)
        bm.verts.index_update()
        lower, upper = set(), set()
        for f, up in reg.items():
            for v in f.verts:
                (upper if up else lower).add(v.index)
        bm.to_mesh(ob.data); bm.free()
        side[ob.name] = (lower - upper, upper - lower)
    if nslit and jaw.get('cavity', True):
        me = bpy.data.meshes.new('mouth_cavity'); bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0)
        for v in bm.verts:
            v.co = Vector((cx + v.co.x * lip_hw * 0.9, lip_front + 0.016 + v.co.y * 0.009, mouth_z - 0.003 + v.co.z * 0.008))
        bm.to_mesh(me); bm.free()
        mat = bpy.data.materials.new('mouth_dark'); mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value = (0.25, 0.08, 0.07, 1); bsdf.inputs['Roughness'].default_value = 1.0
        me.materials.append(mat)
        cav = bpy.data.objects.new('mouth_cavity', me); bpy.context.scene.collection.objects.link(cav)
        cav.vertex_groups.new(name='Head').add(list(range(len(me.vertices))), 1.0, 'REPLACE')
        cav.parent = arm; mod = cav.modifiers.new('Armature', 'ARMATURE'); mod.object = arm
    report['mouth_slit_edges'] = nslit
    nmove = 0
    for ob in meshes:
        g = ob.vertex_groups.get('Head')
        if g is None:
            continue
        jg = ob.vertex_groups.get('Jaw') or ob.vertex_groups.new(name='Jaw')
        mw = ob.matrix_world
        for v in ob.data.vertices:
            hw = next((ge.weight for ge in v.groups if ge.group == g.index), 0.0)
            if hw <= 0.0:
                continue
            p = mw @ v.co
            if p.y > pivot.y or p.z < lowest - soft or abs(p.x - cx) > width + 0.02:
                continue
            lo, up = side.get(ob.name, (set(), set()))
            if v.index in lo:
                t = 1.0                                                       # нижний край разреза
            elif v.index in up:
                t = 0.0                                                       # верхний край разреза
            else:
                t = max(0.0, min(1.0, (mouth_z - p.z) / soft * 0.5 + 0.5))  # над линией рта 0, ниже 1
            s = max(0.0, min(1.0, (width + 0.02 - abs(p.x - cx)) / 0.02))    # спад к щекам
            d = max(0.0, min(1.0, (pivot.y - p.y) / 0.03))                    # спад к уху
            u = max(0.0, min(1.0, (p.z - (lowest - soft)) / soft))            # спад к шее
            w = hw * t * s * d * u
            if w > 0.01:
                jg.add([v.index], w, 'REPLACE')
                g.add([v.index], hw - w, 'REPLACE')
                nmove += 1
    report['jaw_vertices'] = nmove
    # рот по кадрам листа: в кадре i ровно cos(πi) → чётные закрыт, нечётные приоткрыт (амплитуда меняется — как речь)
    act = roles[jaw['role']]
    use(act)
    f0, f1 = act.frame_range
    w0, w1 = jaw.get('window', [0.0, 1.0])
    a0, a1 = f0 + (f1 - f0) * w0, f0 + (f1 - f0) * w1
    nfr = int(jaw['frames'])
    step = (a1 - a0) / (max(1, nfr - 1) if jaw.get('window') else nfr)
    amps = jaw.get('pattern', [1.0, 0.6, 0.9, 0.35, 0.8, 1.0, 0.5, 0.75])
    pb = arm.pose.bones['Jaw']
    pb.rotation_mode = 'QUATERNION'
    for f in range(int(math.floor(f0)), int(math.ceil(f1)) + 1):
        x = (f - a0) / step
        i = int(math.floor(x / 2))
        o = amps[i % len(amps)] * (0.5 - 0.5 * math.cos(math.pi * x))
        pb.rotation_quaternion = Quaternion(Vector((1, 0, 0)), math.radians(jaw.get('open_deg', 7.0)) * o)
        pb.keyframe_insert('rotation_quaternion', frame=f)
    for other in roles.values():
        if other is act:
            continue
        use(other)
        pb.rotation_quaternion = Quaternion()
        g0, g1 = frames_of(other)
        pb.keyframe_insert('rotation_quaternion', frame=g0)
        pb.keyframe_insert('rotation_quaternion', frame=g1)

for role, act in roles.items():
    act.name = role
use(roles.get('idle') or next(iter(roles.values())))
for act in roles.values():
    for sl in list(getattr(act, 'slots', []))[1:]:
        act.slots.remove(sl)
report['slots'] = {r: len(getattr(a, 'slots', [])) for r, a in roles.items()}
if rep_path:
    json.dump(report, open(rep_path, 'w'), ensure_ascii=False, indent=1)
print(json.dumps(report, ensure_ascii=False)[:1500])
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS',
                          export_force_sampling=True)
