#!/usr/bin/env python3
"""Рендер спрайтов персонажа из анимированного GLB (Blender как модуль bpy, Cycles CPU, прозрачный фон).

  python3 pipeline/render/render_sprites.py --glb pipeline/3d/out/agata/animations.glb --name agata \
      --out assets/characters/agata --directions 8 --frames walk=12 idle=8 --size 384 --elev 14 --front-yaw 0

Результат: <out>/<action>_<dir>.png (горизонтальная полоса кадров), <out>/sprites.json
(размер кадра, кадры по действиям, порядок направлений, опорная точка = центр низа = ноги, высота персонажа в кадре).
Направления: индекс d → камера повёрнута на d*360/N° вокруг персонажа; d=0 — персонаж смотрит в камеру (анфас).
Если у модели «перед» смотрит не туда — поправить --front-yaw.
Действия выбираются по подстроке имени клипа (walk, idle…); если в файле один клип, он идёт под именем из --frames.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_frames(items: list[str]) -> dict[str, int]:
    d = {}
    for it in items:
        k, v = it.split("=")
        d[k] = int(v)
    return d


def scene_bounds(objs):
    """Габарит по реально деформированной сетке (скиннинг учтён), а не по bound_box в bind-пространстве."""
    dg = bpy.context.evaluated_depsgraph_get()
    mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        for v in me.vertices:
            w = mw @ v.co
            mins = Vector(map(min, mins, w)); maxs = Vector(map(max, maxs, w))
        ev.to_mesh_clear()
    return mins, maxs


METAL_WORDS = ("metal", "iron", "steel", "brass", "bronze", "gold", "silver", "chrome", "buckle", "blade", "knife")


def matte_materials(objs, rough_min: float = 0.8) -> list:
    """Ткань и кожа — матовые (22.10: Павел блестел, как лакированная кожа, — PBR Meshy enable_pbr): metallic 0,
    roughness не меньше rough_min. Материалы, по имени явно металлические, не трогаются."""
    done = []
    mats = {m for o in objs if o.type == "MESH" for m in o.data.materials if m is not None and m.use_nodes}
    for m in mats:
        # только по имени материала: имя карты PBR Meshy само содержит «metallic» (texture_0_metallic_roughness)
        if any(w in m.name.lower() for w in METAL_WORDS):
            continue
        nt = m.node_tree
        for n in [x for x in nt.nodes if x.type == "BSDF_PRINCIPLED"]:
            met, rough = n.inputs.get("Metallic"), n.inputs.get("Roughness")
            if met is not None:
                for l in list(met.links):
                    nt.links.remove(l)
                met.default_value = 0.0
            if rough is not None:
                if rough.is_linked:
                    src = rough.links[0].from_socket
                    mx = nt.nodes.new("ShaderNodeMath"); mx.operation = "MAXIMUM"
                    mx.inputs[1].default_value = rough_min
                    nt.links.new(src, mx.inputs[0]); nt.links.new(mx.outputs[0], rough)
                else:
                    rough.default_value = max(rough.default_value, rough_min)
            done.append(m.name)
    return done


def screen_extent(meshes, frames_by_act, set_frame, yaws_deg, elev_deg, look_z):
    """Наибольшие |x| и y (вверх) фигуры на экране по всем кадрам листов и направлениям (метры кадра)."""
    import numpy as np  # noqa: PLC0415
    e = math.radians(elev_deg)
    th = np.radians(np.asarray(yaws_deg, float))
    c, s_ = np.cos(th), np.sin(th)
    hx, top = 0.0, -1e9
    for act, fr in frames_by_act:
        for f in fr:
            set_frame(act, f)
            dg = bpy.context.evaluated_depsgraph_get()
            for o in meshes:
                ev = o.evaluated_get(dg)
                me = ev.to_mesh()
                co = np.empty(len(me.vertices) * 3)
                me.vertices.foreach_get("co", co)
                mw = np.array(ev.matrix_world)
                V = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
                ev.to_mesh_clear()
                xs = V[:, 0:1] * c - V[:, 1:2] * s_          # (n, dirs)
                ys = V[:, 0:1] * s_ + V[:, 1:2] * c
                yscr = ys * math.sin(e) + (V[:, 2:3] - look_z) * math.cos(e)
                hx = max(hx, float(np.abs(xs).max()))
                top = max(top, float(yscr.max()))
    return hx, top


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--directions", type=int, default=8)
    ap.add_argument("--frames", nargs="+", default=["walk=12", "idle=8"])
    ap.add_argument("--size", type=int, default=384, help="высота кадра в px; ширина = size*0.75")
    ap.add_argument("--elev", type=float, default=14.0, help="угол камеры над горизонтом, градусы")
    ap.add_argument("--front-yaw", type=float, default=0.0, help="поправка, если анфас не на d=0")
    ap.add_argument("--samples", type=int, default=24)
    ap.add_argument("--margin", type=float, default=1.12)
    ap.add_argument("--clips", nargs="*", default=[], help="точное имя клипа на действие: open_b=open_door_1 (из pipeline/3d/state/<name>.json); без него — подбор по подстроке")
    ap.add_argument("--window", nargs="*", default=[], help="доля клипа на действие: idle=0:0.35 — кадры берутся только из этого отрезка (для клипов с лишним движением), в манифест пишется playback=pingpong")
    ap.add_argument("--feet-fix", nargs="*", default=[], help="действия, у которых перед рендером править стопы (pipeline/3d/feet_fix.py): walk idle")
    ap.add_argument("--feet-report", default="", help="куда записать замеры стоп до/после исправления (JSON)")
    ap.add_argument("--no-matte", action="store_true", help="не делать ткань матовой (по умолчанию metallic 0, roughness ≥ 0.8)")
    ap.add_argument("--no-fit", action="store_true", help="не расширять кадр под движение (по умолчанию кадр шире, если фигура выходит за край)")
    args = ap.parse_args()
    windows: dict[str, tuple[float, float]] = {}
    clip_keys: dict[str, str] = dict(c.split("=", 1) for c in args.clips)
    for w in args.window:
        k, v = w.split("=", 1); a, b = v.split(":"); windows[k] = (float(a), float(b))

    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    frames_by_action = parse_frames(args.frames)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # в режиме модуля сцена может быть не пустой — вычищаем всё, что было до импорта
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.glb).resolve()), disable_bone_shape=True)
    # импортёр кладёт служебные объекты (форма костей) в коллекцию glTF_not_exported — их не считаем и не рендерим
    objs = []
    for o in bpy.context.scene.objects:
        if o in before:
            continue
        if any(c.name == "glTF_not_exported" for c in o.users_collection):
            o.hide_render = True
            continue
        objs.append(o)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        print("в GLB нет мешей", file=sys.stderr); return 2

    actions = list(bpy.data.actions)

    def pick_action(action_name, idx):
        act = None
        if action_name in clip_keys:
            key = clip_keys[action_name]
            # точное имя (Blender может добавить суффикс .001 при повторном импорте)
            act = next((a for a in actions if a.name == key or a.name.split(".")[0] == key), None)
            if act is None:
                print(f"нет клипа «{key}» для «{action_name}»; в файле: {[a.name for a in actions]}", file=sys.stderr)
                return None
        if act is None:
            act = next((a for a in actions if action_name.lower() in a.name.lower()), None)
        if act is None and len(actions) == 1:
            act = actions[0]
        if act is None and len(actions) == len(frames_by_action):
            act = actions[idx]  # клипы Meshy идут в порядке action_ids = порядке --frames
        return act

    # стопы: разворот ботинок и «носок вверх» у ходьбы и стойки — до рендера, в самих ключах клипа
    if args.feet_fix and arm is not None:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "3d"))
        import feet_fix  # noqa: PLC0415
        reps = []
        ad0 = arm.animation_data
        orig_act = ad0.action if ad0 else None  # кадрирование ниже — по позе этого клипа, как без исправления
        try:
            rig = feet_fix.rig_from_blender(arm, meshes)
            for idx, action_name in enumerate(frames_by_action):
                if action_name not in args.feet_fix:
                    continue
                act = pick_action(action_name, idx)
                kind = feet_fix.kind_of(action_name) or (feet_fix.kind_of(act.name) if act else None)
                if act is None or kind is None:
                    continue
                rep = feet_fix.fix_action(arm, rig, act, kind, window=windows.get(action_name))
                rep["role"] = action_name
                reps.append(rep)
                print(f"  стопы {action_name} ({act.name}): " + json.dumps(
                    {"до": {k: (v["stance_toe_out_deg"], v["toe_abs_max_deg"], v["slide_max_mm"]) for k, v in rep["before"].items()},
                     "после": {k: (v["stance_toe_out_deg"], v["toe_abs_max_deg"], v["slide_max_mm"]) for k, v in rep["after"].items()},
                     "не прошло": rep["fail"]}, ensure_ascii=False), flush=True)
        except Exception as e:  # шаг не должен ронять рендер; проверка (check_feet.py) покажет, что стопы не исправлены
            print(f"  стопы: исправление не выполнено: {e!r}", file=sys.stderr, flush=True)
        if args.feet_report:
            Path(args.feet_report).parent.mkdir(parents=True, exist_ok=True)
            Path(args.feet_report).write_text(json.dumps({"name": args.name, "clips": reps}, ensure_ascii=False, indent=1), encoding="utf-8")
        feet_fix.assign(arm, orig_act)
        bpy.context.scene.frame_set(0)

    # статичная поза для кадрирования — первое действие (стойка) в начале своего окна
    first = next(iter(frames_by_action), None)
    if arm is not None and first is not None:
        a0 = pick_action(first, 0)
        if a0 is not None:
            if arm.animation_data is None:
                arm.animation_data_create()
            arm.animation_data.action = a0
            g0, g1 = a0.frame_range
            if first in windows:
                g0 = g0 + (g1 - g0) * windows[first][0]
            bpy.context.scene.frame_set(int(round(g0)))
    matte = [] if args.no_matte else matte_materials(meshes)
    if matte:
        print(f"  матовые материалы (metallic 0, roughness ≥ 0.8): {matte}", flush=True)

    # корень для вращения: всё, что без родителя
    roots = [o for o in objs if o.parent is None]
    pivot = bpy.data.objects.new("SpritePivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for r in roots:
        r.parent = pivot

    # кадрирование: по статичной позе
    bpy.context.view_layer.update()
    mins, maxs = scene_bounds(meshes)
    height = maxs.z - mins.z
    width = max(maxs.x - mins.x, maxs.y - mins.y)
    center = Vector(((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, mins.z))  # у ног
    pivot.location = Vector((0, 0, 0))
    for r in roots:
        r.location -= Vector((center.x, center.y, mins.z))
    bpy.context.view_layer.update()

    # камера: ортографическая, под углом elev, смотрит на середину роста
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("SpriteCam"); cam_data.type = "ORTHO"
    extent = height * args.margin
    cam_data.ortho_scale = extent
    cam = bpy.data.objects.new("SpriteCam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    dist = extent * 4
    elev = math.radians(args.elev)
    cam.location = Vector((0, -dist * math.cos(elev), height / 2 + dist * math.sin(elev)))
    look = Vector((0, 0, height / 2))
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()

    # свет: мягкий ключевой + заполняющий, нейтральный мир
    sun = bpy.data.lights.new("Key", "SUN"); sun.energy = 4.5; sun.angle = math.radians(20)
    so = bpy.data.objects.new("Key", sun); scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(55), 0, math.radians(-35))
    fill = bpy.data.lights.new("Fill", "SUN"); fill.energy = 2.0; fill.angle = math.radians(40)
    fo = bpy.data.objects.new("Fill", fill); scene.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(70), 0, math.radians(140))
    rim = bpy.data.lights.new("Rim", "SUN"); rim.energy = 2.5; rim.angle = math.radians(10)
    ro = bpy.data.objects.new("Rim", rim); scene.collection.objects.link(ro)
    ro.rotation_euler = (math.radians(120), 0, math.radians(20))
    world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.6, 0.6, 0.65, 1); bg.inputs[1].default_value = 1.0

    # рендер
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"; scene.cycles.samples = args.samples; scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_y = args.size; scene.render.resolution_x = int(args.size * 0.75)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"; scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    # ortho_scale в Blender относится к большей стороне кадра; кадр вертикальный → это высота
    cam_data.ortho_scale = height * args.margin

    def act_frames(action_name, idx, nframes):
        act = pick_action(action_name, idx)
        if act is None:
            return None, []
        f0, f1 = act.frame_range
        if action_name in windows:
            wa, wb = windows[action_name]
            f0, f1 = f0 + (f1 - f0) * wa, f0 + (f1 - f0) * wb
        return act, [int(round(f0 + (f1 - f0) * i / nframes)) for i in range(nframes)]

    fit = {}
    if not args.no_fit and arm is not None:
        # кадр шире, если фигура в каком-то кадре выходит за боковой край (наклон «поднять» — голова, коса, рука):
        # высота кадра, опорная точка и масштаб (px на метр) — прежние
        def set_frame(act, f):
            arm.animation_data.action = act
            scene.frame_set(f)
        todo = []
        for idx, (an, nf) in enumerate(frames_by_action.items()):
            act, fr = act_frames(an, idx, nf)
            if act is not None:
                todo.append((act, fr))
        yaws = [args.front_yaw + d * 360.0 / args.directions for d in range(args.directions)]
        hx, top = screen_extent(meshes, todo, set_frame, yaws, args.elev, height / 2)
        m_per_px = extent / scene.render.resolution_y
        need = int(math.ceil(2 * hx * 1.03 / m_per_px / 16.0) * 16)
        fit = {"half_width_m": round(hx, 3), "top_m": round(top, 3), "frame_top_m": round(extent / 2, 3)}
        if need > scene.render.resolution_x:
            print(f"  кадр шире: {scene.render.resolution_x} → {need} px (фигура до {hx:.2f} м от оси)", flush=True)
            scene.render.resolution_x = need
            cam_data.ortho_scale = extent * max(need, scene.render.resolution_y) / scene.render.resolution_y
        if top > extent / 2:
            print(f"  ВНИМАНИЕ: верх фигуры {top:.2f} м выше кадра {extent / 2:.2f} м — обрежется", file=sys.stderr, flush=True)
        fit["frame_w"] = scene.render.resolution_x
        arm.animation_data.action = todo[0][0] if todo else arm.animation_data.action

    print("клипы в файле:", [a.name for a in actions])
    manifest = {"name": args.name, "frame_w": scene.render.resolution_x, "frame_h": scene.render.resolution_y,
                "pivot": {"x": 0.5, "y": 1.0 - (1 - 1 / args.margin) / 2}, "directions": args.directions,
                "direction_order": "d=0 анфас, далее по часовой стрелке (камера вокруг персонажа)",
                "character_height_m": round(height, 3), "actions": {}}
    if fit:
        manifest["fit"] = fit
    if matte:
        manifest["matte_materials"] = True

    wanted_order = list(frames_by_action.keys())
    for idx, (action_name, nframes) in enumerate(frames_by_action.items()):
        act = pick_action(action_name, idx)
        if act is None:
            print(f"нет клипа для «{action_name}» — пропускаю", file=sys.stderr); continue
        if arm is not None:
            if arm.animation_data is None:
                arm.animation_data_create()
            arm.animation_data.action = act
        f0, f1 = act.frame_range
        if action_name in windows:
            wa, wb = windows[action_name]
            f0, f1 = f0 + (f1 - f0) * wa, f0 + (f1 - f0) * wb
            print(f"  {action_name}: окно клипа {wa:.2f}–{wb:.2f} → кадры {f0:.1f}–{f1:.1f}", flush=True)
        strip = None
        from PIL import Image  # локальный импорт: Pillow не нужен Blender'у
        sheet = Image.new("RGBA", (scene.render.resolution_x * nframes, scene.render.resolution_y * args.directions), (0, 0, 0, 0))
        for d in range(args.directions):
            pivot.rotation_euler = (0, 0, math.radians(args.front_yaw + d * 360.0 / args.directions))
            for i in range(nframes):
                scene.frame_set(int(round(f0 + (f1 - f0) * i / nframes)))
                tmp = out / f"_tmp_{action_name}_{d}_{i}.png"
                scene.render.filepath = str(tmp)
                bpy.ops.render.render(write_still=True)
                im = Image.open(tmp).convert("RGBA")
                sheet.paste(im, (i * scene.render.resolution_x, d * scene.render.resolution_y))
                tmp.unlink()
            print(f"  {action_name}: направление {d+1}/{args.directions} готово", flush=True)
        path = out / f"{action_name}.png"
        sheet.save(path)
        manifest["actions"][action_name] = {"sheet": path.name, "frames": nframes, "fps": 12 if action_name == "walk" else 8, "clip": act.name}
        if action_name in windows:
            manifest["actions"][action_name]["window"] = list(windows[action_name])
            manifest["actions"][action_name]["playback"] = "pingpong"
    (out / "sprites.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("готово:", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
