#!/usr/bin/env python3
"""A painted thing in a living picture stays the painting: it moves as a whole, as the clip moves it, but is not redrawn
from frame to frame (Director 15.11, 16:44 and 17:15: «та [лодка], которая качается на причале в кадре, где Митя,
Пелагея, — вот её корёжит»: the fal clip of the hug at the far pier rocks the boat and redraws its boards, oar and
seats a little differently every frame).

For every frame of the clip the region (`region`, a polygon on the painting's canvas, data tools/rigid/<frame>.json)
is registered to the painting (ECC, an affine map — the rock and the bob of the boat in the clip), and the painting's
own region is laid over the frame, moved by that map, its light matched to the frame's (the lantern, the evening —
a gain per colour, smoothed in time). The clip is cut into the game's intro and loop as tools/video_loop.py cut it
(the same points, seam and weights; Theora with one key frame) — only at the loop's seam the boat is laid once, between
its two places, instead of two boats dissolving into each other.

  python3 tools/video_rigid.py tools/rigid/F_hug_pelageya.json            → the game's intro.ogv and loop.ogv
  python3 tools/video_rigid.py tools/rigid/F_hug_pelageya.json --check    → the game's films: the region is rigid
  python3 tools/video_rigid.py tools/rigid/F_hug_pelageya.json --self-check  the raw clip is caught, a held one passes
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
LIMIT = 6.0          # mean difference (of 255) of the region from the painting moved as a whole
KEEP_LIMIT = 5.0     # mean difference (of 255) from the clip on what is kept (the encoding alone: ~2)
SMOOTH_WARP = 3      # frames
SMOOTH_GAIN = 9


def _need():
    try:
        import cv2  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError as e:
        print(f"SKIP  video_rigid: {e} (pip install opencv-python-headless pillow)")
        sys.exit(0)


def probe_size(path: str):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height",
                                   "-of", "csv=p=0", path]).decode().strip().split(",")
    return int(out[0]), int(out[1])


def frames(path: str, w: int, h: int):
    p = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         stdout=subprocess.PIPE)
    n = w * h * 3
    try:
        while True:
            b = p.stdout.read(n)
            if len(b) < n:
                break
            yield np.frombuffer(b, np.uint8).reshape(h, w, 3)
    finally:   # left early (a shorter film beside a longer clip) — the decoder goes quietly
        if p.poll() is None:
            p.kill()
        p.stdout.close()
        p.wait()


class Region:
    def __init__(self, spec: dict, w: int, h: int):
        import cv2
        from PIL import Image
        cw, ch = spec["canvas"]
        self.w, self.h = w, h
        self.paint = np.asarray(Image.open(ROOT / spec["painting"]).convert("RGB").resize((w, h), Image.LANCZOS)).astype(np.float32)
        poly = np.array([[x * w / cw, y * h / ch] for x, y in spec["region"]], np.int32)
        m = np.zeros((h, w), np.uint8)
        cv2.fillPoly(m, [poly], 255)
        mg = int(spec.get("margin_px", 4) * w / cw)
        if mg > 0:
            m = cv2.dilate(m, np.ones((2 * mg + 1, 2 * mg + 1), np.uint8))
        f = float(spec.get("feather_px", 3)) * w / cw
        self.mask = cv2.GaussianBlur(m.astype(np.float32) / 255.0, (0, 0), f) if f > 0 else m.astype(np.float32) / 255.0
        # registration at half size, over the inside of the region (its edge is where water and pier meet the boat)
        self.tw, self.th = w // 2, h // 2
        self.tpl = cv2.resize(cv2.cvtColor(self.paint.astype(np.uint8), cv2.COLOR_RGB2GRAY), (self.tw, self.th), interpolation=cv2.INTER_AREA).astype(np.float32)
        # `film_keep` (Director 15.11, 22:03: «канат теперь в „стало“ корёжит»): what crosses the region but is not
        # part of it stays the clip's — the mooring rope runs from the bollard on the pier (still) over the bow (rocking
        # with the boat); a painted rope cut at the region's edge broke where the clip's rope met it. A corridor along
        # it: each point moves with the region by its `follow` (0 — stays, 1 — as the boat), `width` px of the canvas.
        self.keep = []
        for k in spec.get("film_keep", []):
            pts = np.array([[x * w / cw, y * h / ch] for x, y in k["points"]], np.float64)
            self.keep.append((pts, np.array(k.get("follow", [1.0] * len(pts)), np.float64), float(k["width"]) * w / cw))
        self.keep_feather = f
        inner = cv2.erode(m, np.ones((15, 15), np.uint8))
        inner[self.corridor(np.eye(2, 3), core=False) > 0.01] = 0   # registered on the boards, not on the rope
        self.inner = cv2.resize(inner, (self.tw, self.th), interpolation=cv2.INTER_NEAREST)
        self.inner_full = inner > 0

    def corridor(self, warp_full, core: bool = False):
        """0…1 — where the clip is kept (the rope's corridor for this frame's map); `core` — its middle, the rope itself,
        narrowed by the margin and not softened (what the check compares with the clip)."""
        import cv2
        out = np.zeros((self.h, self.w), np.float32)
        for pts, follow, width in self.keep:
            moved = pts @ warp_full[:, :2].T + warp_full[:, 2]
            at = pts + (moved - pts) * follow[:, None]
            wd = width * (0.5 if core else 1.0)
            cv2.polylines(out, [np.round(at).astype(np.int32)], False, 1.0, thickness=max(1, int(round(wd))), lineType=cv2.LINE_AA)
        if not core and self.keep_feather > 0 and self.keep:
            out = cv2.GaussianBlur(out, (0, 0), self.keep_feather)
        return np.clip(out, 0.0, 1.0)

    def register(self, frame, warp0=None):
        import cv2
        g = cv2.resize(cv2.cvtColor(frame, cv2.COLOR_RGB2GRAY), (self.tw, self.th), interpolation=cv2.INTER_AREA).astype(np.float32)
        warp = np.eye(2, 3, dtype=np.float32) if warp0 is None else warp0.astype(np.float32).copy()
        crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 80, 1e-5)
        try:
            cc, warp = cv2.findTransformECC(self.tpl, g, warp, cv2.MOTION_AFFINE, crit, self.inner, 5)
        except cv2.error:
            cc = -1.0
        return cc, warp

    def full(self, warp_half):
        w = warp_half.astype(np.float64).copy()
        w[:, 2] *= self.w / self.tw
        return w

    def moved(self, warp_full):
        """The painting and the mask moved as the clip moves the region (dst(W·x) = painting(x))."""
        import cv2
        p = cv2.warpAffine(self.paint, warp_full, (self.w, self.h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        m = cv2.warpAffine(self.mask, warp_full, (self.w, self.h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        inner = cv2.warpAffine(self.inner_full.astype(np.uint8), warp_full, (self.w, self.h), flags=cv2.INTER_NEAREST) > 0
        if self.keep:
            c = self.corridor(warp_full)
            m = m * (1.0 - c)
            inner &= c < 0.01
        return p, m, inner


def smooth(a: np.ndarray, n: int) -> np.ndarray:
    out = a.copy()
    r = n // 2
    for i in range(len(a)):
        out[i] = a[max(0, i - r): i + r + 1].mean(axis=0)
    return out


def _theora(path: str, w: int, h: int, n: int, quality: int):
    """Raw frames → Ogg Theora as the game's films are (tools/video_loop.py: one key frame, no sound)."""
    return subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
                             "-r", "24", "-i", "-", "-an", "-c:v", "libtheora", "-q:v", str(quality), "-g", str(n + 8), path],
                            stdin=subprocess.PIPE)


