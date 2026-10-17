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
  generate --request <файл>   реплики сцен из запроса → assets/voice/ru/<scene>_<index>.ogg + manifest.json
           [--dry-run]        только список реплик и число символов, без запросов к API
  run --request <файл>        режим берётся из поля "mode" запроса (так запускает workflow)

Идентификатор реплики: <scene>_<index>, index — позиция в mandatory_lines сцены (для заданий — lines), как её
показывает StoryRunner (beat.line_id). Контекстная реплика (поле context — вариант вопроса) озвучивает только text.
Повторный запуск тратит кредиты только на новые/изменённые реплики: sha1 текста, голос, модель и настройки
сравниваются с манифестом; ответ API хранится в src/<id>.mp3, поэтому переобработка громкости бесплатна.
"""
from __future__ import annotations

import argparse
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

ROOT = Path(__file__).resolve().parents[2]
API = "https://api.elevenlabs.io"
VOICE_DIR = ROOT / "pipeline" / "voice"
CAST_PATH = VOICE_DIR / "cast.json"
VOICES_PATH = VOICE_DIR / "voices.json"
STATE_DIR = VOICE_DIR / "state"
OUT_DIR = ROOT / "assets" / "voice" / "ru"
SRC_DIR = OUT_DIR / "src"
MANIFEST_PATH = OUT_DIR / "manifest.json"
SCENES_DIR = ROOT / "data" / "story" / "scenes"
QUESTS_PATH = ROOT / "data" / "story" / "quests.json"
META_PATH = ROOT / "data" / "story" / "meta.json"

PROBE_MAX_LINES = 40          # пока text_freeze=false — только проба (решение Директора 17.10)
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
            e = {"scene": scene_id, "index": i, "speaker": str(ln.get("speaker", "")), "text": str(ln.get("text", ""))}
            if ln.get("context"):
                e["context"] = str(ln["context"])
            out[lid] = e

    for f in sorted(SCENES_DIR.glob("E*.json")):
        for sc in read_json(f, {}).get("scenes", []):
            add(str(sc["id"]), sc.get("mandatory_lines", []))
    for q in read_json(QUESTS_PATH, {}).get("quests", []):
        add(str(q["id"]), q.get("mandatory_lines", q.get("lines", [])))
    return out


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
    _ffmpeg(["-i", str(src), "-af", chain, "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", str(dst)])
    out_i, out_tp = measure(dst)
    return {"duration_s": duration_s(dst), "lufs": round(out_i, 2), "true_peak_db": round(out_tp, 2),
            "gain_db": gain, "source_lufs": round(src_i, 2), "source_true_peak_db": round(src_tp, 2)}


# --- generate ----------------------------------------------------------------------------------------

def cast_for(cast: dict, speaker: str) -> dict:
    c = cast.get("cast", {}).get(speaker)
    if not c or not c.get("voice_id"):
        raise VoiceError(f"персонаж {speaker!r} без голоса в cast.json")
    settings = dict(cast.get("defaults", {}).get("voice_settings", {}))
    settings.update(c.get("voice_settings", {}))
    return {"voice_id": c["voice_id"], "voice_name": c.get("voice_name", ""),
            "model_id": c.get("model_id", cast.get("model_id", "eleven_v4")), "voice_settings": settings}


def synth(text: str, spec: dict, cast: dict, seed: int) -> tuple[bytes, dict]:
    body = {"text": text, "model_id": spec["model_id"], "voice_settings": spec["voice_settings"]}
    if cast.get("language_code"):
        body["language_code"] = cast["language_code"]
    if cast.get("use_seed", True):
        body["seed"] = seed
    params = {"output_format": cast.get("output_format", "mp3_44100_128")}
    path = f"/v1/text-to-speech/{spec['voice_id']}"
    st, hdr, payload = http("POST", path, params, body, accept="audio/mpeg")
    dropped: list[str] = []
    if st in (400, 422) and any(k in body for k in OPTIONAL_BODY_KEYS):
        log(f"    {error_text(st, payload)} — повтор без {', '.join(k for k in OPTIONAL_BODY_KEYS if k in body)}")
        for k in OPTIONAL_BODY_KEYS:
            if body.pop(k, None) is not None:
                dropped.append(k)
        st, hdr, payload = http("POST", path, params, body, accept="audio/mpeg")
    if st != 200:
        raise VoiceError(f"синтез {spec['voice_name'] or spec['voice_id']}: {error_text(st, payload)}")
    if len(payload) < 512:
        raise VoiceError(f"синтез: подозрительно короткий ответ ({len(payload)} байт)")
    info = {"request_id": hdr.get("request-id", ""), "history_item_id": hdr.get("history-item-id", ""),
            "character_cost": hdr.get("character-cost", hdr.get("x-character-count", "")), "dropped_params": dropped,
            "output_format": params["output_format"], "sent": {k: body[k] for k in ("language_code", "seed") if k in body}}
    return payload, info


def same_spec(entry: dict, sha: str, spec: dict) -> bool:
    return (entry.get("text_sha1") == sha and entry.get("voice_id") == spec["voice_id"]
            and entry.get("model_id") == spec["model_id"] and entry.get("voice_settings") == spec["voice_settings"])


def load_manifest() -> dict:
    m = read_json(MANIFEST_PATH, None) or {}
    m.setdefault("lines", {})
    return m


def mark_stale(manifest: dict, lines: dict[str, dict]) -> list[str]:
    """Помечает записи, которых нет в сценах или чей текст изменился; снимает метку с совпавших."""
    changed = []
    for lid, e in manifest["lines"].items():
        cur = lines.get(lid)
        reason = ""
        if cur is None:
            reason = "нет в сценах"
        elif text_sha1(cur["text"]) != e.get("text_sha1"):
            reason = "текст изменён"
        elif cur["speaker"] != e.get("speaker"):
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
    lines = story_lines()
    scenes = [str(s) for s in req.get("scenes", [])]
    scope = {lid: ln for lid, ln in lines.items() if ln["scene"] in scenes}
    unknown = [s for s in scenes if not any(ln["scene"] == s for ln in lines.values())]
    if unknown:
        raise VoiceError(f"в сценах нет реплик для: {', '.join(unknown)}")
    meta = read_json(META_PATH, {})
    if not meta.get("text_freeze", False):
        if not req.get("probe"):
            raise VoiceError("text_freeze=false: массовая запись запрещена (решение Директора); пробный запрос — \"probe\": true")
        if len(scope) > PROBE_MAX_LINES:
            raise VoiceError(f"проба больше {PROBE_MAX_LINES} реплик ({len(scope)}) до text_freeze — сократить запрос")
    specs: dict[str, dict] = {}
    missing = []
    for ln in scope.values():
        if ln["speaker"] not in specs:
            try:
                specs[ln["speaker"]] = cast_for(cast, ln["speaker"])
            except VoiceError as e:
                missing.append(str(e))
    if missing:
        raise VoiceError("; ".join(sorted(set(missing))))
    limit = int(cast.get("max_chars", 5000))
    too_long = [lid for lid, ln in scope.items() if len(ln["text"]) > limit]
    if too_long:
        raise VoiceError(f"реплики длиннее {limit} символов: {too_long}")

    manifest = load_manifest()
    for note in mark_stale(manifest, lines):
        log(f"  манифест: {note}")
    redo = set(str(x) for x in req.get("redo", []))
    todo, reprocess = [], []
    for lid, ln in scope.items():
        spec = specs[ln["speaker"]]
        e = manifest["lines"].get(lid)
        sha = text_sha1(ln["text"])
        fresh = e is not None and same_spec(e, sha, spec) and (OUT_DIR / e.get("file", "")).is_file() and "stale" not in e
        if lid in redo or not fresh:
            if e is not None and same_spec(e, sha, spec) and (OUT_DIR / e.get("source", "-")).is_file() and lid not in redo:
                reprocess.append(lid)       # ответ API уже есть — только обработать заново
            else:
                todo.append(lid)
        elif req.get("reprocess") or e.get("loudness_target_lufs") != float(lc.get("target_lufs", -17.0)):
            reprocess.append(lid)
    chars = sum(len(scope[lid]["text"]) for lid in todo)
    log(f"[{set_name}] реплик в запросе: {len(scope)}; к синтезу: {len(todo)} ({chars} символов); переобработка: {len(reprocess)}")
    for lid in todo:
        ln = scope[lid]
        log(f"  {lid:7} {ln['speaker']:9} {specs[ln['speaker']]['model_id']:14} {ln['text']}")
    if dry_run:
        return 0
    if not shutil.which("ffmpeg"):
        raise VoiceError("нет ffmpeg")

    sub_before = subscription() if todo else None
    done, failed = [], []
    for lid in todo + reprocess:
        ln = scope[lid]
        spec = specs[ln["speaker"]]
        sha = text_sha1(ln["text"])
        src = SRC_DIR / f"{lid}.mp3"
        dst = OUT_DIR / f"{lid}.ogg"
        try:
            info = {}
            if lid in todo:
                seed = int(hashlib.sha1(f"{lid}|{ln['text']}".encode("utf-8")).hexdigest()[:8], 16)
                audio, info = synth(ln["text"], spec, cast, seed)
                src.parent.mkdir(parents=True, exist_ok=True)
                src.write_bytes(audio)
            meas = process(src, dst, lc)
        except VoiceError as e:
            failed.append(f"{lid}: {e}")
            log(f"  ОШИБКА {lid}: {e}")
            if "401" in str(e) or "quota" in str(e).lower():
                break             # ключ/баланс — дальше не пытаться
            continue
        prev = manifest["lines"].get(lid, {})
        entry = {"scene": ln["scene"], "index": ln["index"], "speaker": ln["speaker"], "text": ln["text"], "text_sha1": sha,
                 "voice_id": spec["voice_id"], "voice_name": spec["voice_name"], "model_id": spec["model_id"],
                 "voice_settings": spec["voice_settings"], "file": dst.name, "source": f"src/{src.name}",
                 "characters": len(ln["text"]), "loudness_target_lufs": float(lc.get("target_lufs", -17.0)), **meas,
                 "generated_at": prev.get("generated_at") if lid not in todo else now_iso(),
                 "run": prev.get("run") if lid not in todo else os.environ.get("GITHUB_RUN_ID", "local")}
        if "context" in ln:
            entry["context_not_voiced"] = ln["context"]
        if lid in todo:
            entry["api"] = info
        elif prev.get("api"):
            entry["api"] = prev["api"]
        manifest["lines"][lid] = entry
        done.append(lid)
        write_json(MANIFEST_PATH, _manifest_doc(manifest, cast))
        log(f"  {lid:7} {'синтез' if lid in todo else 'обработка'}: {meas['duration_s']:.2f} с, {meas['lufs']} LUFS, "
            f"TP {meas['true_peak_db']} dB (усиление {meas['gain_db']:+.1f} dB)")
    write_json(MANIFEST_PATH, _manifest_doc(manifest, cast))
    sub_after = subscription() if todo else None
    synthesized = [lid for lid in done if lid in todo]
    run = {"run": os.environ.get("GITHUB_RUN_ID", "local"), "at": now_iso(), "request": str(req_path.relative_to(ROOT)) if req_path.is_absolute() else str(req_path),
           "synthesized": synthesized, "reprocessed": [lid for lid in done if lid not in todo],
           "characters_text": sum(len(scope[lid]["text"]) for lid in synthesized), "failed": failed,
           "subscription_before": sub_before, "subscription_after": sub_after}
    if sub_before and sub_after and sub_before.get("character_count") is not None and sub_after.get("character_count") is not None:
        run["credits_spent"] = int(sub_after["character_count"]) - int(sub_before["character_count"])
    st_path = STATE_DIR / f"{set_name}.json"
    st = read_json(st_path, {"set": set_name, "runs": []})
    st["runs"].append(run)
    write_json(st_path, st)
    log(f"[{set_name}] синтезировано {len(synthesized)}, переобработано {len(run['reprocessed'])}, ошибок {len(failed)}; "
        f"символов текста {run['characters_text']}; списано по балансу: {run.get('credits_spent', 'н/д')}")
    return 1 if failed else 0


def _manifest_doc(manifest: dict, cast: dict) -> dict:
    lc = cast.get("loudness", {})
    lines = dict(sorted(manifest["lines"].items(), key=lambda kv: (kv[1].get("scene", ""), int(kv[1].get("index", 0)))))
    return {"_comment": "Озвученные реплики: id = <scene>_<index> (index — позиция в mandatory_lines/lines). Пишет "
                        "pipeline/voice/eleven_voice.py; игра читает копию (tools/sync_voice.sh) и играет файл, только если sha1 "
                        "текста совпадает с текущей репликой. stale — реплики больше нет или текст изменён.",
            "language": "ru", "format": "ogg_vorbis_mono_44100", "loudness_target_lufs": float(lc.get("target_lufs", -17.0)),
            "loudness_measure": "EBU R128 integrated, моно на оба канала (как играет Godot)", "updated_at": now_iso(),
            "lines": lines}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["check", "list", "generate", "run"])
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
