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
     перегенерации (ошибка с --strict);
  7. закадровый голос (data/story/voice.json → narration): список не озвучиваемых категорий есть (skip_sections /
     skip_fields / skip_keys), параметры наведения на сумку в пределах; каждая запись kind=narration — ключ, который
     есть в data/story/text/*.json и озвучивается по этим правилам (не подпись, не интерфейс), sha1 её текста совпадает
     с текстом ключа (иначе stale), голос narrator, файл <subdir>/<ключ>.ogg.
  8. подача по персонажу (H5, Директор 24.10): громкость исходника записи (source_lufs, до нормализации) не дальше
     ± 4 LU от медианы своего персонажа — иначе ошибка; строка из pipeline/requests/voice_after_H59.json (ждёт
     финальной перезаписи после H59, tools/voice_after_h59.py) — предупреждение;
  9. вопрос-приглашение разговора (H4/H14): каждый choice.prompt хотспота kind=npc — в voice.json →
     narration.ask_prompts.keys (игра озвучивает его один раз и не чаще раза в repeat_after_s).
Самопроверка (каждый запуск): испорченные копии — реплика, которой нет; изменённый текст без stale; персонаж без
голоса; тихая реплика; тег не из списка; voice_text с чужими словами; закадровая запись подписи (label) или интерфейса
(ui.*); закадровая запись с чужим текстом; закадровый файл не в своей папке; нет списка не озвучиваемых категорий —
должны дать ошибку.
Устаревшая запись (ключ/реплика есть, текст изменён после записи; или ключ удалён) — ПРЕДУПРЕЖДЕНИЕ со списком на
перезапись, код 0: игра такую запись не играет (сверяет sha1), правка текста не роняет main; перезапись — одним
запросом (pipeline/voice/README.md → «Текст изменился»). С --strict (workflow озвучки, после пометки stale) неотмеченная
устаревшая запись — ошибка. Ошибка всегда (код 1): запись для ключа, который не озвучивается (подпись, интерфейс,
вариант…), чужая папка или чужой голос у закадровой записи, первое лицо у закадрового голоса, файл OGG без записи
манифеста, тихая/обрезанная запись.
Код 0 — ошибок нет. Запуск: python3 tools/validate_voice.py [--quiet] [--strict] [--source-only — без проверки копии игры]
"""
from __future__ import annotations

import copy
import fnmatch
import hashlib
import importlib.util
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
TEXT_DIR = STORY / "text"
LUFS_TOL = 1.5
# Подсказка к старому слову «[[слово|значение]]» (H59, T7): в голос идёт только слово — как в eleven_voice.api_text.
GLOSS_RE = re.compile(r"\[\[([^\[\]|]+)\|[^\[\]|]+\]\]")
SPEAKER_LU_TOL = 4.0   # H5: подача реплики (громкость исходника до нормализации) не дальше 4 LU от медианы персонажа
AFTER_H59 = REQUESTS / "voice_after_H59.json"   # строки, ждущие финальной перезаписи после старорусской правки (H59)

_pspec = importlib.util.spec_from_file_location("pronounce", ROOT / "pipeline" / "voice" / "pronounce.py")
pronounce = importlib.util.module_from_spec(_pspec)
_pspec.loader.exec_module(pronounce)
_dspec = importlib.util.spec_from_file_location("direction", ROOT / "pipeline" / "voice" / "direction.py")
direction = importlib.util.module_from_spec(_dspec)
_dspec.loader.exec_module(direction)
NARRATION_REQUIRED = ("speaker", "subdir", "skip_sections", "skip_fields")


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

    def add(scene_id: str, lines: list) -> None:
        for i, ln in enumerate(lines or []):
            # выбор внутри разговора (M13): звучат слова выбранного варианта, line_id <scene>_<index>_<вариант>
            for o in ln.get("options") or []:
                if str(o.get("text", "")).strip():
                    out[f"{scene_id}_{i}_{o['id']}"] = _line(scene_id, dict(o, speaker=ln.get("speaker", "agata") or "agata"))
            # строки-продолжения (then: след необязательной истории в эпилоге) — line_id <scene>_<index>_then<k>,
            # своей позиции в mandatory_lines не занимают: записанные голоса после них не сдвигаются
            for k, t in enumerate(ln.get("then") or []):
                if str(t.get("text", "")).strip():
                    out[f"{scene_id}_{i}_then{k}"] = _line(scene_id, dict(t, speaker=t.get("speaker", "narrator") or "narrator"))
            # продолжения эпилога (`then`) — line_id <scene>_<index>_then<k>
            for k, sub in enumerate(ln.get("then") or []):
                if str(sub.get("text", "")).strip():
                    out[f"{scene_id}_{i}_then{k}"] = _line(scene_id, dict(sub, speaker=sub.get("speaker", "narrator") or "narrator"))
            if ln.get("options") or not str(ln.get("text", "")).strip():
                continue
            out[f"{scene_id}_{i}"] = _line(scene_id, ln)

    for ep in sorted((STORY / "scenes").glob("E*.json")):
        for sc in load(ep)["scenes"]:
            add(sc["id"], sc.get("mandatory_lines", []))
    for q in load(STORY / "quests.json")["quests"]:
        add(q["id"], q.get("mandatory_lines", q.get("lines", [])))
    return out


def narration_cfg(voice_cfg: dict | None) -> dict:
    return ((voice_cfg or {}).get("narration") or {}) if isinstance(voice_cfg, dict) else {}


def narration_key_ok(key: str, cfg: dict) -> bool:
    """Как pipeline/voice/eleven_voice.py и voice_director.gd: ключ озвучивается закадровым голосом."""
    parts = key.split(".")
    if len(parts) < 2 or not cfg:
        return False
    if parts[0] in cfg.get("skip_sections", []) or key in cfg.get("skip_keys", []):
        return False
    return not any(fnmatch.fnmatchcase(parts[-1], str(p)) for p in cfg.get("skip_fields", []))


def all_texts() -> dict[str, tuple[str, dict]]:
    """Ключ → (имя файла текста, запись) по всем data/story/text/*.json."""
    out: dict[str, tuple[str, dict]] = {}
    for f in sorted(TEXT_DIR.glob("*.json")):
        for k, v in (load(f, {}) or {}).get("texts", {}).items():
            out[str(k)] = (f.stem, v)
    return out


def by_speaker(cfg: dict) -> dict[str, dict]:
    """voice.json → narration.by_speaker: персонаж → {subdir, keys, tags, hold}."""
    return {str(sp): v for sp, v in (cfg.get("by_speaker") or {}).items() if not str(sp).startswith("_") and isinstance(v, dict)}


def key_owner(cfg: dict) -> dict[str, str]:
    """Ключ → персонаж, которому он назначен (остальные ключи читает закадровый голос)."""
    return {str(k): sp for sp, v in by_speaker(cfg).items() for k in v.get("keys", [])}


def narration_lines(cfg: dict, texts: dict | None = None) -> dict[str, dict]:
    """Как pipeline/voice/eleven_voice.py: id → {kind, key, speaker, text, source, assigned, subdir[, tags, voice_text]}.
    Закадровая запись (id = ключ) — у каждого озвучиваемого ключа (у назначенных персонажу — запасная, assigned
    false); запись персонажа — id <персонаж>:<ключ>."""
    out: dict[str, dict] = {}
    owner = key_owner(cfg)
    bs = by_speaker(cfg)
    for k, (src, v) in (texts if texts is not None else all_texts()).items():
        if not narration_key_ok(k, cfg):
            continue
        ln_spec = v.get("line") if isinstance(v.get("line"), dict) else None
        e = {"kind": "narration", "key": k, "scene": "", "speaker": str(cfg.get("speaker", "narrator")),
             "text": str(v.get("text", "")), "source": src, "assigned": k not in owner and ln_spec is None,
             "subdir": str(cfg.get("subdir", "narrator"))}
        for f in ("tags", "voice_text"):
            if f in v:
                e[f] = v[f]
        out[k] = e
        if ln_spec is not None and ln_spec.get("speaker") and ln_spec.get("text"):
            sp = str(ln_spec["speaker"])
            ce = {"kind": "narration", "key": k, "scene": "", "speaker": sp, "text": str(ln_spec["text"]), "source": src,
                  "assigned": True, "as_line": True, "subdir": str((cfg.get("character_lines") or {}).get("subdir", "character_lines"))}
            if "tags" in ln_spec:
                ce["tags"] = ln_spec["tags"]
            out[f"{sp}:{k}"] = ce
            continue
        if k in owner:
            sp = owner[k]
            pe = {"kind": "narration", "key": k, "scene": "", "speaker": sp, "text": e["text"], "source": src,
                  "assigned": True, "subdir": str(bs[sp].get("subdir", sp))}
            tags = (bs[sp].get("tags") or {}).get(k)
            if tags is not None:
                pe["tags"] = tags
            out[f"{sp}:{k}"] = pe
    return out


QUOTES_RE = re.compile(r"«[^«»]*»|„[^„“]*“|\"[^\"]*\"")


def first_person_hits(text: str, fp: dict) -> list[str]:
    """Слова первого лица вне кавычек: местоимения fp.pronouns и формы fp.forms (без учёта регистра)."""
    bare = QUOTES_RE.sub(" ", text)
    words = [w.lower() for w in re.findall(r"[\w-]+", bare)]
    vocab = {str(x).lower() for x in fp.get("pronouns", [])} | {str(x).lower() for x in fp.get("forms", [])}
    return [w for w in words if w in vocab]


def character_names() -> dict[str, str]:
    """Имя персонажа (characters.json name, именительный падеж) → id."""
    return {str(c["name"]): str(c["id"]) for c in load(STORY / "characters.json")["characters"] if c.get("name")}


def speech_hits(key: str, text: str, cs: dict, names: dict[str, str]) -> list[str]:
    """Признаки слов персонажа: ключ повторного разговора (talk_fields) или цитата «…» с атрибуцией —
    глагол речи рядом с именем персонажа, или «Имя …: «…»». Надписи («Почта», тётины заметки) не речь."""
    hits = []
    if key.split(".")[-1] in [str(x) for x in cs.get("talk_fields", [])]:
        hits.append(f"ключ повторного разговора .{key.split('.')[-1]}")
    if not re.search(r"«|„", text):
        return hits
    words = {w.lower() for w in re.findall(r"[\w-]+", text)}
    who = [n for n in names if re.search(rf"(?<![\w-]){re.escape(n)}(?![\w-])", text)]
    verbs = [str(v) for v in cs.get("verbs", []) if str(v).lower() in words]
    if who and verbs:
        hits.append(f"цитата с атрибуцией ({', '.join(who)} — {', '.join(verbs)})")
    for n in names:
        if re.search(rf"(?<![\w-]){re.escape(n)}(?![\w-])[^.«»]*:\s*[«„]", text):
            hits.append(f"«{n} …: «…»»")
    return hits


def check_character_speech(lines: dict, cfg: dict, names: dict[str, str] | None = None) -> list[str]:
    """Решение Директора 18.10, 01:52: слова персонажа рядом с Агатой говорит он сам, не закадровый голос."""
    cs = cfg.get("character_speech") or {}
    if not cs.get("verbs"):
        return ["voice.json narration.character_speech.verbs: нет списка — проверка слов персонажей не работает"]
    names = names if names is not None else character_names()
    narrator = str(cfg.get("speaker", "narrator"))
    errors = []
    for lid, ln in sorted(lines.items()):
        if ln.get("kind") != "narration" or ln.get("speaker") != narrator or not ln.get("assigned", True):
            continue
        hits = speech_hits(str(ln.get("key", lid)), str(ln["text"]), cs, names)
        if hits:
            errors.append(f"{lid}: закадровому голосу назначены слова персонажа ({'; '.join(hits)}) — поле line "
                          f"{{speaker, text}} у записи текста (реплика персонажа его голосом): «{ln['text']}»")
    return errors


def check_first_person(lines: dict, cfg: dict) -> list[str]:
    """Дефект п. 75: строка, назначенная закадровому голосу, не говорит от первого лица (кавычечные цитаты — можно)."""
    fp = cfg.get("first_person") or {}
    if not fp.get("pronouns"):
        return ["voice.json narration.first_person.pronouns: нет списка — проверка первого лица не работает"]
    narrator = str(cfg.get("speaker", "narrator"))
    errors = []
    for lid, ln in sorted(lines.items()):
        if ln.get("kind") != "narration" or ln.get("speaker") != narrator or not ln.get("assigned", True):
            continue
        hits = first_person_hits(str(ln["text"]), fp)
        if hits:
            errors.append(f"{lid}: закадровый голос говорит от первого лица ({', '.join(sorted(set(hits)))}) — назначить "
                          f"персонажу (voice.json → narration.by_speaker.<персонаж>.keys) или переписать: «{ln['text']}»")
    return errors


def check_empty(lines: dict) -> list[str]:
    """Реплика/фраза к озвучке без текста — дефект 23.10 (M13_1, M23d_0, M25_6: строка-выбор, у которой звучат
    слова варианта, ушла бы в синтез пустой строкой; её варианты — id <scene>_<index>_<вариант>)."""
    return [f"{lid}: пустой текст в списке к озвучке (строка-выбор? варианты — <scene>_<index>_<вариант>)"
            for lid, ln in sorted(lines.items()) if not str(ln.get("text", "")).strip()]


def _line(scene: str, ln: dict) -> dict:
    e = {"scene": scene, "speaker": ln.get("speaker", ""), "text": ln.get("text", "")}
    for k in ("tags", "voice_text"):
        if k in ln:
            e[k] = ln[k]
    return e


def api_text(ln: dict) -> str:
    """Как pipeline/voice/eleven_voice.py: voice_text или теги перед текстом; произношение — pronounce.py."""
    lid = str(ln.get("id", ""))
    if ln.get("voice_text"):
        return pronounce.apply(direction.apply(GLOSS_RE.sub(r"\1", str(ln["voice_text"])), lid), lid)
    # Теги подачи из voice_direction.json (правка Директора) заменяют прежние теги строки, а не добавляются к ним
    # (партия J: «[warmly] [surprised]» — два противоречащих тега).
    line_tags = [] if direction.for_line(lid).get("tags") else ln.get("tags", [])
    return "".join(f"[{t}] " for t in line_tags) + pronounce.apply(direction.apply(GLOSS_RE.sub(r"\1", str(ln["text"])), lid), lid)


def check_direction(lines: dict, allowed: set[str] | None) -> list[str]:
    """Партия J: data/story/voice_direction.json — id есть среди реплик, слова акцента и паузы есть в тексте, теги из списка."""
    errors: list[str] = []
    for lid in sorted(direction.table()):
        ln = lines.get(lid)
        if ln is None:
            errors.append(f"voice_direction.json: {lid} — нет такой реплики (id как в манифесте озвучки)")
            continue
        errors += direction.problems(lid, GLOSS_RE.sub(r"\1", str(ln.get("text", ""))), allowed)
    return errors


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
            if bare != " ".join(GLOSS_RE.sub(r"\1", str(ln["text"])).split()):
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


def requested_narration() -> set[str]:
    """Файлы текста, закадровые фразы которых заказаны (narration.texts в запросах mode=generate)."""
    out: set[str] = set()
    for f in sorted(REQUESTS.glob("voice_*.json")):
        r = load(f, {})
        if str(r.get("mode", "generate")) == "generate":
            out |= {str(t) for t in (r.get("narration") or {}).get("texts", [])}
    return out


def check_narration_cfg(voice_cfg: dict | None, texts: dict) -> list[str]:
    """Раздел narration в data/story/voice.json: список не озвучиваемых категорий и параметры наведения на сумку."""
    errors: list[str] = []
    cfg = narration_cfg(voice_cfg)
    if not cfg:
        return ["data/story/voice.json: нет раздела narration (закадровый голос и список не озвучиваемых категорий)"]
    for k in NARRATION_REQUIRED:
        if k not in cfg:
            errors.append(f"voice.json narration: нет поля {k}")
    for k in ("skip_sections", "skip_fields", "skip_keys"):
        if k in cfg and (not isinstance(cfg[k], list) or not all(isinstance(x, str) and x for x in cfg[k])):
            errors.append(f"voice.json narration.{k}: массив непустых строк")
    narrator = str(cfg.get("speaker", "narrator"))
    seen: dict[str, str] = {}
    chars = {c["id"] for c in load(STORY / "characters.json")["characters"]}
    for sp, v in by_speaker(cfg).items():
        if sp not in chars:
            errors.append(f"voice.json narration.by_speaker: {sp} — не персонаж characters.json")
        sd = str(v.get("subdir", ""))
        if not sd or "/" in sd or sd == str(cfg.get("subdir", "")) or sd.startswith("."):
            errors.append(f"voice.json narration.by_speaker.{sp}.subdir «{sd}»: своя папка, одно имя")
        keys = [str(k) for k in v.get("keys", [])]
        for k in keys:
            if k not in texts:
                errors.append(f"voice.json narration.by_speaker.{sp}: ключа {k} нет в data/story/text")
            elif not narration_key_ok(k, cfg):
                errors.append(f"voice.json narration.by_speaker.{sp}: ключ {k} не озвучивается по правилам (подпись/интерфейс)")
            if k in seen:
                errors.append(f"voice.json narration.by_speaker: {k} назначен и {seen[k]}, и {sp}")
            seen[k] = sp
        for k in (v.get("tags") or {}):
            if k not in keys:
                errors.append(f"voice.json narration.by_speaker.{sp}.tags: {k} не в keys")
        for k in v.get("hold", []):
            if k not in keys:
                errors.append(f"voice.json narration.by_speaker.{sp}.hold: {k} не в keys")
        if sp == narrator:
            errors.append("voice.json narration.by_speaker: закадровый голос не назначается сам себе")
    csub = str((cfg.get("character_lines") or {}).get("subdir", ""))
    if not csub or "/" in csub or csub in {str(cfg.get("subdir", ""))} | {str(v.get("subdir", "")) for v in by_speaker(cfg).values()}:
        errors.append(f"voice.json narration.character_lines.subdir «{csub}»: своя папка, одно имя")
    for k, (_src, v) in texts.items():
        if "line" not in v:
            continue
        ls = v["line"]
        if not isinstance(ls, dict) or not ls.get("speaker") or not str(ls.get("text", "")).strip():
            errors.append(f"{k}: line — {{speaker, text}} с непустым текстом")
            continue
        if str(ls["speaker"]) not in chars or str(ls["speaker"]) == narrator:
            errors.append(f"{k}: line.speaker {ls['speaker']} — не персонаж characters.json")
        if k in seen:
            errors.append(f"{k}: и реплика персонажа (line), и мысль {seen[k]} (by_speaker) — что-то одно")
        if not narration_key_ok(k, cfg):
            errors.append(f"{k}: line у ключа, который не озвучивается (подпись/интерфейс)")
    for must in ("ui",):
        if must not in cfg.get("skip_sections", []):
            errors.append(f"voice.json narration.skip_sections: нет «{must}» — служебный интерфейс озвучивался бы")
    for must in ("label", "label_*", "opt_*"):
        if must not in cfg.get("skip_fields", []):
            errors.append(f"voice.json narration.skip_fields: нет «{must}» — подписи/варианты озвучивались бы")
    sub = str(cfg.get("subdir", ""))
    if not sub or "/" in sub or "\\" in sub or sub.startswith("."):
        errors.append(f"voice.json narration.subdir «{sub}»: одно имя папки")
    for k in cfg.get("skip_keys", []) if isinstance(cfg.get("skip_keys", []), list) else []:
        if k not in texts:
            errors.append(f"voice.json narration.skip_keys: ключа {k} нет в data/story/text")
    ih = cfg.get("item_hover", {})
    for k, lo, hi in (("dwell_s", 0.2, 3.0), ("repeat_after_s", 0.0, 600.0), ("fade_out_s", 0.0, 2.0)):
        v = ih.get(k) if isinstance(ih, dict) else None
        if not isinstance(v, (int, float)) or not lo <= float(v) <= hi:
            errors.append(f"voice.json narration.item_hover.{k} = {v} вне [{lo}, {hi}]")
    return errors


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
          scenes: set[str], strict: bool, files: bool = True, game_copy: bool = True,
          narr_texts: set[str] | None = None) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warns: list[str] = []
    ncfg = narration_cfg(voice_cfg)
    narrator = str(ncfg.get("speaker", "narrator"))
    # Роль закадрового голоса — не персонаж characters.json (задаётся voice.json → narration.speaker).
    chars = {c["id"] for c in load(STORY / "characters.json")["characters"]} | ({narrator} if ncfg else set())
    # 1. cast
    speakers = {ln["speaker"] for ln in lines.values() if ln.get("kind") != "narration" and ln["scene"] in scenes}
    if narr_texts:
        speakers |= {ln["speaker"] for ln in lines.values() if ln.get("kind") == "narration" and ln.get("source") in narr_texts
                     and ln.get("assigned", True)}
    for m in manifests.values():
        speakers |= {str(e.get("speaker", "")) for e in m.get("lines", {}).values() if "stale" not in e}
    # Сцены, снятые решением Директора (data/story/voice.json → removed_scenes, напр. Q09 — партия J, Р10), в прежних
    # запросах остаются как история: их запросы не перезапускаются (workflow берёт только изменённые файлы запросов).
    removed = {str(x) for x in ((voice_cfg or {}).get("removed_scenes") or [])}
    for s in sorted(s for s in scenes if s not in removed and not any(ln["scene"] == s for ln in lines.values())):
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
    text_keys = set(all_texts())
    rerecord: list[str] = []      # устарели: текст изменён после записи — игра молчит, ждут перезаписи
    orphaned: list[str] = []      # ключа/реплики больше нет — запись не звучит, убрать или вернуть ключ
    spares: list[str] = []        # запасные записи (ключ сейчас читает другой голос) с устаревшим текстом
    for rel, manifest in sorted(manifests.items()):
        target = float(manifest.get("loudness_target_lufs", default_target))
        only = manifest.get("speaker_only")
        src_dir = VOICE_SRC.parent / rel
        game_dir = VOICE_GAME.parent / rel
        for lid, e in sorted(manifest.get("lines", {}).items()):
            tag = lid if rel == "ru" else f"{lid}@{rel.split('/', 1)[1]}"
            narr = e.get("kind") == "narration"
            own = lines.get(lid)
            # Запасная запись (ключ отдан другому голосу или возвращён закадровому) сверяется только с текстом ключа.
            cur = own or (lines.get(str(e.get("key", ""))) if narr else None)
            reason = ""
            ekey = str(e.get("key", lid))
            if cur is None and narr and ekey in text_keys:
                # ключ есть, но по правилам его не озвучивают (подпись, интерфейс, вариант, skip_keys) — не устаревание
                errors.append(f"{tag}: ключ {ekey} не озвучивается по правилам data/story/voice.json → narration "
                              f"(подпись/интерфейс/вариант) — такой записи быть не должно")
                continue
            if cur is None:
                reason = "ключа больше нет в data/story/text" if narr else "реплики нет в сценах"
                orphaned.append(tag)
            elif narr != (cur.get("kind") == "narration"):
                errors.append(f"{tag}: запись реплики под ключом закадровой фразы (или наоборот)")
                continue
            elif sha1(cur["text"]) != e.get("text_sha1"):
                reason = "текст изменён после записи (sha1 не совпадает) — игра молчит"
                if narr and (own is None or not own.get("assigned", True)):
                    spares.append(tag)      # запасная запись другого голоса: перезаписывается, только если ключ вернут ему
                else:
                    rerecord.append(tag)
            elif not narr and cur["speaker"] != e.get("speaker"):
                reason = f"персонаж сменился ({e.get('speaker')} → {cur['speaker']})"
                rerecord.append(tag)
            if reason:
                if "stale" in e:
                    warns.append(f"{tag}: устарела ({e['stale']}) — игра покажет только субтитры")
                else:
                    (errors if strict else warns).append(f"{tag}: {reason}, а запись не помечена stale — перегенерировать (pipeline-voice)")
                continue
            if "stale" in e:
                errors.append(f"{tag}: помечена stale ({e['stale']}), но совпадает с текущей репликой")
            # запасная запись другого голоса (ключ читает персонаж) не перезаписывается — её теги/произношение не сверяем
            if own is not None and own.get("assigned", True) and e.get("voice_sha1", e.get("text_sha1")) != sha1(api_text(cur)):
                (errors if strict else warns).append(f"{tag}: теги подачи изменены — ждёт перегенерации (pipeline-voice); пока звучит прежний дубль")
            if e.get("text") != cur["text"]:
                errors.append(f"{tag}: text записи ≠ text реплики при равном sha1")
            if narr:
                key = str(e.get("key", lid))
                sp_id, _, rest = lid.partition(":")
                want_sp = sp_id if rest else narrator
                want_key = rest if rest else lid
                bsc = by_speaker(ncfg)
                if not rest:
                    want_sub = str(ncfg.get("subdir", "narrator"))
                elif own is not None and own.get("subdir"):
                    want_sub = str(own["subdir"])
                elif want_sp in bsc:
                    want_sub = str(bsc[want_sp].get("subdir", want_sp))
                else:
                    want_sub = str((ncfg.get("character_lines") or {}).get("subdir", "character_lines"))
                if key != want_key:
                    errors.append(f"{tag}: key {key} ≠ id записи")
                if str(e.get("speaker", "")) != want_sp:
                    errors.append(f"{tag}: голос записи {e.get('speaker')} ≠ {want_sp} (id <персонаж>:<ключ> или ключ — закадровый)")
                want_file = f"{want_sub}/{want_key}.ogg"
                if str(e.get("file", "")) != want_file:
                    errors.append(f"{tag}: файл закадровой фразы {e.get('file')} — ожидается {want_file}")
            if only and e.get("speaker") != only:
                errors.append(f"{tag}: в наборе только для {only}, а реплика {e.get('speaker')}")
            want = expected_voice(cast_map, rel, str(e.get("speaker", "")) if narr else cur["speaker"])
            if want and want != e.get("voice_id"):
                warns.append(f"{tag}: голос записи ≠ голос cast.json — ждёт перегенерации")
            if float(e.get("duration_s", 0)) <= 0.15:
                errors.append(f"{tag}: длительность {e.get('duration_s')} с")
            lufs = e.get("lufs")
            if not isinstance(lufs, (int, float)) or abs(float(lufs) - target) > LUFS_TOL:
                errors.append(f"{tag}: громкость {lufs} LUFS вне {target} ± {LUFS_TOL}")
            vq_want = int((cast or {}).get("loudness", {}).get("vorbis_quality", 5))
            if int(e.get("vorbis_q", 5)) < vq_want and own is not None and own.get("assigned", True):   # запасные не трогаем
                warns.append(f"{tag}: OGG Vorbis q{e.get('vorbis_q', 5)} < q{vq_want} из cast.json — переобработка из src без кредитов (\"reprocess\": true)")
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
            g = game_dir / str(e.get("file", ""))
            if not g.is_file() or g.read_bytes() != f.read_bytes():
                errors.append(f"{tag}: копия игры {g.relative_to(ROOT)} отсутствует или отличается — tools/sync_voice.sh")
            else:
                imp = g.with_name(g.name + ".import")
                if not imp.is_file() or "loop=false" not in imp.read_text(encoding="utf-8"):
                    errors.append(f"{tag}: у копии нет .import с loop=false")
        if files and src_dir.is_dir():
            known = {str(e.get("file", "")) for e in manifest.get("lines", {}).values()}
            for f in sorted(src_dir.rglob("*.ogg")):
                rel_f = f.relative_to(src_dir).as_posix()
                if rel_f.startswith("src/"):
                    continue
                if rel_f not in known:
                    errors.append(f"{rel}/{rel_f}: файл без записи в манифесте (не соответствует ни одному ключу/реплике)")
        if files and game_copy:
            gm = game_dir / "manifest.json"
            if not gm.is_file() or gm.read_bytes() != (src_dir / "manifest.json").read_bytes():
                errors.append(f"{gm.relative_to(ROOT)} отсутствует или отличается — tools/sync_voice.sh")
    if rerecord:
        warns.append(f"к перезаписи {len(rerecord)} (текст изменён после записи, игра их не играет): {', '.join(rerecord)} — "
                     f"один запрос: pipeline/voice/README.md → «Текст изменился»")
    if spares:
        warns.append(f"запасные записи с устаревшим текстом {len(spares)} (ключ сейчас читает другой голос; не перезаписываются): {', '.join(spares)}")
    if orphaned:
        warns.append(f"записи без ключа/реплики {len(orphaned)} (не звучат; после перезаписи помечаются stale): {', '.join(orphaned)}")
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


SELFTEST_CASES = 25


def after_h59() -> dict[str, str]:
    """pipeline/requests/voice_after_H59.json → {id записи: почему}: строки, которые перезаписываются одним финальным
    прогоном после H59 (решение Директора 24.10: до H59 голос не записываем). Их отклонения — предупреждения."""
    doc = load(AFTER_H59, {}) or {}
    return {str(r["id"]): "; ".join(r.get("why", [])) if isinstance(r.get("why"), list) else str(r.get("why", ""))
            for r in doc.get("lines", []) if isinstance(r, dict) and r.get("id")}


def soft_lines(voice_cfg: dict | None = None) -> tuple[set[str], float]:
    """data/story/voice.json → soft_lines: нарочно тихие реплики (Директор 24.10) — не тише min_lu от медианы."""
    cfg = (voice_cfg if voice_cfg is not None else load(STORY / "voice.json", {}) or {}).get("soft_lines") or {}
    return {str(x) for x in cfg.get("ids", [])}, float(cfg.get("min_lu", -6.0))


def loud_lines(voice_cfg: dict | None = None) -> tuple[set[str], float]:
    """data/story/voice.json → loud_lines: нарочно громкие (выкрик, ликование; I-T5) — не громче max_lu от медианы."""
    cfg = (voice_cfg if voice_cfg is not None else load(STORY / "voice.json", {}) or {}).get("loud_lines") or {}
    return {str(x) for x in cfg.get("ids", [])}, float(cfg.get("max_lu", 6.0))


def check_speaker_loudness(manifests: dict[str, dict], waiting: dict[str, str],
                           soft_cfg: tuple[set[str], float] | None = None,
                           loud_cfg: tuple[set[str], float] | None = None) -> tuple[list[str], list[str]]:
    """H5 (Директор 24.10: тихие реплики Пелагеи выбиваются): все записи нормализованы к одной цели LUFS, но шёпот
    после нормализации звучит тише и глуше. Мерило подачи — громкость исходника (source_lufs, до нормализации):
    дальше SPEAKER_LU_TOL от медианы своего персонажа (≥ 4 записи) — ошибка; строка из списка ожидания H59 —
    предупреждение (перезапишется в финальном прогоне)."""
    errors: list[str] = []
    warns: list[str] = []
    soft, soft_min = soft_cfg if soft_cfg is not None else soft_lines()
    loud, loud_max = loud_cfg if loud_cfg is not None else (loud_lines() if soft_cfg is None else (set(), 6.0))
    for rel, m in sorted(manifests.items()):
        by: dict[str, list[tuple[float, str]]] = {}
        for lid, e in m.get("lines", {}).items():
            src = e.get("source_lufs")
            if "stale" in e or not isinstance(src, (int, float)):
                continue
            by.setdefault(str(e.get("speaker", "")), []).append((float(src), lid))
        for sp, rows in sorted(by.items()):
            if len(rows) < 4:
                continue
            vals = sorted(v for v, _ in rows)
            n = len(vals)
            med = vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2]) / 2
            for v, lid in sorted(rows, key=lambda r: r[1]):
                low = soft_min if lid in soft else -SPEAKER_LU_TOL
                high = loud_max if lid in loud else SPEAKER_LU_TOL
                if not low <= v - med <= high:
                    msg = (f"{rel}/{lid}: подача {v:+.1f} LUFS до нормализации — {v - med:+.1f} LU от медианы {sp} "
                           f"({med:.1f}); допустимо {low:+g}…+{high:g}" + (" (нарочно тихая)" if lid in soft else "")
                           + (" (нарочно громкая)" if lid in loud else ""))
                    if lid in waiting:
                        warns.append(msg + " — в списке перезаписи после H59")
                    else:
                        errors.append(msg + " — перезаписать голосом и громкостью персонажа (или внести в "
                                      "pipeline/requests/voice_after_H59.json, если ждёт H59)")
    return errors, warns


def check_ask_prompts(voice_cfg: dict | None, texts: dict) -> list[str]:
    """H4/H14: вопрос-приглашение разговора («О чём спросить …») — в voice.json → narration.ask_prompts.keys: игра
    озвучивает его при первом показе и не чаще раза в repeat_after_s. Каждый choice.prompt хотспота kind=npc — в списке."""
    errors: list[str] = []
    ap = narration_cfg(voice_cfg).get("ask_prompts")
    if not isinstance(ap, dict):
        return ["voice.json narration.ask_prompts: нет раздела — «О чём спросить …» звучал бы при каждом показе (H4)"]
    keys = ap.get("keys") or []
    rs = ap.get("repeat_after_s")
    if not isinstance(rs, (int, float)) or not 60 <= float(rs) <= 1800:
        errors.append(f"voice.json narration.ask_prompts.repeat_after_s = {rs} вне [60, 1800]")
    for k in keys:
        if k not in texts:
            errors.append(f"voice.json narration.ask_prompts: ключа {k} нет в data/story/text")
    for f in sorted((STORY / "rooms").glob("*.json")):
        room = load(f, {}) or {}
        for h in room.get("hotspots", []):
            pk = str((h.get("choice") or {}).get("prompt", ""))
            if h.get("kind") == "npc" and pk.startswith("@") and pk[1:] not in keys:
                errors.append(f"rooms/{f.name} {h.get('id')}: вопрос {pk} — не в voice.json narration.ask_prompts.keys "
                              f"(звучал бы при каждом клике, H4)")
    return errors


def selftest(lines, cast, voice_cfg, scenes) -> list[str]:
    """Каждая порча должна дать ошибку (strict). Возвращает непойманные."""
    first = next(iter(sorted(lid for lid, ln in lines.items() if ln.get("kind") != "narration")), None)
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
    # закадровый голос: запись подписи / интерфейса, чужой текст, файл не в своей папке, нет списка категорий
    ncfg = narration_cfg(voice_cfg)
    narrator = str(ncfg.get("speaker", "narrator"))
    sub = str(ncfg.get("subdir", "narrator"))
    texts = all_texts()
    nkey = next(iter(sorted(k for k, ln in lines.items() if ln.get("kind") == "narration" and ln.get("speaker") == narrator
                            and ln.get("assigned", True))), None)
    tkey = next(iter(sorted(k for k, ln in lines.items() if ln.get("kind") == "narration" and ln.get("speaker") != narrator)), None)
    label_key = next(iter(sorted(k for k in texts if k.split(".")[-1] == "label")), None)
    ui_key = next(iter(sorted(k for k in texts if k.startswith("ui."))), None)
    ncast = copy.deepcopy(test_cast)
    ncast["cast"][narrator] = {"voice_id": "v_test"}

    def narr_entry(key: str, text: str) -> dict:
        return {"kind": "narration", "key": key, "speaker": narrator, "text": text, "text_sha1": sha1(text),
                "voice_sha1": sha1(text), "voice_id": "v_test", "file": f"{sub}/{key}.ogg", "duration_s": 1.0,
                "lufs": -17.0, "true_peak_db": -3.0}

    ncases = []
    if label_key:
        ncases.append(("закадровая запись подписи (label)", label_key, narr_entry(label_key, str(texts[label_key][1].get("text", "")))))
    if ui_key:
        ncases.append(("закадровая запись интерфейса (ui.*)", ui_key, narr_entry(ui_key, str(texts[ui_key][1].get("text", "")))))
    if nkey:
        nl = lines[nkey]
        ncases.append(("закадровая запись с чужим текстом", nkey, dict(narr_entry(nkey, nl["text"]), text_sha1=sha1(nl["text"] + " иначе"))))
        ncases.append(("закадровый файл не в своей папке", nkey, dict(narr_entry(nkey, nl["text"]), file=f"{nkey}.ogg",
                                                                      voice_sha1=sha1(api_text(nl)))))
    else:
        missed.append("нет ни одной закадровой фразы для самопроверки")
    if tkey:
        tl = lines[tkey]
        ncases.append(("мысль персонажа записана закадровым голосом", tkey,
                       dict(narr_entry(tl["key"], tl["text"]), voice_sha1=sha1(api_text(tl)), file=f"{tl['subdir']}/{tl['key']}.ogg")))
    else:
        missed.append("нет ни одной мысли персонажа (by_speaker) для самопроверки")
    for name, key, entry in ncases:
        m = copy.deepcopy(base)
        m["lines"][key] = entry
        errs, _ = check(lines, {"ru": m}, ncast, None, voice_cfg, scenes, strict=True, files=False)
        if not [x for x in errs if x.startswith(key)]:
            missed.append(name)
    # без --strict (tools/run_tests.sh): правка текста — предупреждение, не ошибка; подпись — ошибка и здесь
    if nkey:
        nl = lines[nkey]
        m = copy.deepcopy(base)
        m["lines"][nkey] = dict(narr_entry(nkey, nl["text"]), text_sha1=sha1(nl["text"] + " старый"), voice_sha1=sha1(api_text(nl)))
        errs, ws = check(lines, {"ru": m}, ncast, None, voice_cfg, scenes, strict=False, files=False)
        if [x for x in errs if x.startswith(nkey)] or not [w for w in ws if "к перезаписи" in w and nkey in w]:
            missed.append("правка текста роняет проверку или не попадает в список на перезапись")
    if label_key:
        m = copy.deepcopy(base)
        m["lines"][label_key] = narr_entry(label_key, str(texts[label_key][1].get("text", "")))
        errs, _ = check(lines, {"ru": m}, ncast, None, voice_cfg, scenes, strict=False, files=False)
        if not [x for x in errs if x.startswith(label_key)]:
            missed.append("закадровая запись подписи без --strict")
    if not check_narration_cfg({k: v for k, v in (voice_cfg or {}).items() if k != "narration"}, texts):
        missed.append("нет списка не озвучиваемых категорий")
    # первое лицо у закадрового голоса — ошибка; та же фраза в кавычках (цитата героя) — нет
    if nkey:
        fp_lines = copy.deepcopy(lines)
        fp_lines[nkey]["text"] = "Я ещё вернусь сюда."
        if not [x for x in check_first_person(fp_lines, ncfg) if x.startswith(nkey)]:
            missed.append("закадровый голос от первого лица")
        fp_lines[nkey]["text"] = "«Я ещё вернусь сюда», — говорит Тамара."
        if [x for x in check_first_person(fp_lines, ncfg) if x.startswith(nkey)]:
            missed.append("цитата героя в кавычках принята за первое лицо")
        # слова персонажа у закадрового голоса — ошибка (цитата с атрибуцией; «Имя: «…»»); надпись в кавычках — нет
        if not [x for x in check_character_speech(fp_lines, ncfg) if x.startswith(nkey)]:
            missed.append("цитата с атрибуцией у закадрового голоса")
        fp_lines[nkey]["text"] = "Тихон оглядывает полку: «Годится»."
        if not [x for x in check_character_speech(fp_lines, ncfg) if x.startswith(nkey)]:
            missed.append("«Имя …: «…»» у закадрового голоса")
        fp_lines[nkey]["text"] = "«Почта». На старой доске не раз подновляли буквы."
        if [x for x in check_character_speech(fp_lines, ncfg) if x.startswith(nkey)]:
            missed.append("надпись в кавычках принята за слова персонажа")
        talk = copy.deepcopy(lines)
        talk["Z9.npc.after"] = dict(lines[nkey], key="Z9.npc.after", text="Она кивает и молчит.")
        if not [x for x in check_character_speech(talk, ncfg) if x.startswith("Z9.npc.after")]:
            missed.append("ключ повторного разговора у закадрового голоса")
    # строка без текста в списке к озвучке (строка-выбор M13_1) — ошибка; варианты выбора — свои id
    empty = copy.deepcopy(lines)
    empty[first] = dict(empty[first], text="")
    if not check_empty(empty):
        missed.append("реплика без текста в списке к озвучке")
    # контроль: неиспорченная запись ошибок не даёт (иначе самопроверка ловила бы что угодно)
    m = copy.deepcopy(base)
    m["lines"][first] = dict(good)
    errs, _ = check(lines, {"ru": m}, test_cast, None, voice_cfg, scenes, strict=True, files=False)
    if [x for x in errs if x.startswith(first)]:
        missed.append("чистая запись даёт ошибку: " + "; ".join(errs[:2]))
    return missed


def check_main_takes(takes_man: dict | None, game_man: dict | None, takes_dir: Path = VOICE_SRC.parent / "ru_takes",
                     game_dir: Path = VOICE_SRC) -> list[str]:
    """I-T3 (вариант Б): дубль «в игре» — выбранный Директором (chosen_take основной записи, tools/apply_takes.py),
    иначе отмеченный конвейером main (ровно один); это тот же файл, что играет игра. Так же его подписывает страница
    прослушивания (tools/listen_page.py). Строка, текст которой с тех пор изменился (text_sha1 не тот), не проверяется."""
    import hashlib
    errs: list[str] = []
    glines = (game_man or {}).get("lines", {})
    for lid, e in sorted(((takes_man or {}).get("lines") or {}).items()):
        g = glines.get(lid)
        if not g or "stale" in g or g.get("text_sha1") != e.get("text_sha1"):
            continue
        mains = [t for t in e.get("takes", []) if t.get("main")]
        if g.get("chosen_take"):
            mains = [t for t in e.get("takes", []) if t.get("take") == g["chosen_take"]]
        if len(mains) != 1:
            errs.append(f"дубли {lid}: «в игре» отмечено {len(mains)} дублей, нужен один")
            continue
        a, b = takes_dir / str(mains[0].get("file", "")), game_dir / str(g.get("file", ""))
        if a.is_file() and b.is_file() and hashlib.sha1(a.read_bytes()).digest() != hashlib.sha1(b.read_bytes()).digest():
            errs.append(f"дубли {lid}: дубль {mains[0].get('take')} отмечен «в игре», а игра играет другой файл")
    return errs


def main() -> int:
    quiet = "--quiet" in sys.argv
    strict = "--strict" in sys.argv
    source_only = "--source-only" in sys.argv   # workflow озвучки: копии игры там нет (её делает tools/sync_voice.sh)
    voice_cfg = load(STORY / "voice.json")
    texts = all_texts()
    lines = story_lines()
    lines.update(narration_lines(narration_cfg(voice_cfg), texts))
    for lid, ln in lines.items():
        ln["id"] = lid   # правила произношения по репликам (pronounce.py)
    manifests = manifests_on_disk()
    cast = load(CAST)
    voices = load(VOICES)
    scenes = requested_scenes()
    narr_texts = requested_narration()
    errors, warns = check(lines, manifests, cast, voices, voice_cfg, scenes, strict, game_copy=not source_only,
                          narr_texts=narr_texts)
    errors += check_narration_cfg(voice_cfg, texts)
    errors += check_first_person(lines, narration_cfg(voice_cfg))
    errors += check_character_speech(lines, narration_cfg(voice_cfg))
    for t in sorted(narr_texts):
        if t not in {src for src, _ in texts.values()}:
            errors.append(f"запрос озвучки: narration.texts — нет data/story/text/{t}.json")
    tags_doc = load(TAGS)
    if tags_doc is None:
        errors.append("нет pipeline/voice/tags.json — список разрешённых тегов")
    errors += check_tags(lines, set(tags_doc.get("tags", {}).keys()) if tags_doc else None)
    errors += check_direction(lines, set(tags_doc.get("tags", {}).keys()) if tags_doc else None)
    errors += check_empty(lines)
    tagged = sum(1 for ln in lines.values() if ln.get("kind") != "narration" and (ln.get("tags") or ln.get("voice_text")))
    n_tagged = sum(1 for ln in lines.values() if ln.get("kind") == "narration" and (ln.get("tags") or ln.get("voice_text")))
    n_total = sum(1 for ln in lines.values() if ln.get("kind") == "narration")
    waiting = after_h59()
    if not AFTER_H59.is_file():
        errors.append(f"нет {AFTER_H59.relative_to(ROOT)} — список строк к перезаписи после H59")
    # H59/T7: в голос идёт только слово подсказки — ни «[[», ни «|значение]]» в тексте запроса к TTS
    errors += [f"{lid}: в тексте для голоса осталась разметка подсказки: «{api_text(dict(ln, id=lid))[:80]}»"
               for lid, ln in sorted(lines.items()) if "[[" in api_text(dict(ln, id=lid)) or "]]" in api_text(dict(ln, id=lid))]
    l_err, l_warn = check_speaker_loudness(manifests, waiting)
    errors += l_err
    warns += l_warn
    errors += check_ask_prompts(voice_cfg, texts)
    errors += check_main_takes(load(VOICE_SRC.parent / "ru_takes" / "manifest.json"), manifests.get("ru"))
    missed = selftest(lines, cast, voice_cfg, scenes)
    # самопроверка H5/H4: шёпот вне списка ожидания и вопрос персонажа без ограничения повтора — ошибки
    _sp = {"lines": {f"T_{i}": {"speaker": "tst", "source_lufs": -16.0} for i in range(5)}}
    _sp["lines"]["T_q"] = {"speaker": "tst", "source_lufs": -24.0}
    if (not check_speaker_loudness({"ru": _sp}, {}, (set(), -6.0))[0]
            or check_speaker_loudness({"ru": _sp}, {"T_q": "H59"}, (set(), -6.0))[0]):
        missed.append("тихая подача персонажа (H5) не поймана или список ожидания не понят")
    # нарочно тихая (voice.json → soft_lines): −5 LU можно, −8 LU — нет
    _sp["lines"]["T_s"] = {"speaker": "tst", "source_lufs": -21.0}
    if (not check_speaker_loudness({"ru": _sp}, {}, ({"T_q", "T_s"}, -6.0))[0]
            or any("T_s" in e for e in check_speaker_loudness({"ru": _sp}, {}, ({"T_q", "T_s"}, -6.0))[0])):
        missed.append("нарочно тихая реплика: предел −6 LU не понят")
    # нарочно громкая (voice.json → loud_lines, I-T5): +5 LU можно, +8 LU — нет
    _sp["lines"]["T_l"] = {"speaker": "tst", "source_lufs": -11.0}
    _sp["lines"]["T_x"] = {"speaker": "tst", "source_lufs": -8.0}
    _le = check_speaker_loudness({"ru": _sp}, {}, ({"T_q", "T_s"}, -6.0), ({"T_l", "T_x"}, 6.0))[0]
    if any("T_l" in e for e in _le) or not any("T_x" in e for e in _le):
        missed.append("нарочно громкая реплика: предел +6 LU не понят")
    _vc = copy.deepcopy(voice_cfg or {})
    _vc.setdefault("narration", {}).setdefault("ask_prompts", {})["keys"] = []
    if not any("ask_prompts.keys" in e for e in check_ask_prompts(_vc, texts)):
        missed.append("вопрос персонажа без ограничения повтора (H4) не пойман")
    # I-T3: два дубля «в игре» у одной строки — ошибка
    _tm = {"lines": {"T_t": {"text_sha1": "a", "takes": [{"take": 1, "main": True}, {"take": 2, "main": True}]}}}
    if not check_main_takes(_tm, {"lines": {"T_t": {"text_sha1": "a"}}}):
        missed.append("два дубля «в игре» у одной строки")
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
              f"персонажей в cast.json: {len((cast or {}).get('cast', {}))}; реплик с тегами: {tagged}; "
              f"закадровых фраз по правилам voice.json: {n_total} (с тегами {n_tagged}), заказаны тексты: "
              f"{', '.join(sorted(narr_texts)) or '—'}")
    print(f"[voice] validate_voice.py: {'OK' if not errors else 'FAIL'} ({len(errors)} ошибок, {len(warns)} предупреждений"
          f"{', strict' if strict else ''}; самопроверка {SELFTEST_CASES - len(missed)}/{SELFTEST_CASES})")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