def _track(clip: str, reg: "Region"):
    w, h = reg.w, reg.h
    warps, gains, prev = [], [], None
    for f in frames(clip, w, h):
        cc, prev = reg.register(f, prev)
        wf = reg.full(prev)
        p, m, inner = reg.moved(wf)
        warps.append(wf)
        gains.append(f[inner].astype(np.float64).mean(axis=0) / np.maximum(p[inner].astype(np.float64).mean(axis=0), 1.0))
    warps = smooth(np.stack(warps), SMOOTH_WARP)
    gains = smooth(np.stack(gains), SMOOTH_GAIN)
    warps[0] = np.eye(2, 3)          # the first frame is the painting itself
    return warps, gains


def _paste(reg: "Region", f, warp, gain):
    p, m, _ = reg.moved(warp)
    m3 = m[..., None]
    out = f.astype(np.float32) * (1.0 - m3) + np.clip(p * gain[None, None, :].astype(np.float32), 0, 255) * m3
    return np.ascontiguousarray(out.round().astype(np.uint8))


def hold(spec: dict, out_mp4: str = "") -> dict:
    """The held clip: to `out_mp4` (a look at it), or — no mp4 — the game's intro and loop as tools/video_loop.py cuts
    them (`loop`: from, to, seam): the intro [0, A) once from the painting; the loop [A, B) whose last `seam` seconds
    dissolve into the stretch before A. The water, the people, the light dissolve as before; the boat does not — two
    boats half seen through each other were the one place left where it «warped» (10.19 of 255 at the seam): it is laid
    once, at the place between its two places (the maps blended by the same weight)."""
    clip = str(ROOT / spec["clip"])
    w, h = probe_size(clip)
    reg = Region(spec, w, h)
    warps, gains = _track(clip, reg)
    info = {"frames": len(warps), "gain_range": [round(float(gains.min()), 3), round(float(gains.max()), 3)]}
    if out_mp4:
        enc = subprocess.Popen(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
                                "-r", "24", "-i", "-", "-c:v", "libx264", "-crf", "8", "-preset", "veryfast", "-pix_fmt", "yuv420p", out_mp4],
                               stdin=subprocess.PIPE)
        for i, f in enumerate(frames(clip, w, h)):
            enc.stdin.write(_paste(reg, f, warps[i], gains[i]).tobytes())
        enc.stdin.close()
        enc.wait()
        return info
    lp = spec["loop"]
    fps = 24
    na, nb = int(round(lp["from"] * fps)), int(round(lp["to"] * fps))
    ns = max(2, int(round(lp["seam"] * fps)))
    q = int(lp.get("quality", 10))
    intro = _theora(str(ROOT / (lp["intro"] + ".ogv")), w, h, na, q)
    loop = _theora(str(ROOT / (lp["out"] + ".ogv")), w, h, nb - na, q)
    pre = {}
    for i, f in enumerate(frames(clip, w, h)):
        if i < na:
            intro.stdin.write(_paste(reg, f, warps[i], gains[i]).tobytes())
        if na - ns <= i < na:
            pre[i - (na - ns)] = f.copy()
        if na <= i < nb - ns:
            loop.stdin.write(_paste(reg, f, warps[i], gains[i]).tobytes())
        elif nb - ns <= i < nb:
            j = i - (nb - ns)
            # tools/video_loop.py's weight: smooth, the last frame of the loop is the clip's frame A−1
            u = min(1.0, (j + 1) / ns)
            sm = u * u * (3 - 2 * u)
            k = na - ns + j
            bg = f.astype(np.float32) * (1 - sm) + pre[j].astype(np.float32) * sm
            warp = warps[i] * (1 - sm) + warps[k] * sm
            gain = gains[i] * (1 - sm) + gains[k] * sm
            loop.stdin.write(_paste(reg, bg.round().astype(np.uint8), warp, gain).tobytes())
    for e in (intro, loop):
        e.stdin.close()
        e.wait()
    info.update({"intro_frames": na, "loop_frames": nb - na, "seam_frames": ns})
    return info


