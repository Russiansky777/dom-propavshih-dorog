#!/usr/bin/env python3
"""Озвучка реплик через ElevenLabs (stdlib Python + ffmpeg). Запускается в GitHub Actions (pipeline_voice.yml).

Контракт API сверен с elevenlabs.io/docs 17.10.2026 (выжимка и ссылки — pipeline/voice/README.md):
  GET  /v2/voices?page_size=100&next_page_token=…[&voice_type=personal]   voices[].voice_id/name/category/labels
  POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128          {text, model_id, language_code, voice_settings, seed}
  GET  /v1/user/subscription                                               character_count / character_limit / tier
  Заголовок ключа: xi-api-key. Ключ — переменная окружения ELEVEN_API (секрет репозитория Eleven_API).

Режимы:
  check                       ключ доходит? (печатается только наличие/длина/формат, не ключ) + баланс
  list                        голоса аккаунта → pipeline/voice/voices.json
  generate --request <файл>   реплики сцен из запроса → assets/voice/ru/<scene>_<index>.ogg + manifest.json;
                              закадровые фразы ("narration": {"texts": [...]}) → assets/voice/ru/narrator/<ключ>.ogg
           [--dry-run]        только список реплик и число символов, без запросов к API
  запрос с "only_changed": true  перезапись после правки текста: всё, что изменилось (sha1), одним запросом —
                              pipeline/voice/rerecord_template.json, pipeline/voice/README.md → «Текст изменился»
  design --request <файл>     Voice Design: превью новых голосов по описанию → pipeline/voice/design/<персонаж>/
  create_voice --request <ф>  выбранное превью → голос в My Voices (voice_id в design/<персонаж>.json) + список голосов
  say --request <файл>        пробные фразы с выравниванием по символам → pipeline/voice/probe/<набор>/ (ударение)
  run --request <файл>        режим берётся из поля "mode" запроса (так запускает workflow)

Идентификатор реплики: <scene>_<index>, index — позиция в mandatory_lines сцены (для заданий — lines), как её
показывает StoryRunner (beat.line_id). Контекстная реплика (поле context — вариант вопроса) озвучивает только text.
Закадровая фраза (голос narrator): id — ключ текста data/story/text/*.json (H1.stove.look, item.key_house); какие ключи
озвучиваются — правила data/story/voice.json → narration (их же применяют игра и tools/validate_voice.py); ключи, на
которые не ссылаются данные игры, пропускаются (кредиты не тратятся на текст, который никогда не покажется).
Повторный запуск тратит кредиты только на новые/изменённые реплики: sha1 текста, голос, модель и настройки
сравниваются с манифестом; ответ API хранится в src/<id>.mp3, поэтому переобработка громкости бесплатна.
"""
from __future__ import annotations

import argparse
import base64
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pronounce  # noqa: E402  (правила произношения — общий модуль с tools/validate_voice.py)

ROOT = Path(__file__).resolve().parents[2]
API = "https://api.elevenlabs.io"
VOICE_DIR = ROOT / "pipeline" / "voice"
CAST_PATH = VOICE_DIR / "cast.json"
VOICES_PATH = VOICE_DIR / "voices.json"
STATE_DIR = VOICE_DIR / "state"
OUT_DIR = ROOT / "assets" / "voice" / "ru"
ALT_ROOT = ROOT / "assets" / "voice" / "ru_alt"   # альтернативные голоса персонажа: ru_alt/<персонаж>_<вариант>/
SCENES_DIR = ROOT / "data" / "story" / "scenes"
QUESTS_PATH = ROOT / "data" / "story" / "quests.json"
META_PATH = ROOT / "data" / "story" / "meta.json"
STORY_DIR = ROOT / "data" / "story"
TEXT_DIR = STORY_DIR / "text"
ITEMS_PATH = STORY_DIR / "items.json"
VOICE_CFG_PATH = STORY_DIR / "voice.json"

PROBE_MAX_LINES = 40          # пока text_freeze=false — только проба (решение Директора 17.10)
ORDER_KEYS = ("by", "date", "what", "max_lines", "max_chars")   # явное задание Директора на объём сверх пробы
RETRY_STATUSES = (429, 500, 502, 503, 504)
OPTIONAL_BODY_KEYS = ("language_code", "seed")
TIMEOUT_S = 120


class VoiceError(RuntimeError):
    pass


def log(msg: str) -> None:
    print(msg, flush=True)


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def read_json(p: Path, default=None):
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8"))


