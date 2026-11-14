#!/usr/bin/env python3
"""A trailer shot taken from a ready video instead of the engine (shot kind `clip`; Director 14.11, 19:56: «Да нужен
фал, делай и покажи именно тот кусок» — the crossing of trailer v3 is a picture of the game brought to life by fal,
not a room the engine can film).

    python3 tools/trailer_clip.py <plan.json> <shot_id> <out_dir> --size 1920x1080 --fps 30
    python3 tools/trailer_clip.py --check <plan.json> [<plan.json> …]
    python3 tools/trailer_clip.py --self-check

The shot in the plan:
    {"id": "crossing", "kind": "clip", "duration": 2.8, "transition_in": {...},
     "clip": {"file": "assets/incoming/video/crossing_1/<take>.mp4", "first_frame": 6, "play_fps": 30},
     "grade": {"tint": [1.04, 0.98, 0.9], "lift": [0.008, 0.004, 0.0], "vignette": 0.3}}

Writes `<out_dir>/f%08d.png` from 0 — what tools/trailer_assemble.py reads for any shot: (duration + the next shot's
transition) × fps frames. Frame k of the shot is frame `first_frame + floor(k × play_fps / fps)` of the file: the
file's frames go by at `play_fps` whatever its own rate (a 24 fps take at play_fps 30 runs 1.25× and never repeats a
frame at 30 fps; at 60 fps every frame is shown twice). The grade is the trailer's own (game/shaders/trailer/
trailer_post.gdshader: c·tint + lift·(1 − c), then the vignette 1 − v·smoothstep(0.25, 0.75, |q|), q.x × 1.25), so the
clip sits among the engine's shots. A clip shot has no `preroll_s` (nothing settles) and no sound of its own.

--check: every clip shot of the plans — the file is there, has frames enough for the shot at its play_fps, no preroll.
--self-check: a made-up clip whose frames are numbered by colour — the frames picked at 30, 60 and 6 fps are the ones
the rule above names, the grade of a flat colour is the shader's, and a shot longer than the clip is refused.
Needs ffmpeg/ffprobe and numpy (as tools/trailer_assemble.py).
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VIGNETTE_SOFT = 0.75   # trailer_post.gdshader: vignette_soft


def load(plan_path: Path) -> dict:
    return json.loads(plan_path.read_text(encoding="utf-8"))


def shot_of(plan: dict, shot_id: str) -> tuple[dict, float]:
    """The shot and the next shot's transition (the tail rendered past the shot's own duration)."""
    shots = plan["shots"]
    for i, s in enumerate(shots):
        if s.get("id") == shot_id:
            tail = float(shots[i + 1].get("transition_in", {}).get("duration", 0.0)) if i + 1 < len(shots) else 0.0
            return s, tail
    raise SystemExit(f"trailer_clip: no shot «{shot_id}» in the plan")


def clip_file(shot: dict, root: Path = ROOT) -> Path:
    p = Path(str(shot.get("clip", {}).get("file", "")))
    return p if p.is_absolute() else root / p


def count_frames(path: Path) -> int:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout.strip()
    return int(out.split(",")[0])


def picks(shot: dict, tail: float, fps: int) -> list[int]:
    """The file's frame for every frame of the shot."""
    c = shot.get("clip", {})
    first = int(c.get("first_frame", 0))
    play = float(c.get("play_fps", fps))
    n = int(round((float(shot["duration"]) + tail) * fps))
    # the small epsilon keeps k·play/fps from landing a hair under a whole number (0.1 + 0.2 arithmetic)
    return [first + int(math.floor(k * play / fps + 1e-9)) for k in range(n)]


def problems(shot: dict, tail: float, root: Path = ROOT) -> list[str]:
    bad: list[str] = []
    sid = shot.get("id", "?")
    c = shot.get("clip")
    if not isinstance(c, dict) or not c.get("file"):
        return [f"{sid}: a clip shot needs clip.file"]
    if float(shot.get("preroll_s", 0.0)) != 0.0:
        bad.append(f"{sid}: a clip shot has no preroll_s (nothing settles in a ready video)")
    if float(c.get("play_fps", 30)) <= 0 or int(c.get("first_frame", 0)) < 0:
        bad.append(f"{sid}: clip.play_fps must be above 0 and clip.first_frame not below 0")
        return bad
    f = clip_file(shot, root)
    if not f.is_file():
        bad.append(f"{sid}: no file {c['file']}")
        return bad
    have = count_frames(f)
    # the frames needed do not depend on the movie's fps: the last one is first + (length × play_fps) − 1 at most
    need = int(c.get("first_frame", 0)) + int(math.ceil((float(shot["duration"]) + tail) * float(c.get("play_fps", 30)) - 1e-9))
    if need > have:
        bad.append(f"{sid}: the shot needs frames up to {need} of {c['file']}, it has {have} — shorten the shot, "
                   f"start earlier (first_frame) or lower play_fps")
    return bad


