#!/usr/bin/env python3
"""Выбор превью Voice Design по замерам (на слух выбрать некому — решение по фактам звука, оно записывается в запрос
create_voice → design/<персонаж>.json → created.selection).

Для каждого превью pipeline/voice/design/<персонаж>/preview_<n>.mp3 (режим design конвейера pipeline/voice/eleven_voice.py):
  - высота голоса: медиана и разброс основного тона (автокорреляция по кадрам 40 мс, только озвученные кадры);
  - темп: символы текста превью / время речи (кадры громче порога, паузы не считаются);
  - чистота: шумовой пол (10-й перцентиль громкости кадров относительно 90-го) и доля клиппинга;
  - язык, который вернул API (должен быть ru).
Оценка — расстояние до целевых диапазонов персонажа (--f0 lo hi, --cps lo hi) плюс штрафы за шум, клиппинг и чужой язык;
меньше — лучше. Печатает таблицу и строку selection для запроса.

  python3 tools/voice_design_pick.py ilya_wife --f0 170 230 --cps 10 14
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "pipeline" / "voice" / "design"
SR = 16000


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def analyse(x: np.ndarray, n_chars: int) -> dict:
    frame, hop = int(0.04 * SR), int(0.01 * SR)
    n = max(0, (len(x) - frame) // hop)
    rms = np.array([np.sqrt(np.mean(x[i * hop:i * hop + frame] ** 2)) + 1e-9 for i in range(n)])
    db = 20 * np.log10(rms)
    loud = db > (np.percentile(db, 95) - 30)
    lo_lag, hi_lag = SR // 400, SR // 60          # 60–400 Гц
    f0 = []
    win = np.hanning(frame)
    for i in np.nonzero(loud)[0]:
        seg = x[i * hop:i * hop + frame] * win
        seg = seg - seg.mean()
        ac = np.correlate(seg, seg, mode="full")[frame - 1:]
        if ac[0] <= 0:
            continue
        ac = ac / ac[0]
        lag = lo_lag + int(np.argmax(ac[lo_lag:hi_lag]))
        if ac[lag] > 0.45:
            # уточнение параболой
            if 1 <= lag < len(ac) - 1:
                a, b, c = ac[lag - 1], ac[lag], ac[lag + 1]
                d = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else 0.0
            else:
                d = 0.0
            f0.append(SR / (lag + d))
    f0 = np.array(f0)
    speech_s = float(loud.sum()) * hop / SR
    return {
        "duration_s": round(len(x) / SR, 2),
        "speech_s": round(speech_s, 2),
        "chars_per_s": round(n_chars / speech_s, 2) if speech_s > 0 else 0.0,
        "f0_median_hz": round(float(np.median(f0)), 1) if len(f0) else 0.0,
        "f0_iqr_hz": round(float(np.percentile(f0, 75) - np.percentile(f0, 25)), 1) if len(f0) else 0.0,
        "voiced_frames": int(len(f0)),
        "noise_floor_db": round(float(np.percentile(db, 10) - np.percentile(db, 90)), 1),
        "clip_fraction": round(float(np.mean(np.abs(x) > 0.985)), 5),
        "peak": round(float(np.max(np.abs(x))), 3),
    }


def dist(v: float, lo: float, hi: float) -> float:
    """0 в середине диапазона, 1 на краю, больше 1 — вне."""
    mid, half = (lo + hi) / 2.0, (hi - lo) / 2.0
    return abs(v - mid) / half if half > 0 else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("speaker")
    ap.add_argument("--f0", nargs=2, type=float, required=True)
    ap.add_argument("--cps", nargs=2, type=float, required=True)
    a = ap.parse_args()
    doc = json.loads((DESIGN / f"{a.speaker}.json").read_text(encoding="utf-8"))
    text = str(doc.get("preview_text", ""))
    n_chars = len([ch for ch in text if ch.isalnum()])   # буквы и цифры: пробелы и знаки — не речь
    rows = []
    for p in doc.get("previews", []):
        m = analyse(decode(DESIGN / p["file"]), n_chars)
        score = dist(m["f0_median_hz"], *a.f0) + 0.7 * dist(m["chars_per_s"], *a.cps)
        score += 0.05 * max(0.0, m["noise_floor_db"] + 45.0)      # шумовой пол выше −45 dB — штраф
        score += 50.0 * m["clip_fraction"]
        if str(p.get("language", "ru")) not in ("ru", ""):
            score += 5.0
        rows.append({"n": p["n"], "generated_voice_id": p["generated_voice_id"], "language": p.get("language", ""),
                     **m, "score": round(score, 3)})
    rows.sort(key=lambda r: r["score"])
    print(f"{a.speaker}: цель f0 {a.f0[0]:.0f}–{a.f0[1]:.0f} Гц, темп {a.cps[0]}–{a.cps[1]} букв/с; текст {n_chars} букв")
    for r in rows:
        print(f"  #{r['n']} {r['generated_voice_id']}: f0 {r['f0_median_hz']} Гц (IQR {r['f0_iqr_hz']}), темп {r['chars_per_s']} букв/с, "
              f"речь {r['speech_s']}/{r['duration_s']} с, шум {r['noise_floor_db']} dB, клип {r['clip_fraction']}, "
              f"язык {r['language']}, оценка {r['score']}")
    best = rows[0]
    print("selection: " + json.dumps(
        f"превью {best['n']} из {len(rows)} по замерам (tools/voice_design_pick.py): основной тон {best['f0_median_hz']} Гц "
        f"(цель {a.f0[0]:.0f}–{a.f0[1]:.0f}), темп {best['chars_per_s']} букв/с (цель {a.cps[0]}–{a.cps[1]}), шумовой пол "
        f"{best['noise_floor_db']} dB, клиппинга {best['clip_fraction']}; остальные: "
        + "; ".join(f"#{r['n']} f0 {r['f0_median_hz']} Гц, темп {r['chars_per_s']}, оценка {r['score']}" for r in rows[1:]),
        ensure_ascii=False))
    print("best: " + best["generated_voice_id"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
