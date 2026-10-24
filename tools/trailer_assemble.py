#!/usr/bin/env python3
"""TR1: монтаж трейлера из кадров Movie Maker (tools/make_trailer.sh) — ffmpeg.

Вход: data/trailer/<plan>.json и build/trailer/<plan>/<shot>/f########.png + f.wav (3840×2160, fps плана).
Выход: build/trailer/<plan>.mp4 — H.264 High + AAC 48 кГц, 1920×1080, fps плана, поток ≥ 8000 кбит/с (Steam).

  - уменьшение 4K → 1080 (Lanczos), склейки по `transition_in` следующего плана: dissolve — растворение,
    fadeblack — через чёрное; лёгкое плёночное зерно на итоговом размере; в конце — короткое затемнение;
  - звук: музыка плана (вход из тишины, мягкий выход), звук игры каждого плана (шаги, печь — то, что игра играла
    сама), окружение (файл или синтез «ветер и вода»), низкий удар под проявление титра; громкость — loudnorm
    в два прохода к loudness_lufs, пик не выше true_peak_db;
  - `--analyze`: где в музыке доли и сильные ноты, и какое начало трека кладёт склейки на них (печатает).

Запуск: python3 tools/trailer_assemble.py [plan] [--analyze]
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SR = 48000


def res(p: str) -> Path:
    return ROOT / "game" / p.removeprefix("res://")


def run(cmd: list[str], capture: bool = False) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-4000:])
        raise SystemExit(f"[assemble] failed: {' '.join(cmd[:6])} …")
    return r.stderr if capture else ""


def timeline(plan: dict) -> list[dict]:
    """Per shot: start on the edit, visible duration, rendered length (with the next transition's tail)."""
    shots = plan["shots"]
    t = 0.0
    out = []
    for i, s in enumerate(shots):
        tail = float(shots[i + 1].get("transition_in", {}).get("duration", 0.0)) if i + 1 < len(shots) else 0.0
        out.append({"shot": s, "start": t, "dur": float(s["duration"]), "len": float(s["duration"]) + tail,
                    "tail": tail, "tin": s.get("transition_in", {})})
        t += float(s["duration"])
    return out


def decode_mono(path: Path, sr: int = 22050) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def onsets(x: np.ndarray, sr: int = 22050, hop: int = 256, n: int = 1024) -> tuple[np.ndarray, np.ndarray]:
    frames = np.lib.stride_tricks.sliding_window_view(x, n)[::hop] * np.hanning(n)
    s = np.log1p(np.abs(np.fft.rfft(frames, axis=1)) * 10)
    flux = np.concatenate([[0], np.maximum(0, np.diff(s, axis=0)).sum(1)])
    flux = flux / (np.percentile(flux, 99) + 1e-9)
    return np.arange(len(flux)) * hop / sr, flux


def analyze(plan: dict) -> None:
    a = plan["audio"]
    x = decode_mono(res(a["music"]))
    t, flux = onsets(x)
    tl = timeline(plan)
    # The perceived edit points: the middle of every transition, and the impact under the title.
    events = []
    for s in tl[1:]:
        d = float(s["tin"].get("duration", 0.0))
        events.append(s["start"] + d / 2)
    total = sum(s["dur"] for s in tl)
    best = []
    win = int(0.04 / (t[1] - t[0]))
    for start in np.arange(0.0, max(0.0, t[-1] - total - 1), 0.01):
        score = 0.0
        for e in events:
            k = int((start + e) / (t[1] - t[0]))
            score += float(flux[max(0, k - win):k + win + 1].max())
        best.append((score, round(float(start), 2)))
    best.sort(reverse=True)
    print("[analyze] edit points (s on the edit):", [round(e, 2) for e in events])
    for score, start in best[:8]:
        print(f"[analyze] music_start_s {start:7.2f}  score {score:.2f}")
    cur = float(a.get("music_start_s", 0.0))
    print(f"[analyze] current music_start_s {cur}: onsets near edits:",
          [round(float(t[np.argmax(flux * (np.abs(t - cur - e) < 0.12))] - cur - e), 3) for e in events])


def wav_write(path: Path, x: np.ndarray) -> None:
    x = np.clip(x, -1, 1)
    st = np.stack([x, x], 1) if x.ndim == 1 else x
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((st * 32767).astype("<i2").tobytes())


def lowpass(x: np.ndarray, hz: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):   # one-pole; short clips only
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def synth_wind_water(seconds: float, seed: int = 11) -> np.ndarray:
    """Placeholder ambience until a recorded one exists: wind (slowly breathing filtered noise, gusts) and water
    lapping (low brown noise with soft swells), stereo-decorrelated."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = []
    for ch in range(2):
        white = rng.standard_normal(n).astype(np.float64)
        brown = np.cumsum(white)
        brown -= lowpass(brown, 2.0)      # remove the drift
        brown /= np.abs(brown).max() + 1e-9
        wind = lowpass(white, 900.0) - lowpass(white, 180.0)
        gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 3.7 + ch) * np.sin(2 * np.pi * t / 2.3 + 0.7)
        wind = wind / (np.abs(wind).max() + 1e-9) * gust
        lap = lowpass(brown, 350.0)
        swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / 1.9 + ch * 1.3) ** 2
        lap = lap / (np.abs(lap).max() + 1e-9) * swell
        out.append(0.55 * wind + 0.8 * lap)
    st = np.stack(out, 1)
    return st / (np.abs(st).max() + 1e-9) * 0.8


def synth_impact(seed: int = 5) -> np.ndarray:
    """A soft low hit under the title: a sine falling 62 → 38 Hz with a slow decay, a felt-like noise thump."""
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    f = 38 + 24 * np.exp(-t * 6)
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t * 2.2) * (1 - np.exp(-t * 300))
    rng = np.random.default_rng(seed)
    thump = lowpass(rng.standard_normal(n), 160.0) * np.exp(-t * 18) * 3.0
    x = body + thump
    return x / (np.abs(x).max() + 1e-9) * 0.9


def load_plan(arg: str) -> tuple[str, dict]:
    """`arg` is a plan file or the id of data/trailer/<id>.json."""
    p = Path(arg)
    if not p.suffix:
        p = ROOT / "data" / "trailer" / f"{arg}.json"
    return p.stem, json.loads(p.read_text(encoding="utf-8"))


def decode_stereo(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def lufs_of(x: np.ndarray) -> float:
    """Integrated loudness (ebur128) of a stereo clip."""
    tmp = ROOT / "build" / "trailer" / "_lufs.wav"
    wav_write(tmp, x)
    log = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(tmp), "-af", "ebur128", "-f", "null", "-"], capture=True)
    return float(log[log.rindex("I:"):].split()[1])


def db(x: float) -> float:
    return 10 ** (x / 20.0)


def fade_env(n: int, fin: float, fout: float) -> np.ndarray:
    e = np.ones(n)
    k = min(n, int(fin * SR))
    if k > 0:
        e[:k] = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
    k = min(n, int(fout * SR))
    if k > 0:
        e[n - k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return e


def place(buf: np.ndarray, x: np.ndarray, at_s: float) -> None:
    i = max(0, int(round(at_s * SR)))
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def audio_mix(plan: dict, tl: list[dict], work: Path, total: float) -> np.ndarray:
    """Everything on one timeline (numpy, 48 kHz stereo): music (one track or several crossfaded, with a gain curve
    and ducking under the voices), the game's own sound of every shot, ambience, voices, the impact under the title.
    Loudness is set afterwards (loudnorm)."""
    a = plan["audio"]
    n = int(total * SR)
    by_id = {s["shot"]["id"]: s for s in tl}
    # --- music
    tracks = a["music"] if isinstance(a["music"], list) else [
        {"file": a["music"], "at": 0.0, "start_s": a.get("music_start_s", 0.0), "fade_in_s": a.get("music_fade_in_s", 1.0)}]
    music = np.zeros((n, 2))
    for i, t in enumerate(tracks):
        x = decode_stereo(res(t["file"]))
        k0 = int(float(t.get("start_s", 0.0)) * SR)
        at = float(t.get("at", 0.0))
        end = float(tracks[i + 1]["at"]) + float(tracks[i + 1].get("fade_in_s", 0.0)) if i + 1 < len(tracks) else total
        length = int((end - at) * SR)
        seg = x[k0:k0 + length]
        seg = seg * fade_env(len(seg), float(t.get("fade_in_s", 0.0)), float(tracks[i + 1].get("fade_in_s", 0.0)) if i + 1 < len(tracks) else 0.0)[:, None]
        place(music, seg * db(float(t.get("gain_db", 0.0))), at)
    curve = a.get("music_curve")
    if curve:
        tt = np.arange(n) / SR
        music *= (10 ** (np.interp(tt, [c[0] for c in curve], [c[1] for c in curve]) / 20.0))[:, None]
    fo = float(a.get("music_fade_out_s", 1.5))
    music *= fade_env(n, 0.0, fo)[:, None]
    music *= db(float(a.get("music_gain_db", 0.0)))
    # --- voices: level = the music's own level at that place (Director: «ровно с музыкой»), the music ducks under them
    voices = []
    for v in a.get("voice", []):
        s = by_id[v["shot"]]
        at = s["start"] + float(v.get("at_s", 0.0))
        x = decode_stereo(res(v["file"]))
        i0, i1 = int(at * SR), min(n, int(at * SR) + len(x))
        m = music[i0:i1]
        gain = float(v.get("gain_db", 0.0))
        if len(m) > SR and float(v.get("match_music", 1)):
            gain += lufs_of(m) - lufs_of(x)
        voices.append((at, len(x) / SR, x * db(gain)))
    duck = np.ones(n)
    dk = a.get("duck", {"db": -8.0, "attack_s": 0.25, "release_s": 0.7})
    for at, dur, _ in voices:
        i0, i1 = int((at - float(dk["attack_s"])) * SR), int((at + dur + float(dk["release_s"])) * SR)
        ramp_in, ramp_out = int(dk["attack_s"] * SR), int(dk["release_s"] * SR)
        env = np.ones(max(0, i1 - i0)) * db(float(dk["db"]))
        if ramp_in > 0 and len(env) > ramp_in:
            env[:ramp_in] = db(float(dk["db"])) ** np.linspace(0, 1, ramp_in)
        if ramp_out > 0 and len(env) > ramp_out:
            env[-ramp_out:] = db(float(dk["db"])) ** np.linspace(1, 0, ramp_out)
        lo = max(0, i0)
        duck[lo:i1] = np.minimum(duck[lo:i1], env[lo - i0:lo - i0 + (i1 - lo)])
    mix = music * duck[:, None]
    for at, _, x in voices:
        place(mix, x, at)
    # --- the game's own sound of every shot (Movie Maker's wav), faded with its transitions
    for s in tl:
        wavp = work / s["shot"]["id"] / "f.wav"
        if not wavp.exists() or wavp.stat().st_size < 1000:
            continue
        x = decode_stereo(wavp)
        pre = int(float(s["shot"].get("preroll_s", 0.0)) * SR)
        x = x[pre:pre + int(s["len"] * SR)]
        fin = max(0.05, float(s["tin"].get("duration", 0.05)))
        fout = max(0.05, s["tail"])
        x = x * fade_env(len(x), fin, fout)[:, None] * db(float(s["shot"].get("game_audio_db", a.get("game_audio_gain_db", 0.0))))
        place(mix, x, s["start"])
    # --- ambience (a file, or the placeholder wind and water) under a shot
    for amb in a.get("ambience", []):
        s = by_id.get(amb.get("shot"))
        if s is None:
            continue
        length = int(s["len"] * SR)
        if "synth" in amb:
            x = synth_wind_water(s["len"] + 0.5)
        else:
            x = decode_stereo(res(amb["file"]))
        x = np.tile(x, (length // len(x) + 1, 1))[:length]
        fi, fo2 = amb.get("fade_s", [0.5, 0.5])
        x = x * fade_env(length, float(fi), max(float(fo2), s["tail"]))[:, None] * db(float(amb.get("gain_db", -20)))
        place(mix, x, s["start"])
    imp = a.get("impact")
    if imp and imp.get("at_shot") in by_id:
        place(mix, np.stack([synth_impact()] * 2, 1) * db(float(imp.get("gain_db", -10))),
              by_id[imp["at_shot"]]["start"] + float(imp.get("offset_s", 0.0)))
    return mix * fade_env(n, 0.0, 0.25)[:, None]


def assemble(plan_arg: str) -> Path:
    plan_id, plan = load_plan(plan_arg)
    fps = int(os.environ.get("FPS") or plan.get("fps", 60))
    ow, oh = plan.get("out_size", [1920, 1080])
    work = ROOT / "build" / "trailer" / plan_id
    tl = timeline(plan)
    total = sum(s["dur"] for s in tl)
    end_fade = float(plan.get("end_fade_s", 0.4))
    grain = float(plan.get("grain", 5))

    # --- video ---------------------------------------------------------------------------------
    inputs, chains = [], []
    for i, s in enumerate(tl):
        d = work / s["shot"]["id"]
        skip = int(round(float(s["shot"].get("preroll_s", 0.0)) * fps))
        nframes = int(round(s["len"] * fps))
        inputs += ["-framerate", str(fps), "-start_number", str(skip), "-i", str(d / "f%08d.png")]
        chains.append(f"[{i}:v]trim=end_frame={nframes},setpts=PTS-STARTPTS,"
                      f"scale={ow}:{oh}:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv444p,fps={fps}[v{i}]")
    last = "v0"
    for i in range(1, len(tl)):
        kind = {"dissolve": "fade", "fadeblack": "fadeblack"}.get(tl[i]["tin"].get("kind", "dissolve"), "fade")
        dur = float(tl[i]["tin"].get("duration", 0.5))
        chains.append(f"[{last}][v{i}]xfade=transition={kind}:duration={dur}:offset={tl[i]['start']:.4f}[x{i}]")
        last = f"x{i}"
    chains.append(f"[{last}]trim=duration={total:.4f},noise=c0s={grain}:c0f=t+u:c1s={grain * 0.4}:c1f=t+u:c2s={grain * 0.4}:c2f=t+u,"
                  f"fade=t=out:st={total - end_fade:.4f}:d={end_fade},format=yuv420p[vout]")

    # --- audio ---------------------------------------------------------------------------------
    a = plan["audio"]
    pre = work / "premix.wav"
    wav_write(pre, audio_mix(plan, tl, work, total))
    target = float(a.get("loudness_lufs", -14.0))
    tp = float(a.get("true_peak_db", -1.5))
    log = run(["ffmpeg", "-hide_banner", "-i", str(pre), "-af", f"loudnorm=I={target}:TP={tp}:LRA=11:print_format=json",
               "-f", "null", "-"], capture=True)
    m = json.loads(log[log.rindex("{"):log.rindex("}") + 1])
    ln = (f"loudnorm=I={target}:TP={tp}:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
          f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    out = ROOT / "build" / "trailer" / f"{plan_id}.mp4"
    run(["ffmpeg", "-y", "-v", "error", *inputs, "-i", str(pre),
         "-filter_complex", ";".join(chains) + f";[{len(tl)}:a]{ln},aresample={SR}[aout]",
         "-map", "[vout]", "-map", "[aout]",
         "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level", "4.2", "-pix_fmt", "yuv420p",
         "-b:v", "24M", "-minrate", "12M", "-maxrate", "30M", "-bufsize", "48M", "-r", str(fps), "-g", str(fps // 2),
         "-tune", "film", "-x264-params", "nal-hrd=vbr",
         "-c:a", "aac", "-b:a", "320k", "-ar", str(SR), "-movflags", "+faststart", str(out)])
    print(f"[assemble] {out.relative_to(ROOT)}  ({total:.2f} s)")
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    plan_arg = args[0] if args else "test_7s"
    if "--analyze" in sys.argv:
        analyze(load_plan(plan_arg)[1])
        return 0
    assemble(plan_arg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