def write_json(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def text_sha1(text: str) -> str:
    # Тот же хеш считает игра: String.sha1_text() (UTF-8) в voice_director.gd.
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


# --- Сценарий ---------------------------------------------------------------------------------

def story_lines() -> dict[str, dict]:
    """Все реплики сцен и заданий: id → {scene, index, speaker, text[, context]} в порядке файлов."""
    out: dict[str, dict] = {}

    def add(scene_id: str, lines: list) -> None:
        for i, ln in enumerate(lines or []):
            lid = f"{scene_id}_{i}"
            # Выбор внутри разговора (M13: что Агата отвечает Павлу): StoryRunner показывает не text строки, а слова
            # выбранного варианта — line_id <scene>_<index>_<вариант>, говорящий — speaker строки (по умолчанию Агата).
            for o in ln.get("options") or []:
                if str(o.get("text", "")).strip():
                    oe = {"scene": scene_id, "index": i, "option": str(o["id"]),
                          "speaker": str(ln.get("speaker", "agata") or "agata"), "text": str(o["text"])}
                    if o.get("tags"):
                        oe["tags"] = [str(t) for t in o["tags"]]
                    if o.get("voice_text"):
                        oe["voice_text"] = str(o["voice_text"])
                    out[f"{lid}_{o['id']}"] = oe
            if ln.get("options") or not str(ln.get("text", "")).strip():
                continue   # строка-выбор (вопрос — закадровая фраза prompt) или без текста: звучать нечему
            e = {"scene": scene_id, "index": i, "speaker": str(ln.get("speaker", "")), "text": str(ln.get("text", ""))}
            if ln.get("context"):
                e["context"] = str(ln["context"])
            if ln.get("tags"):
                e["tags"] = [str(t) for t in ln["tags"]]
            if ln.get("voice_text"):
                e["voice_text"] = str(ln["voice_text"])
            out[lid] = e

    for f in sorted(SCENES_DIR.glob("E*.json")):
        for sc in read_json(f, {}).get("scenes", []):
            add(str(sc["id"]), sc.get("mandatory_lines", []))
    for q in read_json(QUESTS_PATH, {}).get("quests", []):
        add(str(q["id"]), q.get("mandatory_lines", q.get("lines", [])))
    return out


# --- Закадровые фразы (narration) --------------------------------------------------------------

def narration_cfg() -> dict:
    return (read_json(VOICE_CFG_PATH, {}) or {}).get("narration", {}) or {}


def narration_key_ok(key: str, cfg: dict) -> bool:
    """Ключ текста озвучивается закадровым голосом: не служебная секция, не подпись/вариант/деталь загадки
    (data/story/voice.json → narration.skip_sections / skip_fields / skip_keys; то же правило — voice_director.gd)."""
    parts = key.split(".")
    if len(parts) < 2 or not cfg:
        return False
    if parts[0] in cfg.get("skip_sections", []) or key in cfg.get("skip_keys", []):
        return False
    return not any(fnmatch.fnmatchcase(parts[-1], str(p)) for p in cfg.get("skip_fields", []))


def referenced_keys() -> set[str]:
    """Ключи @…, на которые ссылаются данные игры (комнаты, сцены, задания, предметы, план), + item.<id> каждого
    предмета сумки (InventoryBag берёт строку item.<id> по id предмета)."""
    refs: set[str] = set()

    def walk(o) -> None:
        if isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
        elif isinstance(o, str) and o.startswith("@"):
            refs.add(o[1:])

    for f in sorted(STORY_DIR.rglob("*.json")):
        if TEXT_DIR in f.parents:
            continue
        walk(read_json(f, {}))
    items = (read_json(ITEMS_PATH, {}) or {}).get("items", [])
    for it in (items if isinstance(items, list) else [dict(v, id=k) for k, v in items.items()]):
        if it.get("inventory"):
            refs.add(f"item.{it['id']}")
    return refs


def narration_by_speaker(cfg: dict) -> dict[str, dict]:
    """voice.json → narration.by_speaker: персонаж → {subdir, keys, tags, hold} (мысли Агаты от первого лица)."""
    return {str(sp): v for sp, v in (cfg.get("by_speaker") or {}).items() if not str(sp).startswith("_") and isinstance(v, dict)}


def narration_lines() -> dict[str, dict]:
    """Закадровые фразы: id → {kind: narration, key, speaker, text, source (имя файла текста), used, assigned,
    subdir[, tags, profile, hold]}. Закадровая запись (id = ключ) есть у каждого озвучиваемого ключа — для ключей,
    назначенных персонажу (by_speaker), она запасная (assigned = false); запись персонажа — id <персонаж>:<ключ>."""
    cfg = narration_cfg()
    speaker = str(cfg.get("speaker", "narrator"))
    refs = referenced_keys() if cfg else set()
    by_sp = narration_by_speaker(cfg)
    owner = {str(k): sp for sp, v in by_sp.items() for k in v.get("keys", [])}
    out: dict[str, dict] = {}
    for f in sorted(TEXT_DIR.glob("*.json")):
        for k, v in (read_json(f, {}) or {}).get("texts", {}).items():
            k = str(k)
            if not narration_key_ok(k, cfg):
                continue
            ln_spec = v.get("line") if isinstance(v.get("line"), dict) else None
            e = {"kind": "narration", "key": k, "scene": "", "index": 0, "speaker": speaker,
                 "text": str(v.get("text", "")), "source": f.stem, "used": k in refs,
                 "assigned": k not in owner and ln_spec is None, "subdir": str(cfg.get("subdir", "narrator"))}
            if v.get("tags"):
                e["tags"] = [str(t) for t in v["tags"]]
            if v.get("voice_text"):
                e["voice_text"] = str(v["voice_text"])
            out[k] = e
            if ln_spec is not None and ln_spec.get("speaker") and ln_spec.get("text"):
                # Реплика персонажа рядом с Агатой (поле line): его голос, настройки его реплик, текст прямой речи.
                sp = str(ln_spec["speaker"])
                ce = {"kind": "narration", "key": k, "scene": "", "index": 0, "speaker": sp, "text": str(ln_spec["text"]),
                      "source": f.stem, "used": e["used"], "assigned": True, "as_line": True,
                      "subdir": str((cfg.get("character_lines") or {}).get("subdir", "character_lines"))}
                if ln_spec.get("tags"):
                    ce["tags"] = [str(t) for t in ln_spec["tags"]]
                out[f"{sp}:{k}"] = ce
                continue
            if k in owner:
                sp = owner[k]
                bs = by_sp[sp]
                pe = {"kind": "narration", "key": k, "scene": "", "index": 0, "speaker": sp, "text": e["text"],
                      "source": f.stem, "used": e["used"], "assigned": True, "subdir": str(bs.get("subdir", sp)),
                      "profile": "inner", "hold": k in [str(x) for x in bs.get("hold", [])]}
                tags = (bs.get("tags") or {}).get(k)
                if tags:
                    pe["tags"] = [str(t) for t in tags]
                out[f"{sp}:{k}"] = pe
    return out


def all_lines() -> dict[str, dict]:
    """Реплики сцен (<scene>_<index>) и закадровые фразы (ключ текста) — всё, что может звучать в игре."""
    out = story_lines()
    out.update(narration_lines())
    for lid, ln in out.items():
        ln["id"] = lid   # правила произношения могут относиться к отдельным репликам (pronounce.py, поле lines)
    return out


def file_rel(ln: dict, lid: str, ext: str) -> str:
    """Путь файла относительно набора: <id>.<ext> для реплик, <subdir>/<ключ>.<ext> для закадровых фраз
    (narrator/… — закадровый голос, agata_thoughts/… — мысли Агаты)."""
    if ln.get("kind") == "narration":
        return f"{ln.get('subdir') or narration_cfg().get('subdir', 'narrator')}/{ln.get('key', lid)}.{ext}"
    return f"{lid}.{ext}"


TAG_IN_TEXT = re.compile(r"\[[^\[\]]+\]")


def api_text(ln: dict) -> str:
    """Текст запроса к API: voice_text (теги внутри фразы) или теги перед текстом; субтитры — text без тегов.
    Произношение (pipeline/voice/pronunciation_ru.json, pronounce.py) — только здесь, не в субтитрах."""
    if ln.get("voice_text"):
        return pronounce.apply(str(ln["voice_text"]), str(ln.get("id", "")))
    return "".join(f"[{t}] " for t in ln.get("tags", [])) + pronounce.apply(str(ln["text"]), str(ln.get("id", "")))


# --- Ключ и HTTP ---------------------------------------------------------------------------------

def api_key() -> str:
    raw = (os.environ.get("ELEVEN_API") or os.environ.get("ELEVENLABS_API_KEY") or "").strip()
    if not raw:
        raise VoiceError("ключ не дошёл: переменная ELEVEN_API пуста (секрет Eleven_API не задан или не передан в шаг)")
    m = re.search(r"sk_[A-Za-z0-9]{20,}", raw)
    return m.group(0) if m else raw.strip().strip('"').strip("'")


def key_report() -> dict:
    raw = (os.environ.get("ELEVEN_API") or os.environ.get("ELEVENLABS_API_KEY") or "")
    k = api_key() if raw.strip() else ""
    return {"present": bool(k), "length": len(k), "looks_like_sk": k.startswith("sk_"),
            "trimmed_from_wrapper": bool(k) and k != raw.strip()}


def http(method: str, path: str, params: dict | None = None, body: dict | None = None,
         accept: str = "application/json", retry_on_disconnect: bool = True) -> tuple[int, dict, bytes]:
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    headers = {"xi-api-key": api_key(), "Accept": accept}
    if data is not None:
        headers["Content-Type"] = "application/json"
    disconnect_retries = 1 if retry_on_disconnect else 0
    for attempt in range(5):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
                return r.status, {k.lower(): v for k, v in r.headers.items()}, r.read()
        except urllib.error.HTTPError as e:
            payload = e.read()
            if e.code in RETRY_STATUSES and attempt < 4:
                wait = 2 ** (attempt + 1)
                log(f"  {method} {path}: HTTP {e.code}, повтор через {wait} с")
                time.sleep(wait)
                continue
            return e.code, {k.lower(): v for k, v in e.headers.items()}, payload
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if disconnect_retries > 0:
                disconnect_retries -= 1
                log(f"  {method} {path}: обрыв связи ({e}); один повтор — возможно двойное списание за эту реплику")
                time.sleep(5)
                continue
            raise VoiceError(f"{method} {path}: нет связи с API: {e}") from e
    raise VoiceError(f"{method} {path}: исчерпаны повторы")


def error_text(status: int, payload: bytes) -> str:
    try:
        d = json.loads(payload.decode("utf-8"))
        return f"HTTP {status}: {json.dumps(d.get('detail', d), ensure_ascii=False)[:600]}"
    except Exception:
        return f"HTTP {status}: {payload[:300]!r}"


def get_json(path: str, params: dict | None = None) -> dict:
    st, _, payload = http("GET", path, params)
    if st != 200:
        raise VoiceError(f"GET {path}: {error_text(st, payload)}")
    return json.loads(payload.decode("utf-8"))


def subscription() -> dict | None:
    """Баланс символов; None, если ключу не разрешено читать пользователя (это не ошибка конвейера)."""
    st, _, payload = http("GET", "/v1/user/subscription")
    if st != 200:
        log(f"  баланс недоступен ({error_text(st, payload)}) — кредиты посчитаем по символам текста")
        return None
    d = json.loads(payload.decode("utf-8"))
    return {k: d.get(k) for k in ("tier", "status", "character_count", "character_limit", "next_character_count_reset_unix")}


# --- check / list ----------------------------------------------------------------------------------

def cmd_check() -> int:
    kr = key_report()
    log(f"ключ: {'есть' if kr['present'] else 'НЕТ'}, длина {kr['length']}, формат sk_…: {'да' if kr['looks_like_sk'] else 'нет'}"
        + (", вырезан из обёртки" if kr["trimmed_from_wrapper"] else ""))
    if not kr["present"]:
        return 1
    sub = subscription()
    if sub:
        log(f"план: {sub.get('tier')} ({sub.get('status')}), израсходовано {sub.get('character_count')} из {sub.get('character_limit')} символов")
    st, _, payload = http("GET", "/v2/voices", {"page_size": 1})
    if st != 200:
        log(f"голоса: {error_text(st, payload)}")
        return 1
    log("ключ принят API (GET /v2/voices → 200)")
    return 0


def _all_voices(extra: dict | None = None) -> list[dict]:
    out: list[dict] = []
    token = None
    for _ in range(50):
        params = {"page_size": 100, "include_total_count": "true"}
        if extra:
            params.update(extra)
        if token:
            params["next_page_token"] = token
        d = get_json("/v2/voices", params)
        out += d.get("voices", [])
        if not d.get("has_more") or not d.get("next_page_token"):
            break
        token = d["next_page_token"]
    return out


def cmd_list() -> int:
    if cmd_check() != 0:
        return 1
    voices = _all_voices()
    order: dict[str, int] = {}
    try:
        mine = _all_voices({"voice_type": "personal", "sort": "created_at_unix", "sort_direction": "asc"})
        personal = {v["voice_id"] for v in mine}
        order = {v["voice_id"]: i + 1 for i, v in enumerate(mine)}   # 1 — создан первым
    except VoiceError as e:
        log(f"  voice_type=personal не принят ({e}); отметка «мой голос» — по категории")
        personal = {v["voice_id"] for v in voices if v.get("category") in ("cloned", "generated", "professional")}
    rows = []
    for v in voices:
        desc = (v.get("description") or "").strip()
        row = {"name": v.get("name", ""), "voice_id": v.get("voice_id", ""), "category": v.get("category", ""),
               "personal": v.get("voice_id") in personal, "labels": v.get("labels") or {},
               "description": desc[:240]}
        created = v.get("created_at_unix")
        if isinstance(created, (int, float)) and created > 0:
            row["created_at_unix"] = int(created)
            row["created_at"] = datetime.fromtimestamp(int(created), timezone.utc).isoformat()
        if row["voice_id"] in order:
            row["created_order"] = order[row["voice_id"]]
        rows.append(row)
    rows.sort(key=lambda r: (not r["personal"], r["category"], r["name"].lower()))
    write_json(VOICES_PATH, {
        "_comment": "Голоса аккаунта ElevenLabs (GET /v2/voices; personal — раздел My Voices, voice_type=personal). "
                    "Пишет pipeline/voice/eleven_voice.py list; ключа здесь нет. Сопоставление с персонажами — cast.json.",
        "fetched_at": now_iso(), "count": len(rows), "personal_count": sum(r["personal"] for r in rows), "voices": rows})
    log(f"голосов: {len(rows)}, из них моих (My Voices): {sum(r['personal'] for r in rows)} → {VOICES_PATH.relative_to(ROOT)}")
    for r in rows:
        if r["personal"]:
            log(f"  [мой] {r['name']!r:32} {r['voice_id']}  {r['category']}  создан: {r.get('created_at', '?')} "
                f"(по порядку {r.get('created_order', '?')})  {json.dumps(r['labels'], ensure_ascii=False)}")
    return 0


# --- Voice Design: новый голос по описанию ------------------------------------------------------------
# Документация (сверено 23.10.2026): https://elevenlabs.io/docs/api-reference/text-to-voice/design —
#   POST /v1/text-to-voice/design?output_format=…  {voice_description 20–1000, model_id eleven_ttv_v3 |
#   eleven_multilingual_ttv_v2, text 100–1000, guidance_scale 0–100, quality −1…1, loudness −1…1, seed, should_enhance}
#   → previews[] {generated_voice_id, audio_base_64, media_type, duration_secs, language}, text;
# https://elevenlabs.io/docs/api-reference/text-to-voice/create —
#   POST /v1/text-to-voice {voice_name, voice_description, generated_voice_id, labels?, played_not_selected_voice_ids?}
#   → voice_id (голос в My Voices). Списание — только символы текста превью, один раз за три варианта
#   (https://elevenlabs.io/docs/eleven-creative/voices/voice-design.md).
DESIGN_DIR = VOICE_DIR / "design"
DESIGN_KEYS = ("guidance_scale", "quality", "loudness", "seed", "should_enhance")


def cmd_design(req_path: Path) -> int:
    """Режим design: превью голосов по описанию → pipeline/voice/design/<персонаж>/preview_<n>.mp3 и <персонаж>.json."""
    req = read_json(req_path, {})
    fmt = str(req.get("output_format", "mp3_44100_192"))
    model = str(req.get("model_id", "eleven_ttv_v3"))
    voices = [v for v in req.get("voices", []) if v.get("speaker")]
    if not voices:
        raise VoiceError("design: нет voices[]")
    for v in voices:
        d, t = str(v.get("description", "")), str(v.get("text", ""))
        if not 20 <= len(d) <= 1000:
            raise VoiceError(f"design {v['speaker']}: description {len(d)} символов, нужно 20–1000")
        if not 100 <= len(t) <= 1000:
            raise VoiceError(f"design {v['speaker']}: text {len(t)} символов, нужно 100–1000")
    sub_before = subscription()
    failed = []
    for v in voices:
        sp = str(v["speaker"])
        body = {"voice_description": str(v["description"]), "model_id": str(v.get("model_id", model)), "text": str(v["text"]),
                "auto_generate_text": False}
        body.update({k: v[k] for k in DESIGN_KEYS if k in v})
        log(f"  design {sp}: {body['model_id']}, {fmt}, текст {len(body['text'])} символов, "
            + ", ".join(f"{k}={body[k]}" for k in DESIGN_KEYS if k in body))
        st, hdr, payload = http("POST", "/v1/text-to-voice/design", {"output_format": fmt}, body, retry_on_disconnect=False)
        # 400/422 с именем параметра (так API отвечает, например, «Quality parameter is only supported for
        # eleven_multilingual_ttv_v2») — повтор без него
        rejected = [k for k in DESIGN_KEYS if k in body and st in (400, 422) and k in error_text(st, payload).lower()]
        if rejected:
            # отклонённый запрос кредитов не списывает; что убрано — в журнал и в design/<персонаж>.json
            log(f"    {error_text(st, payload)} — повтор без {', '.join(rejected)}")
            for k in rejected:
                body.pop(k)
            st, hdr, payload = http("POST", "/v1/text-to-voice/design", {"output_format": fmt}, body, retry_on_disconnect=False)
        if st != 200:
            failed.append(f"{sp}: {error_text(st, payload)}")
            log(f"  ОШИБКА design {sp}: {error_text(st, payload)}")
            continue
        d = json.loads(payload.decode("utf-8"))
        out_dir = DESIGN_DIR / sp
        out_dir.mkdir(parents=True, exist_ok=True)
        previews = []
        for n, p in enumerate(d.get("previews", []), 1):
            f = out_dir / f"preview_{n}.mp3"
            f.write_bytes(base64.b64decode(p.get("audio_base_64", "")))
            row = {"n": n, "generated_voice_id": p.get("generated_voice_id", ""), "file": f"{sp}/{f.name}",
                   "media_type": p.get("media_type", ""), "duration_secs": p.get("duration_secs"), "language": p.get("language", "")}
            try:
                i_lufs, tp = measure(f)
                row.update({"lufs": round(i_lufs, 2), "true_peak_db": round(tp, 2), "duration_s": duration_s(f)})
            except VoiceError as e:
                row["measure_error"] = str(e)[:200]
            previews.append(row)
            log(f"    вариант {n}: {row['generated_voice_id']}  {row.get('duration_s', '?')} с  язык {row['language']}  "
                f"{row.get('lufs', '?')} LUFS  TP {row.get('true_peak_db', '?')}")
        doc = read_json(DESIGN_DIR / f"{sp}.json", {}) or {}
        doc.update({"speaker": sp, "voice_name": v.get("voice_name", ""), "request": dict(body, output_format=fmt),
                    "dropped_params": rejected,
                    "designed_at": now_iso(), "run": os.environ.get("GITHUB_RUN_ID", "local"),
                    "request_id": hdr.get("request-id", ""), "character_cost": hdr.get("character-cost", ""),
                    "preview_text": d.get("text", body["text"]), "previews": previews})
        write_json(DESIGN_DIR / f"{sp}.json", doc)
    sub_after = subscription()
    if sub_before and sub_after and sub_before.get("character_count") is not None and sub_after.get("character_count") is not None:
        log(f"  design: изменение счётчика подписки {int(sub_after['character_count']) - int(sub_before['character_count'])} "
            f"(счётчик обновляется с задержкой)")
    return 1 if failed else 0


def cmd_create_voice(req_path: Path) -> int:
    """Режим create_voice: выбранное превью → голос в My Voices (voice_id в pipeline/voice/design/<персонаж>.json),
    затем список голосов (voices.json) — для cast.json и tools/validate_voice.py."""
    req = read_json(req_path, {})
    failed = []
    for v in req.get("voices", []):
        sp = str(v.get("speaker", ""))
        doc = read_json(DESIGN_DIR / f"{sp}.json", {}) or {}
        gid = str(v.get("generated_voice_id", ""))
        known = {str(p.get("generated_voice_id")) for p in doc.get("previews", [])}
        if not sp or not gid or gid not in known:
            failed.append(f"{sp}: generated_voice_id {gid!r} не из превью design/{sp}.json")
            log(f"  ОШИБКА create {sp}: generated_voice_id не из превью")
            continue
        if (doc.get("created") or {}).get("generated_voice_id") == gid and (doc.get("created") or {}).get("voice_id"):
            log(f"  create {sp}: уже создан — {doc['created']['voice_id']}")
            continue
        body = {"voice_name": str(v.get("voice_name") or doc.get("voice_name") or sp),
                "voice_description": str(v.get("description") or doc.get("request", {}).get("voice_description", ""))[:1000],
                "generated_voice_id": gid}
        if v.get("labels"):
            body["labels"] = v["labels"]
        others = [g for g in known if g != gid]
        if others:
            body["played_not_selected_voice_ids"] = others
        st, _, payload = http("POST", "/v1/text-to-voice", None, body, retry_on_disconnect=False)
        if st in (400, 422) and "labels" in body:
            log(f"    {error_text(st, payload)} — повтор без labels")
            body.pop("labels")
            st, _, payload = http("POST", "/v1/text-to-voice", None, body, retry_on_disconnect=False)
        if st != 200:
            failed.append(f"{sp}: {error_text(st, payload)}")
            log(f"  ОШИБКА create {sp}: {error_text(st, payload)}")
            continue
        d = json.loads(payload.decode("utf-8"))
        doc["created"] = {"voice_id": d.get("voice_id", ""), "name": d.get("name", body["voice_name"]),
                          "generated_voice_id": gid, "category": d.get("category", ""), "at": now_iso(),
                          "run": os.environ.get("GITHUB_RUN_ID", "local"), "selection": v.get("selection", "")}
        write_json(DESIGN_DIR / f"{sp}.json", doc)
        log(f"  создан голос {sp}: {doc['created']['name']!r} → {doc['created']['voice_id']} ({doc['created']['category']})")
    rc = cmd_list()
    return 1 if failed or rc else 0


PROBE_DIR = VOICE_DIR / "probe"


def cmd_say(req_path: Path) -> int:
    """Режим say: короткие пробные фразы (не реплики игры) голосом персонажа с выравниванием по символам →
    pipeline/voice/probe/<набор>/<id>.mp3 и <id>.json. Для проверки способов задать ударение (pronounce.py) —
    tools/voice_stress_check.py --probe <набор>. Потолок символов — поле max_chars запроса."""
    req = read_json(req_path, {})
    set_name = str(req.get("set", req_path.stem))
    cast = dict(read_json(CAST_PATH, {}) or {})
    cast["timestamps"] = True
    items = [it for it in req.get("items", []) if it.get("id") and it.get("text")]
    chars = sum(len(str(it["text"])) for it in items)
    if chars > int(req.get("max_chars", 0)):
        raise VoiceError(f"say: {chars} символов > max_chars {req.get('max_chars')}")
    sub_before = subscription()
    if sub_before and sub_before.get("character_limit"):
        reserve = float((cast.get("quota") or {}).get("margin_fraction", 0.10)) * int(sub_before["character_limit"])
        if chars > int(sub_before["character_limit"]) - int(sub_before["character_count"]) - reserve:
            raise VoiceError("say: не помещается в остаток квоты с запасом")
    out = PROBE_DIR / set_name
    out.mkdir(parents=True, exist_ok=True)
    failed, spent = [], 0
    for it in items:
        sp = str(it.get("speaker", "narrator"))
        spec = cast_for(cast, sp, None, str(it.get("profile", "")))
        text = str(it["text"])
        seed = int(hashlib.sha1(f"probe|{it['id']}".encode("utf-8")).hexdigest()[:8], 16)
        try:
            audio, info = synth(text, spec, cast, seed)
        except VoiceError as e:
            failed.append(f"{it['id']}: {e}")
            log(f"  ОШИБКА {it['id']}: {e}")
            continue
        f = out / f"{it['id']}.mp3"
        f.write_bytes(audio)
        cc = str(info.get("character_cost", ""))
        spent += int(cc) if cc.isdigit() else len(text)
        write_json(out / f"{it['id']}.json", {"id": it["id"], "speaker": sp, "voice_name": spec["voice_name"],
                                               "model_id": spec["model_id"], "text": text, "duration_s": duration_s(f),
                                               "character_cost": cc, "alignment": info.get("alignment"),
                                               "expect": it.get("expect"), "variant": it.get("variant", ""),
                                               "run": os.environ.get("GITHUB_RUN_ID", "local")})
        log(f"  {it['id']:28} {duration_s(f):5.2f} с  выравнивание: {'есть' if info.get('alignment') else 'нет'}  {text}")
    log(f"[say {set_name}] фраз {len(items) - len(failed)}, ошибок {len(failed)}, символов {chars}, кредитов {spent}")
    return 1 if failed else 0


# --- Обработка звука (ffmpeg) ---------------------------------------------------------------------

def _ffmpeg(args: list[str]) -> str:
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-y"] + args, capture_output=True, text=True)
    if p.returncode != 0:
        raise VoiceError("ffmpeg: " + p.stderr[-800:])
    return p.stderr


def _loudness(stderr: str) -> tuple[float, float]:
    """(integrated LUFS, true peak dBFS) из сводки фильтра ebur128."""
    summary = stderr[stderr.rfind("Summary:"):] if "Summary:" in stderr else stderr
    mi = re.search(r"I:\s+(-?[\d.]+|-inf) LUFS", summary)
    mp = re.search(r"True peak:\s+Peak:\s+(-?[\d.]+|-inf) dBFS", summary)
    i = float(mi.group(1)) if mi and mi.group(1) != "-inf" else float("-inf")
    tp = float(mp.group(1)) if mp and mp.group(1) != "-inf" else float("-inf")
    return i, tp


def _trim_chain(lc: dict) -> str:
    thr = float(lc.get("trim_threshold_db", -50.0))
    head = float(lc.get("keep_head_s", 0.04))
    tail = float(lc.get("keep_tail_s", 0.12))
    return (f"aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=mono,"
            f"silenceremove=start_periods=1:start_threshold={thr}dB:start_silence={head},areverse,"
            f"silenceremove=start_periods=1:start_threshold={thr}dB:start_silence={tail},areverse")


# Громкость «как слышит игрок»: моно-файл Godot играет на оба канала — меряем стерео-дубль (EBU R128).
AS_PLAYED = "pan=stereo|c0=c0|c1=c0,ebur128=peak=true"


def measure(path: Path, pre: str = "") -> tuple[float, float]:
    chain = (pre + "," if pre else "") + AS_PLAYED
    return _loudness(_ffmpeg(["-i", str(path), "-af", chain, "-f", "null", "-"]))


def duration_s(path: Path) -> float:
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)],
                       capture_output=True, text=True)
    try:
        return round(float(p.stdout.strip()), 3)
    except ValueError:
        return 0.0


