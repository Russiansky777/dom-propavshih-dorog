#!/usr/bin/env python3
"""A mechanic shown as a film (Director 14.11, 21:15: the repeated crossing — «можно на повторные, но он с резким
началом и концом ведь, тоже надо учитывать»): every `film` of a mechanic in data/story/rooms and data/story/scenes.

  1. the file is there, Ogg Theora, silent, one key frame (as the game's other clips: tools/validate_video_loops.py);
  2. the start: its first picture is the painted view the mechanic opens with (`art.bg` and the rope layer of the
     same room, at 1920×1080) — mean difference ≤ 5/255, so the film can come in over the painting without a jump;
  3. the end: it is long enough for the crossing itself (pulls × pull_s), the hold at the shore (arrive_hold_s) and
     the black of the `crossed` event (close_black.fade_out_s), with 0.4 s to spare — the black comes down over a
     picture that still moves, not over a stopped one.
--self-check: the same film against a crossing one second longer is caught as too short; against another painting
(the arrival's) — as a start that does not match.

    python3 tools/validate_films.py [--self-check]      → 0 when all is well
Needs ffmpeg/ffprobe, numpy, Pillow.
"""
from __future__ import annotations

import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START_MAX = 5.0      # of 255
SPARE_S = 0.4


def res(path: str) -> str:
    return os.path.join(ROOT, "game", path.replace("res://", ""))


def films() -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []

    def walk(x, where: str) -> None:
        if isinstance(x, dict):
            if isinstance(x.get("film"), dict) and x["film"].get("video"):
                out.append((where, x))
            for k, v in x.items():
                walk(v, where + "/" + str(k))
        elif isinstance(x, list):
            for i, v in enumerate(x):
                walk(v, where + f"[{i}]")

    for f in sorted(glob.glob(os.path.join(ROOT, "data/story/rooms/*.json")) + glob.glob(os.path.join(ROOT, "data/story/scenes/*.json"))):
        walk(json.load(open(f, encoding="utf-8")), os.path.basename(f))
    return out


def probe(path: str) -> dict:
    j = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-count_packets", "-of", "json", path],
                                  capture_output=True, text=True, check=True).stdout)
    v = [s for s in j["streams"] if s["codec_type"] == "video"]
    keys = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=flags", "-of", "csv=p=0", path],
                          capture_output=True, text=True, check=True).stdout.split()
    return {"codec": v[0]["codec_name"] if v else "", "audio": any(s["codec_type"] == "audio" for s in j["streams"]),
            "length": float(j["format"]["duration"]), "keys": sum(1 for k in keys if k.startswith("K"))}


def first_frame(path: str):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-vf", "scale=960:540", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(540, 960, 3).astype(float)


def painted(spec: dict, bg_key: str = "bg"):
    """The view the mechanic opens with: its painting and, over it, the room's rope layer beside it (fg_rope.png)."""
    import numpy as np
    from PIL import Image
    bg_path = res(str(spec.get("art", {}).get(bg_key, "")))
    im = Image.open(bg_path).convert("RGBA")
    rope = os.path.join(os.path.dirname(bg_path), "fg_rope.png")
    if bg_key == "bg" and os.path.exists(rope):
        top = Image.open(rope).convert("RGBA")
        if top.size == im.size:
            im = Image.alpha_composite(im, top)
    return np.asarray(im.convert("RGB").resize((960, 540), Image.LANCZOS)).astype(float)


def needed_s(spec: dict) -> float:
    black = float(spec.get("events", {}).get("crossed", {}).get("close_black", {}).get("fade_out_s", 0.0))
    hold = spec.get("arrive_hold_s")
    return int(spec.get("pulls", 10)) * float(spec.get("pull_s", 0.9)) + float(0.8 if hold is None else hold) + black + SPARE_S


def problems(spec: dict, bg_key: str = "bg") -> list[str]:
    import numpy as np
    bad: list[str] = []
    path = res(str(spec["film"]["video"]))
    if not os.path.isfile(path):
        return [f"no file {spec['film']['video']}"]
    p = probe(path)
    if p["codec"] != "theora":
        bad.append(f"codec «{p['codec']}», the game plays Ogg Theora")
    if p["audio"]:
        bad.append("has a sound track")
    if p["keys"] != 1:
        bad.append(f"{p['keys']} key frames, wanted one")
    need = needed_s(spec)
    if p["length"] < need:
        bad.append(f"too short: {p['length']:.2f} s, the crossing with its hold and black needs {need:.2f} s")
    d = float(np.abs(first_frame(path) - painted(spec, bg_key)).mean())
    if d > START_MAX:
        bad.append(f"the start does not match the painted view: first picture differs by {d:.1f} of 255 (limit {START_MAX})")
    return bad


def main() -> int:
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError as e:
        print(f"validate_films: {e}")
        return 2
    fs = films()
    bad_n = 0
    for where, spec in fs:
        bad = problems(spec)
        bad_n += bool(bad)
        print(("FAIL  " if bad else "OK    ") + f"film {where}: " + ("; ".join(bad) if bad else f"{spec['film']['video']} — start matches, long enough ({needed_s(spec):.2f} s needed)"))
    if not fs:
        print("validate_films: no films in the data")
    if "--self-check" in sys.argv and fs:
        _w, spec = fs[0]
        longer = json.loads(json.dumps(spec))
        longer["pulls"] = int(spec.get("pulls", 10)) + 2
        other = [b for b in problems(spec, "arrival")]
        c1 = any("too short" in b for b in problems(longer))
        c2 = any("does not match" in b for b in other)
        print(("PASS  " if c1 and c2 else "FAIL  ") + f"validate_films self-check: a longer crossing is caught as too short ({c1}), another painting — as a start that does not match ({c2})")
        bad_n += not (c1 and c2)
    if not bad_n:
        print(f"PASS  films: {len(fs)} film(s) of mechanics — start from the painting, long enough for the end")
    return 1 if bad_n else 0


if __name__ == "__main__":
    sys.exit(main())
