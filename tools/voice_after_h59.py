#!/usr/bin/env python3
"""Список строк к финальной перезаписи голоса после старорусской правки текстов (H59):
pipeline/requests/voice_after_H59.json.

Решение Директора 24.10: партия H → H59 (старорусская правка всех текстов) → одна финальная перезапись озвучки →
английский. До H59 голос не записывается: новые и изменённые реплики идут субтитрами (игра не играет запись с другим
sha1 текста), а строки с дефектом записи ждут того же прогона. Этот скрипт собирает список заново:
  - всё, что в игре должно звучать, но записано для другого текста / тегов или не записано вовсе
    (tools/voice_coverage.py: «устарела», «теги изменены», «нет записи»);
  - подача вне ± 4 LU от медианы персонажа (громкость исходника до нормализации; H5, tools/validate_voice.py);
  - строки, названные Директором и координатором (MANUAL: H5 — тихая Пелагея, H44 — ударение у Тамары, G57 — M09_1).
tools/validate_voice.py читает список: отклонения этих строк — предупреждения, не ошибки.

  python3 tools/voice_after_h59.py           пересобрать список
  python3 tools/voice_after_h59.py --check   код 1, если список устарел (строка к перезаписи не внесена)
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "pipeline" / "requests" / "voice_after_H59.json"
MANIFEST = ROOT / "assets" / "voice" / "ru" / "manifest.json"


def _mod(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


# Финальная запись после H59 (T7, прогоны pipeline-voice 40103286671 и 40103298522): названные строки, записанные
# не раньше этого времени, из списка уходят.
H59_RECORDED_FROM = "2026-10-24T14:30"

MANUAL = {
    "pelageya:R1.pelageya.after": "H5: «Без плиты лодку вернёт сюда же… я тут, у лодки» — шёпотом, тише остальных реплик "
                                  "Пелагеи; тег quietly снят (теперь firm) — записать её голосом и громкостью",
    "M02_8": "H5: «Митя мой там…» — шёпот (quietly) снят, тег sad; подача как у остальных реплик Пелагеи",
    "M23a_1": "H44: ударение во фразе Тамары про Агатины письма — «по письму́ в месяц» "
              "(pipeline/voice/pronunciation_ru.json, fix acute); проверить на слух и voice_stress_check.py",
    "M09_1": "G57: веб-проверка слышала −66 dBFS; файл проверен 24.10 — 2,91 с, RMS −20 dBFS, пик −6,8 dBFS "
             "(тишины нет, вероятно, замер попал в паузу); перезаписать в общем прогоне и проверить voice_audio_check.py",
}

RULES = [
    "Записывать только после H59 (старорусская правка в ChatGPT) и text_freeze — одним прогоном все строки списка "
    "(решение Директора 24.10, 00:17); до этого голос не записывается.",
    "Подача: громкость исходника (source_lufs до нормализации) в пределах ± 4 LU от медианы своего персонажа — "
    "tools/validate_voice.py (H5). Шёпот (теги quietly / whispers / whispering) — только если сцена прямо требует; "
    "у Пелагеи — нет: её реплики звучат одним голосом и громкостью.",
    "Ударения: pipeline/voice/pronunciation_ru.json (H44: «письму́» в M23a_1); после записи — "
    "tools/voice_stress_check.py по выравниванию.",
    "Тишина и обрывы: tools/voice_audio_check.py (пауза внутри > 1,6 с, длительность < 0,3 с, громкость вне цели) — "
    "для каждой новой записи (G57).",
    "Вопрос-приглашение «О чём спросить …» записывается как обычная закадровая фраза; игра сама озвучивает его "
    "при первом показе и не чаще раза в 5 минут (data/story/voice.json → narration.ask_prompts, H4/H14).",
    "После записи строка уходит из списка (python3 tools/voice_after_h59.py), а tools/validate_voice.py --strict "
    "завершается кодом 0.",
]


def build() -> dict:
    vc = _mod("voice_coverage", ROOT / "tools" / "voice_coverage.py")
    vv = _mod("validate_voice", ROOT / "tools" / "validate_voice.py")
    rows = vc.coverage()["rows"]
    lines: dict[str, dict] = {}

    def add(lid: str, speaker: str, why: str) -> None:
        e = lines.setdefault(lid, {"id": lid, "speaker": speaker, "why": []})
        if why not in e["why"]:
            e["why"].append(why)

    for r in rows:
        if r["status"] in ("устарела", "теги изменены", "нет записи"):
            add(r["id"], r.get("speaker", ""), {"устарела": "текст изменён после записи",
                                                 "теги изменены": "теги подачи изменены после записи",
                                                 "нет записи": "новая строка — пока только субтитры"}[r["status"]])
    man = json.loads(MANIFEST.read_text(encoding="utf-8"))
    errs, _w = vv.check_speaker_loudness({"ru": man}, {})
    for e in errs:
        # «ru/agata:H2.bell.thought: подача …» — id записи может сам содержать двоеточие
        head = e.split(": подача", 1)[0]
        lid = head.split("/", 1)[1] if head.startswith("ru/") else head
        sp = str(man["lines"].get(lid, {}).get("speaker", ""))
        add(lid, sp, "H5: подача " + e.split(": подача", 1)[1].split(" — перезаписать", 1)[0].strip())
    for lid, why in MANUAL.items():
        if str(man["lines"].get(lid, {}).get("generated_at", "")) >= H59_RECORDED_FROM:
            continue   # перезаписана финальным прогоном после H59 (T7) — названная строка закрыта
        sp = str(man["lines"].get(lid, {}).get("speaker", "")) or lid.split(":", 1)[0]
        add(lid, sp, why)
    return {
        "_comment": "Строки к одной финальной перезаписи голоса после старорусской правки текстов (H59). Собирает "
                    "tools/voice_after_h59.py; tools/validate_voice.py считает отклонения этих строк предупреждениями. "
                    "Задание T1 партии H (Docs/tasks/H_T1_text_voice_scenes.md); голос до H59 не записывается.",
        "status": "ждёт H59",
        "rules": RULES,
        "count": len(lines),
        "lines": sorted(lines.values(), key=lambda e: e["id"]),
    }


def main() -> int:
    doc = build()
    text = json.dumps(doc, ensure_ascii=False, indent=1) + "\n"
    if "--check" in sys.argv:
        old = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {"lines": []}
        have = {e["id"] for e in old.get("lines", [])}
        miss = [e["id"] for e in doc["lines"] if e["id"] not in have]
        print(f"[voice] после H59: {doc['count']} строк; не внесены: {', '.join(miss) or '—'}")
        return 1 if miss else 0
    OUT.write_text(text, encoding="utf-8")
    print(f"[voice] {OUT.relative_to(ROOT)}: {doc['count']} строк к перезаписи после H59")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