def vorbis_quality(lc: dict) -> int:
    """Качество кодирования OGG Vorbis (cast.json → loudness.vorbis_quality; до 23.10 — 5)."""
    return int(lc.get("vorbis_quality", 5))


def process(src: Path, dst: Path, lc: dict) -> dict:
    """src (ответ API) → dst OGG: срез тишины, линейное усиление к target_lufs, ограничитель, фейды."""
    target = float(lc.get("target_lufs", -17.0))
    limit_db = float(lc.get("limiter_db", -2.0))
    trim = _trim_chain(lc)
    src_i, src_tp = measure(src, trim)
    if src_i == float("-inf"):
        raise VoiceError(f"{src.name}: после среза тишины не осталось звука")
    gain = round(target - src_i, 2)
    lim = 10 ** (limit_db / 20.0)
    chain = (f"{trim},volume={gain}dB,alimiter=limit={lim:.4f}:level=0:attack=5:release=60,"
             f"afade=t=in:d=0.008,areverse,afade=t=in:d=0.03,areverse")
    dst.parent.mkdir(parents=True, exist_ok=True)
    vq = vorbis_quality(lc)
    _ffmpeg(["-i", str(src), "-af", chain, "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", str(vq), str(dst)])
    out_i, out_tp = measure(dst)
    return {"duration_s": duration_s(dst), "lufs": round(out_i, 2), "true_peak_db": round(out_tp, 2),
            "gain_db": gain, "source_lufs": round(src_i, 2), "source_true_peak_db": round(src_tp, 2), "vorbis_q": vq}


