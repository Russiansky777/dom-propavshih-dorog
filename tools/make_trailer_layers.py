#!/usr/bin/env python3
"""TR1: слои глубины для плана «art» трейлера (data/trailer/<id>.json) → game/assets/trailer/.

Плоский арт (пейзаж главного меню) делится на планы по оценке глубины Depth Anything v2 small (ONNX, CPU): у каждого
слоя в данных `depth: [от, до]` — порог, выше которого пиксель принадлежит этому слою или более ближнему (мягкая
граница smoothstep). Слой — RGBA во весь холст, вдвое крупнее арта (Lanczos + лёгкая резкость: в 4K-съёмке меньше
«мыла»). Под ближними слоями цвет дорисован (cv2.inpaint), альфа там 0 у ближнего и 1 у дальнего: при параллаксе
из-за края ближнего показывается дорисованный фон, а не дыра и не растянутая «резина».

Модель скачивается один раз в build/cache/depth_anything_v2_small.onnx (нужны onnxruntime, opencv-contrib-python-headless, Pillow, numpy;
в CI не входят — готовые слои лежат в репозитории).

Запуск: python3 tools/make_trailer_layers.py [data/trailer/test_7s.json] [--debug]
"""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MODEL_URL = "https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model.onnx"
MODEL = ROOT / "build" / "cache" / "depth_anything_v2_small.onnx"
UPSCALE = 2


def res_path(res: str) -> Path:
    return ROOT / "game" / res.removeprefix("res://")


def depth_map(rgb: np.ndarray) -> np.ndarray:
    import onnxruntime as ort
    if not MODEL.exists():
        MODEL.parent.mkdir(parents=True, exist_ok=True)
        print(f"[layers] downloading {MODEL_URL}")
        urllib.request.urlretrieve(MODEL_URL, MODEL)
    h_img, w_img = rgb.shape[:2]
    h = 518
    w = int(round(w_img / h_img * h / 14)) * 14
    x = cv2.resize(rgb, (w, h), interpolation=cv2.INTER_CUBIC).astype(np.float32) / 255.0
    x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    x = x.transpose(2, 0, 1)[None].astype(np.float32)
    sess = ort.InferenceSession(str(MODEL), providers=["CPUExecutionProvider"])
    d = sess.run(None, {"pixel_values": x})[0][0]
    d = (d - d.min()) / max(1e-6, d.max() - d.min())
    d = cv2.resize(d.astype(np.float32), (w_img, h_img), interpolation=cv2.INTER_CUBIC)
    # Edge-aware refine: the depth comes at ~0.55× the art; a guided pass snaps the steps to the art's edges.
    d = cv2.ximgproc.guidedFilter(rgb.astype(np.float32) / 255.0, d, 4, 1e-4)
    return np.clip(d, 0.0, 1.0)


def smooth(e0: float, e1: float, d: np.ndarray) -> np.ndarray:
    if e1 <= e0:
        return (d >= e0).astype(np.float32)
    t = np.clip((d - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def upscale(rgba: np.ndarray) -> Image.Image:
    im = Image.fromarray(rgba, "RGBA")
    big = im.resize((im.width * UPSCALE, im.height * UPSCALE), Image.LANCZOS)
    rgb = big.convert("RGB").filter(ImageFilter.UnsharpMask(radius=1.6, percent=55, threshold=2))
    rgb.putalpha(big.getchannel("A"))
    return rgb


def fill(img: np.ndarray, hole: np.ndarray, radius: int = 9) -> np.ndarray:
    """Inpaints `hole` (uint8 mask) at half size (wide holes: smoother, faster), keeps the rest as it was."""
    small = cv2.resize(img, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
    hs = cv2.resize(hole, (small.shape[1], small.shape[0]), interpolation=cv2.INTER_NEAREST)
    filled = cv2.inpaint(small, hs, radius, cv2.INPAINT_TELEA)
    filled = cv2.resize(filled, (img.shape[1], img.shape[0]), interpolation=cv2.INTER_CUBIC)
    m = cv2.GaussianBlur(hole.astype(np.float32), (0, 0), 2.0)
    if img.ndim == 3:
        m = m[..., None]
    return (img * (1 - m) + filled * m).astype(img.dtype)


def build(shot: dict, debug: bool) -> None:
    """Two image layers (far: opaque, filled under the front; front: alpha by depth) and one depth texture:
    R — the far layer's depth (clamped below the front threshold, filled under the front), G — the front layer's
    depth (extended past its silhouette). The shader zooms every pixel by its own depth, so a surface that crosses
    the threshold (the ground) moves the same in both layers — no seam; only true depth steps (the house against
    the sky) open, and there the filled far layer shows."""
    art = Image.open(res_path(shot["art"])).convert("RGB")
    rgb = np.asarray(art)
    d = depth_map(rgb)
    far, front = [l for l in shot["layers"] if "image" in l]
    t0, t1 = front["depth"]
    alpha = smooth(t0, t1, d)
    # Matte: the depth edge comes blurred from 0.55× — a guided filter with the art as guide snaps it to the colour
    # edges (the post's dark rim belongs to the post), then a 2 px grow keeps the whole rim in the front layer.
    guide = rgb.astype(np.float32) / 255.0
    alpha = np.clip(cv2.ximgproc.guidedFilter(guide, alpha.astype(np.float32), 6, 1e-3), 0.0, 1.0)
    alpha = np.clip((alpha - 0.15) / 0.7, 0.0, 1.0)
    alpha = cv2.dilate(alpha, np.ones((3, 3), np.uint8), iterations=2)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.7)
    # The far layer is cleaned well past the silhouette (no ghost of the rim left behind when the front moves).
    hole = cv2.dilate((alpha > 0.02).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=8)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    far_rgb = cv2.cvtColor(fill(bgr, hole), cv2.COLOR_BGR2RGB)
    d8 = (d * 255).astype(np.uint8)
    far_d = fill(np.minimum(d8, int(t1 * 255)), hole, 15)
    inside = (alpha > 0.5).astype(np.uint8)
    front_d = fill(d8, cv2.erode(1 - inside, np.ones((3, 3), np.uint8)), 15)
    out = res_path(far["image"]).parent
    out.mkdir(parents=True, exist_ok=True)
    upscale(np.dstack([far_rgb, np.full(d.shape, 255, np.uint8)])).convert("RGB").save(res_path(far["image"]), optimize=True)
    upscale(np.dstack([rgb, (alpha * 255).astype(np.uint8)])).save(res_path(front["image"]), optimize=True)
    depth_rgb = np.dstack([far_d, front_d, np.zeros_like(d8)])
    Image.fromarray(depth_rgb).save(res_path(shot["depth_tex"]), optimize=True)
    print(f"[layers] {res_path(front['image']).relative_to(ROOT)}: front coverage {alpha.mean():.2f}")
    if debug:
        dbg = ROOT / "build" / "trailer_debug"
        dbg.mkdir(parents=True, exist_ok=True)
        Image.fromarray(d8).save(dbg / f"{shot['id']}_depth.png")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    plan = json.loads((ROOT / (args[0] if args else "data/trailer/test_7s.json")).read_text(encoding="utf-8"))
    for shot in plan["shots"]:
        if shot.get("kind") == "art" and any("image" in l for l in shot.get("layers", [])):
            build(shot, "--debug" in sys.argv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
