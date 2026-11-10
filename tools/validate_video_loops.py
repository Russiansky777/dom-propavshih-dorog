#!/usr/bin/env python3
"""Петли-картины в игре (game/assets/rooms/**/*.ogv) без рывков (Директор 09.11: «качество ужасное видео» на ужине).

Проверяет каждый ролик:
  1. ключевой кадр один — в начале (Theora на промежуточных кадрах не кодирует мелкое движение, и оно выскакивает на
     каждом ключевом кадре: рывок раз в 0,5 с при ключевых кадрах ffmpeg по умолчанию);
  2. шов петли: средняя разница последнего и первого кадра ≤ 3/255 (конец клипа приходит в картину);
  3. нет звуковой дорожки;
  4. картина живая (Директор 09.11, 22:18: «сцена с Агатой и мамой почему-то не живая — мы же её сделали и утвердили»:
     утверждённый 08.11 клип объятия заменили вечером 09.11 почти неподвижным — Kling Pro с последним кадром = первому):
     средняя разница кадров через 0,5 с (480×270, серое) не ниже background.video_motion_min комнаты, которая ролик
     показывает (data/story/rooms/*.json). Мерка: утверждённые объятия — 1,5 и 4,2; неподвижная замена — 0,26 и 0,61.
     Комната с роликом без video_motion_min — ошибка.
  5. камера стоит (10.11: в клипе объятия Агаты и мамы, Kling 3.0 Pro 1080p, вся картина за последние 2,5 с сползла
     на 3,7 точки вниз — на шве петли она вся двоилась бы и «дышала» раз в 10 с; клип выровнен
     tools/video_stabilize.py): наибольший сдвиг всей картины против первого кадра (фазовая корреляция, кадры
     через 0,5 с, в точках кадра 1080p) ≤ 1,0. Мерка: все ролики игры — 0,03–0,20; сырой клип — 3,73.
Самопроверка (--self-check): тот же ролик, перекодированный с ключевым кадром каждые 12 кадров, должен быть пойман;
стоп-кадр первого кадра на 2 с должен быть пойман как неживой; ролик, в котором картина съезжает на 8 точек,
должен быть пойман как «камера сползает».

  python3 tools/validate_video_loops.py [--self-check]   → код 0, если всё в порядке
"""
import glob
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEAM_MAX = 3.0
DRIFT_MAX = 1.0   # точек кадра 1080p


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


def motion(path: str) -> float:
    """Средняя разница соседних кадров, взятых через 0,5 с (480×270, серое), /255; -1 без numpy."""
    try:
        import numpy as np
    except ImportError:
        return -1.0
    p = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", path, "-vf", "fps=2,scale=480:270,format=gray",
                        "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True, check=True)
    a = np.frombuffer(p.stdout, np.uint8).reshape(-1, 270, 480).astype(np.int16)
    if len(a) < 2:
        return 0.0
    return float(np.abs(a[1:] - a[:-1]).mean())


def drift(path: str) -> float:
    """Наибольший сдвиг всей картины против первого кадра, в точках кадра высотой 1080 (фазовая корреляция по
    кадрам через 0,5 с, 960×540, серое, с уточнением до долей точки); -1 без numpy."""
    try:
        import numpy as np
    except ImportError:
        return -1.0
    w, h = 960, 540
    p = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", path, "-vf", f"fps=2,scale={w}:{h},format=gray",
                        "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True, check=True)
    a = np.frombuffer(p.stdout, np.uint8).reshape(-1, h, w).astype(np.float32)
    if len(a) < 2:
        return 0.0
    win = np.outer(np.hanning(h), np.hanning(w)).astype(np.float32)
    f0 = np.fft.rfft2((a[0] - a[0].mean()) * win)
    worst = 0.0
    for i in range(1, len(a)):
        f = np.fft.rfft2((a[i] - a[i].mean()) * win)
        r = f0 * np.conj(f)
        r /= np.abs(r) + 1e-6
        c = np.fft.irfft2(r, s=(h, w))
        y, x = np.unravel_index(int(np.argmax(c)), c.shape)
        c0 = c[y, x]
        ym, yp, xm, xp = c[(y - 1) % h, x], c[(y + 1) % h, x], c[y, (x - 1) % w], c[y, (x + 1) % w]
        dy = y + (ym - yp) / (2.0 * (ym - 2.0 * c0 + yp) + 1e-9)
        dx = x + (xm - xp) / (2.0 * (xm - 2.0 * c0 + xp) + 1e-9)
        dy = dy - h if dy > h / 2 else dy
        dx = dx - w if dx > w / 2 else dx
        worst = max(worst, float((dx * dx + dy * dy) ** 0.5) * 1080.0 / h)
    return worst


