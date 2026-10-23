#!/usr/bin/env python3
"""Ударение в записанной речи — по выравниванию по символам (ElevenLabs /with-timestamps) и по звуку.

Ударная гласная в русском заметно длиннее и громче безударных. Для каждого слова с правилом произношения
(pipeline/voice/pronunciation_ru.json; ожидаемое ударение — поле stress) берутся интервалы его гласных из выравнивания
(знак U+0301 прибавляется к своей гласной; у IPA /…/ ударная — первая гласная после ˈ), и сравниваются:
  - по выравниванию: самая долгая гласная;
  - по звуку: длительность × громкость (RMS в интервале гласной, файл ответа API).
Совпали оба с ожидаемой — «ок»; иначе — «?» с цифрами (послушать или перезаписать).

  python3 tools/voice_stress_check.py --probe pron_probe     пробные фразы pipeline/voice/probe/<набор>/ (способы)
  python3 tools/voice_stress_check.py --manifest              записи игры с выравниванием (assets/voice/ru)
"""
from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "pipeline" / "voice" / "probe"
VOICE = ROOT / "assets" / "voice" / "ru"
CYR_V = set("аеёиоуыэюяАЕЁИОУЫЭЮЯ")
IPA_V = set("aɐeɛiɪɨoɔuʊəæyʏøœɵɯʉɘɜɞʌɤ")
ACUTE = "́"
SR = 16000

_ps = importlib.util.spec_from_file_location("pronounce", ROOT / "pipeline" / "voice" / "pronounce.py")
pronounce = importlib.util.module_from_spec(_ps)
_ps.loader.exec_module(pronounce)


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def vowel_spans(chars: list[str], st: list[float], en: list[float], a: int, b: int, ipa: bool) -> tuple[list[tuple[float, float]], int]:
    """Интервалы гласных в символах [a, b) и индекс ударной по разметке (IPA: после ˈ; иначе −1)."""
    spans: list[tuple[float, float]] = []
    marked = -1
    pending_mark = False
    vset = IPA_V if ipa else CYR_V
    for i in range(a, b):
        c = chars[i]
        if ipa and c == "ˈ":
            pending_mark = True
            continue
        if c == ACUTE and spans:
            s0, _ = spans[-1]
            spans[-1] = (s0, en[i])
            continue
        if c in vset:
            if ipa and spans and i > a and chars[i - 1] in vset:
                s0, _ = spans[-1]        # дифтонг/долгота в IPA — одна гласная
                spans[-1] = (s0, en[i])
                continue
            spans.append((st[i], en[i]))
            if pending_mark:
                marked = len(spans) - 1
                pending_mark = False
    return spans, marked


def find_word(text: str, word: str, ipa: str) -> tuple[int, int, bool] | None:
    """Позиция слова в тексте запроса: /ipa/ или словоформа (без учёта регистра и знака ударения)."""
    if ipa:
        k = text.find("/" + ipa + "/")
        if k >= 0:
            return k + 1, k + 1 + len(ipa), True
    plain = text.replace(ACUTE, "")
    # индекс в тексте с U+0301: идём по исходной строке, пропуская знаки
    m = re.search(r"(?<![А-Яа-яЁё])" + re.escape(word.lower()) + r"(?![А-Яа-яЁё])", plain.lower())
    if not m:
        return None
    pos = [i for i, ch in enumerate(text) if ch != ACUTE]
    a = pos[m.start()]
    b = pos[m.end() - 1] + 1
    while b < len(text) and text[b] == ACUTE:
        b += 1
    return a, b, False


def judge(x: np.ndarray | None, spans: list[tuple[float, float]]) -> tuple[int, int, list[float], list[float]]:
    durs = [max(0.0, e - s) for s, e in spans]
    by_align = int(np.argmax(durs)) if durs else -1
    score = []
    if x is not None and len(x):
        for s, e in spans:
            seg = x[int(s * SR):max(int(e * SR), int(s * SR) + 1)]
            rms = float(np.sqrt(np.mean(seg ** 2))) if len(seg) else 0.0
            score.append((e - s) * rms)
    by_sound = int(np.argmax(score)) if score else -1
    return by_align, by_sound, durs, score


def check_item(text: str, al: dict, audio: Path | None, word: str, stress: int, ipa: str = "") -> dict:
    chars, st, en = al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"]
    joined = "".join(chars)
    loc = find_word(joined, word, ipa)
    if loc is None:
        return {"word": word, "status": "нет слова в выравнивании"}
    a, b, is_ipa = loc
    spans, marked = vowel_spans(chars, st, en, a, b, is_ipa)
    want = marked if is_ipa and marked >= 0 else stress - 1
    x = decode(audio) if audio and audio.exists() else None
    ba, bs, durs, score = judge(x, spans)
    ok = ba == want and (bs == want or bs < 0)
    return {"word": word, "want": want + 1, "by_alignment": ba + 1, "by_sound": bs + 1,
            "vowel_ms": [round(d * 1000) for d in durs], "status": "ок" if ok else ("≈" if (ba == want or bs == want) else "?")}


def probe(set_name: str) -> int:
    rows = []
    for f in sorted((PROBE / set_name).glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        if not d.get("alignment"):
            rows.append((d["id"], d.get("variant", ""), "-", "нет выравнивания"))
            continue
        for ex in d.get("expect") or []:
            r = check_item(d["text"], d["alignment"], f.with_suffix(".mp3"), ex["word"], int(ex["stress"]),
                           ex.get("ipa", "") if d.get("variant") == "ipa" else "")
            rows.append((d["id"], d.get("variant", ""), ex["word"], r))
    by_var: dict[str, list[str]] = {}
    for rid, var, word, r in rows:
        if isinstance(r, str):
            print(f"  {rid:24} {r}")
            continue
        print(f"  {rid:24} {word:9} ждём {r.get('want')}  выравнивание {r.get('by_alignment')}  звук {r.get('by_sound')}  "
              f"гласные, мс {r.get('vowel_ms')}  {r['status']}")
        by_var.setdefault(var, []).append(r["status"])
    print()
    for var, st in sorted(by_var.items()):
        print(f"  {var:6}: ок {st.count('ок')}/{len(st)}, частично {st.count('≈')}, нет {st.count('?')}")
    return 0


def manifest() -> int:
    man = json.loads((VOICE / "manifest.json").read_text(encoding="utf-8")).get("lines", {})
    n = bad = 0
    for lid, e in sorted(man.items()):
        if "stale" in e or not e.get("alignment"):
            continue
        al_doc = json.loads((VOICE / e["alignment"]).read_text(encoding="utf-8"))
        hits = pronounce.matches(str(e.get("text", "")), lid)
        for word, rule in hits:
            fix = str(rule.get("fix", pronounce.rules().get("default_fix", "check")))
            r = check_item(al_doc["text"], al_doc["alignment"], VOICE / e["source"], word, int(rule["stress"]),
                           str(rule.get("ipa", "")) if fix == "ipa" else "")
            n += 1
            if r["status"] != "ок":
                bad += 1
                print(f"  {lid:40} {word:10} ждём {r.get('want')}  выравнивание {r.get('by_alignment')}  звук {r.get('by_sound')}  "
                      f"{r.get('vowel_ms')}  {r['status']}")
    print(f"[stress] слов с правилами в записях с выравниванием: {n}, под вопросом: {bad}")
    return 0


if __name__ == "__main__":
    if "--probe" in sys.argv:
        raise SystemExit(probe(sys.argv[sys.argv.index("--probe") + 1]))
    raise SystemExit(manifest())
