"""Произношение в тексте запроса к TTS (не в субтитрах): правила pipeline/voice/pronunciation_ru.json.

Правило — одна словоформа (совпадение целым словом, без учёта регистра первой буквы) с ударением `stress`
(номер гласной, с 1) и способом исправления `fix`:
  "acute" — знак ударения U+0301 после ударной гласной («замо́к»);
  "caps"  — ударная гласная заглавной («замОк»);
  "ipa"   — слово заменяется на /IPA/ (поле `ipa`; Eleven v4 «understands IPA symbols when they are wrapped in
            forward slashes» — https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices);
  "alias" — слово заменяется на `alias` (ё, иное написание);
  "check" — ничего не менять, только проверять ударение по выравниванию (tools/voice_stress_check.py).
Способ по умолчанию — поле `default_fix` файла (выбран пробой, см. `probe`). `lines` — только эти реплики/ключи
(id из манифеста, fnmatch-шаблоны), без поля — везде. Один и тот же модуль применяют конвейер
(eleven_voice.api_text) и проверка (tools/validate_voice.py), поэтому sha1 запроса у них совпадает; смена правил
меняет voice_sha1 только у затронутых реплик — перезаписываются только они.
"""
from __future__ import annotations

import fnmatch
import json
import re
from pathlib import Path

PATH = Path(__file__).resolve().parent / "pronunciation_ru.json"
VOWELS = "аеёиоуыэюяАЕЁИОУЫЭЮЯ"
ACUTE = "́"
_WORD = re.compile(r"[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)?")
_cache: dict | None = None


def rules() -> dict:
    global _cache
    if _cache is None:
        _cache = json.loads(PATH.read_text(encoding="utf-8")) if PATH.exists() else {"rules": []}
    return _cache


def reset() -> None:
    global _cache
    _cache = None


def vowel_positions(word: str) -> list[int]:
    return [i for i, ch in enumerate(word) if ch in VOWELS]


def _applies(rule: dict, line_id: str) -> bool:
    pats = rule.get("lines")
    if not pats:
        return True
    return any(fnmatch.fnmatchcase(line_id, str(p)) for p in pats)


def render(word: str, rule: dict, default_fix: str) -> str:
    """Словоформа в тексте запроса по правилу (регистр первой буквы сохраняется, где это возможно)."""
    fix = str(rule.get("fix", default_fix))
    if fix == "check":
        return word
    if fix == "alias":
        a = str(rule["alias"])
        return a[:1].upper() + a[1:] if word[:1].isupper() else a
    if fix == "ipa":
        return "/" + str(rule["ipa"]) + "/"
    vp = vowel_positions(word)
    k = int(rule["stress"]) - 1
    if not 0 <= k < len(vp):
        return word
    i = vp[k]
    if fix == "caps":
        return word[:i] + word[i].upper() + word[i + 1:]
    if fix == "acute":
        return word[:i + 1] + ACUTE + word[i + 1:]
    return word


def apply(text: str, line_id: str = "") -> str:
    """Текст для TTS: правила к словам (теги в [скобках] не трогаются — в них нет кириллицы)."""
    doc = rules()
    rl = [r for r in doc.get("rules", []) if _applies(r, line_id)]
    if not rl:
        return text
    by_word: dict[str, dict] = {}
    for r in rl:
        by_word.setdefault(str(r["word"]).lower(), r)
    default_fix = str(doc.get("default_fix", "check"))

    def sub(m: re.Match) -> str:
        w = m.group(0)
        r = by_word.get(w.lower())
        return render(w, r, default_fix) if r else w

    return _WORD.sub(sub, text)


def matches(text: str, line_id: str = "") -> list[tuple[str, dict]]:
    """Слова текста (субтитров), к которым относится правило: [(слово, правило)] — для проверки ударения."""
    doc = rules()
    rl = {str(r["word"]).lower(): r for r in doc.get("rules", []) if _applies(r, line_id)}
    return [(m.group(0), rl[m.group(0).lower()]) for m in _WORD.finditer(text) if m.group(0).lower() in rl]
