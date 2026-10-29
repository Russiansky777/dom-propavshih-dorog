#!/usr/bin/env python3
"""Измеритель ударения в записях голоса (партия J, Директор 29.10: «акценты будто бы снова не везде верно»).

ElevenLabs вместе с записью отдаёт время каждой буквы (src/<id>.align.json). По нему запись режется на слова,
и у каждого слова мерятся три признака логического ударения русской речи:
  - высота: пик основного тона (Praat, parselmouth) в полутонах над медианой фразы;
  - громкость: пик интенсивности (дБ) над медианой пиков слов фразы;
  - растяжка: длительность на букву относительно средней по фразе.
Сумма z-оценок (веса — WEIGHTS) — «выделенность» слова. Для строки с целями из data/story/voice_direction.json
(emph) печатает, на каком месте по выделенности стоят слова-цели; для «нейтральных» строк — насколько самое
выделенное слово выбивается из остальных.

  python3 -I tools/voice_prominence.py LINE_ID ...            # строки из assets/voice/ru/manifest.json
  python3 -I tools/voice_prominence.py --probe DIR            # пробы pipeline/voice/probe/<set> (mp3 + json)
  python3 -I tools/voice_prominence.py --calibrate REVIEW.json # сверка с отметками Директора (ok / redo)
  --json OUT — записать слова и оценки.
Нужны: ffmpeg, numpy, praat-parselmouth (pip install praat-parselmouth).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
VOICE = ROOT / "assets" / "voice" / "ru"
DIRECTION = ROOT / "data" / "story" / "voice_direction.json"
SR = 16000
WEIGHTS = {"f0": 0.45, "db": 0.35, "dur": 0.20}
WORD_CH = re.compile(r"[0-9A-Za-zА-Яа-яЁё́-]")


def norm(w: str) -> str:
    return w.lower().replace("ё", "е").replace("́", "").strip("-")


def load_audio(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def words_from_alignment(al: dict) -> list[dict]:
    """Слова (буквы подряд) с началом и концом; теги в [скобках] пропускаются."""
    chars = al.get("characters", [])
    st = al.get("character_start_times_seconds", [])
    en = al.get("character_end_times_seconds", [])
    out, cur, in_tag = [], None, False
    for i, ch in enumerate(chars):
        if ch == "[":
            in_tag = True
        if in_tag:
            if ch == "]":
                in_tag = False
            if cur:
                out.append(cur)
                cur = None
            continue
        if WORD_CH.match(ch) and not (ch == "-" and cur is None):
            if cur is None:
                cur = {"word": "", "t0": float(st[i]), "t1": float(en[i]), "letters": 0}
            cur["word"] += ch
            cur["t1"] = float(en[i])
            if ch.isalpha():
                cur["letters"] += 1
        elif cur:
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    return [w for w in out if w["letters"] > 0]


def measure(audio: np.ndarray, words: list[dict]) -> list[dict]:
    import parselmouth
    snd = parselmouth.Sound(audio.astype(np.float64), sampling_frequency=SR)
    pitch = snd.to_pitch_ac(time_step=0.01, pitch_floor=65.0, pitch_ceiling=600.0)
    f0 = pitch.selected_array["frequency"]
    f0_t = pitch.xs()
    inten = snd.to_intensity(minimum_pitch=75.0, time_step=0.01)
    db = inten.values[0]
    db_t = inten.xs()
    voiced = f0[f0 > 0]
    f0_med = float(np.median(voiced)) if voiced.size else 150.0
    for w in words:
        sel = (f0_t >= w["t0"]) & (f0_t <= w["t1"]) & (f0 > 0)
        if sel.sum() >= 2:
            st = 12.0 * np.log2(f0[sel] / f0_med)
            w["f0_max"] = float(np.percentile(st, 90))
            w["f0_rng"] = float(np.percentile(st, 90) - np.percentile(st, 10))
        else:
            w["f0_max"], w["f0_rng"] = float("nan"), float("nan")
        sd = (db_t >= w["t0"]) & (db_t <= w["t1"])
        w["db_max"] = float(np.max(db[sd])) if sd.any() else float("nan")
        w["dur_per_letter"] = (w["t1"] - w["t0"]) / max(1, w["letters"])
    return words


def _z(vals: list[float]) -> list[float]:
    a = np.array(vals, dtype=float)
    ok = ~np.isnan(a)
    if ok.sum() < 2:
        return [0.0] * len(vals)
    m, s = float(np.mean(a[ok])), float(np.std(a[ok])) or 1.0
    return [float((v - m) / s) if not np.isnan(v) else 0.0 for v in a]


def score(words: list[dict]) -> list[dict]:
    zf = _z([w["f0_max"] for w in words])
    zd = _z([w["db_max"] for w in words])
    zl = _z([w["dur_per_letter"] for w in words])
    for w, a, b, c in zip(words, zf, zd, zl):
        w["z_f0"], w["z_db"], w["z_dur"] = round(a, 2), round(b, 2), round(c, 2)
        w["prom"] = round(WEIGHTS["f0"] * a + WEIGHTS["db"] * b + WEIGHTS["dur"] * c, 3)
    order = sorted(range(len(words)), key=lambda i: -words[i]["prom"])
    for r, i in enumerate(order):
        words[i]["rank"] = r + 1
    return words


def analyse(mp3: Path, align: dict) -> list[dict]:
    words = words_from_alignment(align)
    if not words:
        return []
    return score(measure(load_audio(mp3), words))


def target_hits(words: list[dict], targets: list[str]) -> list[dict]:
    """Для каждой цели (одно или несколько слов подряд) — лучшее место по выделенности среди её слов."""
    seq = [norm(w["word"]) for w in words]
    out = []
    for t in targets:
        tw = [norm(x) for x in re.findall(r"[A-Za-zА-Яа-яЁё́-]+", t)]
        best = None
        for i in range(len(seq) - len(tw) + 1):
            if all(seq[i + j] == tw[j] or (len(tw[j]) > 3 and seq[i + j].startswith(tw[j][:-1])) for j in range(len(tw))):
                cand = min(words[i + j]["rank"] for j in range(len(tw)))
                prom = max(words[i + j]["prom"] for j in range(len(tw)))
                if best is None or cand < best["rank"]:
                    best = {"target": t, "rank": cand, "prom": prom, "at": i}
        out.append(best or {"target": t, "rank": None, "prom": None, "at": None})
    return out


def line_report(lid: str, words: list[dict], targets: list[str]) -> dict:
    proms = sorted((w["prom"] for w in words), reverse=True)
    gap = proms[0] - proms[1] if len(proms) > 1 else 0.0
    top = max(words, key=lambda w: w["prom"]) if words else None
    return {"id": lid, "words": len(words), "top": top["word"] if top else "", "top_prom": top["prom"] if top else 0.0,
            "top_gap": round(gap, 3), "targets": target_hits(words, targets) if targets else []}


def _manifest() -> dict:
    return json.loads((VOICE / "manifest.json").read_text(encoding="utf-8"))["lines"]


def _direction() -> dict:
    d = json.loads(DIRECTION.read_text(encoding="utf-8")) if DIRECTION.is_file() else {}
    return {k: v for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)}


def analyse_line(lid: str, man: dict) -> tuple[list[dict], str]:
    e = man[lid]
    src = str(e.get("source", ""))
    mp3 = VOICE / src if src else VOICE / str(e["file"])
    al_rel = str(e.get("alignment", ""))
    al = json.loads((VOICE / al_rel).read_text(encoding="utf-8"))["alignment"] if al_rel else {}
    return analyse(mp3, al), str(e.get("voice_text", ""))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--probe")
    ap.add_argument("--calibrate")
    ap.add_argument("--json")
    a = ap.parse_args()
    man, dirs = _manifest(), _direction()
    out = []
    if a.probe:
        for js in sorted(Path(a.probe).glob("*.json")):
            d = json.loads(js.read_text(encoding="utf-8"))
            al = d.get("alignment")
            if isinstance(al, str):
                import ast
                al = ast.literal_eval(al)
            mp3 = js.with_suffix(".mp3")
            if not al or not mp3.is_file():
                continue
            words = analyse(mp3, al)
            line = str(d.get("line", js.stem.split("__")[0]))
            rep = line_report(js.stem, words, (dirs.get(line) or {}).get("emph", []))
            rep["words_detail"] = words
            out.append(rep)
            _print(rep, words)
    ids = list(a.ids)
    marks = {}
    if a.calibrate:
        marks = json.loads(Path(a.calibrate).read_text(encoding="utf-8"))["marks"]
        ids = [k for k in marks if k in man]
    for lid in ids:
        try:
            words, _vt = analyse_line(lid, man)
        except Exception as ex:   # noqa: BLE001 — a broken file is reported, the rest goes on
            print(f"{lid}: {ex}", file=sys.stderr)
            continue
        rep = line_report(lid, words, (dirs.get(lid) or {}).get("emph", []))
        rep["mark"] = (marks.get(lid) or {}).get("mark")
        rep["note"] = (marks.get(lid) or {}).get("note", "")
        rep["words_detail"] = words
        out.append(rep)
        if not a.calibrate:
            _print(rep, words)
    if a.calibrate:
        _calibration(out)
    if a.json:
        Path(a.json).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


def _print(rep: dict, words: list[dict]) -> None:
    tg = ", ".join(f"{t['target']}→{t['rank']}" for t in rep["targets"])
    print(f"{rep['id']}: самое выделенное «{rep['top']}» ({rep['top_prom']:+.2f}, отрыв {rep['top_gap']:.2f})"
          + (f"; цели: {tg}" if tg else ""))
    print("   " + " ".join(f"{w['word']}[{w['prom']:+.1f}]" for w in words))


def _calibration(out: list[dict]) -> None:
    with_t = [r for r in out if r["targets"] and r.get("mark") in ("ok", "redo")]
    def best_rank(r):
        ranks = [t["rank"] for t in r["targets"] if t["rank"]]
        return min(ranks) if ranks else 99
    def worst_rank(r):
        ranks = [t["rank"] for t in r["targets"] if t["rank"]]
        return max(ranks) if ranks else 99
    for mark in ("ok", "redo"):
        rs = [r for r in with_t if r["mark"] == mark]
        if not rs:
            continue
        br = [best_rank(r) for r in rs]
        wr = [worst_rank(r) for r in rs]
        print(f"{mark}: строк с целями {len(rs)}; лучшая цель на 1-м месте: {sum(1 for x in br if x == 1)}, "
              f"в первых двух: {sum(1 for x in br if x <= 2)}; все цели в первых двух: {sum(1 for x in wr if x <= 2)}")
    for r in sorted(with_t, key=lambda r: (r["mark"], best_rank(r))):
        print(f"  {r['mark']:4} {r['id']}: " + ", ".join(f"{t['target']}→{t['rank']}" for t in r["targets"])
              + f" | топ «{r['top']}» | {r.get('note', '')[:60]}")


if __name__ == "__main__":
    sys.exit(main())
