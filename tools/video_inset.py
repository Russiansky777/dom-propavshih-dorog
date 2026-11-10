#!/usr/bin/env python3
"""Вклеить в ролик-картину фигуру, оживлённую отдельно (Директор 10.11, 17:36–17:43: Агата на ужине — «как ты
собираешься оживить и вставить… там же не идеально пиксель в пиксель окружение будет» → «Ок, можем сделать пробу»).

Kling в двух пробах всего кадра ужина не оживил Агату (она мала и наполовину за самоваром). Её крупная вырезка из той
же картины оживляется отдельным роликом, а в основной ролик берётся только сама фигура:
  · маска — слой фигуры в картине (--figure, альфа) минус всё, что нарисовано перед ней (--front, альфа: стол, кувшин,
    соседи), расширенная на --grow точек холста (голова поворачивается — силуэт меняется) с мягким краем --feather;
    то, что перед фигурой, всегда остаётся от основного ролика;
  · вырезка стоит в основном кадре там же, где в картине (--rect x0,y0,x1,y1 холста), с точностью до долей точки;
  · сползание вырезки (камера) меряется по неподвижной кайме вокруг маски против её первого кадра и убирается;
  · цвет: по той же кайме средний цвет вырезки подгоняется к основному ролику в каждом кадре (свеча в основном ролике
    мерцает — фигура мерцает вместе с ним).
Печатает замеры: сдвиг, поправку цвета, разницу по кайме до и после (шов), сколько движется сама фигура.

  python3 tools/video_inset.py --main dinner.mp4 --inset agata.mp4 --canvas 1672x941 --rect 1213,300,1429,588 \
      --figure game/assets/rooms/EP_dinner/agata.png --front game/assets/rooms/EP_dinner/family.png --out out.mp4
"""
import argparse
import json
import subprocess
import sys

import cv2
import numpy as np


def probe(path: str):
    o = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                 "stream=width,height,r_frame_rate,nb_frames", "-of", "csv=p=0", path]).decode().strip().split(",")
    return int(o[0]), int(o[1]), o[2]