def graded(frame, tint, lift, vig):
    """One frame (H×W×3, 0…1) through the trailer's grade."""
    import numpy as np
    return np.clip((frame * tint + lift * (1.0 - frame)) * vig, 0.0, 1.0)


def vignette_map(w: int, h: int, amount: float):
    import numpy as np
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    qx = ((xx + 0.5) / w - 0.5) * 1.25
    qy = (yy + 0.5) / h - 0.5
    t = np.clip((np.sqrt(qx * qx + qy * qy) - 0.25) / (VIGNETTE_SOFT - 0.25), 0.0, 1.0)
    return (1.0 - amount * (t * t * (3.0 - 2.0 * t)))[..., None]


def render(shot: dict, tail: float, out_dir: Path, w: int, h: int, fps: int, root: Path = ROOT) -> int:
    import numpy as np
    bad = problems(shot, tail, root)
    if bad:
        raise SystemExit("trailer_clip: " + "; ".join(bad))
    want = picks(shot, tail, fps)
    g = shot.get("grade", {})
    tint = np.array(g.get("tint", [1.0, 1.0, 1.0]), np.float32)
    lift = np.array(g.get("lift", [0.0, 0.0, 0.0]), np.float32)
    vig = vignette_map(w, h, float(g.get("vignette", 0.3)))
    out_dir.mkdir(parents=True, exist_ok=True)
    # the decoder stops by itself after the last frame the shot takes (closing its pipe early prints «Broken pipe»)
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(clip_file(shot, root)),
                            "-vf", f"scale={w}:{h}:flags=lanczos+accurate_rnd+full_chroma_int",
                            "-frames:v", str(want[-1] + 1), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
                            "-framerate", str(fps), "-i", "-", "-start_number", "0", str(out_dir / "f%08d.png")],
                           stdin=subprocess.PIPE)
    size = w * h * 3
    n = wrote = 0
    k = 0   # next frame of the shot to write
    while k < len(want):
        buf = dec.stdout.read(size)
        if len(buf) < size:
            break
        if n == want[k]:
            px = graded(np.frombuffer(buf, np.uint8).reshape(h, w, 3).astype(np.float32) / 255.0, tint, lift, vig)
            out = (px * 255.0 + 0.5).astype(np.uint8).tobytes()
            while k < len(want) and want[k] == n:   # the same frame of the file for several frames of the shot
                enc.stdin.write(out)
                k += 1
                wrote += 1
        n += 1
    dec.stdout.read()
    dec.stdout.close()
    enc.stdin.close()
    if dec.wait() != 0 or enc.wait() != 0 or wrote != len(want):
        raise SystemExit(f"trailer_clip: {shot.get('id')}: wrote {wrote} of {len(want)} frames")
    return wrote


def check(plans: list[str]) -> int:
    bad: list[str] = []
    seen = 0
    for p in plans:
        plan = load(Path(p))
        for s in plan.get("shots", []):
            if s.get("kind") == "clip":
                seen += 1
                bad += [f"{Path(p).name}/{b}" for b in problems(s, shot_of(plan, s["id"])[1])]
    for b in bad:
        print(f"FAIL  trailer clip: {b}")
    if not bad:
        print(f"PASS  trailer clips: {seen} clip shot(s) in {len(plans)} plan(s) — file there, frames enough, no preroll")
    return 1 if bad else 0


