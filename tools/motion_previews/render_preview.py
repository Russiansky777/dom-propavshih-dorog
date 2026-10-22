#!/usr/bin/env python3
"""Ролик-превью клипа на Агате (Blender как модуль bpy, Cycles CPU): 1280×720, 24 к/с, H.264, ≤ 1,5 МБ.

  python render_preview.py --clip <id> --clips clips.json --target agata_rt.glb --rt out/ --out previews/ \
      [--font PT_Serif.ttf] [--only-frames 0,40] [--samples 8]

Ходьба — три панели: к зрителю (вниз по экрану, как в игре), профиль (вправо), по диагонали; idle — 3/4 спереди
и профиль. Ортокамера 14° над горизонтом (как у листов и 3D в игре); свет — три солнца и мир 0,6 из
pipeline/render/render_sprites.py, повёрнутые вместе с камерой (как при рендере листов: свет и камера неподвижны
относительно кадра). Камера едет за тазом по прямой с постоянной скоростью, пол неподвижен: шкала 10 см / 50 см /
1 м — проскальзывание стоп видно по шкале. Подпись в кадре: библиотека, клип, лицензия, замеры.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import bsrc  # noqa: E402
import mlib  # noqa: E402

W, H = 1280, 720
CAP = 84          # полоса подписи снизу (3 строки)
ELEV = 14.0
PX_PER_M = 290.0  # масштаб фигуры в панели
LOOK_Z = 0.80

VIEWS = {
    # азимут камеры: 0 — камера в −Y (персонаж идёт к зрителю), −90 — камера в −X (ход вправо по экрану)
    "walk": [("к зрителю", 0.0), ("профиль", -90.0), ("по диагонали", -45.0)],
    "idle": [("3/4 спереди", -35.0), ("профиль", -90.0)],
}


def floor_texture(path: Path, size_m=2.0, px=2048):
    """Плитка пола 2×2 м: светлое дерево, линии каждые 10 см, толще — 50 см, ещё толще — 1 м."""
    rng = np.random.default_rng(7)
    base = np.array([172, 150, 124], float)
    img = np.ones((px, px, 3)) * base
    # доски вдоль Y по 20 см с лёгкой разницей тона и волокном
    ppm = px / size_m
    for i in range(int(size_m / 0.2)):
        x0, x1 = int(i * 0.2 * ppm), int((i + 1) * 0.2 * ppm)
        img[:, x0:x1] *= 1.0 + rng.uniform(-0.035, 0.035)
    grain = rng.normal(0, 1, (px, 64))
    grain = np.repeat(grain, px // 64, axis=1)
    from numpy.fft import fft, ifft
    g = np.real(ifft(fft(grain, axis=0) * (np.abs(np.fft.fftfreq(px))[:, None] < 0.01), axis=0))
    img *= (1 + 0.025 * g / (np.abs(g).max() + 1e-9))[..., None]
    def line(pos_m, w_px, col):
        c = int(round(pos_m * ppm)) % px
        for d in range(-(w_px // 2), w_px - w_px // 2):
            img[:, (c + d) % px] = col
            img[(c + d) % px, :] = col
    for k in range(int(size_m / 0.1)):
        line(k * 0.1, 3, (118, 100, 82))
    for k in range(int(size_m / 0.5)):
        line(k * 0.5, 7, (92, 76, 60))
    for k in range(int(size_m / 1.0)):
        line(k * 1.0, 12, (62, 50, 40))
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(path)


def build_scene(target: str, work: Path, samples: int):
    bsrc.reset(24.0)
    arm, meshes, acts, sk, fg = bsrc.load_target(target)
    sc = bpy.context.scene
    # пол
    tex = work / "floor.png"
    if not tex.exists():
        floor_texture(tex)
    bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("Floor")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (0.5, 0.5, 0.5)
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = bpy.data.images.load(str(tex))
    im.interpolation = "Cubic"
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], im.inputs["Vector"])
    nt.links.new(im.outputs["Color"], bsdf.inputs["Base Color"])
    floor.data.materials.append(mat)
    # свет — как render_sprites.py, на общем «держателе», который поворачивается вместе с камерой
    rig = bpy.data.objects.new("LightRig", None)
    sc.collection.objects.link(rig)
    for nm, en, ang, rot in (("Key", 4.5, 20, (55, 0, -35)), ("Fill", 2.0, 40, (70, 0, 140)), ("Rim", 2.5, 10, (120, 0, 20))):
        ld = bpy.data.lights.new(nm, "SUN")
        ld.energy = en
        ld.angle = math.radians(ang)
        lo = bpy.data.objects.new(nm, ld)
        sc.collection.objects.link(lo)
        lo.rotation_euler = tuple(math.radians(x) for x in rot)
        lo.parent = rig
    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.6, 0.6, 0.65, 1)
    bg.inputs[1].default_value = 1.0
    # камера
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.clip_start = 0.1
    cd.clip_end = 200
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # Cycles
    sc.render.engine = "CYCLES"
    c = sc.cycles
    c.device = "CPU"
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.05
    c.use_denoising = True
    c.max_bounces = 4
    c.diffuse_bounces = 2
    c.glossy_bounces = 1
    c.transmission_bounces = 1
    c.transparent_max_bounces = 6
    c.volume_bounces = 0
    sc.render.use_persistent_data = True
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.resolution_percentage = 100
    return arm, sk, fg, cam, rig


def place_camera(cam, rig, az_deg, look: np.ndarray, w_px: int, h_px: int):
    sc = bpy.context.scene
    sc.render.resolution_x = w_px
    sc.render.resolution_y = h_px
    cam.data.ortho_scale = max(w_px, h_px) / PX_PER_M
    e = math.radians(ELEV)
    a = math.radians(az_deg)
    # направление от цели к камере: азимут 0 → −Y
    d = np.array([math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)])
    dist = 20.0
    pos = look + d * dist
    cam.location = Vector(pos.tolist())
    cam.rotation_euler = (Vector(look.tolist()) - cam.location).to_track_quat("-Z", "Y").to_euler()
    rig.rotation_euler = (0.0, 0.0, a)


def caption_font(path: str | None, size: int):
    for p in [path, "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if p and Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip", required=True)
    ap.add_argument("--clips", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--rt", required=True, help="каталог с <id>.npz и <id>.json от retarget_clip.py")
    ap.add_argument("--out", required=True)
    ap.add_argument("--font", default=None)
    ap.add_argument("--font-bold", default=None)
    ap.add_argument("--samples", type=int, default=8)
    ap.add_argument("--only-frames", default="")
    ap.add_argument("--duration", type=float, nargs=2, default=[6.0, 8.0])
    ap.add_argument("--max-bytes", type=int, default=1_450_000)
    args = ap.parse_args()
    if not args.only_frames and not shutil.which("ffmpeg"):
        print("нет ffmpeg — рендер не начинаю (кадры пропали бы без ролика)", flush=True)
        return 4
    cfg = json.load(open(args.clips, encoding="utf-8"))
    spec = next(c for c in cfg["clips"] if c["id"] == args.clip)
    lib = cfg["libraries"][spec["library"]]
    d = np.load(Path(args.rt) / f"{spec['id']}.npz")
    meta = json.loads((Path(args.rt) / f"{spec['id']}.json").read_text(encoding="utf-8"))
    N = len(d["root_P"])
    loop_s = N / 24.0
    reps = max(1, int(math.ceil(args.duration[0] / loop_s - 1e-6)))
    while reps > 1 and reps * loop_s > args.duration[1] + 1e-6:
        reps -= 1
    total = N * reps
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    work = out_dir / f"_frames_{spec['id']}"
    work.mkdir(parents=True, exist_ok=True)

    arm, sk, fg, cam, rig = build_scene(args.target, work, args.samples)
    basis = mlib.quat_to_mat(d["basis_quat"].astype(float))
    root = d["root_P"].astype(float)
    disp = d["disp"].astype(float)
    views = VIEWS[spec["type"]]
    # все панели рендерятся одного размера (Cycles с persistent data не пересобирает сцену между панелями),
    # последняя обрезается до края кадра
    pw = -(-W // len(views))
    widths = [pw] * len(views)
    ph = H - CAP
    f_big = caption_font(args.font_bold or args.font, 22)
    f_small = caption_font(args.font, 15)
    f_lab = caption_font(args.font, 17)
    feet = meta["feet"]
    def fmt(v, unit):
        return "—" if v is None else f"{v:.1f}".replace(".", ",") + unit
    line1 = spec["caption"]
    if spec["type"] == "walk":
        m = (f"скольжение опорной стопы ≤ L {fmt(feet['L']['slide_mm_max'], ' мм')} / R {fmt(feet['R']['slide_mm_max'], ' мм')}"
             f" · носок наружу L {fmt(feet['L']['toe_out_deg'], '°')} / R {fmt(feet['R']['toe_out_deg'], '°')}"
             f" · {meta['speed_mps']:.2f} м/с".replace(".", ","))
    else:
        m = (f"скольжение стоп ≤ L {fmt(feet['L']['slide_mm_max'], ' мм')} / R {fmt(feet['R']['slide_mm_max'], ' мм')}"
             f" · носок наружу L {fmt(feet['L']['toe_out_deg'], '°')} / R {fmt(feet['R']['toe_out_deg'], '°')}"
             f" · рыскание таза {meta['hips_yaw_range_deg']:.0f}°".replace(".", ","))
    line2 = (f"Лицензия: {lib['license']}   ·   петля {loop_s:.2f} с ×{reps}".replace(".", ",")
             + ("   ·   без чистки (как в игре)" if not meta.get("cleanup", True) else "   ·   после чистки стоп (IK)"))
    only = [int(x) for x in args.only_frames.split(",") if x != ""]
    frames = only if only else list(range(total))
    sc = bpy.context.scene
    for f in frames:
        k, j = divmod(f, N)
        rootw = root[j] + k * disp
        bsrc.pose_agata(arm, sk, basis[j], rootw)
        bpy.context.view_layer.update()
        if spec["type"] == "walk":
            look = np.array([0.0, 0.0, LOOK_Z]) + disp * (f / N)
            look[:2] += root[0, :2]
        else:
            look = np.array([root[:, 0].mean(), root[:, 1].mean(), LOOK_Z])
        canvas = Image.new("RGB", (W, H), (24, 22, 20))
        x = 0
        for (label, az), w in zip(views, widths):
            place_camera(cam, rig, az, look, w, ph)
            tmp = work / f"_p{f:04d}_{int(az)}.png"
            sc.render.filepath = str(tmp)
            bpy.ops.render.render(write_still=True)
            pim = Image.open(tmp).convert("RGB")
            canvas.paste(pim.crop((0, 0, min(w, W - x), ph)), (x, 0))
            dr = ImageDraw.Draw(canvas)
            dr.rectangle([x + 8, 8, x + 16 + dr.textlength(label, font=f_lab), 34], fill=(24, 22, 20))
            dr.text((x + 12, 10), label, font=f_lab, fill=(235, 228, 215))
            if x > 0:
                dr.line([(x, 0), (x, ph)], fill=(24, 22, 20), width=2)
            x += w
            tmp.unlink()
        dr = ImageDraw.Draw(canvas)
        dr.text((14, ph + 5), line1, font=f_big, fill=(240, 232, 218))
        dr.text((14, ph + 35), line2, font=f_small, fill=(200, 192, 180))
        dr.text((14, ph + 57), m, font=f_small, fill=(200, 192, 180))
        canvas.save(work / f"f{f:04d}.png")
        print(f"кадр {f + 1}/{total}", flush=True)
    if only:
        return 0
    mp4 = out_dir / f"{spec['id']}.mp4"
    dur = total / 24.0
    ok = encode(work, mp4, dur, args.max_bytes)
    shutil.rmtree(work, ignore_errors=True)
    info = {"id": spec["id"], "mp4": mp4.name, "bytes": mp4.stat().st_size, "duration_s": round(dur, 3), "frames": total,
            "loop_frames": N, "loops": reps, "size_ok": ok}
    (out_dir / f"{spec['id']}.render.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(info, ensure_ascii=False), flush=True)
    return 0 if ok else 3


def encode(frames_dir: Path, mp4: Path, dur: float, max_bytes: int) -> bool:
    """Двухпроходный x264 под потолок размера; если всё же больше — понижаем битрейт."""
    rate = max_bytes * 8 / dur * 0.92
    for attempt in range(4):
        kb = int(rate / 1000)
        base = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", "24", "-i", str(frames_dir / "f%04d.png"),
                "-c:v", "libx264", "-preset", "slow", "-pix_fmt", "yuv420p", "-b:v", f"{kb}k",
                "-maxrate", f"{int(kb * 1.3)}k", "-bufsize", f"{kb * 2}k", "-movflags", "+faststart"]
        log = str(frames_dir / "x264")
        subprocess.run(base + ["-pass", "1", "-passlogfile", log, "-an", "-f", "mp4", "/dev/null"], check=True)
        subprocess.run(base + ["-pass", "2", "-passlogfile", log, str(mp4)], check=True)
        size = mp4.stat().st_size
        print(f"x264 {kb} кбит/с → {size} байт", flush=True)
        if size <= max_bytes:
            return True
        rate *= max_bytes / size * 0.95
    return False


if __name__ == "__main__":
    sys.exit(main())
