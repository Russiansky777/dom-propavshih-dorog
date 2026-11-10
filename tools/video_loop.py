#!/usr/bin/env python3
"""Петля из клипа image-to-video для кадра-картины (Директор 08.11, 23:07/23:26: «луп… первый и последний кадр
должны совпадать, и разрыва не было»). У клипов fal.ai первый кадр — сама картина; хвост (последние `--seam` с)
наплывом сводится в первый кадр, так что стык — короткое «успокоение» в рисунок, не скачок. Звук отбрасывается.
Выход: Ogg Theora для Godot (VideoStreamPlayer: data background.video) + MP4 для просмотра.

  python3 tools/video_loop.py --in clip.mp4 --out game/assets/rooms/F_hug_pelageya/loop [--seam 1.0] [--fps 24]
  → loop.ogv, loop.mp4; печатает длительность и разницу первого/последнего кадра (0..255, до и после).

Вступление + петля (Директор 10.11, 16:01 о петле объятий 1080p: «это явно не кадр в кадр склейка»). У клипа без
заданного последнего кадра поза к концу уходит от картины (рука мамы с плеча легла на голову), и наплыв хвоста в
первый кадр виден: рука «перетекает» обратно. С `--from A --to B --intro путь` клип делится на две части:
  вступление [0, A] — играет один раз, от картины до начала петли;
  петля [A, B] — её последние `--seam` секунд наплывом сводятся в кусок клипа ПЕРЕД A ([A−seam, A]), так что последний
  кадр петли — это кадр клипа прямо перед A: повтор начинается кадр в кадр, а сам наплыв спрятан между двумя почти
  одинаковыми позами ([B−seam, B] и [A−seam, A] — точки подбираются по сходству поз).
В игре: комната называет оба файла (background.video_intro и background.video), FrameVideo играет вступление и
переходит на петлю.

  python3 tools/video_loop.py --in clip.mp4 --out …/loop --intro …/intro --from 2.708 --to 9.667 --seam 0.75
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


def to_ogv(mp4: str, ogv: str, fps: int, quality: int) -> None:
    """Theora с одним ключевым кадром в начале (см. main: рывки на ключевых кадрах)."""
    frames = int(round(duration(mp4) * fps)) + 1
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", mp4, "-an", "-c:v", "libtheora", "-q:v", str(quality), "-g", str(frames + 8), ogv])


def intro_and_loop(a) -> int:
    d = duration(a.src)
    end = a.end if a.end > 0.0 else d
    f = 1.0 / a.fps
    # всё на сетке кадров: A и B — целые кадры клипа
    na, nb = int(round(a.start * a.fps)), int(round(end * a.fps))
    ns = max(2, int(round(a.seam * a.fps)))
    if na < ns or nb - na < 4 * ns:
        raise SystemExit(f"петля [{a.start}, {end}] с наплывом {a.seam} с не помещается в клип {d:.2f} с")
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    x = ns * f
    # хвост [B−x, B) → кусок перед началом [A−x, A): вес нового растёт плавно и на последнем кадре равен 1,
    # то есть последний кадр петли — кадр клипа A−1, а первый — кадр A
    w = f"min(1,(T+{f:.6f})/{x:.6f})"
    sm = f"({w})*({w})*(3-2*({w}))"
    filt = (
        f"[0:v]fps={a.fps},trim=start_frame={na}:end_frame={nb - ns},setpts=PTS-STARTPTS[body];"
        f"[0:v]fps={a.fps},trim=start_frame={nb - ns}:end_frame={nb},setpts=PTS-STARTPTS[tail];"
        f"[0:v]fps={a.fps},trim=start_frame={na - ns}:end_frame={na},setpts=PTS-STARTPTS[pre];"
        f"[tail][pre]blend=all_expr='A*(1-{sm})+B*({sm})':shortest=1[x];"
        f"[body][x]concat=n=2:v=1:a=0[v]"
    )
    loop_mp4 = a.out + ".mp4"
    run(["ffmpeg", "-loglevel", "error", "-y", "-i", a.src, "-filter_complex", filt, "-map", "[v]", "-an", "-c:v", "libx264",
         "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", loop_mp4])
    to_ogv(loop_mp4, a.out + ".ogv", a.fps, a.quality)
    info = {"source": a.src, "loop_from_s": round(na * f, 3), "loop_to_s": round(nb * f, 3), "loop_seconds": round(duration(loop_mp4), 2),
            "seam_s": round(x, 3), "ogv_bytes": os.path.getsize(a.out + ".ogv")}
    if a.intro:
        os.makedirs(os.path.dirname(a.intro) or ".", exist_ok=True)
        intro_mp4 = a.intro + ".mp4"
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", a.src, "-vf", f"fps={a.fps},trim=start_frame=0:end_frame={na},setpts=PTS-STARTPTS",
             "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", intro_mp4])
        to_ogv(intro_mp4, a.intro + ".ogv", a.fps, a.quality)
        info["intro_seconds"] = round(duration(intro_mp4), 2)
        info["intro_ogv_bytes"] = os.path.getsize(a.intro + ".ogv")
    print(json.dumps(info, ensure_ascii=False))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True, help="путь без расширения")
    ap.add_argument("--seam", type=float, default=1.0, help="наплыв хвоста в первый кадр, с")
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--quality", type=int, default=8, help="Theora q 0–10")
    ap.add_argument("--from", dest="start", type=float, default=0.0, help="начало петли в клипе, с (с --intro)")
    ap.add_argument("--to", dest="end", type=float, default=0.0, help="конец петли в клипе, с (0 — конец клипа)")
    ap.add_argument("--intro", default="", help="путь вступления без расширения: клип [0, --from], играет один раз")
    a = ap.parse_args()
    if a.start > 0.0:
        return intro_and_loop(a)
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
        # Один ключевой кадр на петлю (09.11, вечер): Theora даже на q10 не кодирует мелкое «дыхание» картинки в
        # промежуточных кадрах — оно копится и выскакивает на каждом ключевом кадре (ffmpeg ставит их каждые 12 кадров),
        # то есть рывок раз в 0,5 с (лица: шаг на ключевом кадре 1,07 против 0,35 между ними, у исходника 0,38/0,45).
        # С одним ключевым кадром в начале рывков нет, расхождение с исходником то же (1,4 против 1,05 из 255), файл
        # в 3–7 раз меньше; петля начинается с ключевого кадра, плеер её не перематывает. Проверка — tools/validate_video_loops.py.
        # (Проверено и отброшено: петля, записанная в файл трижды подряд, — стык внутри файла даёт тот же шаг ~1,0–1,2,
        # что и переход на ключевой кадр; выигрыша нет.)
        frames = int(round(duration(loop_mp4) * a.fps)) + 1
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", loop_mp4, "-an", "-c:v", "libtheora", "-q:v", str(a.quality), "-g", str(frames + 8), a.out + ".ogv"])
    d2 = duration(loop_mp4)
    before = frame_diff(a.src, 0.0, d - 0.1)
    after = frame_diff(loop_mp4, 0.0, d2 - 0.06)
    info = {"source": a.src, "seconds": round(d2, 2), "seam_s": seam, "first_last_diff_before": round(before, 1), "first_last_diff_after": round(after, 1),
            "ogv_bytes": os.path.getsize(a.out + ".ogv")}
    print(json.dumps(info, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