def frames(path: str, w: int, h: int, fps: str):
    """Кадры в YUV 4:4:4 как (h, w, 3): без перевода в RGB (путь через rgb24 затемняет картинку на 1,1–1,3/255)."""
    p = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vf", f"fps={fps}", "-f", "rawvideo", "-pix_fmt", "yuv444p", "-"],
                         stdout=subprocess.PIPE)
    n = w * h * 3
    while True:
        b = p.stdout.read(n)
        if len(b) < n:
            break
        yield np.ascontiguousarray(np.frombuffer(b, np.uint8).reshape(3, h, w).transpose(1, 2, 0))
    p.wait()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--main", required=True)
    ap.add_argument("--inset", required=True)
    ap.add_argument("--canvas", required=True, help="размер картины, WxH")
    ap.add_argument("--rect", required=True, help="место вырезки в картине: x0,y0,x1,y1")
    ap.add_argument("--figure", required=True, help="слой фигуры (PNG с альфой, холст картины)")
    ap.add_argument("--front", default="", help="слой того, что перед фигурой (PNG с альфой)")
    ap.add_argument("--grow", type=float, default=10.0, help="расширение маски, точек холста")
    ap.add_argument("--feather", type=float, default=3.0, help="мягкий край маски, точек холста")
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--no-steady", action="store_true")
    a = ap.parse_args()
    cw, ch = (int(v) for v in a.canvas.lower().split("x"))
    x0, y0, x1, y1 = (float(v) for v in a.rect.split(","))
    mw, mh, fps = probe(a.main)
    iw, ih, _ = probe(a.inset)
    sx, sy = mw / cw, mh / ch
    # маска на холсте → в кадр основного ролика
    fig = cv2.imread(a.figure, cv2.IMREAD_UNCHANGED)[:, :, 3].astype(np.float32) / 255.0
    front = np.zeros_like(fig)
    if a.front:
        front = cv2.imread(a.front, cv2.IMREAD_UNCHANGED)[:, :, 3].astype(np.float32) / 255.0
    g = max(1, int(round(a.grow)))
    grown = cv2.dilate(fig, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * g + 1, 2 * g + 1)))
    soft = cv2.GaussianBlur(grown, (0, 0), a.feather)
    # вырезка не знает ничего за своим краем: маска гаснет к краю вырезки
    box = np.zeros_like(fig)
    m = int(round(a.feather * 2))
    box[int(y0) + m:int(y1) - m, int(x0) + m:int(x1) - m] = 1.0
    box = cv2.GaussianBlur(box, (0, 0), a.feather)
    mask_c = soft * box * (1.0 - front)
    # кайма: вокруг расширенной маски, внутри вырезки, не перед фигурой и не под ней — по ней сверяются цвет и сдвиг
    ring_c = (cv2.dilate(grown, np.ones((25, 25), np.uint8)) > 0.5) & (grown < 0.01) & (front < 0.01)
    ring_box = np.zeros_like(fig, dtype=bool)
    ring_box[int(y0) + 4:int(y1) - 4, int(x0) + 4:int(x1) - 4] = True
    ring_c &= ring_box
    mask = cv2.resize(mask_c, (mw, mh), interpolation=cv2.INTER_LINEAR)[:, :, None]
    ring = cv2.resize(ring_c.astype(np.uint8), (mw, mh), interpolation=cv2.INTER_NEAREST) > 0
    # вырезка → кадр: масштаб и сдвиг
    kx, ky = (x1 - x0) * sx / iw, (y1 - y0) * sy / ih
    ys, xs = np.where(mask[:, :, 0] > 0.004)
    bx0, bx1, by0, by1 = max(0, xs.min() - 30), min(mw, xs.max() + 31), max(0, ys.min() - 30), min(mh, ys.max() + 31)
    ring_b = ring[by0:by1, bx0:bx1]
    enc = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "yuv444p", "-s", f"{mw}x{mh}", "-r", fps, "-i", "-",
                            "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p", a.out], stdin=subprocess.PIPE)
    ref = None
    win = None
    cover = 1.0 - cv2.resize(cv2.GaussianBlur(grown, (0, 0), 2.0)[int(y0):int(y1), int(x0):int(x1)], (iw, ih), interpolation=cv2.INTER_LINEAR)
    stats = {"shift": [], "gain": [], "seam_before": [], "seam_after": [], "figure_motion": []}
    first_fig = None
    n = 0
    for fm, fi in zip(frames(a.main, mw, mh, fps), frames(a.inset, iw, ih, fps)):
        dx = dy = 0.0
        if not a.no_steady:
            # фигура закрыта: сдвиг — по окружению; мерим на уменьшенной яркости (шум кодека не решает), ответ в точках вырезки
            gi_s = cv2.resize(fi[:, :, 0].astype(np.float32) * cover, (iw // 3, ih // 3), interpolation=cv2.INTER_AREA)
            if ref is None:
                ref = gi_s
                win = cv2.createHanningWindow((iw // 3, ih // 3), cv2.CV_32F)
            (dx, dy), resp = cv2.phaseCorrelate(ref, gi_s, win)
            dx, dy = dx * 3.0, dy * 3.0
            if resp < 0.15 or abs(dx) > 40.0 or abs(dy) > 40.0:
                dx = dy = 0.0   # нет уверенного пика — кадр не двигаем
        M = np.float32([[kx, 0, x0 * sx - dx * kx - bx0], [0, ky, y0 * sy - dy * ky - by0]])
        warped = cv2.warpAffine(fi, M, (bx1 - bx0, by1 - by0), flags=cv2.INTER_AREA if kx < 0.6 else cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE).astype(np.float32)
        sub = fm[by0:by1, bx0:bx1].astype(np.float32)
        before = float(np.abs(warped[ring_b] - sub[ring_b]).mean())
        gain = np.ones(3, np.float32)
        if not a.no_color and ring_b.any():
            # яркость (Y) — множителем от чёрного (16), цветность (U, V) — сдвигом: свеча мерцает — фигура с ней
            ms, mi = sub[ring_b].mean(axis=0), warped[ring_b].mean(axis=0)
            gain[0] = float(np.clip((ms[0] - 16.0) / max(mi[0] - 16.0, 1.0), 0.8, 1.25))
            warped[:, :, 0] = (warped[:, :, 0] - 16.0) * gain[0] + 16.0
            warped[:, :, 1:] += np.clip(ms[1:] - mi[1:], -6.0, 6.0)
            warped = np.clip(warped, 0, 255)
        after = float(np.abs(warped[ring_b] - sub[ring_b]).mean())
        mk = mask[by0:by1, bx0:bx1]
        out = fm.copy()
        out[by0:by1, bx0:bx1] = np.clip(warped * mk + sub * (1.0 - mk), 0, 255).astype(np.uint8)
        enc.stdin.write(np.ascontiguousarray(out.transpose(2, 0, 1)).tobytes())
        figpx = warped[mk[:, :, 0] > 0.9]
        if first_fig is None:
            first_fig = figpx.copy()
        stats["shift"].append((round(float(dx), 2), round(float(dy), 2)))
        stats["gain"].append(float(gain[0]))
        stats["seam_before"].append(before)
        stats["seam_after"].append(after)
        stats["figure_motion"].append(float(np.abs(figpx - first_fig).mean()))
        n += 1
    enc.stdin.close()
    enc.wait()
    sh = np.array(stats["shift"])
    print(json.dumps({"frames": n, "inset_px": [iw, ih], "scale": [round(kx, 4), round(ky, 4)],
                      "shift_max_px_inset": [float(np.abs(sh[:, 0]).max()), float(np.abs(sh[:, 1]).max())],
                      "gain_range": [round(min(stats["gain"]), 3), round(max(stats["gain"]), 3)],
                      "seam_ring_diff_before": round(float(np.mean(stats["seam_before"])), 2),
                      "seam_ring_diff_after": round(float(np.mean(stats["seam_after"])), 2),
                      "figure_away_from_start_max": round(max(stats["figure_motion"]), 1),
                      "figure_away_from_start_mean": round(float(np.mean(stats["figure_motion"])), 1),
                      "out": a.out}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