# --- generate ----------------------------------------------------------------------------------------

def cast_for(cast: dict, speaker: str, alt: dict | None = None, profile: str = "") -> dict:
    """Голос персонажа: основной (cast.<id>) или альтернативный (cast.<id>.alternates.<вариант>) поверх основного;
    profile "inner" — подача мыслей (cast.<id>.inner_voice.voice_settings поверх настроек реплик)."""
    c = cast.get("cast", {}).get(speaker)
    if not c or not c.get("voice_id"):
        raise VoiceError(f"персонаж {speaker!r} без голоса в cast.json")
    settings = dict(cast.get("defaults", {}).get("voice_settings", {}))
    settings.update(c.get("voice_settings", {}))
    if profile:
        settings.update((c.get(f"{profile}_voice") or {}).get("voice_settings", {}))
    spec = {"voice_id": c["voice_id"], "voice_name": c.get("voice_name", ""),
            "model_id": c.get("model_id", cast.get("model_id", "eleven_v4")), "voice_settings": settings}
    if alt:
        if not alt.get("voice_id"):
            raise VoiceError(f"персонаж {speaker!r}: альтернативный голос без voice_id")
        spec.update({"voice_id": alt["voice_id"], "voice_name": alt.get("voice_name", ""),
                     "model_id": alt.get("model_id", spec["model_id"])})
        spec["voice_settings"] = dict(settings, **alt.get("voice_settings", {}))
    return spec