def rigidity(spec: dict, film: str, every: int = 3) -> list:
    """Per sampled frame: how far the region is from the painting moved as a whole (mean of 255 over its inside)."""
    w, h = probe_size(film)
    reg = Region(spec, w, h)
    out, prev = [], None
    for i, f in enumerate(frames(film, w, h)):
        cc, prev = reg.register(f, prev)
        if i % every:
            continue
        p, m, inner = reg.moved(reg.full(prev))
        g = f[inner].astype(np.float64).mean(axis=0) / np.maximum(p[inner].astype(np.float64).mean(axis=0), 1.0)
        d = np.abs(f[inner].astype(np.float32) - np.clip(p[inner] * g.astype(np.float32), 0, 255)).mean()
        out.append((i, float(d)))
    return out


def kept(spec: dict, film: str, clip: str, every: int = 4) -> list:
    """Per sampled frame: how far the film is from the clip on what it keeps (the rope through the boat, the middle of
    its corridor inside the region) — 0 but for the encoding when the clip's rope is left whole."""
    import cv2
    w, h = probe_size(film)
    reg = Region(spec, w, h)
    if not reg.keep:
        return []
    out, prev = [], None
    for i, (f, c) in enumerate(zip(frames(film, w, h), frames(clip, w, h))):
        cc, prev = reg.register(f, prev)
        if i % every:
            continue
        wf = reg.full(prev)
        region = cv2.warpAffine(reg.mask, wf, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE) > 0.99
        core = (reg.corridor(wf, core=True) > 0.5) & region
        if core.sum() < 100:
            continue
        out.append((i, float(np.abs(f[core].astype(np.float32) - c[core].astype(np.float32)).mean())))
    return out


