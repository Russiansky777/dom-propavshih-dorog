#!/usr/bin/env python3
"""Механическая проверка записей голоса (на слух проверить некому): assets/voice/ru/manifest.json.

Для каждой актуальной записи (не stale, назначенный голос):
  - темп: буквы текста / длительность — вне 5…20 букв/с или дальше 3,5 σ от среднего говорящего (по лог-темпу) —
    подозрение: обрыв, лишние слова, прочитанный вслух тег, затянутая пауза;
  - громкость: LUFS вне цели ±1 LU, true peak выше −1 dBTP;
  - пустота и обрывы: длительность < 0,3 с; внутри записи пауза > 1,6 с (кадры тише −50 dBFS);
  - теги: tag_check.suspect из конвейера (тег мог прозвучать словом).
Печатает выбросы и строку "reseed" для запроса перезаписи (новый дубль другим seed — один раз).

  python3 tools/voice_audio_check.py [--json build/voice_audio_check.json]
"""
from __future__ import annotations

import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
VOICE = ROOT / "assets" / "voice" / "ru"
SR = 16000

_vs = importlib.util.spec_from_file_location("voice_coverage", ROOT / "tools" / "voice_coverage.py")
vc = importlib.util.module_from_spec(_vs)
_vs.loader.exec_module(vc)


def letters(t: str) -> int:
    return sum(1 for ch in t if ch.isalpha())


def longest_pause(path: Path) -> float:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    fr = int(0.02 * SR)
    n = len(x) // fr
    if n == 0:
        return 0.0
    rms = np.sqrt(np.mean(x[:n * fr].reshape(n, fr) ** 2, axis=1)) + 1e-9
    quiet = 20 * np.log10(rms) < -50
    best = run = 0
    for q in quiet:
        run = run + 1 if q else 0
        best = max(best, run)
    return best * 0.02


def main() -> int:
    man = json.loads((VOICE / "manifest.json").read_text(encoding="utf-8"))
    target = float(man.get("loudness_target_lufs", -17.0))
    playing = {r["id"] for r in vc.coverage()["rows"] if r["status"] == "записана"}
    rows = []
    for lid, e in man["lines"].items():
        if lid not in playing:
            continue
        n = letters(str(e.get("text", "")))
        d = float(e.get("duration_s", 0))
        rows.append({"id": lid, "speaker": e.get("speaker", ""), "letters": n, "duration_s": d,
                     "rate": n / d if d > 0 else 0.0, "lufs": e.get("lufs"), "tp": e.get("true_peak_db"),
                     "file": e.get("file"), "tag_suspect": bool((e.get("tag_check") or {}).get("suspect")),
                     "text": e.get("text", "")})
    by_sp: dict[str, list[float]] = {}
    for r in rows:
        if r["letters"] >= 12:
            by_sp.setdefault(r["speaker"], []).append(math.log(max(r["rate"], 0.1)))
    stats = {sp: (float(np.mean(v)), float(np.std(v)) or 0.1) for sp, v in by_sp.items() if len(v) >= 4}
    flagged = []
    for r in rows:
        why = []
        if r["duration_s"] < 0.3:
            why.append(f"длительность {r['duration_s']} с")
        if r["letters"] >= 8 and not 5.0 <= r["rate"] <= 20.0:
            why.append(f"темп {r['rate']:.1f} букв/с")
        st = stats.get(r["speaker"])
        if st and r["letters"] >= 12:
            z = (math.log(max(r["rate"], 0.1)) - st[0]) / st[1]
            if abs(z) > 3.5:
                why.append(f"темп {r['rate']:.1f} букв/с — {z:+.1f} σ от среднего {math.exp(st[0]):.1f} у {r['speaker']}")
        if not isinstance(r["lufs"], (int, float)) or abs(float(r["lufs"]) - target) > 1.0:
            why.append(f"громкость {r['lufs']} LUFS")
        if isinstance(r["tp"], (int, float)) and float(r["tp"]) > -1.0:
            why.append(f"true peak {r['tp']} dBTP")
        if r["tag_suspect"]:
            why.append("тег мог прозвучать словом")
        p = longest_pause(VOICE / str(r["file"]))
        r["longest_pause_s"] = round(p, 2)
        if p > 1.6:
            why.append(f"пауза внутри {p:.1f} с")
        if why:
            r["why"] = why
            flagged.append(r)
    print(f"[audio] записей: {len(rows)}; темп по говорящим (букв/с): " +
          ", ".join(f"{sp} {math.exp(m):.1f}" for sp, (m, _s) in sorted(stats.items())))
    for r in flagged:
        print(f"  {r['id']:36} {r['speaker']:9} {r['duration_s']:5.2f} с  {'; '.join(r['why'])}  «{r['text'][:70]}»")
    print(f"[audio] выбросов: {len(flagged)}")
    if flagged:
        print("reseed: " + json.dumps({r["id"]: 1 for r in flagged}, ensure_ascii=False))
    if "--json" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--json") + 1])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"rows": rows, "flagged": flagged, "speaker_rate": {k: math.exp(v[0]) for k, v in stats.items()}},
                                  ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
