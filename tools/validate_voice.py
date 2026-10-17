#!/usr/bin/env python3
"""Проверка озвучки: assets/voice/ru/manifest.json, pipeline/voice/cast.json, data/story/voice.json.

Проверяет:
  1. каждый персонаж, чьи реплики озвучиваются (сцены из pipeline/requests/voice_*.json c mode=generate, и все
     персонажи манифеста), есть в cast.json с voice_id; голоса cast.json есть в voices.json (если он уже снят);
  2. манифест: реплики, которых нет в сценах, и реплики с изменённым текстом (sha1 текста ≠ sha1 записи) помечены
     "stale" — иначе это ошибка с --strict (так запускает workflow озвучки) и предупреждение без него (tools/run_tests.sh:
     правка текста до перегенерации не должна блокировать сборку — игра такую запись не играет, сверяя sha1 сама);
  3. у каждой актуальной записи есть файл OGG, длительность > 0,15 с, громкость в пределах target ± 1,5 LU,
     true peak ≤ −1 dBTP; персонаж записи совпадает с персонажем реплики;
  4. копия игры (game/assets/voice/ru, tools/sync_voice.sh) совпадает с assets/voice/ru побайтно; у каждого OGG есть
     .import с loop=false;
  5. data/story/voice.json: известные персонажи в pan, panning_strength ∈ [0, 3], volume_db ∈ [−20, 12].
Самопроверка (каждый запуск): испорченные копии — реплика, которой нет; изменённый текст без stale; персонаж без
голоса; тихая реплика — должны дать ошибку.
Код 0 — ошибок нет. Запуск: python3 tools/validate_voice.py [--quiet] [--strict]
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
VOICE_SRC = ROOT / "assets" / "voice" / "ru"
VOICE_GAME = ROOT / "game" / "assets" / "voice" / "ru"
CAST = ROOT / "pipeline" / "voice" / "cast.json"
VOICES = ROOT / "pipeline" / "voice" / "voices.json"
REQUESTS = ROOT / "pipeline" / "requests"
LUFS_TOL = 1.5


def load(path: Path, default=None):
    if not path.exists():
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def sha1(t: str) -> str:
    return hashlib.sha1(t.encode("utf-8")).hexdigest()


def story_lines() -> dict[str, dict]:
    """id <scene>_<index> → {scene, speaker, text} — как StoryRunner (beat.line_id) и eleven_voice.py."""
    out: dict[str, dict] = {}
    for ep in sorted((STORY / "scenes").glob("E*.json")):
        for sc in load(ep)["scenes"]:
            for i, ln in enumerate(sc.get("mandatory_lines", [])):
                out[f"{sc['id']}_{i}"] = {"scene": sc["id"], "speaker": ln.get("speaker", ""), "text": ln.get("text", "")}
    for q in load(STORY / "quests.json")["quests"]:
        for i, ln in enumerate(q.get("mandatory_lines", q.get("lines", []))):
            out[f"{q['id']}_{i}"] = {"scene": q["id"], "speaker": ln.get("speaker", ""), "text": ln.get("text", "")}
    return out


def requested_scenes() -> set[str]:
    out: set[str] = set()
    for f in sorted(REQUESTS.glob("voice_*.json")):
        r = load(f, {})
        if str(r.get("mode", "generate")) == "generate":
            out |= {str(s) for s in r.get("scenes", [])}
    return out


def check(lines: dict, manifest: dict | None, cast: dict | None, voices: dict | None, voice_cfg: dict | None,
          scenes: set[str], strict: bool, files: bool = True) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warns: list[str] = []
    chars = {c["id"] for c in load(STORY / "characters.json")["characters"]}
    # 1. cast
    speakers = {ln["speaker"] for ln in lines.values() if ln["scene"] in scenes}
    if manifest:
        speakers |= {str(e.get("speaker", "")) for e in manifest.get("lines", {}).values() if "stale" not in e}
    unknown_scenes = sorted(s for s in scenes if not any(ln["scene"] == s for ln in lines.values()))
    for s in unknown_scenes:
        errors.append(f"запрос озвучки: сцены {s} нет (или у неё нет реплик)")
    cast_map = (cast or {}).get("cast", {})
    if speakers and cast is None:
        errors.append("нет pipeline/voice/cast.json, а реплики к озвучке есть")
    known_ids = {v["voice_id"] for v in (voices or {}).get("voices", [])}
    for sp in sorted(speakers):
        c = cast_map.get(sp)
        if not c or not c.get("voice_id"):
            errors.append(f"персонаж {sp}: нет голоса в cast.json")
        elif voices is not None and c["voice_id"] not in known_ids:
            errors.append(f"персонаж {sp}: voice_id {c['voice_id']} нет в voices.json")
    for sp in cast_map:
        if sp not in chars:
            errors.append(f"cast.json: неизвестный персонаж {sp}")
    # 2–3. manifest
    target = float((manifest or {}).get("loudness_target_lufs", (cast or {}).get("loudness", {}).get("target_lufs", -17.0)))
    for lid, e in sorted((manifest or {}).get("lines", {}).items()):
        cur = lines.get(lid)
        reason = ""
        if cur is None:
            reason = "реплики нет в сценах"
        elif sha1(cur["text"]) != e.get("text_sha1"):
            reason = "текст изменён (sha1 не совпадает)"
        elif cur["speaker"] != e.get("speaker"):
            reason = f"персонаж сменился ({e.get('speaker')} → {cur['speaker']})"
        if reason:
            if "stale" in e:
                warns.append(f"{lid}: устарела ({e['stale']}) — игра покажет только субтитры")
            else:
                (errors if strict else warns).append(f"{lid}: {reason}, а запись не помечена stale — перегенерировать (pipeline-voice)")
            continue
        if "stale" in e:
            errors.append(f"{lid}: помечена stale ({e['stale']}), но совпадает с текущей репликой")
        if e.get("text") != cur["text"]:
            errors.append(f"{lid}: text записи ≠ text реплики при равном sha1")
        c = cast_map.get(cur["speaker"], {})
        if c.get("voice_id") and c["voice_id"] != e.get("voice_id"):
            warns.append(f"{lid}: голос записи ≠ голос cast.json — ждёт перегенерации")
        if float(e.get("duration_s", 0)) <= 0.15:
            errors.append(f"{lid}: длительность {e.get('duration_s')} с")
        lufs = e.get("lufs")
        if not isinstance(lufs, (int, float)) or abs(float(lufs) - target) > LUFS_TOL:
            errors.append(f"{lid}: громкость {lufs} LUFS вне {target} ± {LUFS_TOL}")
        tp = e.get("true_peak_db")
        if isinstance(tp, (int, float)) and tp > -1.0:
            errors.append(f"{lid}: true peak {tp} dBTP > −1")
        if not files:
            continue
        f = VOICE_SRC / str(e.get("file", ""))
        if not f.is_file():
            errors.append(f"{lid}: нет файла {f.relative_to(ROOT)}")
            continue
        g = VOICE_GAME / f.name
        if not g.is_file() or g.read_bytes() != f.read_bytes():
            errors.append(f"{lid}: копия игры {g.relative_to(ROOT)} отсутствует или отличается — tools/sync_voice.sh")
        else:
            imp = g.with_name(g.name + ".import")
            if not imp.is_file() or "loop=false" not in imp.read_text(encoding="utf-8"):
                errors.append(f"{lid}: у копии нет .import с loop=false")
    if files and manifest is not None:
        gm = VOICE_GAME / "manifest.json"
        if not gm.is_file() or gm.read_bytes() != (VOICE_SRC / "manifest.json").read_bytes():
            errors.append("game/assets/voice/ru/manifest.json отсутствует или отличается — tools/sync_voice.sh")
    # 5. data/story/voice.json
    if voice_cfg is not None:
        for sp, p in voice_cfg.get("pan", {}).items():
            if sp.startswith("_"):
                continue
            if sp not in chars:
                errors.append(f"voice.json pan: неизвестный персонаж {sp}")
            ps = p.get("panning_strength", 1.0) if isinstance(p, dict) else None
            if not isinstance(ps, (int, float)) or not 0.0 <= float(ps) <= 3.0:
                errors.append(f"voice.json pan.{sp}: panning_strength {ps} вне [0, 3]")
        vdb = voice_cfg.get("volume_db", 0.0)
        if not isinstance(vdb, (int, float)) or not -20.0 <= float(vdb) <= 12.0:
            errors.append(f"voice.json volume_db {vdb} вне [−20, 12]")
    return errors, warns


def selftest(lines, manifest, cast, voices, voice_cfg, scenes) -> list[str]:
    """Каждая порча должна дать ошибку (strict). Возвращает непойманные."""
    base_m = manifest or {"loudness_target_lufs": -17.0, "lines": {}}
    first = next(iter(sorted(lines)), None)
    if first is None:
        return []
    ln = lines[first]
    good = {"scene": ln["scene"], "speaker": ln["speaker"], "text": ln["text"], "text_sha1": sha1(ln["text"]),
            "voice_id": "v_test", "file": "x.ogg", "duration_s": 1.0, "lufs": -17.0, "true_peak_db": -3.0}
    test_cast = copy.deepcopy(cast) if cast else {"cast": {}}
    test_cast.setdefault("cast", {})[ln["speaker"]] = {"voice_id": "v_test"}

    def orphan(m, c):
        m["lines"]["M99_0"] = dict(good, scene="M99")

    def changed(m, c):
        m["lines"][first] = dict(good, text_sha1=sha1(ln["text"] + "!"))

    def no_voice(m, c):
        m["lines"][first] = dict(good)
        c["cast"].pop(ln["speaker"], None)

    def quiet(m, c):
        m["lines"][first] = dict(good, lufs=-30.0)

    missed = []
    for name, fn in (("реплика, которой нет", orphan), ("изменённый текст без stale", changed),
                     ("персонаж без голоса", no_voice), ("тихая реплика", quiet)):
        m = copy.deepcopy(base_m)
        c = copy.deepcopy(test_cast)
        fn(m, c)
        errs, _ = check(lines, m, c, None, voice_cfg, scenes, strict=True, files=False)
        if not errs:
            missed.append(name)
    # контроль: неиспорченная запись ошибок не даёт (иначе самопроверка ловила бы что угодно)
    m = copy.deepcopy(base_m)
    m["lines"][first] = dict(good)
    errs, _ = check(lines, m, test_cast, None, voice_cfg, scenes, strict=True, files=False)
    if [x for x in errs if x.startswith(first)]:
        missed.append("чистая запись даёт ошибку: " + "; ".join(errs[:2]))
    return missed


def main() -> int:
    quiet = "--quiet" in sys.argv
    strict = "--strict" in sys.argv
    lines = story_lines()
    manifest = load(VOICE_SRC / "manifest.json")
    cast = load(CAST)
    voices = load(VOICES)
    voice_cfg = load(STORY / "voice.json")
    scenes = requested_scenes()
    errors, warns = check(lines, manifest, cast, voices, voice_cfg, scenes, strict)
    missed = selftest(lines, manifest, cast, voices, voice_cfg, scenes)
    for m in missed:
        errors.append(f"самопроверка: порча «{m}» не поймана")
    n = len((manifest or {}).get("lines", {}))
    live = sum(1 for e in (manifest or {}).get("lines", {}).values() if "stale" not in e)
    for w in warns:
        print(f"  предупреждение: {w}")
    for e in errors:
        print(f"  ОШИБКА: {e}")
    if not quiet or errors:
        print(f"validate_voice: манифест {n} записей ({live} актуальных), сцены к озвучке: {', '.join(sorted(scenes)) or '—'}; "
              f"персонажей в cast.json: {len((cast or {}).get('cast', {}))}")
    print(f"[voice] validate_voice.py: {'OK' if not errors else 'FAIL'} ({len(errors)} ошибок, {len(warns)} предупреждений"
          f"{', strict' if strict else ''}; самопроверка {5 - len(missed)}/5)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
