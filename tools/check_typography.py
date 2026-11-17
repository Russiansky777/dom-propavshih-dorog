#!/usr/bin/env python3
"""Typography of every line the player reads, Russian and English (the review before release, Director 17.11:
«полный ультимативный ревью перед релизом»; the review of 15.11 ran the same checks by hand — now a tool).

The corpus is data/l10n/en.json `rows`: every player-facing string of the game (texts, lines, items, places, journal
facts, quests, names) with its Russian source and English translation (tools/build_story_en.py keeps it complete).

Russian (`ru`): straight quotes " (the game uses «»), three dots ... (…), a hyphen between spaces - (an em dash —),
two spaces, a space before , . ! ? : ; a Latin letter inside a Cyrillic word (a look-alike: «о» typed as «o»),
unbalanced «», the name «Дарья» (CLAUDE.md: not used), placeholders (TODO, XXX, ???, заглушка, lorem), leading or
trailing spaces.
English (`en`): Cyrillic letters (untranslated), three dots ..., two spaces, a space before punctuation, placeholders,
leading or trailing spaces, unbalanced quotes.

  python3 tools/check_typography.py            # report, exit 1 on any finding
  python3 tools/check_typography.py --self-check
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EN = ROOT / "data" / "l10n" / "en.json"

CYR = "А-Яа-яЁё"
LAT_IN_CYR = re.compile(rf"[{CYR}][A-Za-z]|[A-Za-z][{CYR}]")
PLACEHOLDER = re.compile(r"TODO|XXX|\?\?\?|заглушк|lorem|FIXME", re.I)
SPACE_BEFORE = re.compile(r" [,.!?:;](?!\.\.)")
# markup the game itself reads inside texts: {item} placeholders, [b] tags — a word for the checks, not typography
MARKUP = re.compile(r"\{[a-z_]+\}|\[/?[a-z]+\]")
# Deliberate, each with its reason (the review of 17.11 looked at every one):
ALLOW = {
    # Dunya's painted labels on the stands are Cyrillic in the art itself («ЗМ» — mill mirror, «ЗГ» — gallery);
    # the English text names them as drawn and says what they mean
    ("text:H2.stand_zm.look", "en"), ("text:H3.mirror_home.look", "en"), ("text:item.mirror_mill.wrong", "en"),
    ("text:item.mirror_mill.wrong#line", "en"), ("scene:M09b/goal", "en"), ("scene:M10/hints[1]", "en"),
    # the language menu names each language in itself, in both menus
    ("text:ui.lang_voice_ru", "en"), ("text:ui.lang_subs_ru", "en"), ("text:ui.lang_subs_none", "en"),
    ("text:ui.lang_en_warning", "en"),
    # the note under the school door (M07) is read over three boxes: «» open in the first and close in the last
    ("scene:M07/lines[1].text", "ru"), ("scene:M07/lines[3].text", "ru"),
    ("scene:M07/lines[1].text", "en"), ("scene:M07/lines[3].text", "en"),
}
# the head of a list the game appends to («Сегодня ещё не сделано: » + the things) ends with its space on purpose
HEAD_KEY = re.compile(r"/head$")


def ru_problems(s: str, key: str = "") -> list:
    out = []
    t = MARKUP.sub("Икс", s)
    if '"' in t:
        out.append("прямая кавычка \" (нужны «»)")
    if "..." in t:
        out.append("три точки ... (нужно …)")
    if re.search(r"(^| )-( |$)", t):
        out.append("дефис между пробелами (нужно тире —)")
    if "  " in t:
        out.append("два пробела подряд")
    if SPACE_BEFORE.search(t):
        out.append("пробел перед знаком препинания")
    if LAT_IN_CYR.search(t):
        out.append("латинская буква в русском слове: %s" % LAT_IN_CYR.search(t).group(0))
    if t.count("«") != t.count("»"):
        out.append("кавычки «» не парные")
    if re.search(r"Дарь[яеиюё]", t):
        out.append("имя «Дарья» (не используется)")
    if PLACEHOLDER.search(t):
        out.append("заглушка: %s" % PLACEHOLDER.search(t).group(0))
    if s != s.strip() and not (HEAD_KEY.search(key) and s == s.lstrip()):
        out.append("пробел в начале или в конце")
    return out


def en_problems(s: str, key: str = "") -> list:
    out = []
    t = MARKUP.sub("Ex", s)
    if re.search(f"[{CYR}]", t):
        out.append("Cyrillic in English: %s" % re.search(rf"\S*[{CYR}]\S*", t).group(0))
    if "..." in t:
        out.append("three dots ... (the game uses …)")
    if "  " in t:
        out.append("two spaces")
    if SPACE_BEFORE.search(t):
        out.append("a space before punctuation")
    if PLACEHOLDER.search(t):
        out.append("placeholder: %s" % PLACEHOLDER.search(t).group(0))
    if s != s.strip() and not (HEAD_KEY.search(key) and s == s.lstrip()):
        out.append("leading or trailing space")
    if t.count("“") != t.count("”"):
        out.append("unbalanced “”")
    if t.count('"') % 2 == 1:
        out.append('an odd number of "')
    return out


def check(rows: dict) -> list:
    found = []
    for key, row in rows.items():
        if not isinstance(row, dict):
            continue
        ru = row.get("ru")
        en = row.get("en")
        if isinstance(ru, str) and ru.strip() and (key, "ru") not in ALLOW:
            for p in ru_problems(ru, key):
                found.append((key, "ru", p, ru))
        if isinstance(en, str) and en.strip() and (key, "en") not in ALLOW:
            for p in en_problems(en, key):
                found.append((key, "en", p, en))
    return found


def self_check() -> list:
    bad = []
    cases_ru = {
        'Он сказал "да"': "прямая", "Ну...": "три точки", "Да - нет": "дефис", "Да  нет": "два пробела",
        "Да , нет": "пробел перед", "мoст": "латинская", "«Да": "кавычки", "Дарья пришла": "Дарья",
        "TODO текст": "заглушка", " Да": "пробел в начале",
    }
    for s, want in cases_ru.items():
        if not any(want in p for p in ru_problems(s)):
            bad.append("самопроверка ru: «%s» — не поймано (%s)" % (s, want))
    for s in ["«Да», — сказала она… Ну и ну.", "Выбрано: {item}. Щёлкнуть по месту, где применить.", "Агата — 18."]:
        if ru_problems(s):
            bad.append("самопроверка ru: «%s» — ложная находка %s" % (s, ru_problems(s)))
    for s, want in {"Mama сказала": "Cyrillic", "Well...": "three dots", "Yes  no": "two spaces", "Yes , no": "a space",
                    "She said “yes": "unbalanced"}.items():
        if not any(want in p for p in en_problems(s)):
            bad.append("self-check en: «%s» — not caught (%s)" % (s, want))
    for s in ["Mama's ribbon. Nina weaves it in — as she used to.", "“Yes,” she said…"]:
        if en_problems(s):
            bad.append("self-check en: «%s» — false finding %s" % (s, en_problems(s)))
    return bad


def main() -> int:
    if "--self-check" in sys.argv:
        bad = self_check()
        for b in bad:
            print("[typography] " + b)
        print("[typography] self-check: %s" % ("OK" if not bad else "FAIL"))
        return 1 if bad else 0
    rows = json.loads(EN.read_text(encoding="utf-8"))["rows"]
    found = check(rows)
    for key, lang, p, s in found:
        print("[typography] %s %s: %s — «%s»" % (key, lang, p, s[:140]))
    n_ru = sum(1 for r in rows.values() if isinstance(r, dict) and isinstance(r.get("ru"), str) and r["ru"].strip())
    n_en = sum(1 for r in rows.values() if isinstance(r, dict) and isinstance(r.get("en"), str) and r["en"].strip())
    print("[typography] check_typography: %d строк ru, %d en — находок %d" % (n_ru, n_en, len(found)))
    bad = self_check()
    for b in bad:
        print("[typography] " + b)
    return 1 if found or bad else 0


if __name__ == "__main__":
    sys.exit(main())
