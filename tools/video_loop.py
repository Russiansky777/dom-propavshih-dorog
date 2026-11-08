#!/usr/bin/env python3
"""Петля из клипа image-to-video для кадра-картины (Директор 08.11, 23:07/23:26: «луп… первый и последний кадр
должны совпадать, и разрыва не было»). У клипов fal.ai первый кадр — сама картина; хвост (последние `--seam` с)
наплывом сводится в первый кадр, так что стык — короткое «успокоение» в рисунок, не скачок. Звук отбрасывается.
Выход: Ogg Theora для Godot (VideoStreamPlayer: data background.video) + MP4 для просмотра.

  python3 tools/video_loop.py --in clip.mp4 --out game/assets/rooms/F_hug_pelageya/loop [--seam 1.0] [--fps 24]
  → loop.ogv, loop.mp4; печатает длительность и разницу первого/последнего кадра (0..255, до и после).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-2000:], file=sys.stderr)
        raise SystemExit("ffmpeg: " + " ".join(cmd[:3]))
    return r


def duration(path: str) -> float:
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]).decode().strip()
    return float(out)


def frame_diff(path: str, t0: float, t1: float) -> float:
    from PIL import Image
    import numpy as np
    with tempfile.TemporaryDirectory() as d:
        a, b = os.path.join(d, "a.png"), os.path.join(d, "b.png")
        run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(t0), "-i", path, "-frames:v", "1", a])
        run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(t1), "-i", path, "-frames:v", "1", b])
        x = np.asarray(Image.open(a).convert("RGB"), dtype=int)
        y = np.asarray(Image.open(b).convert("RGB"), dtype=int)
        return float(abs(x - y).mean())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True, help="путь без расширения")
    ap.add_argument("--seam", type=float, default=1.0, help="наплыв хвоста в первый кадр, с")
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--quality", type=int, default=8, help="Theora q 0–10")
    a = ap.parse_args()
    d = duration(a.src)
    seam = min(a.seam, d / 4.0)
    body = d - seam
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        first = os.path.join(tmp, "first.png")
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", a.src, "-frames:v", "1", first])
        # [0] — клип без хвоста; [1] — хвост; [2] — первый кадр, растянутый на длину хвоста; хвост → первый кадр наплывом
        filt = (
            f"[0:v]trim=0:{body:.3f},setpts=PTS-STARTPTS,fps={a.fps}[body];"
            f"[0:v]trim={body:.3f}:{d:.3f},setpts=PTS-STARTPTS,fps={a.fps}[tail];"
            f"[1:v]fps={a.fps},trim=0:{seam:.3f},setpts=PTS-STARTPTS[head];"
            f"[tail][head]blend=all_expr='A*(1-T/{seam:.3f})+B*(T/{seam:.3f})':shortest=1[x];"
            f"[body][x]concat=n=2:v=1:a=0[v]"
        )
        loop_mp4 = a.out + ".mp4"
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", a.src, "-loop", "1", "-t", f"{seam + 0.5:.3f}", "-i", first,
             "-filter_complex", filt, "-map", "[v]", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", loop_mp4])
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", loop_mp4, "-an", "-c:v", "libtheora", "-q:v", str(a.quality), a.out + ".ogv"])
    d2 = duration(loop_mp4)
    before = frame_diff(a.src, 0.0, d - 0.1)
    after = frame_diff(loop_mp4, 0.0, d2 - 0.06)
    info = {"source": a.src, "seconds": round(d2, 2), "seam_s": seam, "first_last_diff_before": round(before, 1), "first_last_diff_after": round(after, 1),
            "ogv_bytes": os.path.getsize(a.out + ".ogv")}
    print(json.dumps(info, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
