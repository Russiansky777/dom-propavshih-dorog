#!/usr/bin/env python3
"""Минимальный клиент Meshy OpenAPI v1 (stdlib only).

Контракт снят с docs.meshy.ai 17.10.2026:
  POST /openapi/v1/multi-image-to-3d   image_urls[1..4] (первая — фронт), ai_model, pose_mode, texture_resolution, target_formats, origin_at, auto_size
  GET  /openapi/v1/multi-image-to-3d/:id
  POST /openapi/v1/rigging             input_task_id | model_url, height_meters
  GET  /openapi/v1/rigging/:id          result.rigged_character_glb_url, result.basic_animations.walking_glb_url
  GET  /openapi/v1/animations/library   ?search=&category=   → action_id, name, key, category
  POST /openapi/v1/animations           rig_task_id, action_ids[1..10]
  GET  /openapi/v1/animations/:id       result.animation_glb_url
Статусы: PENDING, IN_PROGRESS, SUCCEEDED, FAILED, CANCELED. Ссылки на файлы истекают — скачивать сразу.
Ключ: переменная окружения MESHY_API_KEY. Создание задачи никогда не повторяется после таймаута (чтобы не списать кредиты дважды).
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://api.meshy.ai/openapi/v1"


class MeshyError(RuntimeError):
    pass


def _key() -> str:
    k = os.environ.get("MESHY_API_KEY", "").strip()
    if not k:
        raise MeshyError("MESHY_API_KEY не задан в окружении")
    return k


def _request(method: str, path: str, body: dict | None = None, timeout: int = 120) -> dict:
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {_key()}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        raise MeshyError(f"{method} {path} → HTTP {e.code}: {detail}") from None


def data_uri(png_path: Path) -> str:
    mime = "image/png" if png_path.suffix.lower() == ".png" else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(png_path.read_bytes()).decode("ascii")


def create(path: str, body: dict) -> str:
    """Создать задачу один раз; возвращает id. Повтор при сетевой ошибке НЕ делается."""
    r = _request("POST", path, body)
    tid = r.get("result")
    if not tid:
        raise MeshyError(f"нет id в ответе: {r}")
    return tid


def wait(path: str, tid: str, poll_s: int = 10, max_s: int = 3600, log=print) -> dict:
    t0 = time.time()
    last = None
    while True:
        r = _request("GET", f"{path}/{tid}")
        st = r.get("status")
        pr = r.get("progress")
        if (st, pr) != last:
            log(f"  {path.split('/')[-1]} {tid}: {st} {pr if pr is not None else ''}")
            last = (st, pr)
        if st == "SUCCEEDED":
            return r
        if st in ("FAILED", "CANCELED"):
            raise MeshyError(f"задача {tid} завершилась {st}: {r.get('task_error')}")
        if time.time() - t0 > max_s:
            raise MeshyError(f"задача {tid} не завершилась за {max_s} с")
        time.sleep(poll_s)


def download(url: str, dest: Path, timeout: int = 600) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    return dest


def balance() -> dict:
    return _request("GET", "/balance")


def library(search: str | None = None, category: str | None = None) -> list[dict]:
    q = []
    if search:
        q.append("search=" + urllib.request.quote(search))
    if category:
        q.append("category=" + urllib.request.quote(category))
    r = _request("GET", "/animations/library" + ("?" + "&".join(q) if q else ""))
    # ответ может быть списком или объектом с result
    return r if isinstance(r, list) else r.get("result", r.get("data", []))


if __name__ == "__main__":
    try:
        print(json.dumps(balance(), ensure_ascii=False))
    except MeshyError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
