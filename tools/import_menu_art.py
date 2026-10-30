#!/usr/bin/env python3
"""Арт главного меню и паузы → game/assets/ui/menu/ (данные: data/story/menu.json).

Что пишет (все 1672×941, кроме листа и маски):
  title_bg.png         фон титульного экрана без пунктов меню — копия assets/incoming/main_menu_clean.png (чистый арт
                       ChatGPT 23.10: без пунктов, подсветки, листа, разделителей и подписи).
  title_signature.png  слой подписи «made by Yahor Zavatski, 2026», процарапанной на панели, — main_menu_signature_v2.png
                       (партия 10а, крупнее; нарисована под отражённое меню — сдвигается на левую панель на
                       title.signature_shift, H57: меню не отражаем, Директор 24.10, 01:06).
  pause_panel.png      резная деревянная панель паузы внизу экрана с вырезанным «Пауза» (без пунктов и строки Esc) —
                       pause_panel_wood.png (партия 10а, H58; прежний рушник pause_rushnik_panel.png не используется).
  title_leaf.png       лист-маркер, вырезанный из main_menu_v2.png (title.leaf_box) с мягкой прозрачностью.
  title_fx_mask.png    маска анимации 836×471 (половина арта): R — вода, G — ветви и травы (вес = размах), B — свет
                       окна. Полигоны — title.masks, внутри них отбор по цвету и гладкости арта.
  menu_art.json        откуда взят каждый файл.

Новая версия арта — положить файлы с теми же именами в assets/incoming/ и запустить скрипт; игра читает те же имена.
Оригиналы в assets/incoming не меняются. Нужны Pillow, numpy, opencv (не входят в CI: копии лежат в репозитории).

Запуск: python3 tools/import_menu_art.py            — записать
        python3 tools/import_menu_art.py --debug    — ещё и наложения масок в build/menu_debug/
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
INCOMING = ROOT / "assets" / "incoming"
OUT = ROOT / "game" / "assets" / "ui" / "menu"
DEBUG = ROOT / "build" / "menu_debug"
ART = (1672, 941)


def load_rgb(p: Path) -> np.ndarray:
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32)


def poly_mask(polys: list, size=ART, feather: float = 0.0) -> np.ndarray:
    im = Image.new("L", size, 0)
    d = ImageDraw.Draw(im)
    for p in polys:
        d.polygon([(float(p[i]), float(p[i + 1])) for i in range(0, len(p), 2)], fill=255)
    m = np.asarray(im).astype(np.float32) / 255.0
    if feather > 0:
        m = cv2.GaussianBlur(m, (0, 0), feather)
    return m


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def save_png(arr: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = "RGBA" if arr.shape[-1] == 4 else "RGB"
    Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), mode).save(path, optimize=True)


# --- Pieces --------------------------------------------------------------------------------

def leaf_from(src: np.ndarray, box: list) -> np.ndarray:
    x0, y0, x1, y1 = box
    c = src[y0:y1, x0:x1]
    L = luma(c)
    warm = c[..., 0] - c[..., 2]
    a = smoothstep(70, 125, L) * smoothstep(40, 90, warm)
    a = cv2.GaussianBlur(a, (0, 0), 0.6)
    # Colour of the leaf itself, un-darkened at the soft edge (premultiplication would leave a dark rim).
    return np.dstack([np.clip(c * 1.05, 0, 255), a * 255.0])


def fx_mask(src: np.ndarray, masks: dict) -> np.ndarray:
    H, W = src.shape[:2]
    L = luma(src)
    hsv = cv2.cvtColor(np.clip(src, 0, 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
    sat, val = hsv[..., 1], hsv[..., 2]
    # Water: inside the polygons, minus the piers, and only where the picture is smooth (open water) — the
    # trees at the near bank and the island edges have texture and stay still.
    zone = poly_mask(masks["water"]) * (1.0 - poly_mask(masks["water_cut"], feather=0))
    zone = np.clip(zone, 0, 1)
    mean = cv2.blur(L, (7, 7))
    var = cv2.blur(L * L, (7, 7)) - mean * mean
    smooth = 1.0 - smoothstep(70.0, 260.0, var)
    water = cv2.GaussianBlur(zone * smooth, (0, 0), 3.0) * cv2.GaussianBlur(zone, (0, 0), 2.0)
    water = np.clip(water * 1.25, 0, 1)
    # J (Директор 29.10, стр. 4: «ближняя вода тоже качается»): лужи на тропинке у крыльца — свой отбор, мягче (в
    # них листья и блики заката), и слабее (`water_near_weight`): рябь лужи, не течение реки.
    if masks.get("water_near"):
        zn = poly_mask(masks["water_near"], feather=6.0)
        smooth_n = 1.0 - smoothstep(180.0, 900.0, var)
        near = cv2.GaussianBlur(zn * smooth_n, (0, 0), 2.0) * float(masks.get("water_near_weight", 0.6))
        water = np.maximum(water, np.clip(near, 0, 1))
    # Директор 25.10 стр. 2, 29.10 стр. 4: «вода ближе к берегу статична» — полоса озера у ближнего берега, между
    # верхушками прибрежных деревьев, и дорожка солнца у берега. Здесь вода в бликах (рябь заката) — отбор мягче, чем
    # у открытой воды, но без деревьев: кроны тёплые/тёмные, стволы и ветки дают вертикальные перепады (|gx| > |gy|),
    # а рябь — горизонтальные; всё «не вода» расширено на 3 px, чтобы края крон не плыли.
    if masks.get("water_shore"):
        zs = poly_mask(masks["water_shore"], feather=4.0)
        smooth_s = 1.0 - smoothstep(300.0, 1400.0, var)
        gx = cv2.GaussianBlur(np.abs(cv2.Sobel(L, cv2.CV_32F, 1, 0, ksize=3)), (0, 0), 3.0)
        gy = cv2.GaussianBlur(np.abs(cv2.Sobel(L, cv2.CV_32F, 0, 1, ksize=3)), (0, 0), 3.0)
        flat = 1.0 - smoothstep(0.9, 1.5, gx / (gy + 4.0))
        tree = smoothstep(90, 140, sat) * (1.0 - smoothstep(170, 215, val))
        dark = 1.0 - smoothstep(55, 85, val)
        ok = np.clip(smooth_s * flat * (1.0 - tree) * (1.0 - dark), 0, 1)
        not_water = cv2.dilate((ok < 0.5).astype(np.uint8), np.ones((7, 7), np.uint8)).astype(np.float32)
        shore = cv2.GaussianBlur(zs * (1.0 - not_water), (0, 0), 1.5) * float(masks.get("water_shore_weight", 0.85))
        water = np.maximum(water, np.clip(shore, 0, 1))
    # Sway: leaves (warm, saturated) and thin twigs (darker than the sky around them) inside each zone; the weight
    # grows with the distance from the anchor (trunk / ground) up to reach_px — tips move, the base does not.
    sway = np.zeros((H, W), np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    for z in masks["sway"]:
        zm = poly_mask([z["poly"]], feather=2.0)
        leaves = smoothstep(70, 130, sat) * smoothstep(60, 110, val) * (src[..., 0] > src[..., 2] + 20)
        sky = cv2.GaussianBlur(L, (0, 0), 6.0)
        twigs = smoothstep(10, 35, sky - L) if z["kind"] == "branches" else np.zeros_like(L)
        stuff = np.clip(np.maximum(leaves, twigs), 0, 1)
        if z["kind"] == "branches":
            # Leaves are textured and in shade; the warm clouds behind them are smooth and bright.
            stuff = stuff * smoothstep(40.0, 160.0, var) * (1.0 - smoothstep(190.0, 225.0, val))
        stuff = cv2.dilate(stuff, np.ones((3, 3), np.uint8))
        stuff = cv2.GaussianBlur(stuff, (0, 0), 1.6)
        if "trunk" in z:
            trunk = poly_mask([z["trunk"]])
            dist = cv2.distanceTransform((1 - trunk).astype(np.uint8), cv2.DIST_L2, 5)
        else:
            dist = np.clip(float(z["anchor_y"]) - yy, 0, None)
        reach = smoothstep(0.0, float(z["reach_px"]), dist)
        sway = np.maximum(sway, zm * stuff * reach)
    if masks.get("sway_cut"):
        sway *= 1.0 - poly_mask(masks["sway_cut"], feather=1.5)
    # Window: the warm light behind the glass (bright, warm), softly feathered past the panes.
    win = poly_mask([masks["window"]], feather=1.5)
    light = smoothstep(95, 170, L) * smoothstep(20, 60, src[..., 0] - src[..., 2])
    glow = np.clip(cv2.GaussianBlur(win * light, (0, 0), 2.5) * 1.15, 0, 1)
    out = np.dstack([water, sway, glow]) * 255.0
    half = cv2.resize(out, (W // 2, H // 2), interpolation=cv2.INTER_AREA)
    return half


def copy_layer(name: str, out: str, mode: str, shift=(0, 0)) -> str:
    src = INCOMING / name
    if not src.exists():
        raise SystemExit(f"нет {src.relative_to(ROOT)} — чистый арт меню (ChatGPT) не доставлен")
    im = Image.open(src).convert(mode)
    if im.size != ART:
        raise SystemExit(f"{name}: {im.size}, ждём {ART}")
    if tuple(shift) != (0, 0):
        moved = Image.new(mode, ART, (0, 0, 0, 0))
        moved.alpha_composite(im, (int(shift[0]), int(shift[1])))
        im = moved
    im.save(OUT / out, optimize=True)
    return f"assets/incoming/{name}" + (f" shifted {list(shift)}" if tuple(shift) != (0, 0) else "")


def main() -> int:
    debug = "--debug" in sys.argv
    menu = json.loads((ROOT / "data" / "story" / "menu.json").read_text(encoding="utf-8"))
    t = menu["title"]
    OUT.mkdir(parents=True, exist_ok=True)
    record: dict = {}
    record["title_bg"] = copy_layer("main_menu_clean.png", "title_bg.png", "RGB")
    record["title_signature"] = copy_layer("main_menu_signature_v2.png", "title_signature.png", "RGBA",
                                          t.get("signature_shift", [0, 0]))
    record["pause_panel"] = copy_layer("pause_panel_wood.png", "pause_panel.png", "RGBA")
    save_png(leaf_from(load_rgb(INCOMING / "main_menu_v2.png"), t["leaf_box"]), OUT / "title_leaf.png")
    record["title_leaf"] = "cut from assets/incoming/main_menu_v2.png " + str(t["leaf_box"])
    bg = load_rgb(INCOMING / "main_menu_clean.png")
    mask = fx_mask(bg, t["masks"])
    save_png(mask, OUT / "title_fx_mask.png")
    record["title_fx_mask"] = "data/story/menu.json title.masks over main_menu_clean.png"
    (OUT / "menu_art.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if debug:
        DEBUG.mkdir(parents=True, exist_ok=True)
        big = cv2.resize(mask, ART, interpolation=cv2.INTER_LINEAR) / 255.0
        ov = bg * 0.55
        ov[..., 0] += big[..., 1] * 200          # sway — red
        ov[..., 2] += big[..., 0] * 220          # water — blue
        ov[..., 1] += big[..., 2] * 220          # window — green
        save_png(np.clip(ov, 0, 255), DEBUG / "fx_mask_overlay.png")
    for k, v in record.items():
        print(f"{k}: {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