def self_check() -> int:
    import numpy as np
    ok = True

    def say(cond: bool, text: str) -> None:
        nonlocal ok
        ok = ok and cond
        print(("PASS  " if cond else "FAIL  ") + "trailer_clip self-check: " + text)

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        # 40 frames at 24 fps, frame i a flat grey of level 20 + 5·i (lossless, so the level reads back exactly ±1)
        w, h, n = 64, 36, 40
        raw = b"".join(bytes([20 + 5 * i]) * (w * h * 3) for i in range(n))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-framerate", "24",
                        "-i", "-", "-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv444p", str(tmp / "clip.mp4")], input=raw, check=True)
        say(count_frames(tmp / "clip.mp4") == n, f"the made-up clip has {n} frames")
        shot = {"id": "c", "kind": "clip", "duration": 0.8, "clip": {"file": str(tmp / "clip.mp4"), "first_frame": 4, "play_fps": 30}}
        tail = 0.2

        def levels(d: Path) -> list[int]:
            out = []
            for f in sorted(d.glob("f*.png")):
                px = subprocess.run(["ffmpeg", "-v", "error", "-i", str(f), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                                    capture_output=True, check=True).stdout
                a = np.frombuffer(px, np.uint8).reshape(h, w, 3)
                out.append(int(round(float(a[h // 2, w // 2].mean()))))   # the centre: the vignette is 1 there
            return out

        for fps, expect in ((30, [4 + k for k in range(30)]),
                            (60, [4 + k // 2 for k in range(60)]),
                            (6, [4 + 5 * k for k in range(6)])):
            say(picks(shot, tail, fps) == expect, f"at {fps} fps the shot takes frames {expect[0]}…{expect[-1]} of the file, {len(expect)} in all")
            d = tmp / f"o{fps}"
            wrote = render(shot, tail, d, w, h, fps, root=tmp)
            got = levels(d)
            want = [20 + 5 * i for i in expect]
            say(wrote == len(expect) and len(got) == len(want) and all(abs(a - b) <= 1 for a, b in zip(got, want)),
                f"at {fps} fps the frames written are those frames ({wrote} files)")
        # the grade: a flat colour through the shader's formula, the corner darker by the vignette
        g_shot = dict(shot, grade={"tint": [1.04, 0.98, 0.9], "lift": [0.008, 0.004, 0.0], "vignette": 0.3})
        d = tmp / "g"
        render(g_shot, tail, d, w, h, 30, root=tmp)
        px = subprocess.run(["ffmpeg", "-v", "error", "-i", str(d / "f00000010.png"), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                            capture_output=True, check=True).stdout
        a = np.frombuffer(px, np.uint8).reshape(h, w, 3).astype(float)
        c = (20 + 5 * 14) / 255.0
        want_c = [(c * t + l * (1 - c)) * 255.0 for t, l in zip([1.04, 0.98, 0.9], [0.008, 0.004, 0.0])]
        say(all(abs(a[h // 2, w // 2, i] - want_c[i]) <= 1.5 for i in range(3)),
            "the grade at the centre is c·tint + lift·(1 − c)")
        corner = float(vignette_map(w, h, 0.3)[0, 0, 0])
        say(abs(a[0, 0, 1] - want_c[1] * corner) <= 1.5 and corner < 0.75,
            f"the corner is darker by the vignette (×{corner:.2f})")
        # a shot longer than the clip is refused, and so is a preroll
        long_shot = dict(shot, duration=2.0)
        say(any("needs frames" in b for b in problems(long_shot, tail, tmp)), "a shot longer than the clip is refused")
        say(any("preroll" in b for b in problems(dict(shot, preroll_s=0.8), tail, tmp)), "a clip shot with a preroll is refused")
        say(any("no file" in b for b in problems(dict(shot, clip={"file": "nothing.mp4"}), tail, tmp)), "a missing file is named")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--self-check":
        return self_check()
    if argv and argv[0] == "--check":
        return check(argv[1:])
    if len(argv) < 3:
        print(__doc__)
        return 2
    plan_path, shot_id, out_dir = Path(argv[0]), argv[1], Path(argv[2])
    w, h, fps = 1920, 1080, 0
    i = 3
    while i < len(argv):
        if argv[i] == "--size":
            w, h = (int(v) for v in argv[i + 1].split("x"))
        elif argv[i] == "--fps":
            fps = int(argv[i + 1])
        i += 2
    plan = load(plan_path)
    shot, tail = shot_of(plan, shot_id)
    if shot.get("kind") != "clip":
        raise SystemExit(f"trailer_clip: shot «{shot_id}» is «{shot.get('kind')}», not a clip")
    n = render(shot, tail, out_dir, w, h, fps or int(plan.get("fps", 60)))
    print(f"[trailer] clip {shot_id}: {n} frames from {shot['clip']['file']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