def voice_sets(cast: dict) -> list[dict]:
    """Основной набор assets/voice/ru (все персонажи) + по набору на каждый альтернативный голос персонажа:
    assets/voice/ru_alt/<персонаж>_<вариант>/ (только его реплики) — чтобы Директор сравнил голоса на слух."""
    sets = [{"variant": "", "dir": OUT_DIR, "speaker": None, "alt": None}]
    for sp, c in sorted(cast.get("cast", {}).items()):
        for alt_id, alt in sorted((c.get("alternates") or {}).items()):
            if alt_id.startswith("_"):
                continue
            v = f"{sp}_{alt_id}"
            sets.append({"variant": v, "dir": ALT_ROOT / v, "speaker": sp, "alt": alt})
    return sets


def synth(text: str, spec: dict, cast: dict, seed: int) -> tuple[bytes, dict]:
    """Синтез одной фразы. cast.json → timestamps: true — тот же синтез через /with-timestamps (та же цена;
    https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps): в info["alignment"] — время
    каждого символа запроса; по нему tools/voice_stress_check.py проверяет ударение (ударная гласная — самая долгая)."""
    body = {"text": text, "model_id": spec["model_id"], "voice_settings": spec["voice_settings"]}
    if cast.get("language_code"):
        body["language_code"] = cast["language_code"]
    if cast.get("use_seed", True):
        body["seed"] = seed
    params = {"output_format": cast.get("output_format", "mp3_44100_128")}
    stamps = bool(cast.get("timestamps", False))
    path = f"/v1/text-to-speech/{spec['voice_id']}" + ("/with-timestamps" if stamps else "")
    accept = "application/json" if stamps else "audio/mpeg"
    st, hdr, payload = http("POST", path, params, body, accept=accept)
    dropped: list[str] = []
    if st in (400, 422) and any(k in body for k in OPTIONAL_BODY_KEYS):
        log(f"    {error_text(st, payload)} — повтор без {', '.join(k for k in OPTIONAL_BODY_KEYS if k in body)}")
        for k in OPTIONAL_BODY_KEYS:
            if body.pop(k, None) is not None:
                dropped.append(k)
        st, hdr, payload = http("POST", path, params, body, accept=accept)
    if st != 200:
        raise VoiceError(f"синтез {spec['voice_name'] or spec['voice_id']}: {error_text(st, payload)}")
    alignment = None
    if stamps:
        try:
            d = json.loads(payload.decode("utf-8"))
            payload = base64.b64decode(d.get("audio_base64", ""))
            alignment = d.get("alignment") or d.get("normalized_alignment")
        except (ValueError, UnicodeDecodeError) as e:
            raise VoiceError(f"синтез с выравниванием: ответ не JSON ({e})") from e
    if len(payload) < 512:
        raise VoiceError(f"синтез: подозрительно короткий ответ ({len(payload)} байт)")
    info = {"request_id": hdr.get("request-id", ""), "history_item_id": hdr.get("history-item-id", ""),
            "character_cost": hdr.get("character-cost", hdr.get("x-character-count", "")), "dropped_params": dropped,
            "output_format": params["output_format"], "sent": {k: body[k] for k in ("language_code", "seed") if k in body}}
    if alignment is not None:
        info["alignment"] = alignment
    return payload, info