def motion_mins() -> dict:
    """ролик (путь от корня) → наименьшая живость, которую объявила комната; None — комната её не назвала."""
    out = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "data/story/rooms/*.json"))):
        bg = json.load(open(f, encoding="utf-8")).get("background", {})
        files = [bg["video"]] if bg.get("video") else []
        for v in bg.get("videos", []) or []:
            files += v.get("files", [])
        for res in files:
            out["game/" + str(res).replace("res://", "")] = bg.get("video_motion_min")
    return out


def check(path: str, motion_min=None) -> list:
    errs = []
    if motion_min is not None:
        m = motion(path)
        if 0.0 <= m < float(motion_min):
            errs.append(f"картина не живая: движение {m:.2f}/255 < {motion_min} (video_motion_min комнаты)")
    k = keyframes(path)
    if k != [0]:
        errs.append(f"ключевые кадры {k[:6]}{'…' if len(k) > 6 else ''} ({len(k)} шт.) — нужен один, в начале")
    s = seam(path)
    if s > SEAM_MAX:
        errs.append(f"шов петли {s:.2f}/255 > {SEAM_MAX}")
    if has_audio(path):
        errs.append("есть звуковая дорожка")
    d = drift(path)
    if d > DRIFT_MAX:
        errs.append(f"камера сползает: картина сдвигается на {d:.2f} точки > {DRIFT_MAX} (выровнять: tools/video_stabilize.py)")
    return errs


def main() -> int:
    import shutil
    if not shutil.which("ffprobe") or not shutil.which("ffmpeg"):
        print("видео-петли: пропущено — нет ffmpeg/ffprobe")
        return 0
    files = sorted(glob.glob(os.path.join(ROOT, "game/assets/rooms/**/*.ogv"), recursive=True))
    bad = 0
    mins = motion_mins()
    for f in files:
        rel = os.path.relpath(f, ROOT)
        errs = check(f, mins.get(rel))
        if rel in mins and mins[rel] is None:
            errs.append("комната не назвала video_motion_min (живость ролика не проверяется)")
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
            still = os.path.join(d, "still.ogv")
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", files[0], "-vf", "select=eq(n\\,0),loop=47:1:0,setpts=N/24/TB",
                            "-r", "24", "-an", "-c:v", "libtheora", "-q:v", "8", "-g", "60", still], check=True)
            caught2 = any("не живая" in e for e in check(still, 1.0))
            print(("OK    " if caught2 else "FAIL  ") + "самопроверка: стоп-кадр " + ("пойман как неживой" if caught2 else "НЕ пойман"))
            bad += not caught2
            slid = os.path.join(d, "slid.ogv")
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-t", "3", "-i", files[0], "-vf", "crop=iw:ih-16:0:'min(8,t*4)':exact=1",
                            "-an", "-c:v", "libtheora", "-q:v", "8", "-g", "400", slid], check=True)
            caught3 = any("камера сползает" in e for e in check(slid))
            print(("OK    " if caught3 else "FAIL  ") + "самопроверка: картина, съезжающая на 8 точек, " + ("поймана" if caught3 else "НЕ поймана"))
            bad += not caught3
    print(f"видео-петли: {len(files)} файлов, {bad} с ошибками")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
