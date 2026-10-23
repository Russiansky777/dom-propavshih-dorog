#!/usr/bin/env python3
"""Шаги по снегу (G39, Директор 23.10: на втором берегу шаги «по квартире», а не по снегу) — синтез, собственная работа
(CC0): готового звука CC0 с проверяемым источником в этой сессии взять не удалось, поэтому мягкий хруст делается здесь.

    python3 tools/make_snow_steps.py        (нужны numpy, scipy, ffmpeg; результат коммитится, в CI не выполняется)

Один шаг (0,32–0,42 с): пятка — плотная россыпь мелких «зёрен» (1–4 мс полосового шума, амплитуды по
логнормальному закону — хруст наста), затем перекат стопы — вторая, более редкая и тихая россыпь; под ними глухое
уплотнение снега (шум ниже 280 Гц с коротким спадом). Полоса зёрен 350 Гц – 6,5 кГц с подъёмом около 2 кГц.
У каждого из шести дублей своё зерно генератора, длина и баланс пятки и переката (случайный выбор SfxDirector не
повторяет дубль подряд). Моно 48 кГц 16 бит, пики к −1 dBFS, затем громкость к медиане мягких шагов (максимум
momentary, как в tools/prepare_sfx.py) — снег не громче пола в доме. Измерения дописываются в
game/assets/sfx/levels.json (по ним tools/validate_sfx.py сверяет громкость с музыкой).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import prepare_sfx as ps  # noqa: E402  (measure, momentary_max, SR, PEAK_DB)

OUT = ROOT / "game" / "assets" / "sfx"
SR = 48000
TAKES = 6


def _band(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return sosfiltfilt(butter(4, [lo, hi], btype="band", fs=SR, output="sos"), x)


def _low(x: np.ndarray, hz: float) -> np.ndarray:
    return sosfiltfilt(butter(4, hz, btype="low", fs=SR, output="sos"), x)


def _grains(n: int, rate: np.ndarray, rng: np.random.Generator, amp_sigma: float) -> np.ndarray:
    """Poisson train of short noise grains: `rate` grains per second at each sample."""
    x = np.zeros(n)
    p = rate / SR
    hits = np.nonzero(rng.random(n) < p)[0]
    for i in hits:
        ln = int(rng.integers(int(0.0008 * SR), int(0.004 * SR)))
        ln = min(ln, n - i)
        if ln <= 4:
            continue
        g = rng.standard_normal(ln) * np.exp(-np.linspace(0.0, rng.uniform(3.0, 9.0), ln))
        x[i:i + ln] += g * rng.lognormal(0.0, amp_sigma)
    return x


def step(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.32, 0.42)
    n = int(dur * SR)
    t = np.arange(n) / SR
    heel_t, heel_w = rng.uniform(0.022, 0.035), rng.uniform(0.018, 0.028)
    roll_t, roll_w = rng.uniform(0.13, 0.18), rng.uniform(0.05, 0.07)
    roll_k = rng.uniform(0.45, 0.7)
    dens = np.exp(-0.5 * ((t - heel_t) / heel_w) ** 2) + roll_k * np.exp(-0.5 * ((t - roll_t) / roll_w) ** 2)
    crunch = _grains(n, 2200.0 * dens, rng, 0.55)
    crunch = _band(crunch, 350.0, 6500.0) + 0.6 * _band(crunch, 1400.0, 3000.0)
    loud = np.exp(-0.5 * ((t - heel_t) / (heel_w * 1.6)) ** 2) + 0.75 * roll_k * np.exp(-0.5 * ((t - roll_t) / (roll_w * 1.3)) ** 2)
    crunch *= 0.35 + 0.65 * loud
    thud_env = np.clip(t / 0.006, 0.0, 1.0) * np.exp(-np.maximum(t - 0.006, 0.0) / 0.055)
    thud = _low(rng.standard_normal(n), 280.0) * thud_env
    x = crunch / max(np.abs(crunch).max(), 1e-9) + 0.45 * thud / max(np.abs(thud).max(), 1e-9)
    fi, fo = int(0.002 * SR), int(0.04 * SR)
    x[:fi] *= np.linspace(0.0, 1.0, fi)
    x[-fo:] *= np.linspace(1.0, 0.0, fo)
    x /= np.abs(x).max()
    return x * 10 ** (ps.PEAK_DB / 20.0)


def main() -> int:
    levels_path = OUT / "levels.json"
    levels = json.loads(levels_path.read_text())
    soft = sorted(v["lufs_m_max"] for k, v in levels.items() if k.startswith("sfx_steps_soft_"))
    target = soft[len(soft) // 2]
    print(f"цель: максимум momentary мягких шагов (медиана) {target:.1f} LUFS")
    for i in range(TAKES):
        x = step(7301 + 97 * i)
        m = ps.momentary_max(x[:, None])
        x *= 10 ** ((target - m) / 20.0)
        lim = 10 ** (ps.PEAK_DB / 20.0)
        if np.abs(x).max() > lim:
            x *= lim / np.abs(x).max()
        name = f"sfx_steps_snow_{i + 1:02d}.wav"
        path = OUT / name
        wavfile.write(path, SR, np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16))
        levels[name] = ps.measure(path)
        print(f"  {name}: {levels[name]}")
    levels_path.write_text(json.dumps(levels, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