def same_spec(entry: dict, sha: str, vsha: str, spec: dict) -> bool:
    """sha — текста субтитров (по нему игра решает, играть ли файл), vsha — текста запроса с тегами
    (смена тегов → перегенерация только этой реплики); у записей до тегов voice_sha1 = text_sha1."""
    return (entry.get("text_sha1") == sha and entry.get("voice_sha1", entry.get("text_sha1")) == vsha
            and entry.get("voice_id") == spec["voice_id"]
            and entry.get("model_id") == spec["model_id"] and entry.get("voice_settings") == spec["voice_settings"])


def load_manifest(d: Path) -> dict:
    m = read_json(d / "manifest.json", None) or {}
    m.setdefault("lines", {})
    return m


def mark_stale(manifest: dict, lines: dict[str, dict]) -> list[str]:
    """Помечает записи, которых нет в сценах или чей текст изменился; снимает метку с совпавших."""
    changed = []
    for lid, e in manifest["lines"].items():
        narr = e.get("kind") == "narration"
        # Закадровая фраза устаревает только с текстом ключа: запись персонажа для ключа, который снова
        # отдан закадровому голосу (и наоборот), остаётся запасной — переключение = правка voice.json.
        cur = lines.get(lid) or (lines.get(str(e.get("key", ""))) if narr else None)
        reason = ""
        if cur is None:
            reason = "нет в текстах" if narr else "нет в сценах"
        elif text_sha1(cur["text"]) != e.get("text_sha1"):
            reason = "текст изменён"
        elif not narr and cur["speaker"] != e.get("speaker"):
            reason = "другой персонаж"
        if reason and e.get("stale") != reason:
            e["stale"] = reason
            changed.append(f"{lid}: {reason}")
        elif not reason and "stale" in e:
            del e["stale"]
            changed.append(f"{lid}: снова актуальна")
    return changed


