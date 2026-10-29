"""Режиссура строки в тексте запроса к TTS (партия J, 29.10): data/story/voice_direction.json.

Почему: пометки «акцент на …», «пауза», «подача» с 25.10 лежали в поле `direction` сцен только как описание, а в
синтезатор уходил голый текст — 35 из 52 правок Директора до голоса не дошли (Docs/PLAN_J.md, часть C). Здесь
режиссура превращается в то, что модель читает (ElevenLabs, «Prompting Eleven v4»:
https://elevenlabs.io/docs/best-practices/prompting — «Capitalization increases emphasis», «Ellipses (…) add pauses
and weight», теги подачи в [скобках]):

  "<id реплики>": {
    "emph":        ["слово", "два слова"],  — капсом в запросе (ударное по смыслу слово; ищется целым словом, без
                                             учёта регистра и ё/е; первое вхождение);
    "pause_after": ["слово"],               — «…» сразу после слова (тире или запятая за ним заменяются);
    "tags":        ["warmly"],              — теги подачи перед фразой (из pipeline/voice/tags.json);
    "note":        "слова Директора"        — откуда правка (стр. карты), в запрос не идёт
  }

id — как в манифесте озвучки: реплика сцены «M01_8» / «M23a_4_then0», реплика из текстов «tikhon:H1.tikhon.door»,
закадровая фраза — ключ «H1.scarf.use». Субтитры не меняются: только текст запроса. Один модуль применяют конвейер
(eleven_voice.api_text) и проверка (tools/validate_voice.py) — sha1 запроса у них совпадает, и `only_changed`
перезаписывает ровно строки с новой режиссурой.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

PATH = Path(__file__).resolve().parents[2] / "data" / "story" / "voice_direction.json"
_cache: dict | None = None
_WORD_CH = "А-Яа-яЁёA-Za-z0-9́"


def table() -> dict:
    global _cache
    if _cache is None:
        _cache = json.loads(PATH.read_text(encoding="utf-8")) if PATH.exists() else {}
        _cache = {k: v for k, v in _cache.items() if not k.startswith("_")}
    return _cache


def reset() -> None:
    global _cache
    _cache = None


def for_line(line_id: str) -> dict:
    return table().get(line_id, {}) or {}


def _norm(s: str) -> str:
    return s.replace("ё", "е").replace("Ё", "Е").replace("́", "").lower()


def _find(text: str, phrase: str) -> tuple[int, int] | None:
    """Первое вхождение `phrase` целым словом (регистр, ё/е и знак ударения не важны) → (начало, конец) в text."""
    want = _norm(phrase)
    if not want:
        return None
    # Позиции символов text без знака ударения, чтобы срезы совпадали с исходником.
    idx = [i for i, ch in enumerate(text) if ch != "́"]
    plain = "".join(text[i] for i in idx)
    p = _norm(plain)
    start = 0
    while True:
        j = p.find(want, start)
        if j < 0:
            return None
        before = p[j - 1] if j > 0 else " "
        after = p[j + len(want)] if j + len(want) < len(p) else " "
        if not re.match(f"[{_WORD_CH}]", before) and not re.match(f"[{_WORD_CH}]", after):
            a = idx[j]
            b = idx[j + len(want) - 1] + 1
            while b < len(text) and text[b] == "́":
                b += 1
            return a, b
        start = j + 1


def apply(text: str, line_id: str) -> str:
    """Текст запроса с режиссурой строки (капс, «…», теги). Без записи в таблице — текст как есть."""
    d = for_line(line_id)
    if not d:
        return text
    out = text
    for w in d.get("emph", []):
        r = _find(out, str(w))
        if r:
            a, b = r
            out = out[:a] + out[a:b].upper() + out[b:]
    for w in d.get("pause_after", []):
        r = _find(out, str(w))
        if r:
            _, b = r
            rest = out[b:]
            if rest[:1] in "?!":
                # «Цел затвор? Где рычаг?» → «Цел затвор?… Где рычаг?» — знак остаётся, пауза после него
                out = out[:b] + rest[0] + "… " + rest[1:].lstrip()
                continue
            m = re.match(r"\s*[—,–-]?\s*", rest)
            tail = rest[m.end():] if m else rest
            if tail[:1] in ".…":
                out = out[:b] + "…" + tail.lstrip(".…")
            else:
                out = out[:b] + "… " + tail
    tags = [str(t) for t in d.get("tags", [])]
    if tags:
        out = "".join(f"[{t}] " for t in tags) + out
    return out


def words(t: str) -> list[str]:
    """Слова фразы для сверки: без тегов [..], IPA /../, знаков ударения и препинания; строчные, ё → е."""
    t = re.sub(r"\[\[([^|\]]+)\|[^\]]*\]\]", r"\1", t)
    t = re.sub(r"\[[^\]]*\]", " ", t)
    t = t.replace("\u0301", "").lower().replace("ё", "е")
    return re.findall(r"[a-zа-я0-9]+(?:-[a-zа-я0-9]+)*|/[^/\s]+/", t)


def problems(line_id: str, text: str, allowed_tags: set[str] | None = None) -> list[str]:
    """Что в записи таблицы не сходится с текстом реплики (слова не найдены, тег не из списка)."""
    d = for_line(line_id)
    out: list[str] = []
    ov = d.get("voice_text")
    if ov:
        # текст запроса — те же слова, что в субтитрах (IPA-запись слова считается за него, если стоит на его месте)
        a, b = words(text), words(str(ov))
        same = len(a) == len(b) and all(x == y or y.startswith("/") for x, y in zip(a, b))
        if not same:
            out.append(f"{line_id}: voice_text — другие слова, чем в субтитрах: «{str(ov)[:70]}» / «{text[:70]}»")
    for key in ("emph", "pause_after"):
        for w in d.get(key, []):
            if _find(text, str(w)) is None:
                out.append(f"{line_id}: {key} «{w}» нет в тексте «{text[:60]}»")
    if allowed_tags is not None:
        for t in d.get("tags", []):
            if str(t) not in allowed_tags:
                out.append(f"{line_id}: тег [{t}] не из pipeline/voice/tags.json")
    return out
