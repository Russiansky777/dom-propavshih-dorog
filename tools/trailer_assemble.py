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


def assemble(plan_id: str) -> Path:
    plan = json.loads((ROOT / "data" / "trailer" / f"{plan_id}.json").read_text(encoding="utf-8"))
    fps = int(plan.get("fps", 60))
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
    ain, achains, mix = [], [], []
    idx = len(tl)

    def add_input(path: Path) -> int:
        nonlocal idx
        ain.extend(["-i", str(path)])
        idx += 1
        return idx - 1

    ms = float(a.get("music_start_s", 0.0))
    k = add_input(res(a["music"]))
    achains.append(f"[{k}:a]atrim=start={ms}:duration={total},asetpts=PTS-STARTPTS,aresample={SR},aformat=channel_layouts=stereo,"
                   f"afade=t=in:st=0:d={a.get('music_fade_in_s', 1.0)}:curve=qsin,"
                   f"afade=t=out:st={total - float(a.get('music_fade_out_s', 1.5)):.3f}:d={a.get('music_fade_out_s', 1.5)}:curve=qsin,"
                   f"volume={a.get('music_gain_db', 0.0)}dB[mus]")
    mix.append("[mus]")
    # The game's own sound of every shot (Movie Maker's wav), from the visible start, faded with its transitions.
    for s in tl:
        wavp = work / s["shot"]["id"] / "f.wav"
        if not wavp.exists() or wavp.stat().st_size < 1000:
            continue
        k = add_input(wavp)
        pre = float(s["shot"].get("preroll_s", 0.0))
        fin = max(0.05, float(s["tin"].get("duration", 0.05)))
        fout = max(0.05, s["tail"])
        lab = f"g{k}"
        achains.append(f"[{k}:a]atrim=start={pre}:duration={s['len']},asetpts=PTS-STARTPTS,aresample={SR},aformat=channel_layouts=stereo,"
                       f"afade=t=in:d={fin}:curve=qsin,afade=t=out:st={s['len'] - fout:.3f}:d={fout}:curve=qsin,"
                       f"volume={a.get('game_audio_gain_db', 0.0)}dB,adelay={int(s['start'] * 1000)}:all=1[{lab}]")
        mix.append(f"[{lab}]")
    by_id = {s["shot"]["id"]: s for s in tl}
    for amb in a.get("ambience", []):
        s = by_id.get(amb.get("shot"))
        if s is None:
            continue
        begin = max(0.0, s["start"] - (float(s["tin"].get("duration", 0.0)) if s["tin"] else 0.0) * 0.0)
        length = s["len"]
        if "synth" in amb:
            p = work / f"synth_{amb['id']}.wav"
            wav_write(p, synth_wind_water(length + 0.5))
        else:
            p = res(amb["file"])
        k = add_input(p)
        fi, fo = amb.get("fade_s", [0.5, 0.5])
        fo = max(float(fo), s["tail"])
        lab = f"a{k}"
        achains.append(f"[{k}:a]aloop=loop=-1:size=2e9,atrim=duration={length},asetpts=PTS-STARTPTS,aresample={SR},aformat=channel_layouts=stereo,"
                       f"afade=t=in:d={fi}:curve=qsin,afade=t=out:st={length - fo:.3f}:d={fo}:curve=qsin,"
                       f"volume={amb.get('gain_db', -20)}dB,adelay={int(begin * 1000)}:all=1[{lab}]")
        mix.append(f"[{lab}]")
    imp = a.get("impact")
    if imp and imp.get("at_shot") in by_id:
        p = work / "synth_impact.wav"
        wav_write(p, synth_impact())
        k = add_input(p)
        at = by_id[imp["at_shot"]]["start"] + float(imp.get("offset_s", 0.0))
        achains.append(f"[{k}:a]aresample={SR},volume={imp.get('gain_db', -10)}dB,adelay={int(at * 1000)}:all=1[imp]")
        mix.append("[imp]")
    achains.append(f"{''.join(mix)}amix=inputs={len(mix)}:normalize=0:duration=longest,atrim=duration={total},"
                   f"afade=t=out:st={total - 0.25:.3f}:d=0.25[mixed]")

    graph = ";".join(achains)   # the video inputs stay (indices), only the audio is mixed here
    # Pass 1: measure the mix for loudnorm.
    pre = work / "premix.wav"
    run(["ffmpeg", "-y", "-v", "error", *inputs, *ain, "-filter_complex", graph, "-map", "[mixed]", "-ar", str(SR), str(pre)])
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
    plan_id = args[0] if args else "test_7s"
    if "--analyze" in sys.argv:
        analyze(json.loads((ROOT / "data" / "trailer" / f"{plan_id}.json").read_text(encoding="utf-8")))
        return 0
    assemble(plan_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
