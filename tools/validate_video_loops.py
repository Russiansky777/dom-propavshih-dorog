#!/usr/bin/env python3
"""Петли-картины в игре (game/assets/rooms/**/*.ogv) без рывков (Директор 09.11: «качество ужасное видео» на ужине).

Проверяет каждый ролик:
  1. ключевой кадр один — в начале (Theora на промежуточных кадрах не кодирует мелкое движение, и оно выскакивает на
     каждом ключевом кадре: рывок раз в 0,5 с при ключевых кадрах ffmpeg по умолчанию);
  2. шов петли: средняя разница последнего и первого кадра ≤ 3/255 (конец клипа приходит в картину);
  3. нет звуковой дорожки.
Самопроверка (--self-check): тот же ролик, перекодированный с ключевым кадром каждые 12 кадров, должен быть пойман.

  python3 tools/validate_video_loops.py [--self-check]   → код 0, если всё в порядке
"""
import glob
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEAM_MAX = 3.0


def keyframes(path: str) -> list:
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=key_frame",
                                   "-of", "csv=p=0", path]).decode().split()
    return [i for i, k in enumerate(out) if k.strip() == "1"]


def has_audio(path: str) -> bool:
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0", path]).decode()
    return "audio" in out


def seam(path: str) -> float:
    try:
        import numpy as np
    except ImportError:   # без numpy шов не мерится
        return 0.0
    p = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", path, "-vf", "scale=480:270", "-f", "rawvideo",
                        "-pix_fmt", "rgb24", "-"], capture_output=True, check=True)
    a = np.frombuffer(p.stdout, np.uint8).reshape(-1, 270, 480, 3).astype(int)
    return float(abs(a[-1] - a[0]).mean())


def check(path: str) -> list:
    errs = []
    k = keyframes(path)
    if k != [0]:
        errs.append(f"ключевые кадры {k[:6]}{'…' if len(k) > 6 else ''} ({len(k)} шт.) — нужен один, в начале")
    s = seam(path)
    if s > SEAM_MAX:
        errs.append(f"шов петли {s:.2f}/255 > {SEAM_MAX}")
    if has_audio(path):
        errs.append("есть звуковая дорожка")
    return errs


def main() -> int:
    import shutil
    if not shutil.which("ffprobe") or not shutil.which("ffmpeg"):
        print("видео-петли: пропущено — нет ffmpeg/ffprobe")
        return 0
    files = sorted(glob.glob(os.path.join(ROOT, "game/assets/rooms/**/*.ogv"), recursive=True))
    bad = 0
    for f in files:
        errs = check(f)
        rel = os.path.relpath(f, ROOT)
        print(("OK    " if not errs else "FAIL  ") + rel + ("" if not errs else ": " + "; ".join(errs)))
        bad += bool(errs)
    if "--self-check" in sys.argv and files:
        with tempfile.TemporaryDirectory() as d:
            t = os.path.join(d, "every12.ogv")
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", files[0], "-an", "-c:v", "libtheora",
                            "-q:v", "10", "-g", "12", t], check=True)
            caught = bool(check(t))
            print(("OK    " if caught else "FAIL  ") + "самопроверка: ролик с ключевым кадром каждые 12 кадров " + ("пойман" if caught else "НЕ пойман"))
            bad += not caught
    print(f"видео-петли: {len(files)} файлов, {bad} с ошибками")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
