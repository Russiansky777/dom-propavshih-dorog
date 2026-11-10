#!/usr/bin/env python3
"""Убрать медленное сползание камеры из клипа image-to-video (10.11: объятие Агаты и мамы, Kling 3.0 Pro 1080p —
при «Static camera» вся картина за последние 2,5 с съехала на 3,7 точки вниз; на шве петли, где хвост наплывом
сводится в первый кадр, вся картина двоилась бы раз в 10 с).

Проход 1: сдвиг каждого кадра против первого — фазовая корреляция (до долей точки) по неподвижным участкам
(`--patches "x,y,w,h;…"`, медиана по ним) или по всему кадру (по умолчанию); ряд сглажен (медиана 9, среднее 9).
Проход 2: каждый кадр сдвинут обратно (кубическая интерполяция, край — повтор крайних точек), H.264 crf 10.
Кадры идут через каналы — на диск пишется только результат. Затем петля: tools/video_loop.py.

  python3 tools/video_stabilize.py --in clip.mp4 --out steady.mp4 [--patches "0,0,400,400;100,640,500,400"]
  python3 tools/video_stabilize.py --in clip.mp4 --measure      → только замер (JSON), файл не пишется

Проверка результата — tools/validate_video_loops.py (п. 5 «камера стоит», самопроверка там же).
"""
import argparse
import json
import subprocess
import sys

import cv2
import numpy as np


def probe(src: str):
    info = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                    "stream=width,height,r_frame_rate", "-of", "csv=p=0", src]).decode().strip().split(",")
    return int(info[0]), int(info[1]), info[2]


def frames(src: str, w: int, h: int, pix: str):
    n = w * h * (1 if pix == "gray" else 3)
    p = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-i", src, "-f", "rawvideo", "-pix_fmt", pix, "-"], stdout=subprocess.PIPE)
    while True:
        b = p.stdout.read(n)
        if len(b) < n:
            break
        yield np.frombuffer(b, np.uint8).reshape((h, w) if pix == "gray" else (h, w, 3))
    p.wait()


def smooth(v: np.ndarray, k: int = 9) -> np.ndarray:
    pad = np.pad(v, (k // 2, k // 2), mode="edge")
    med = np.array([np.median(pad[i:i + k]) for i in range(len(v))])
    pad = np.pad(med, (k // 2, k // 2), mode="edge")
    return np.convolve(pad, np.ones(k) / k, mode="valid")


def measure(src: str, patches: list):
    w, h, _fps = probe(src)
    if not patches:
        patches = [(0, 0, w, h)]
    ref = None
    wins = []
    out = []
    for f in frames(src, w, h, "gray"):
        g = f.astype(np.float32)
        if ref is None:
            ref = g
            wins = [cv2.createHanningWindow((pw, ph), cv2.CV_32F) for (_x, _y, pw, ph) in patches]
        s = [cv2.phaseCorrelate(ref[y:y + ph, x:x + pw], g[y:y + ph, x:x + pw], win)[0] for (x, y, pw, ph), win in zip(patches, wins)]
        out.append(np.median(np.array(s), axis=0))
    sh = np.array(out)
    return smooth(sh[:, 0]), smooth(sh[:, 1])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--patches", default="", help='неподвижные участки "x,y,w,h;x,y,w,h"; пусто — весь кадр')
    ap.add_argument("--measure", action="store_true")
    a = ap.parse_args()
    patches = [tuple(int(v) for v in p.split(",")) for p in a.patches.split(";") if p.strip()]
    sx, sy = measure(a.src, patches)
    sec = lambda v: [round(float(v[min(i * 24, len(v) - 1)]), 2) for i in range(0, 11)]
    print(json.dumps({"frames": len(sx), "drift_px_end": [round(float(sx[-1]), 2), round(float(sy[-1]), 2)],
                      "drift_px_max": [round(float(np.abs(sx).max()), 2), round(float(np.abs(sy).max()), 2)],
                      "by_second_x": sec(sx), "by_second_y": sec(sy)}))
    if a.measure or not a.out:
        return 0
    w, h, fps = probe(a.src)
    enc = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", fps,
                            "-i", "-", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "10", "-pix_fmt", "yuv420p", a.out], stdin=subprocess.PIPE)
    for i, f in enumerate(frames(a.src, w, h, "rgb24")):
        if abs(sx[i]) > 0.02 or abs(sy[i]) > 0.02:
            m = np.float32([[1, 0, -sx[i]], [0, 1, -sy[i]]])
            f = cv2.warpAffine(f, m, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        enc.stdin.write(f.tobytes())
    enc.stdin.close()
    enc.wait()
    print("written", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