def check(spec: dict) -> int:
    _need()
    bad = 0
    for film in spec.get("games", []):
        r = rigidity(spec, str(ROOT / film))
        worst = max(r, key=lambda x: x[1])
        ok = worst[1] <= LIMIT
        bad += 0 if ok else 1
        print(("PASS  " if ok else "FAIL  ") + f"{film}: the boat is the painting moving as a whole — off by {worst[1]:.2f} of 255 at worst (frame {worst[0]}, limit {LIMIT})")
    # the intro is the clip's frames from its first: the rope over the bow there is the clip's own, whole
    intro = spec.get("loop", {}).get("intro")
    if intro and spec.get("film_keep"):
        r = kept(spec, str(ROOT / (intro + ".ogv")), str(ROOT / spec["clip"]))
        worst = max(r, key=lambda x: x[1])
        ok = worst[1] <= KEEP_LIMIT
        bad += 0 if ok else 1
        print(("PASS  " if ok else "FAIL  ") + f"{intro}.ogv: the rope over the bow is the clip's own, whole — off it by {worst[1]:.2f} of 255 at worst (frame {worst[0]}, limit {KEEP_LIMIT})")
    return 1 if bad else 0


def self_check(spec: dict) -> int:
    _need()
    tmp = Path(tempfile.mkdtemp(prefix="video_rigid_"))
    cut = tmp / "raw.mp4"
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", "4", "-t", "2", "-i", str(ROOT / spec["clip"]), "-an",
                    "-c:v", "libx264", "-crf", "8", "-preset", "veryfast", "-pix_fmt", "yuv420p", str(cut)], check=True)
    raw = max(d for _, d in rigidity(spec, str(cut)))
    held = tmp / "held.mp4"
    hold(dict(spec, clip=str(cut)), str(held))
    after = max(d for _, d in rigidity(spec, str(held)))
    ok = raw > LIMIT and after <= LIMIT
    print(("PASS  " if ok else "FAIL  ") + f"self-check: the clip's own boat is off by {raw:.2f} of 255 (caught: over {LIMIT}); held, {after:.2f}")
    if spec.get("film_keep"):
        # the version of 15.11 evening: the painted rope over the bow, cut at the region's edge (Director 22:03)
        cut_rope = tmp / "cut_rope.mp4"
        hold(dict({k: v for k, v in spec.items() if k != "film_keep"}, clip=str(cut)), str(cut_rope))
        bad = max(d for _, d in kept(spec, str(cut_rope), str(cut)))
        good = max(d for _, d in kept(spec, str(held), str(cut)))
        ok2 = bad > KEEP_LIMIT and good <= KEEP_LIMIT
        ok = ok and ok2
        print(("PASS  " if ok2 else "FAIL  ") + f"self-check: the rope pasted from the painting (as on 15.11 evening) is off the clip's by {bad:.2f} of 255 (caught: over {KEEP_LIMIT}); kept, {good:.2f}")
    for p in tmp.iterdir():
        p.unlink()
    tmp.rmdir()
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    ap.add_argument("--mp4", default="", help="only the held clip, here (no intro and loop)")
    a = ap.parse_args()
    spec = json.loads(Path(a.spec).read_text(encoding="utf-8"))
    if a.self_check:
        return self_check(spec)
    if a.check:
        return check(spec)
    _need()
    print(json.dumps(hold(spec, a.mp4), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