def cmd_generate(req_path: Path, dry_run: bool) -> int:
    req = read_json(req_path, {})
    set_name = str(req.get("set", req_path.stem))
    cast = read_json(CAST_PATH, None)
    if cast is None:
        raise VoiceError(f"нет {CAST_PATH.relative_to(ROOT)} — сначала режим list и сопоставление голосов")
    lc = cast.get("loudness", {})
    target = float(lc.get("target_lufs", -17.0))
    lines = all_lines()
    scenes = [str(s) for s in req.get("scenes", [])]
    scope = {lid: ln for lid, ln in lines.items() if ln.get("kind") != "narration" and ln["scene"] in scenes}
    unknown = [s for s in scenes if not any(ln["scene"] == s for ln in lines.values())]
    if unknown:
        raise VoiceError(f"в сценах нет реплик для: {', '.join(unknown)}")
    # Закадровые фразы: "narration": {"texts": ["ru_E0_E1", "ru_bag"], "keys": [...] (необязательно — только эти)}
    nreq = req.get("narration") or {}
    if nreq:
        texts = [str(t) for t in nreq.get("texts", [])]
        missing_texts = [t for t in texts if not (TEXT_DIR / f"{t}.json").is_file()]
        if missing_texts:
            raise VoiceError(f"нет файлов текста data/story/text/: {', '.join(missing_texts)}")
        only = {str(k) for k in nreq.get("keys", [])}
        speakers_only = {str(x) for x in nreq.get("speakers", [])}
        # Только назначенный голос ключа (закадровый или персонаж из by_speaker); запасные записи не трогаем.
        narr = {lid: ln for lid, ln in lines.items() if ln.get("kind") == "narration" and ln["source"] in texts
                and ln.get("assigned", True) and (not speakers_only or ln["speaker"] in speakers_only)
                and (not only or lid in only or ln["key"] in only)}
        bad_only = sorted(k for k in only if not any(lid == k or ln["key"] == k for lid, ln in narr.items()))
        if bad_only:
            raise VoiceError(f"narration.keys не озвучиваются по правилам voice.json, не назначены этим голосам или нет в текстах: {bad_only}")
        unused = sorted(lid for lid, ln in narr.items() if not ln["used"])
        if unused:
            log(f"  закадровые фразы без ссылок в данных игры — пропущены: {', '.join(unused)}")
        held = sorted(lid for lid, ln in narr.items() if ln.get("hold"))
        if held:
            log(f"  отложены (voice.json → by_speaker.<персонаж>.hold): {', '.join(held)}")
        scope.update({lid: ln for lid, ln in narr.items() if ln["used"] and not ln.get("hold")})
    limit = int(cast.get("max_chars", 5000))
    too_long = [lid for lid, ln in scope.items() if len(ln["text"]) > limit]
    if too_long:
        raise VoiceError(f"реплики длиннее {limit} символов: {too_long}")

    # План по наборам: (набор, id) → что делать.
    plan: list[dict] = []
    missing: list[str] = []
    sets = voice_sets(cast)
    for vs in sets:
        manifest = load_manifest(vs["dir"])
        for note in mark_stale(manifest, lines):
            log(f"  манифест {vs['variant'] or 'ru'}: {note}")
        vs["manifest"] = manifest
        redo = set(str(x) for x in req.get("redo", []))
        for lid, ln in scope.items():
            if vs["speaker"] is not None and ln["speaker"] != vs["speaker"]:
                continue
            try:
                spec = cast_for(cast, ln["speaker"], vs["alt"], str(ln.get("profile", "")))
            except VoiceError as e:
                missing.append(str(e))
                continue
            e = manifest["lines"].get(lid)
            sha = text_sha1(ln["text"])
            vsha = text_sha1(api_text(ln))
            fresh = (e is not None and same_spec(e, sha, vsha, spec) and e.get("file") == file_rel(ln, lid, "ogg")
                     and (vs["dir"] / e.get("file", "-")).is_file() and "stale" not in e)
            action = ""
            if lid in redo or not fresh:
                has_src = e is not None and same_spec(e, sha, vsha, spec) and (vs["dir"] / e.get("source", "-")).is_file()
                action = "process" if has_src and lid not in redo else "synth"   # ответ API уже есть — только обработать
            elif (req.get("reprocess") or e.get("loudness_target_lufs") != target
                  or int(e.get("vorbis_q", 5)) != vorbis_quality(lc)):
                action = "process"   # громкость или качество OGG сменились — из src/*.mp3, без кредитов
            if action:
                plan.append({"set": vs, "id": lid, "line": ln, "spec": spec, "action": action})
    if missing:
        raise VoiceError("; ".join(sorted(set(missing))))
    total_lines = sum(1 for vs in sets for ln in scope.values() if vs["speaker"] in (None, ln["speaker"]))
    if req.get("only_changed"):
        # Перезапись после правки текста: в счёт пробы идут только новые/изменённые (остальные свежие и не трогаются).
        total_lines = len(plan)
        log(f"  only_changed: к работе {len(plan)} из {sum(1 for _ in scope)} реплик/фраз запроса")
    synth_items = [it for it in plan if it["action"] == "synth"]
    chars = sum(len(api_text(it["line"])) for it in synth_items)
    meta = read_json(META_PATH, {})
    if not meta.get("text_freeze", False):
        if not req.get("probe"):
            raise VoiceError("text_freeze=false: массовая запись запрещена (решение Директора); пробный запрос — \"probe\": true")
        # Больше пробы — только по явному заданию Директора с потолком строк и символов (поле order, Docs/DECISIONS.md).
        order = req.get("order") or {}
        limit_lines = PROBE_MAX_LINES
        if order:
            missing_keys = [k for k in ORDER_KEYS if not order.get(k)]
            if missing_keys:
                raise VoiceError(f"order: нет полей {', '.join(missing_keys)} (кто, когда, что, потолок строк и символов)")
            limit_lines = int(order["max_lines"])
            if chars > int(order["max_chars"]):
                raise VoiceError(f"к синтезу {chars} символов > потолка задания {order['max_chars']} — не запускаю")
            log(f"  задание: {order['by']}, {order['date']} — {order['what']} (потолок {limit_lines} файлов, {order['max_chars']} символов)")
        if total_lines > limit_lines:
            raise VoiceError(f"проба больше {limit_lines} файлов ({total_lines}) до text_freeze — сократить запрос")
    log(f"[{set_name}] реплик в сценах запроса: {len(scope)}; файлов с вариантами голосов: {total_lines}; "
        f"к синтезу: {len(synth_items)} ({chars} символов); переобработка: {len(plan) - len(synth_items)}")
    for it in synth_items:
        log(f"  {it['id']:7} {it['line']['speaker']:9} {(it['set']['variant'] or 'ru'):12} {it['spec']['voice_name']:10} "
            f"{it['spec']['model_id']:12} {api_text(it['line'])}")
    if dry_run:
        return 0
    if not shutil.which("ffmpeg"):
        raise VoiceError("нет ffmpeg")

    sub_before = subscription() if synth_items else None
    # Квота (cast.json → quota): до синтеза — хватит ли остатка подписки на весь запрос с запасом margin_fraction
    # от лимита (по числу символов × credits_per_char_assumed — с запасом: eleven_v4 списывает ≈0,44 кредита за символ);
    # во время — по фактическому списанию (заголовок character-cost) не заходить в запас. Докупка — решение Директора.
    qc = cast.get("quota", {}) or {}
    reserve = None
    spent_now = 0
    if synth_items and sub_before and sub_before.get("character_limit") and sub_before.get("character_count") is not None:
        limit_c, used_c = int(sub_before["character_limit"]), int(sub_before["character_count"])
        reserve = float(qc.get("margin_fraction", 0.10)) * limit_c
        need = chars * float(qc.get("credits_per_char_assumed", 1.0))
        left = limit_c - used_c
        log(f"  квота: осталось {left} из {limit_c}, запас {int(reserve)}, к синтезу ≤ {int(need)} кредитов (оценка сверху)")
        if need > left - reserve:
            raise VoiceError(f"квота: запросу нужно до {int(need)} кредитов, а до запаса {int(reserve)} осталось {int(left - reserve)} — "
                             f"не запускаю (сократить запрос или решение Директора о докупке)")
    elif synth_items:
        log("  квота: баланс не прочитан — проверка остатка невозможна, синтез только в пределах order.max_chars")
    done, failed = [], []
    stop = False
    for it in plan:
        if stop:
            break
        vs, lid, ln, spec = it["set"], it["id"], it["line"], it["spec"]
        sha = text_sha1(ln["text"])
        src = vs["dir"] / "src" / file_rel(ln, lid, "mp3")
        dst = vs["dir"] / file_rel(ln, lid, "ogg")
        tag = f"{lid}{'@' + vs['variant'] if vs['variant'] else ''}"
        if it["action"] == "synth" and reserve is not None:
            if int(sub_before["character_count"]) + spent_now + len(api_text(ln)) > int(sub_before["character_limit"]) - reserve:
                failed.append(f"{tag}: квота — дальше запас {int(reserve)} кредитов, остановлено")
                log(f"  СТОП {tag}: списано {spent_now}, следующая реплика зашла бы в запас квоты")
                break
        try:
            info = {}
            if it["action"] == "synth":
                seed = int(hashlib.sha1(f"{lid}|{ln['text']}".encode("utf-8")).hexdigest()[:8], 16)
                audio, info = synth(api_text(ln), spec, cast, seed)
                cc = str(info.get("character_cost", ""))
                spent_now += int(cc) if cc.isdigit() else len(api_text(ln))
                src.parent.mkdir(parents=True, exist_ok=True)
                src.write_bytes(audio)
                al = info.pop("alignment", None)
                al_path = src.with_name(src.stem + ".align.json")
                if al:
                    write_json(al_path, {"text": api_text(ln), "alignment": al})
                elif al_path.exists():
                    al_path.unlink()   # выравнивание прежнего дубля к новому не относится
            meas = process(src, dst, lc)
        except VoiceError as e:
            failed.append(f"{tag}: {e}")
            log(f"  ОШИБКА {tag}: {e}")
            stop = "401" in str(e) or "quota" in str(e).lower()   # ключ/баланс — дальше не пытаться
            continue
        manifest = vs["manifest"]
        prev = manifest["lines"].get(lid, {})
        fresh_audio = it["action"] == "synth"
        where = ({"kind": "narration", "key": ln["key"], "source_text": ln["source"]} if ln.get("kind") == "narration"
                 else {"scene": ln["scene"], "index": ln["index"]})
        if ln.get("option"):
            where["option"] = ln["option"]
        al_rel = "src/" + file_rel(ln, lid, "align.json")
        if (vs["dir"] / al_rel).is_file():
            where["alignment"] = al_rel
        if ln.get("profile"):
            where["profile"] = ln["profile"]
        if ln.get("as_line"):
            where["as_line"] = True
        entry = {**where, "speaker": ln["speaker"], "text": ln["text"], "text_sha1": sha,
                 "voice_id": spec["voice_id"], "voice_name": spec["voice_name"], "model_id": spec["model_id"],
                 "voice_settings": spec["voice_settings"], "file": file_rel(ln, lid, "ogg"),
                 "source": "src/" + file_rel(ln, lid, "mp3"),
                 "voice_text": api_text(ln), "voice_sha1": text_sha1(api_text(ln)), "tags": ln.get("tags", []),
                 "characters": len(api_text(ln)), "loudness_target_lufs": target, **meas,
                 "output_format": (info.get("output_format") if fresh_audio
                                   else prev.get("output_format") or (prev.get("api") or {}).get("output_format", "")),
                 "generated_at": now_iso() if fresh_audio else prev.get("generated_at"),
                 "run": os.environ.get("GITHUB_RUN_ID", "local") if fresh_audio else prev.get("run")}
        if "context" in ln:
            entry["context_not_voiced"] = ln["context"]
        # Тег прочитан вслух? Тот же текст без тегов звучал prev.duration_s; английское слово тега добавило бы
        # ≈0,5–0,8 с на тег. Подозрение — в журнал и в запись (проверить на слух).
        n_tags = len(TAG_IN_TEXT.findall(api_text(ln)))
        if fresh_audio and n_tags and prev.get("text_sha1") == sha and prev.get("duration_s"):
            delta = round(meas["duration_s"] - float(prev["duration_s"]), 3)
            suspect = delta > 0.45 * n_tags + 0.35
            entry["tag_check"] = {"tags": n_tags, "prev_duration_s": prev["duration_s"], "delta_s": delta, "suspect": suspect}
            if suspect:
                log(f"  ПОДОЗРЕНИЕ {tag}: длиннее прежнего дубля на {delta:.2f} с при {n_tags} тег(ах) — тег мог прозвучать вслух")
        elif prev.get("tag_check") and not fresh_audio:
            entry["tag_check"] = prev["tag_check"]
        if fresh_audio:
            entry["api"] = info
        elif prev.get("api"):
            entry["api"] = prev["api"]
        manifest["lines"][lid] = entry
        done.append(it)
        write_json(vs["dir"] / "manifest.json", _manifest_doc(manifest, cast, vs))
        log(f"  {tag:18} {'синтез' if fresh_audio else 'обработка'}: {meas['duration_s']:.2f} с, {meas['lufs']} LUFS, "
            f"TP {meas['true_peak_db']} dB (усиление {meas['gain_db']:+.1f} dB)")
    pruned: list[str] = []
    if req.get("prune_stale") and not stop:
        # Уборка: запись, которая после этого запроса всё ещё stale (ключа/реплики нет; запасная запись другого голоса
        # под старым текстом; ключ без ссылок в данных игры с изменённым текстом), не прозвучит никогда — убрать запись
        # манифеста, OGG и src/*.mp3. Актуальные записи (в т.ч. запасные с совпадающим текстом) не трогаются.
        for vs in sets:
            for lid, e in sorted(vs["manifest"]["lines"].items()):
                if "stale" not in e:
                    continue
                for rel in (e.get("file"), e.get("source"), e.get("alignment")):
                    if rel and (vs["dir"] / rel).is_file():
                        (vs["dir"] / rel).unlink()
                del vs["manifest"]["lines"][lid]
                pruned.append(f"{lid}{'@' + vs['variant'] if vs['variant'] else ''} ({e['stale']})")
        if pruned:
            log(f"  убраны устаревшие записи ({len(pruned)}): {', '.join(pruned)}")
    for vs in sets:   # манифесты всех наборов (в т.ч. только с новыми метками stale)
        if vs["manifest"]["lines"] or pruned:
            write_json(vs["dir"] / "manifest.json", _manifest_doc(vs["manifest"], cast, vs))
    sub_after = subscription() if synth_items else None
    synthesized = [f"{it['id']}{'@' + it['set']['variant'] if it['set']['variant'] else ''}" for it in done if it["action"] == "synth"]
    run = {"run": os.environ.get("GITHUB_RUN_ID", "local"), "at": now_iso(), "request": str(req_path),
           "synthesized": synthesized,
           "reprocessed": [f"{it['id']}{'@' + it['set']['variant'] if it['set']['variant'] else ''}" for it in done if it["action"] != "synth"],
           "characters_text": sum(len(api_text(it["line"])) for it in done if it["action"] == "synth"), "failed": failed,
           "pruned": pruned,
           "subscription_before": sub_before, "subscription_after": sub_after}
    # Списание по ответам API (заголовок character-cost); счётчик подписки обновляется с задержкой.
    costs = [str(it["set"]["manifest"]["lines"].get(it["id"], {}).get("api", {}).get("character_cost", "")) for it in done if it["action"] == "synth"]
    if costs and all(c.isdigit() for c in costs):
        run["credits_spent"] = sum(int(c) for c in costs)
    if sub_before and sub_after and sub_before.get("character_count") is not None and sub_after.get("character_count") is not None:
        run["subscription_delta"] = int(sub_after["character_count"]) - int(sub_before["character_count"])
    st_path = STATE_DIR / f"{set_name}.json"
    st = read_json(st_path, {"set": set_name, "runs": []})
    st["runs"].append(run)
    write_json(st_path, st)
    log(f"[{set_name}] синтезировано {len(synthesized)}, переобработано {len(run['reprocessed'])}, ошибок {len(failed)}; "
        f"символов текста {run['characters_text']}; списано кредитов (character-cost): {run.get('credits_spent', 'н/д')}, "
        f"изменение счётчика подписки: {run.get('subscription_delta', 'н/д')}")
    return 1 if failed else 0


