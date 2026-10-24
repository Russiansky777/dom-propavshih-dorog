#!/usr/bin/env python3
"""TR1: проверка готового ролика build/trailer/<plan>.mp4 (после tools/make_trailer.sh).

  - формат по требованиям Steam: H.264, 1920×1080, fps плана, AAC 48 кГц, поток видео ≥ 8000 кбит/с;
  - громкость: интегральная (EBU R128, цель loudness_lufs ± 1), истинный пик, кратковременная по секундам;
  - движение: каждый кадр отличается от предыдущего (нет повторов — рывков) — кроме последних кадров титра,
    где картинка по замыслу стоит; разница соседних кадров ровная (нет скачков — склеек без перехода);
  - нет чёрных/пустых кадров вне переходов;
  - лист кадров каждые 0,5 с → Docs/evidence/trailer/<plan>_contact.jpg, ключевые кадры в полный размер →
    build/trailer/<plan>_key/; отчёт → build/trailer/<plan>_check.json.

Запуск: python3 tools/trailer_check.py [plan]   (код 0 — всё в норме)
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from trailer_assemble import timeline  # noqa: E402


def probe(path: Path) -> dict:
    r = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
                       capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def frames_gray(path: Path, w: int = 480, h: int = 270) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"scale={w}:{h}:flags=area,format=gray",
                          "-f", "rawvideo", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)


def frame_at(path: Path, t: float, out: Path) -> Image.Image:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", str(path), "-frames:v", "1", str(out)],
                   check=True)
    return Image.open(out)


def loudness(path: Path) -> dict:
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True)
    log = r.stderr
    summ = log[log.rindex("Summary:"):]
    i = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summ).group(1))
    lra = float(re.search(r"LRA:\s+(-?[\d.]+) LU", summ).group(1))
    tp = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summ).group(1))
    short = [float(m.group(1)) for m in re.finditer(r"t:\s*([\d.]+)\s+TARGET.*?S:\s*(-?[\d.]+)", log)]
    s_vals = [(float(m.group(1)), float(m.group(2))) for m in re.finditer(r"t:\s*([\d.]+)\s+TARGET:[^\n]*?S:\s*(-?[\d.]+)", log)]
    per_s = {}
    for t, s in s_vals:
        per_s[int(t)] = s
    return {"integrated_lufs": i, "lra_lu": lra, "true_peak_dbfs": tp, "short_term_by_s": per_s}


def main() -> int:
    plan_id = next((a for a in sys.argv[1:] if not a.startswith("--")), "test_7s")
    plan = json.loads((ROOT / "data" / "trailer" / f"{plan_id}.json").read_text(encoding="utf-8"))
    mp4 = ROOT / "build" / "trailer" / f"{plan_id}.mp4"
    fps = int(plan.get("fps", 60))
    fails: list[str] = []
    rep: dict = {"file": str(mp4.relative_to(ROOT))}

    info = probe(mp4)
    v = next(s for s in info["streams"] if s["codec_type"] == "video")
    a = next(s for s in info["streams"] if s["codec_type"] == "audio")
    vbr = int(v.get("bit_rate", 0)) // 1000
    rep["format"] = {"video": v["codec_name"], "profile": v.get("profile"), "size": [v["width"], v["height"]],
                     "fps": v["r_frame_rate"], "video_kbps": vbr, "audio": a["codec_name"], "audio_hz": int(a["sample_rate"]),
                     "audio_kbps": int(a.get("bit_rate", 0)) // 1000, "duration_s": float(info["format"]["duration"]),
                     "pix_fmt": v.get("pix_fmt")}
    if v["codec_name"] != "h264" or [v["width"], v["height"]] != plan.get("out_size", [1920, 1080]):
        fails.append("video is not H.264 1920×1080")
    if v["r_frame_rate"] != f"{fps}/1":
        fails.append(f"fps {v['r_frame_rate']}")
    if a["codec_name"] != "aac" or int(a["sample_rate"]) != 48000:
        fails.append("audio is not AAC 48 kHz")
    if vbr < 8000:
        fails.append(f"video bitrate {vbr} kbps < 8000")

    lo = loudness(mp4)
    rep["loudness"] = lo
    target = float(plan["audio"].get("loudness_lufs", -14.0))
    if abs(lo["integrated_lufs"] - target) > 1.0:
        fails.append(f"loudness {lo['integrated_lufs']} LUFS, target {target}")
    if lo["true_peak_dbfs"] > -1.0:
        fails.append(f"true peak {lo['true_peak_dbfs']} dBFS")

    # Motion: mean absolute difference of neighbouring frames (small grey copies; the grain is temporal noise, so a
    # repeated picture still differs by the grain — compare against a grain-free floor from a blur).
    g = frames_gray(mp4)
    blur = np.stack([np.asarray(Image.fromarray(f.astype(np.uint8)).resize((120, 68), Image.BOX), np.float32) for f in g])
    diff = np.abs(np.diff(blur, axis=0)).mean(axis=(1, 2))
    tl = timeline(plan)
    total = sum(s["dur"] for s in tl)
    trans = [(s["start"], s["start"] + float(s["tin"].get("duration", 0))) for s in tl[1:]]
    end_fade = float(plan.get("end_fade_s", 0.4))
    title = tl[-1]

    def in_trans(t: float) -> bool:
        return any(a0 - 1 / fps <= t <= a1 + 1 / fps for a0, a1 in trans) or t >= total - end_fade - 1 / fps

    still_ok_from = title["start"] + float(title["shot"].get("still_after_s", 1.75))   # the title rests once it is up
    repeats = [round(i / fps, 3) for i, d in enumerate(diff, 1) if d < 0.02 and i / fps < still_ok_from and not in_trans(i / fps)]
    if repeats:
        fails.append(f"{len(repeats)} repeated frames (no motion) at {repeats[:10]}")
    jumps = []
    for i in range(2, len(diff) - 2):
        loc = np.median(diff[max(0, i - 6):i + 6])
        if diff[i] > max(1.5, loc * 4) and not in_trans((i + 1) / fps):
            jumps.append(round((i + 1) / fps, 3))
    if jumps:
        fails.append(f"jumps at {jumps[:10]}")
    mean = g.mean(axis=(1, 2))
    black = [round(i / fps, 3) for i, m in enumerate(mean) if m < 6 and not in_trans(i / fps)
             and not (i / fps >= title["start"])]
    if black:
        fails.append(f"{len(black)} black frames outside transitions at {black[:10]}")
    rep["motion"] = {"frames": int(len(g)), "diff_min": float(diff.min()), "diff_median": float(np.median(diff)),
                     "repeats_outside_title_rest": repeats, "jumps": jumps, "black_outside_transitions": black,
                     "diff_by_0_5s": [round(float(diff[int(k * fps / 2):int((k + 1) * fps / 2)].mean()), 3) for k in range(int(total * 2))]}

    # Contact sheet every 0.5 s and key frames.
    key_dir = ROOT / "build" / "trailer" / f"{plan_id}_key"
    key_dir.mkdir(parents=True, exist_ok=True)
    times = [round(k * 0.5, 2) for k in range(int(total * 2) + 1)]
    times[-1] = min(times[-1], total - 0.6)
    thumbs = []
    for t in times:
        im = frame_at(mp4, t, key_dir / f"t{t:05.2f}.png")
        th = im.resize((480, 270), Image.LANCZOS)
        d = ImageDraw.Draw(th)
        d.rectangle([0, 0, 64, 22], fill=(0, 0, 0))
        d.text((6, 5), f"{t:.1f} s", fill=(255, 220, 150))
        thumbs.append(th)
    cols = 4
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 480 + (cols + 1) * 6, rows * 270 + (rows + 1) * 6), (24, 20, 16))
    for i, th in enumerate(thumbs):
        sheet.paste(th, (6 + (i % cols) * 486, 6 + (i // cols) * 276))
    ev = ROOT / "Docs" / "evidence" / "trailer"
    ev.mkdir(parents=True, exist_ok=True)
    sheet.save(ev / f"{plan_id}_contact.jpg", quality=88)
    rep["contact_sheet"] = str((ev / f"{plan_id}_contact.jpg").relative_to(ROOT))
    rep["fails"] = fails
    (ROOT / "build" / "trailer" / f"{plan_id}_check.json").write_text(json.dumps(rep, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({k: rep[k] for k in ("format", "fails")}, ensure_ascii=False, indent=1))
    print(f"[check] loudness I {lo['integrated_lufs']} LUFS, TP {lo['true_peak_dbfs']} dBFS, LRA {lo['lra_lu']} LU")
    print(f"[check] motion: frames {len(g)}, min diff {diff.min():.3f}, median {np.median(diff):.3f}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
