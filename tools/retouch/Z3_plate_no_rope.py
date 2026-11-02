"""Плита у поворота в сумерках до узла (Директор 02.11 вечер, № 7: «канат уже на ушке, когда Агата только хочет ставить
скобу»): слой партии 17 (state_plate_rope_dusk — плита, кольцо и канат с узлом) без каната. Канат выделен по цвету
(светлая пенька: R > G > B, R − B > 40). Плита — выпуклая оболочка её собственных пикселей (y ≥ 481 холста),
кольцо — эллиптическое кольцо по уцелевшей дуге (центр 1110,5; 476,5; полуоси 9,5 × 9; отверстие 4 × 3,6);
закрытые канатом места заполнены соседним железом (OpenCV inpaint), хвост каната над пустотой — прозрачен."""
from __future__ import annotations

import cv2
import numpy as np
from PIL import Image

RING_C = (1110.5, 476.5)
RING_OUT = (9.5, 9.0)
RING_IN = (4.0, 3.6)
PLATE_Y = 481


def retouch(im: Image.Image) -> Image.Image:
    a = np.array(im.convert("RGBA")).astype(np.int32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    rope = (al > 0) & (r > g) & (g > b) & ((r - b) > 40)
    rope = (cv2.dilate(rope.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & (al > 0)
    keep = (al > 128) & ~rope
    h, w = al.shape
    yy, xx = np.mgrid[0:h, 0:w]
    # the plate: convex hull of its own pixels
    py, px = np.nonzero(keep & (yy >= PLATE_Y))
    plate = np.zeros((h, w), np.uint8)
    hull = cv2.convexHull(np.stack([px, py], 1).astype(np.int32))
    cv2.fillConvexPoly(plate, hull, 1)
    # the ring: an elliptic annulus through the surviving arc
    e_out = ((xx - RING_C[0]) / RING_OUT[0]) ** 2 + ((yy - RING_C[1]) / RING_OUT[1]) ** 2 <= 1.0
    e_in = ((xx - RING_C[0]) / RING_IN[0]) ** 2 + ((yy - RING_C[1]) / RING_IN[1]) ** 2 <= 1.0
    ring = e_out & ~e_in
    solid = (plate > 0) | ring | keep
    hole = solid & ~keep
    rgb = a[..., :3].astype(np.uint8).copy()
    mean = rgb[keep].mean(0).astype(np.uint8)
    rgb[~keep] = mean       # transparent pixels carry no colour — the fill takes iron, not black
    filled = cv2.inpaint(np.ascontiguousarray(rgb), hole.astype(np.uint8) * 255, 2, cv2.INPAINT_TELEA)
    out = np.zeros_like(a)
    out[..., :3] = np.where(keep[..., None], a[..., :3], filled)
    alpha = np.where(keep, al, 0)
    alpha = np.where(hole, 255, alpha)
    # the hole of the ring stays open; a soft edge on the new outline
    out[..., 3] = alpha
    soft = cv2.GaussianBlur((out[..., 3] / 255.0).astype(np.float32), (3, 3), 0.6)
    out[..., 3] = np.where(hole, (soft * 255).astype(np.int32), out[..., 3])
    return Image.fromarray(out.astype(np.uint8), "RGBA")