def _manifest_doc(manifest: dict, cast: dict, vs: dict) -> dict:
    lc = cast.get("loudness", {})
    lines = dict(sorted(manifest["lines"].items(), key=lambda kv: (kv[1].get("kind") == "narration", kv[1].get("scene", ""),
                                                                  int(kv[1].get("index", 0)), kv[0])))
    doc = {"_comment": "Озвученные реплики: id = <scene>_<index> (index — позиция в mandatory_lines/lines); закадровые фразы "
                       "(kind narration, голос narrator): id = ключ текста data/story/text, файл narrator/<ключ>.ogg; мысли "
                       "персонажа (data/story/voice.json → narration.by_speaker): id <персонаж>:<ключ>, файл <subdir>/<ключ>.ogg. Пишет "
                       "pipeline/voice/eleven_voice.py; игра читает копию (tools/sync_voice.sh) и играет файл, только если sha1 "
                       "текста совпадает с текущей репликой. stale — реплики больше нет или текст изменён.",
           "language": "ru", "variant": vs["variant"], "speaker_only": vs["speaker"],
           "format": "ogg_vorbis_mono_44100", "loudness_target_lufs": float(lc.get("target_lufs", -17.0)),
           "loudness_measure": "EBU R128 integrated, моно на оба канала (как играет Godot)", "updated_at": now_iso(),
           "lines": lines}
    if not vs["variant"]:
        doc.pop("speaker_only")
    return doc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["check", "list", "generate", "design", "create_voice", "say", "run"])
    ap.add_argument("--request")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    try:
        mode = a.mode
        if mode == "run":
            if not a.request:
                raise VoiceError("run: нужен --request")
            mode = str(read_json(Path(a.request), {}).get("mode", "generate"))
        if mode == "check":
            return cmd_check()
        if mode == "list":
            return cmd_list()
        if mode in ("design", "create_voice", "say"):
            if not a.request:
                raise VoiceError(f"{mode}: нужен --request")
            return {"design": cmd_design, "create_voice": cmd_create_voice, "say": cmd_say}[mode](Path(a.request))
        if mode == "generate":
            if not a.request:
                raise VoiceError("generate: нужен --request")
            return cmd_generate(Path(a.request), a.dry_run)
        raise VoiceError(f"неизвестный режим {mode!r}")
    except VoiceError as e:
        log(f"ОШИБКА: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
