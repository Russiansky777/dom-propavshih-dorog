#!/usr/bin/env python3
"""Губы по звукам (Директор 12.11, 21:40: «нужны губы как минимум»): таблица форм рта для каждой записи голоса.

У каждой записи есть разметка по буквам от синтеза (assets/voice/<язык>/<alignment из манифеста>: буква, начало, конец —
https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps). Из неё — последовательность форм рта:
сомкнут на «м, б, п», почти сомкнут на «в, ф», округлён на «о, у», широк на «а, э, и», приоткрыт на остальных согласных,
сомкнут в паузах. Игра ведёт по ней ширину и высоту нарисованного рта (game/scripts/actors/jaw_modifier.gd); сами формы
(ширина, высота) — данные game/data/lips/shapes.json, их можно править без пересчёта.

Время разметки — по исходной записи (src/*.mp3); в игре звучит файл с обрезанной тишиной в начале и в конце
(pipeline/voice/eleven_voice.py, silenceremove), поэтому для каждой записи находится сдвиг начала: огибающие исходника и
игрового файла совмещаются (ffmpeg → 8 кГц моно, шаг 5 мс). Нужны ffmpeg и numpy.

  python3 tools/bake_lips.py                 пересчитать game/data/lips/{ru,en}.json
  python3 tools/bake_lips.py --check         таблицы соответствуют манифестам (каждая актуальная запись с разметкой есть,
                                             её подпись текста та же, формы по буквам те же); сдвиг начала пересчитывается
                                             у каждой 40-й записи (расхождение > 0,03 с — ошибка); самопроверка разбора
  python3 tools/bake_lips.py --reseq         пересчитать только формы по буквам от уже найденных сдвигов (изменились
                                             правила разбора букв; ffmpeg не нужен) — для записей с той же подписью
  python3 tools/bake_lips.py --self-check    только самопроверка разбора букв (без ffmpeg)
Код 0 — расхождений нет.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOICE = ROOT / "assets" / "voice"
OUT = ROOT / "game" / "data" / "lips"
LANGS = ["ru", "en"]
CLASSES = ["sil", "mbp", "fv", "a", "e", "i", "o", "O", "u", "sh", "c"]
GAP_S = 0.12          # пауза (пробел, знак) длиннее — рот сомкнут; короче — форма соседней буквы держится
SAMPLE_EVERY = 40     # --check: сдвиг начала пересчитывается у каждой такой записи
LAG_TOL_S = 0.03
STRESS = "́"

RU = {}
for _l in "ая":
    RU[_l] = "a"
for _l in "эе":
    RU[_l] = "e"
for _l in "иы":
    RU[_l] = "i"
for _l in "оё":
    RU[_l] = "o"
for _l in "ую":
    RU[_l] = "u"
for _l in "мбп":
    RU[_l] = "mbp"
for _l in "вф":
    RU[_l] = "fv"
for _l in "шжчщ":
    RU[_l] = "sh"
for _l in "тднлрсзцкгхй":
    RU[_l] = "c"
RU_VOWELS = set("аяэеиыоёую")

EN = {}
for _l in "a":
    EN[_l] = "a"
for _l in "e":
    EN[_l] = "e"
for _l in "iy":
    EN[_l] = "i"
for _l in "o":
    EN[_l] = "o"
for _l in "uw":
    EN[_l] = "u"
for _l in "mbp":
    EN[_l] = "mbp"
for _l in "fv":
    EN[_l] = "fv"
for _l in "j":
    EN[_l] = "sh"
for _l in "tdnlrszckghxq":
    EN[_l] = "c"
EN_VOWELS = set("aeiouy")


def shapes_of(chars: list[str], starts: list[float], ends: list[float], lang: str) -> list[tuple[float, str]]:
    """Формы рта по буквам: [(время начала по исходной записи, класс)], соседние одинаковые слиты; в конце — «sil»."""
    table = RU if lang == "ru" else EN
    vowels = RU_VOWELS if lang == "ru" else EN_VOWELS
    low = [c.lower() for c in chars]
    n = len(low)
    # слова (для ударного «о»: единственная гласная слова; «ё»; знак ударения после буквы)
    word_vowels = [0] * n
    i = 0
    while i < n:
        if low[i] in table or low[i] in "ьъ" or low[i] == STRESS:
            j = i
            cnt = 0
            while j < n and (low[j] in table or low[j] in "ьъ" or low[j] == STRESS):
                cnt += 1 if low[j] in vowels else 0
                j += 1
            for k in range(i, j):
                word_vowels[k] = cnt
            i = j
        else:
            i += 1
    out: list[tuple[float, str]] = []
    in_tag = False
    for i, c in enumerate(low):
        cls = None
        if c == "[":
            in_tag = True
        if in_tag:
            cls = "sil"   # тег подачи («[surprised]») не произносится
            if c == "]":
                in_tag = False
        elif c in table:
            cls = table[c]
            if cls == "o" and lang == "ru":
                # безударное «о» звучит ближе к «а» и губы почти не округляет; ударное — округляет
                if c == "ё" or word_vowels[i] == 1 or (i + 1 < n and low[i + 1] == STRESS):
                    cls = "O"
        elif c in "ьъ" or c == STRESS:
            cls = None
        else:
            # пробел, знак: пауза — рот сомкнут; короткий промежуток — форма соседней буквы держится
            cls = "sil" if (ends[i] - starts[i]) >= GAP_S else None
        if cls is None:
            continue
        if out and out[-1][1] == cls:
            continue
        out.append((float(starts[i]), cls))
    end = float(ends[-1]) if ends else 0.0
    if not out or out[-1][1] != "sil":
        out.append((end, "sil"))
    return out


def envelope(path: Path):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    a = np.abs(np.frombuffer(raw, dtype=np.int16).astype(np.float32))
    k = len(a) // 40
    return a[:k * 40].reshape(k, 40).mean(axis=1)   # шаг 5 мс


def lead_lag(src: Path, game: Path) -> float:
    """На сколько секунд начало игрового файла позже начала исходника (обрезанная тишина в начале)."""
    import numpy as np
    a = envelope(src)
    b = envelope(game)
    b = np.log1p(b)
    a = np.log1p(a)
    best = (-1.0, 0)
    n = min(len(b), 600)   # первые 3 секунды игрового файла
    if n < 20:
        return 0.0
    bb = b[:n] - b[:n].mean()
    nb = float(np.linalg.norm(bb)) or 1.0
    for lag in range(0, 161):   # до 0,8 с
        seg = a[lag:lag + n]
        if len(seg) < n:
            break
        ss = seg - seg.mean()
        sc = float(np.dot(ss, bb)) / (nb * (float(np.linalg.norm(ss)) or 1.0))
        if sc > best[0]:
            best = (sc, lag)
    return best[1] * 0.005


def lines_of(lang: str) -> dict:
    man = json.loads((VOICE / lang / "manifest.json").read_text(encoding="utf-8"))
    out = {}
    for lid, e in man.get("lines", {}).items():
        if "stale" in e or not e.get("alignment") or not e.get("file") or e.get("speaker") == "narrator":
            continue
        if not (VOICE / lang / e["alignment"]).exists() or not (VOICE / lang / e["file"]).exists():
            continue
        out[lid] = e
    return out


def seq_of(e: dict, lang: str, lag: float) -> list[int]:
    al = json.loads((VOICE / lang / e["alignment"]).read_text(encoding="utf-8"))["alignment"]
    sh = shapes_of(al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"], lang)
    seq: list[int] = []
    for t, cls in sh:
        cs = max(0, int(round((t - lag) * 100.0)))
        if seq and seq[-2] == cs:
            seq[-1] = CLASSES.index(cls)   # два события в одной сотой — остаётся последнее
            continue
        if seq and seq[-1] == CLASSES.index(cls):
            continue
        seq += [cs, CLASSES.index(cls)]
    if not seq or seq[0] > 0:
        seq = [0, 0] + seq
    return seq


def sha8(e: dict) -> str:
    return str(e.get("voice_sha1") or e.get("text_sha1") or "")[:8]


def bake(lang: str) -> dict:
    lines = {}
    src_lines = lines_of(lang)
    for n, (lid, e) in enumerate(sorted(src_lines.items())):
        lag = lead_lag(VOICE / lang / e["source"], VOICE / lang / e["file"]) if e.get("source") and (VOICE / lang / e["source"]).exists() else 0.0
        lag = round(lag, 3)   # формы считаются от записанного сдвига — проверка пересчитывает их от него же
        lines[lid] = {"sha": sha8(e), "lag": lag, "seq": seq_of(e, lang, lag)}
        if n % 200 == 0:
            print(f"  {lang}: {n}/{len(src_lines)}", flush=True)
    return {"_comment": "Формы рта по буквам для каждой записи голоса (tools/bake_lips.py; Директор 12.11 «нужны губы как минимум»). "
                        "seq — пары [сотые доли секунды от начала игрового файла, номер класса из classes]; lag — на сколько "
                        "секунд игровой файл начинается позже исходной записи (обрезанная тишина); sha — подпись текста записи. "
                        "Сами формы (ширина, высота) — shapes.json. Не править руками: пересчёт — python3 tools/bake_lips.py.",
            "language": lang, "classes": CLASSES, "lines": lines}


def dump(doc: dict, path: Path) -> None:
    head = {k: v for k, v in doc.items() if k != "lines"}
    parts = [json.dumps(head, ensure_ascii=False, indent=1)[:-2] + ',\n "lines": {']
    rows = [f'  {json.dumps(lid, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False, separators=(",", ":"))}' for lid, v in doc["lines"].items()]
    parts.append(",\n".join(rows))
    parts.append(" }\n}\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(parts), encoding="utf-8")


def self_check() -> list[str]:
    bad: list[str] = []

    def classes(text: str, lang: str = "ru", dur: float = 0.1, long_at: tuple = ()) -> list[str]:
        st, en, t = [], [], 0.0
        for i, _c in enumerate(text):
            d = 0.3 if i in long_at else dur
            st.append(t)
            en.append(t + d)
            t += d
        return [c for _t, c in shapes_of(list(text), st, en, lang)]

    got = classes("мама")
    if got != ["mbp", "a", "mbp", "a", "sil"]:
        bad.append(f"«мама» → {got}")
    got = classes("[sad] Угу")
    if got[0] != "sil" or "u" not in got or got.count("sil") != 2:
        bad.append(f"тег подачи и «Угу» → {got}")
    got = classes("вот молоко́")
    if got[:3] != ["fv", "O", "c"] or got.count("O") != 2 or got.count("o") != 2:
        bad.append(f"ударное и безударное «о» («вот молоко́») → {got}")
    got = classes("да, да", long_at=(2,))
    if got != ["c", "a", "sil", "c", "a", "sil"]:
        bad.append(f"пауза на запятой 0,3 с → {got}")
    got = classes("да, да")
    if got != ["c", "a", "c", "a", "sil"]:
        bad.append(f"короткая запятая не смыкает рот → {got}")
    got = classes("my wife", "en")
    if got[0] != "mbp" or "fv" not in got or "u" not in got:
        bad.append(f"английский «my wife» → {got}")
    return bad


def check() -> int:
    errors: list[str] = []
    for m in self_check():
        errors.append(f"самопроверка разбора: {m}")
    have_audio = True
    try:
        import numpy  # noqa: F401
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
    except Exception:
        have_audio = False
    lag_checked = 0
    for lang in LANGS:
        path = OUT / f"{lang}.json"
        if not path.exists():
            errors.append(f"{lang}: нет {path.relative_to(ROOT)} — python3 tools/bake_lips.py")
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        if doc.get("classes") != CLASSES:
            errors.append(f"{lang}: классы форм в таблице {doc.get('classes')} не те, что в tools/bake_lips.py")
            continue
        src_lines = lines_of(lang)
        baked = doc.get("lines", {})
        for lid in sorted(set(baked) - set(src_lines)):
            errors.append(f"{lang}/{lid}: в таблице есть, а актуальной записи с разметкой нет — пересчитать")
        for n, (lid, e) in enumerate(sorted(src_lines.items())):
            b = baked.get(lid)
            if b is None:
                errors.append(f"{lang}/{lid}: записи нет в таблице губ — python3 tools/bake_lips.py")
                continue
            if b.get("sha") != sha8(e):
                errors.append(f"{lang}/{lid}: запись голоса заменена (подпись {sha8(e)}, в таблице {b.get('sha')}) — пересчитать")
                continue
            if seq_of(e, lang, float(b.get("lag", 0.0))) != b.get("seq"):
                errors.append(f"{lang}/{lid}: формы по буквам не совпадают с разметкой — пересчитать")
            if have_audio and n % SAMPLE_EVERY == 0 and e.get("source") and (VOICE / lang / e["source"]).exists():
                lag = lead_lag(VOICE / lang / e["source"], VOICE / lang / e["file"])
                lag_checked += 1
                if abs(lag - float(b.get("lag", 0.0))) > LAG_TOL_S:
                    errors.append(f"{lang}/{lid}: сдвиг начала {lag:.3f} с, в таблице {float(b.get('lag', 0.0)):.3f} — пересчитать")
        print(f"[lips] {lang}: записей с разметкой {len(src_lines)}, в таблице {len(baked)}")
    if not have_audio:
        print("[lips] SKIP: сдвиг начала не пересчитывался — нет ffmpeg или numpy")
    for e in errors[:40]:
        print("FAIL  губы по звукам: " + e)
    print(f"[lips] bake_lips --check: {'OK' if not errors else 'FAIL'} ({len(errors)} ошибок; сдвиг начала пересчитан у {lag_checked} записей; самопроверка разбора {'OK' if not self_check() else 'FAIL'})")
    return 1 if errors else 0


def main() -> int:
    if "--self-check" in sys.argv:
        bad = self_check()
        for m in bad:
            print("FAIL  губы по звукам, самопроверка разбора: " + m)
        print(f"[lips] самопроверка разбора: {'OK' if not bad else 'FAIL'}")
        return 1 if bad else 0
    if "--check" in sys.argv:
        return check()
    if "--reseq" in sys.argv:
        for lang in LANGS:
            path = OUT / f"{lang}.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            src_lines = lines_of(lang)
            n = 0
            for lid, b in doc["lines"].items():
                e = src_lines.get(lid)
                if e is not None and b.get("sha") == sha8(e):
                    seq = seq_of(e, lang, float(b.get("lag", 0.0)))
                    n += 1 if seq != b.get("seq") else 0
                    b["seq"] = seq
            doc["classes"] = CLASSES
            dump(doc, path)
            print(f"[lips] {lang}: формы пересчитаны, изменилось {n} записей")
        return 0
    for lang in LANGS:
        doc = bake(lang)
        dump(doc, OUT / f"{lang}.json")
        lags = sorted(v["lag"] for v in doc["lines"].values())
        print(f"[lips] {lang}: {len(doc['lines'])} записей → {(OUT / (lang + '.json')).relative_to(ROOT)}; сдвиг начала: "
              f"медиана {lags[len(lags) // 2]:.3f} с, наибольший {lags[-1]:.3f} с")
    return 0


if __name__ == "__main__":
    sys.exit(main())
