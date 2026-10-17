#!/usr/bin/env python3
"""Проверка озвучки: assets/voice/ru/manifest.json (+ ru_alt/<персонаж>_<вариант>/), pipeline/voice/cast.json, data/story/voice.json.

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
  5. data/story/voice.json: известные персонажи в pan, panning_strength ∈ [0, 3], volume_db ∈ [−20, 12];
  6. теги подачи у реплик (tags, voice_text): тег из pipeline/voice/tags.json; voice_text без тегов = text (слова
     сценария не меняются); теги voice_text = tags; запись манифеста с другим voice_sha1 (теги изменены) — ждёт
     перегенерации (ошибка с --strict).
Самопроверка (каждый запуск): испорченные копии — реплика, которой нет; изменённый текст без stale; персонаж без
голоса; тихая реплика; тег не из списка; voice_text с чужими словами — должны дать ошибку.
Код 0 — ошибок нет. Запуск: python3 tools/validate_voice.py [--quiet] [--strict] [--source-only — без проверки копии игры]
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "data" / "story"
VOICE_SRC = ROOT / "assets" / "voice" / "ru"
VOICE_GAME = ROOT / "game" / "assets" / "voice" / "ru"
CAST = ROOT / "pipeline" / "voice" / "cast.json"
VOICES = ROOT / "pipeline" / "voice" / "voices.json"
TAGS = ROOT / "pipeline" / "voice" / "tags.json"
TAG_RE = re.compile(r"\[([^\[\]]+)\]")
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
                out[f"{sc['id']}_{i}"] = _line(sc["id"], ln)
    for q in load(STORY / "quests.json")["quests"]:
        for i, ln in enumerate(q.get("mandatory_lines", q.get("lines", []))):
            out[f"{q['id']}_{i}"] = _line(q["id"], ln)
    return out


def _line(scene: str, ln: dict) -> dict:
    e = {"scene": scene, "speaker": ln.get("speaker", ""), "text": ln.get("text", "")}
    for k in ("tags", "voice_text"):
        if k in ln:
            e[k] = ln[k]
    return e


def api_text(ln: dict) -> str:
    """Как pipeline/voice/eleven_voice.py: voice_text или теги перед текстом."""
    if ln.get("voice_text"):
        return str(ln["voice_text"])
    return "".join(f"[{t}] " for t in ln.get("tags", [])) + str(ln["text"])


def check_tags(lines: dict, allowed: set[str] | None) -> list[str]:
    """Теги подачи в данных сцен: из разрешённого списка; voice_text — те же слова, что субтитры."""
    errors: list[str] = []
    for lid, ln in sorted(lines.items()):
        tags = ln.get("tags")
        vt = ln.get("voice_text")
        if tags is None and vt is None:
            continue
        if tags is not None and (not isinstance(tags, list) or not all(isinstance(t, str) and t.strip() for t in tags)):
            errors.append(f"{lid}: tags — массив непустых строк")
            continue
        used = list(tags or [])
        if vt is not None:
            in_text = [t.strip() for t in TAG_RE.findall(str(vt))]
            if tags is not None and in_text != used:
                errors.append(f"{lid}: теги voice_text {in_text} ≠ tags {used}")
            used = in_text
            bare = " ".join(TAG_RE.sub(" ", str(vt)).split())
            if bare != " ".join(str(ln["text"]).split()):
                errors.append(f"{lid}: voice_text без тегов ≠ text (слова сценария менять нельзя): «{bare}»")
        if allowed is not None:
            for t in used:
                if t not in allowed:
                    errors.append(f"{lid}: тег [{t}] не в pipeline/voice/tags.json")
    return errors


def requested_scenes() -> set[str]:
    out: set[str] = set()
    for f in sorted(REQUESTS.glob("voice_*.json")):
        r = load(f, {})
        if str(r.get("mode", "generate")) == "generate":
            out |= {str(s) for s in r.get("scenes", [])}
    return out


def manifests_on_disk() -> dict[str, dict]:
    """rel → манифест: "ru" (основной набор) и "ru_alt/<персонаж>_<вариант>" (альтернативные голоса)."""
    out: dict[str, dict] = {}
    m = load(VOICE_SRC / "manifest.json")
    if m is not None:
        out["ru"] = m
    for f in sorted((VOICE_SRC.parent / "ru_alt").glob("*/manifest.json")):
        out[f"ru_alt/{f.parent.name}"] = load(f)
    return out


def expected_voice(cast_map: dict, rel: str, speaker: str) -> str:
    c = cast_map.get(speaker, {})
    if rel == "ru":
        return str(c.get("voice_id", ""))
    variant = rel.split("/", 1)[1]
    alt_id = variant[len(speaker) + 1:] if variant.startswith(speaker + "_") else ""
    return str((c.get("alternates") or {}).get(alt_id, {}).get("voice_id", ""))


def check(lines: dict, manifests: dict[str, dict], cast: dict | None, voices: dict | None, voice_cfg: dict | None,
          scenes: set[str], strict: bool, files: bool = True, game_copy: bool = True) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warns: list[str] = []
    chars = {c["id"] for c in load(STORY / "characters.json")["characters"]}
    # 1. cast
    speakers = {ln["speaker"] for ln in lines.values() if ln["scene"] in scenes}
    for m in manifests.values():
        speakers |= {str(e.get("speaker", "")) for e in m.get("lines", {}).values() if "stale" not in e}
    for s in sorted(s for s in scenes if not any(ln["scene"] == s for ln in lines.values())):
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
    for sp, c in cast_map.items():
        if sp not in chars:
            errors.append(f"cast.json: неизвестный персонаж {sp}")
        for alt_id, alt in (c.get("alternates") or {}).items():
            if alt_id.startswith("_"):
                continue
            if not alt.get("voice_id"):
                errors.append(f"cast.json {sp}.alternates.{alt_id}: нет voice_id")
            elif voices is not None and alt["voice_id"] not in known_ids:
                errors.append(f"cast.json {sp}.alternates.{alt_id}: voice_id {alt['voice_id']} нет в voices.json")
    # 2–4. manifests
    default_target = float((cast or {}).get("loudness", {}).get("target_lufs", -17.0))
    for rel, manifest in sorted(manifests.items()):
        target = float(manifest.get("loudness_target_lufs", default_target))
        only = manifest.get("speaker_only")
        src_dir = VOICE_SRC.parent / rel
        game_dir = VOICE_GAME.parent / rel
        for lid, e in sorted(manifest.get("lines", {}).items()):
            tag = lid if rel == "ru" else f"{lid}@{rel.split('/', 1)[1]}"
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
                    warns.append(f"{tag}: устарела ({e['stale']}) — игра покажет только субтитры")
                else:
                    (errors if strict else warns).append(f"{tag}: {reason}, а запись не помечена stale — перегенерировать (pipeline-voice)")
                continue
            if "stale" in e:
                errors.append(f"{tag}: помечена stale ({e['stale']}), но совпадает с текущей репликой")
            if e.get("voice_sha1", e.get("text_sha1")) != sha1(api_text(cur)):
                (errors if strict else warns).append(f"{tag}: теги подачи изменены — ждёт перегенерации (pipeline-voice); пока звучит прежний дубль")
            if e.get("text") != cur["text"]:
                errors.append(f"{tag}: text записи ≠ text реплики при равном sha1")
            if only and e.get("speaker") != only:
                errors.append(f"{tag}: в наборе только для {only}, а реплика {e.get('speaker')}")
            want = expected_voice(cast_map, rel, cur["speaker"])
            if want and want != e.get("voice_id"):
                warns.append(f"{tag}: голос записи ≠ голос cast.json — ждёт перегенерации")
            if float(e.get("duration_s", 0)) <= 0.15:
                errors.append(f"{tag}: длительность {e.get('duration_s')} с")
            lufs = e.get("lufs")
            if not isinstance(lufs, (int, float)) or abs(float(lufs) - target) > LUFS_TOL:
                errors.append(f"{tag}: громкость {lufs} LUFS вне {target} ± {LUFS_TOL}")
            tp = e.get("true_peak_db")
            if isinstance(tp, (int, float)) and tp > -1.0:
                errors.append(f"{tag}: true peak {tp} dBTP > −1")
            if not files:
                continue
            f = src_dir / str(e.get("file", ""))
            if not f.is_file():
                errors.append(f"{tag}: нет файла {f.relative_to(ROOT)}")
                continue
            if not game_copy:
                continue
            g = game_dir / f.name
            if not g.is_file() or g.read_bytes() != f.read_bytes():
                errors.append(f"{tag}: копия игры {g.relative_to(ROOT)} отсутствует или отличается — tools/sync_voice.sh")
            else:
                imp = g.with_name(g.name + ".import")
                if not imp.is_file() or "loop=false" not in imp.read_text(encoding="utf-8"):
                    errors.append(f"{tag}: у копии нет .import с loop=false")
        if files and game_copy:
            gm = game_dir / "manifest.json"
            if not gm.is_file() or gm.read_bytes() != (src_dir / "manifest.json").read_bytes():
                errors.append(f"{gm.relative_to(ROOT)} отсутствует или отличается — tools/sync_voice.sh")
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
        for sp, v in voice_cfg.get("variants", {}).items():
            if sp.startswith("_"):
                continue
            if sp not in chars:
                errors.append(f"voice.json variants: неизвестный персонаж {sp}")
                continue
            alts = set((cast_map.get(sp, {}).get("alternates") or {}).keys())
            for o in v.get("options", []):
                oid = str(o.get("id", ""))
                if oid and cast is not None and oid not in {f"{sp}_{a}" for a in alts}:
                    errors.append(f"voice.json variants.{sp}: вариант {oid} не описан в cast.json alternates")
                if oid and not str(o.get("dir", "")).endswith(f"ru_alt/{oid}"):
                    errors.append(f"voice.json variants.{sp}.{oid}: dir должен вести в res://assets/voice/ru_alt/{oid}")
    return errors, warns


def selftest(lines, cast, voice_cfg, scenes) -> list[str]:
    """Каждая порча должна дать ошибку (strict). Возвращает непойманные."""
    first = next(iter(sorted(lines)), None)
    if first is None:
        return []
    ln = lines[first]
    good = {"scene": ln["scene"], "speaker": ln["speaker"], "text": ln["text"], "text_sha1": sha1(ln["text"]),
            "voice_sha1": sha1(api_text(ln)), "voice_id": "v_test", "file": "x.ogg", "duration_s": 1.0, "lufs": -17.0, "true_peak_db": -3.0}
    test_cast = copy.deepcopy(cast) if cast else {"cast": {}}
    test_cast.setdefault("cast", {})[ln["speaker"]] = {"voice_id": "v_test"}
    base = {"loudness_target_lufs": -17.0, "lines": {}}

    def orphan(m, c):
        m["lines"]["M99_0"] = dict(good, scene="M99")

    def changed(m, c):
        m["lines"][first] = dict(good, text_sha1=sha1(ln["text"] + "!"))

    def no_voice(m, c):
        m["lines"][first] = dict(good)
        c["cast"].pop(ln["speaker"], None)

    def quiet(m, c):
        m["lines"][first] = dict(good, lufs=-30.0)

    # теги в данных сцен
    bad_tag = copy.deepcopy(lines)
    bad_tag[first]["tags"] = ["no_such_tag_x"]
    bad_words = copy.deepcopy(lines)
    bad_words[first]["voice_text"] = "[curious] " + ln["text"] + " лишнее"

    missed = []
    for name, fn in (("реплика, которой нет", orphan), ("изменённый текст без stale", changed),
                     ("персонаж без голоса", no_voice), ("тихая реплика", quiet)):
        m = copy.deepcopy(base)
        c = copy.deepcopy(test_cast)
        fn(m, c)
        errs, _ = check(lines, {"ru": m}, c, None, voice_cfg, scenes, strict=True, files=False)
        if not errs:
            missed.append(name)
    allowed = set((load(TAGS, {}) or {}).get("tags", {}).keys())
    if not check_tags(bad_tag, allowed):
        missed.append("тег не из списка")
    if not check_tags(bad_words, allowed | {"curious"}):
        missed.append("voice_text меняет слова")
    # контроль: неиспорченная запись ошибок не даёт (иначе самопроверка ловила бы что угодно)
    m = copy.deepcopy(base)
    m["lines"][first] = dict(good)
    errs, _ = check(lines, {"ru": m}, test_cast, None, voice_cfg, scenes, strict=True, files=False)
    if [x for x in errs if x.startswith(first)]:
        missed.append("чистая запись даёт ошибку: " + "; ".join(errs[:2]))
    return missed


def main() -> int:
    quiet = "--quiet" in sys.argv
    strict = "--strict" in sys.argv
    source_only = "--source-only" in sys.argv   # workflow озвучки: копии игры там нет (её делает tools/sync_voice.sh)
    lines = story_lines()
    manifests = manifests_on_disk()
    cast = load(CAST)
    voices = load(VOICES)
    voice_cfg = load(STORY / "voice.json")
    scenes = requested_scenes()
    errors, warns = check(lines, manifests, cast, voices, voice_cfg, scenes, strict, game_copy=not source_only)
    tags_doc = load(TAGS)
    if tags_doc is None:
        errors.append("нет pipeline/voice/tags.json — список разрешённых тегов")
    errors += check_tags(lines, set(tags_doc.get("tags", {}).keys()) if tags_doc else None)
    tagged = sum(1 for ln in lines.values() if ln.get("tags") or ln.get("voice_text"))
    missed = selftest(lines, cast, voice_cfg, scenes)
    for m in missed:
        errors.append(f"самопроверка: порча «{m}» не поймана")
    for w in warns:
        print(f"  предупреждение: {w}")
    for e in errors:
        print(f"  ОШИБКА: {e}")
    sets = ", ".join(f"{rel} {len(m.get('lines', {}))} ({sum(1 for e in m.get('lines', {}).values() if 'stale' not in e)} актуальных)"
                     for rel, m in sorted(manifests.items())) or "нет"
    if not quiet or errors:
        print(f"validate_voice: манифесты: {sets}; сцены к озвучке: {', '.join(sorted(scenes)) or '—'}; "
              f"персонажей в cast.json: {len((cast or {}).get('cast', {}))}; реплик с тегами: {tagged}")
    print(f"[voice] validate_voice.py: {'OK' if not errors else 'FAIL'} ({len(errors)} ошибок, {len(warns)} предупреждений"
          f"{', strict' if strict else ''}; самопроверка {7 - len(missed)}/7)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
