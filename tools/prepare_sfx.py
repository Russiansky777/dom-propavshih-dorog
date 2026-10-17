#!/usr/bin/env python3
"""Звуки ElevenLabs (assets/sfx_src/*.wav) → игровые файлы game/assets/sfx/ (SfxDirector, data/story/sfx.json).

Запуск: tools/prepare_sfx.sh  (нужны numpy, scipy и ffmpeg; результат коммитится — в CI не выполняется)

Обработка:
  - двери (sfx_door_passage, sfx_door_variant_01/02): срез тишины по краям, срез инфранизких (ВЧ-фильтр
    40 Гц), пики к −1 dBFS, WAV 16 бит 48 кГц стерео; файл целиком (открыть и закрыть);
  - шаги (sfx_steps_gravel 30 с, sfx_steps_soft 5,5 с — серии шагов): нарезка по атакам огибающей
    (5 мс, подъём ≥ 9 dB над медианой предыдущих 100 мс, не чаще 0,45 с — один шаг, а не хруст пятки и
    носка отдельно), отрезок от подъёма до −20 dB от пика (− 10 мс) до следующей атаки − 30 мс (не
    длиннее 0,6 с), хвост обрезается на −32 dB от пика (шум записи), наплыв 2 мс / затухание 40 мс; у мягких шагов сначала срезается
    непрерывный низкий гул источника (ВЧ 150 Гц, 86 % энергии ниже 200 Гц); выбираются до 8 самых
    чистых (сильная атака, тихий конец), моно, пики к −1 dBFS, затем более громкие ослабляются до
    медианы своей группы по максимуму momentary (разброс шагов одного покрытия ≤ ~3 dB, случайный выбор
    не даёт «выстрелов») → sfx_steps_<покрытие>_NN.wav;
  - сумка (sfx_bag_leather): весь шорох (срез тишины) → sfx_bag_leather.wav и отдельные жесты той же
    нарезкой → sfx_bag_leather_short_NN.wav;
  - петли (amb_rain, amb_stove_fire): бесшовная склейка — первые X секунд заменяются равномощной смесью
    начала и хвоста (хвост гаснет, начало нарастает), длина N − X: конец петли переходит в её начало без
    шва; затем громкость к цели (дождь −28 LUFS integrated; огонь — ВЧ 150 Гц убирает гул комнаты
    источника и −24 LUFS), пики ≤ −1 dBFS; OGG Vorbis q5, импорт loop=true.
Измерения каждого файла (пик, LUFS integrated, максимум momentary 400 мс, длительность) пишутся в
game/assets/sfx/levels.json — по ним tools/validate_sfx.py проверяет соотношение громкостей с музыкой.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "sfx_src"
DST = ROOT / "game" / "assets" / "sfx"
SR = 48000
PEAK_DB = -1.0

OGG_IMPORT = """[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[params]

loop=true
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
"""


def read(name: str) -> np.ndarray:
    sr, x = wavfile.read(SRC / name)
    assert sr == SR, f"{name}: {sr} Hz, ожидается {SR}"
    x = x.astype(np.float64) / 32768.0
    return x if x.ndim == 2 else x[:, None]


def write_wav(name: str, x: np.ndarray) -> Path:
    path = DST / name
    y = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    wavfile.write(path, SR, y if y.shape[1] > 1 else y[:, 0])
    return path


def highpass(x: np.ndarray, hz: float) -> np.ndarray:
    sos = butter(4, hz, "highpass", fs=SR, output="sos")
    return sosfiltfilt(sos, x, axis=0)


def db(v: float) -> float:
    return 20.0 * np.log10(max(v, 1e-12))


def peak_normalize(x: np.ndarray, peak_db: float = PEAK_DB) -> np.ndarray:
    p = np.abs(x).max()
    return x * (10 ** (peak_db / 20.0) / p) if p > 0 else x


def fade(x: np.ndarray, fin_s: float, fout_s: float) -> np.ndarray:
    x = x.copy()
    n_in, n_out = int(fin_s * SR), int(fout_s * SR)
    if n_in > 0:
        x[:n_in] *= (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n_in)))[:, None]
    if n_out > 0:
        x[-n_out:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n_out)))[:, None]
    return x


def envelope_db(m: np.ndarray, win_s: float = 0.005) -> np.ndarray:
    w = int(SR * win_s)
    n = len(m) // w
    return 20 * np.log10(np.sqrt((m[: n * w].reshape(n, w) ** 2).mean(axis=1)) + 1e-12)


def trim_silence(x: np.ndarray, rel_db: float = -55.0, pre_s: float = 0.02, post_s: float = 0.05) -> np.ndarray:
    env = envelope_db(x.mean(axis=1))
    on = np.where(env > env.max() + rel_db)[0]
    if len(on) == 0:
        return x
    w = int(SR * 0.005)
    a = max(0, on[0] * w - int(pre_s * SR))
    b = min(len(x), (on[-1] + 1) * w + int(post_s * SR))
    return fade(x[a:b], 0.002, 0.03)


def slice_hits(x: np.ndarray, min_gap_s: float, max_len_s: float, keep: int, detect_hp: float = 300.0,
               tail_db: float = 32.0) -> list[np.ndarray]:
    """Single hits (steps, bag gestures) cut at their attacks; the `keep` cleanest, in time order."""
    m = highpass(x, detect_hp).mean(axis=1)
    env = envelope_db(m)
    w = int(SR * 0.005)
    gap = int(min_gap_s / 0.005)
    onsets: list[int] = []
    for i in range(1, len(env)):
        base = np.median(env[max(0, i - 20):i])
        if env[i] - base >= 9.0 and env[i] > env.max() - 30.0 and (not onsets or i - onsets[-1] >= gap):
            onsets.append(i)
    cands = []
    for k, o in enumerate(onsets):
        a = max(0, o * w - int(0.015 * SR))
        nxt = onsets[k + 1] * w - int(0.03 * SR) if k + 1 < len(onsets) else len(x)
        b = min(nxt, a + int(max_len_s * SR), len(x))
        seg_env = envelope_db(x[a:b].mean(axis=1))
        if len(seg_env) < 16:
            continue
        pk = seg_env.max()
        # Start at the attack itself (a gravel crunch rises gradually from the noise floor) …
        first = int(np.argmax(seg_env > pk - 20.0))
        a2 = a + max(0, first * w - int(0.01 * SR))
        # … and end where the step has died down to the floor of the recording.
        live = np.where(seg_env > pk - tail_db)[0]
        b = a + min((live[-1] + 1) * w + int(0.02 * SR), b - a)
        a = a2
        seg = x[a:b]
        if len(seg) < int(0.1 * SR):
            continue
        tail = envelope_db(seg.mean(axis=1))[-6:].mean()   # last 30 ms
        score = pk - 0.6 * (tail - (pk - tail_db))          # strong attack, quiet end
        cands.append((score, a, seg))
    best = sorted(cands, key=lambda c: -c[0])[:keep]
    return [fade(c[2], 0.002, 0.04) for c in sorted(best, key=lambda c: c[1])]


def seamless_loop(x: np.ndarray, xf_s: float) -> np.ndarray:
    n, xf = len(x), int(xf_s * SR)
    t = np.linspace(0.0, np.pi / 2, xf)[:, None]
    head = x[:xf] * np.sin(t) + x[n - xf:] * np.cos(t)
    return np.concatenate([head, x[xf:n - xf]], axis=0)


def measure(path: Path) -> dict:
    """Peak, integrated loudness and the loudest momentary (400 ms) window; short files are padded."""
    sr, y = wavfile.read(path) if path.suffix == ".wav" else (None, None)
    with tempfile.TemporaryDirectory() as td:
        padded = Path(td) / "p.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-af", "adelay=500|500,apad=pad_dur=0.5",
                        "-ar", str(SR), str(padded)], check=True)
        r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(padded), "-af", "ebur128=peak=sample",
                            "-f", "null", "-"], capture_output=True, text=True)
    log = r.stderr
    moments = [float(v) for v in re.findall(r"M:\s*(-?[\d.]+)", log)]
    summary = log[log.rfind("Summary:"):]
    i_lufs = float(re.search(r"I:\s*(-?[\d.]+) LUFS", summary).group(1))
    peak = float(re.search(r"Peak:\s*(-?[\d.inf]+) dBFS", summary).group(1))
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                               capture_output=True, text=True).stdout.strip())
    return {"peak_db": round(peak, 2), "lufs_i": round(i_lufs, 2), "lufs_m_max": round(max(moments), 2), "duration_s": round(dur, 3)}


def momentary_max(x: np.ndarray) -> float:
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "x.wav"
        pad = np.zeros((SR // 2, x.shape[1]))
        y = np.clip(np.round(np.concatenate([pad, x, pad]) * 32767.0), -32768, 32767).astype(np.int16)
        wavfile.write(p, SR, y)
        r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(p), "-af", "ebur128", "-f", "null", "-"],
                           capture_output=True, text=True)
    return max(float(v) for v in re.findall(r"M:\s*(-?[\d.]+)", r.stderr))


def loudness_i(x: np.ndarray) -> float:
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "x.wav"
        y = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
        wavfile.write(p, SR, y)
        r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(p), "-af", "ebur128", "-f", "null", "-"],
                           capture_output=True, text=True)
    s = r.stderr[r.stderr.rfind("Summary:"):]
    return float(re.search(r"I:\s*(-?[\d.]+) LUFS", s).group(1))


def to_loudness(x: np.ndarray, target: float) -> np.ndarray:
    g = 10 ** ((target - loudness_i(x)) / 20.0)
    y = x * g
    p = np.abs(y).max()
    lim = 10 ** (PEAK_DB / 20.0)
    if p > lim:
        print(f"    пик {db(p):.1f} dBFS после усиления — ограничен до {PEAK_DB} dBFS (громкость ниже цели)")
        y *= lim / p
    return y


def write_ogg(name: str, x: np.ndarray) -> Path:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "loop.wav"
        y = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
        wavfile.write(tmp, SR, y)
        out = DST / name
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "5", str(out)], check=True)
    imp = DST / (name + ".import")
    if not imp.exists():
        imp.write_text(OGG_IMPORT, encoding="utf-8")
    else:
        t = imp.read_text(encoding="utf-8")
        imp.write_text(re.sub(r"(?m)^loop=.*$", "loop=true", t), encoding="utf-8")
    return out


def main() -> int:
    DST.mkdir(parents=True, exist_ok=True)
    for old in list(DST.glob("sfx_*.wav")) + list(DST.glob("amb_*.ogg")):
        old.unlink()
        Path(str(old) + ".import").unlink(missing_ok=True) if old.suffix == ".wav" else None
    made: list[Path] = []
    for name in ("sfx_door_passage", "sfx_door_variant_01", "sfx_door_variant_02"):
        x = trim_silence(highpass(read(name + ".wav"), 40.0))
        made.append(write_wav(name + ".wav", peak_normalize(x)))
    for surface, hp, keep in (("gravel", 60.0, 8), ("soft", 150.0, 8)):
        x = highpass(read(f"sfx_steps_{surface}.wav"), hp)
        hits = slice_hits(x, 0.45, 0.6, keep)
        print(f"  шаги {surface}: {len(hits)} шт., {', '.join(f'{len(h) / SR:.2f}' for h in hits)} с")
        monos = [peak_normalize(h.mean(axis=1, keepdims=True)) for h in hits]
        moms = [momentary_max(mo) for mo in monos]
        med = float(np.median(moms))
        for i, (mo, mm) in enumerate(zip(monos, moms), 1):
            if mm > med:
                mo = mo * 10 ** ((med - mm) / 20.0)
            made.append(write_wav(f"sfx_steps_{surface}_{i:02d}.wav", mo))
    bag = highpass(read("sfx_bag_leather.wav"), 80.0)
    made.append(write_wav("sfx_bag_leather.wav", peak_normalize(trim_silence(bag).mean(axis=1, keepdims=True))))
    gestures = slice_hits(bag, 0.3, 0.7, 3, detect_hp=1000.0)
    print(f"  сумка: жестов {len(gestures)}, {', '.join(f'{len(h) / SR:.2f}' for h in gestures)} с")
    for i, h in enumerate(gestures, 1):
        made.append(write_wav(f"sfx_bag_leather_short_{i:02d}.wav", peak_normalize(h.mean(axis=1, keepdims=True))))
    rain = to_loudness(seamless_loop(read("amb_rain.wav"), 2.0), -28.0)
    made.append(write_ogg("amb_rain.ogg", rain))
    fire = to_loudness(seamless_loop(highpass(read("amb_stove_fire.wav"), 150.0), 1.5), -24.0)
    made.append(write_ogg("amb_stove_fire.ogg", fire))
    levels = {"_comment": "Измерения tools/prepare_sfx.py (ffmpeg ebur128): peak_db, lufs_i, lufs_m_max (громчайшее окно 400 мс), duration_s. Короткие файлы измерены с 0,5 с тишины по краям."}
    for p in made:
        levels[p.name] = measure(p)
        print(f"  {p.name}: {levels[p.name]}")
    (DST / "levels.json").write_text(json.dumps(levels, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"prepare_sfx: {len(made)} файлов → {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
