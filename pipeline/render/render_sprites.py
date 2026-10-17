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
    mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mins = Vector(map(min, mins, w)); maxs = Vector(map(max, maxs, w))
    return mins, maxs


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
    args = ap.parse_args()

    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    frames_by_action = parse_frames(args.frames)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(Path(args.glb).resolve()))
    objs = list(bpy.context.scene.objects)
    arm = next((o for o in objs if o.type == "ARMATURE"), None)
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        print("в GLB нет мешей", file=sys.stderr); return 2

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
    extent = max(height, width) * args.margin
    cam_data.ortho_scale = extent
    cam = bpy.data.objects.new("SpriteCam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    dist = extent * 4
    elev = math.radians(args.elev)
    cam.location = Vector((0, -dist * math.cos(elev), height / 2 + dist * math.sin(elev)))
    look = Vector((0, 0, height / 2))
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()

    # свет: мягкий ключевой + заполняющий, нейтральный мир
    sun = bpy.data.lights.new("Key", "SUN"); sun.energy = 3.0; sun.angle = math.radians(20)
    so = bpy.data.objects.new("Key", sun); scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(55), 0, math.radians(-35))
    fill = bpy.data.lights.new("Fill", "SUN"); fill.energy = 1.2; fill.angle = math.radians(40)
    fo = bpy.data.objects.new("Fill", fill); scene.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(70), 0, math.radians(140))
    world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.5, 0.5, 0.55, 1); bg.inputs[1].default_value = 0.6

    # рендер
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"; scene.cycles.samples = args.samples; scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_y = args.size; scene.render.resolution_x = int(args.size * 0.75)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"; scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    # ортокамера с соотношением 3:4: ortho_scale применяется к большей стороне → по высоте подгоняем
    cam_data.ortho_scale = extent * max(1.0, scene.render.resolution_x / scene.render.resolution_y) if scene.render.resolution_x > scene.render.resolution_y else extent

    actions = list(bpy.data.actions)
    print("клипы в файле:", [a.name for a in actions])
    manifest = {"name": args.name, "frame_w": scene.render.resolution_x, "frame_h": scene.render.resolution_y,
                "pivot": {"x": 0.5, "y": 1.0 - (1 - 1 / args.margin) / 2}, "directions": args.directions,
                "direction_order": "d=0 анфас, далее по часовой стрелке (камера вокруг персонажа)",
                "character_height_m": round(height, 3), "actions": {}}

    wanted_order = list(frames_by_action.keys())
    for idx, (action_name, nframes) in enumerate(frames_by_action.items()):
        act = next((a for a in actions if action_name.lower() in a.name.lower()), None)
        if act is None and len(actions) == 1:
            act = actions[0]
        if act is None and len(actions) == len(wanted_order):
            act = actions[idx]  # клипы Meshy идут в порядке action_ids = порядке --frames
        if act is None:
            print(f"нет клипа для «{action_name}» — пропускаю", file=sys.stderr); continue
        if arm is not None:
            if arm.animation_data is None:
                arm.animation_data_create()
            arm.animation_data.action = act
        f0, f1 = act.frame_range
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
    (out / "sprites.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("готово:", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
