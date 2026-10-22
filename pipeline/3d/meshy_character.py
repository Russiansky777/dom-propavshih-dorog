#!/usr/bin/env python3
"""Лист персонажа (три ракурса на прозрачном фоне) → Meshy: 3D-модель → авториг → анимации → GLB.

Запуск:
  python3 pipeline/3d/meshy_character.py --request pipeline/requests/agata.json
Запрос (JSON): {"character":"agata","sheet":"assets/reference/agata_sheet.png","height_m":1.65,
                "actions":["idle","walk"],"ai_model":"latest","texture_resolution":"2k"}

Результат в pipeline/3d/out/<character>/: views/*.png, model.glb, rigged.glb, anim_<action>.glb, meshy_manifest.json.
Состояние (id задач) хранится в pipeline/3d/state/<character>.json — повторный запуск продолжает с места остановки
и не создаёт задачи заново (кредиты не списываются дважды).
Требуется: MESHY_API_KEY в окружении; Pillow + numpy для нарезки листа.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshy_client as mc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "pipeline" / "3d" / "out"
STATE = ROOT / "pipeline" / "3d" / "state"

# Пресеты Meshy подбираются по ключевым словам в library; порядок — приоритет.
ACTION_KEYWORDS = {
    "idle": ["standing idle", "breathing idle", "neutral idle", "idle"],
    "walk": ["walking woman", "walking", "walk"],
    "run": ["running", "run", "jog"],
    "pick": ["picking up", "pick up", "pickup", "pick", "grab"],
    "talk": ["talking", "talk", "speak", "gesture"],
}
# пресеты с этими словами не подходят под бытовую адвенчуру
ACTION_STOPWORDS = ["swim", "sit", "crouch", "combat", "fight", "sword", "gun", "rifle", "zombie", "dance", "injured", "drunk", "sneak", "crawl", "jump", "fall", "fly", "turn", "look", "phone", "texting", "bored", "angry", "scared"]


def split_sheet(sheet: Path, out_dir: Path, min_width: int = 60, pad: int = 24) -> list[Path]:
    """Режет лист по пустым (прозрачным) столбцам на отдельные фигуры, выравнивает высоту кадров."""
    im = Image.open(sheet).convert("RGBA")
    a = np.array(im)[..., 3]
    cols = (a >= 10).any(axis=0)
    segs, start = [], None
    for x, c in enumerate(cols):
        if c and start is None:
            start = x
        if not c and start is not None:
            segs.append((start, x - 1))
            start = None
    if start is not None:
        segs.append((start, len(cols) - 1))
    segs = [s for s in segs if s[1] - s[0] >= min_width]
    if not segs:
        raise SystemExit("на листе не найдено фигур (нет прозрачного фона?)")
    ys_all = np.where((a >= 10).any(axis=1))[0]
    top, bottom = max(0, ys_all.min() - pad), min(a.shape[0], ys_all.max() + pad)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for i, (x0, x1) in enumerate(segs):
        crop = im.crop((max(0, x0 - pad), top, min(im.width, x1 + pad), bottom))
        p = out_dir / f"view_{i}.png"
        crop.save(p)
        paths.append(p)
    return paths


def load_state(name: str) -> dict:
    p = STATE / f"{name}.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def save_state(name: str, st: dict) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / f"{name}.json").write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")


def pick_actions(wanted: list[str]) -> dict[str, dict]:
    lib = mc.library(category="WalkAndRun") + mc.library(category="BodyMovements") + mc.library(category="DailyActions")
    seen = {}
    for item in lib:
        seen.setdefault(item.get("action_id"), item)
    chosen = {}
    for w in wanted:
        kws = ACTION_KEYWORDS.get(w, [w])
        best = None
        for kw in kws:
            for item in seen.values():
                hay = f"{item.get('name','')} {item.get('key','')}".lower().replace("_", " ")
                if kw in hay and not any(sw in hay for sw in ACTION_STOPWORDS):
                    best = item
                    break
            if best:
                break
        if not best:
            raise SystemExit(f"в библиотеке Meshy не нашёл пресет для «{w}»; доступно: " + ", ".join(sorted(str(i.get("key")) for i in seen.values()))[:2000])
        chosen[w] = best
    return chosen


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    name = req["character"]
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    st = load_state(name)
    log = lambda m: print(m, flush=True)
    # redo_stages: ["model"|"rig"|"anim"] — сбросить стадию и всё после неё (кредиты за эти стадии спишутся заново)
    order = ["model", "rig", "anim"]
    for stage in req.get("redo_stages", []):
        for later in order[order.index(stage):]:
            for k in (f"{later}_task", f"{later}_credits"):
                st.pop(k, None)
            if later == "anim":
                st.pop("actions", None)
        log(f"[{name}] стадия {stage} и последующие будут выполнены заново")
    save_state(name, st)

    log(f"[{name}] баланс: {mc.balance()}")

    # 1. нарезка листа
    views = split_sheet(ROOT / req["sheet"], out / "views")
    log(f"[{name}] ракурсов на листе: {len(views)} → {[v.name for v in views]}")
    views = views[:4]

    # 2. multi-image-to-3d
    if "model_task" not in st:
        body = {
            "image_urls": [mc.data_uri(v) for v in views],
            "ai_model": req.get("ai_model", "latest"),
            "pose_mode": req.get("pose_mode", "a-pose"),
            "should_texture": True,
            "texture_resolution": req.get("texture_resolution", "2k"),
            "target_formats": ["glb"],
            "auto_size": True,
            "origin_at": "bottom",
        }
        # детальность (Директор 22.10: «поднять уровень» против Агаты и Тамары v2): необязательные поля запроса
        for k in ("geometry_resolution", "enable_pbr", "should_remesh", "target_polycount"):
            if k in req:
                body[k] = req[k]
        st["model_task"] = mc.create("/multi-image-to-3d", body)
        save_state(name, st)
        log(f"[{name}] создана задача модели {st['model_task']}")
    model = mc.wait("/multi-image-to-3d", st["model_task"], log=log)
    glb_url = model["model_urls"]["glb"]
    mc.download(glb_url, out / "model.glb")
    st["model_credits"] = model.get("consumed_credits")
    save_state(name, st)
    log(f"[{name}] model.glb скачан, кредитов: {st['model_credits']}")

    # 3. авториг (сначала по id задачи, при отказе — по data URI файла)
    if "rig_task" not in st:
        try:
            st["rig_task"] = mc.create("/rigging", {"input_task_id": st["model_task"], "height_meters": req.get("height_m", 1.7)})
        except mc.MeshyError as e:
            log(f"[{name}] риг по input_task_id отклонён ({e}); пробую model_url")
            glb = out / "model.glb"
            if glb.stat().st_size > 95 * 1024 * 1024:
                raise
            uri = "data:model/gltf-binary;base64," + __import__("base64").b64encode(glb.read_bytes()).decode("ascii")
            st["rig_task"] = mc.create("/rigging", {"model_url": uri, "height_meters": req.get("height_m", 1.7)})
        save_state(name, st)
        log(f"[{name}] создана задача рига {st['rig_task']}")
    rig = mc.wait("/rigging", st["rig_task"], log=log)
    res = rig.get("result") or {}
    mc.download(res["rigged_character_glb_url"], out / "rigged.glb")
    basic = res.get("basic_animations") or {}
    if basic.get("walking_glb_url"):
        mc.download(basic["walking_glb_url"], out / "anim_walk_basic.glb")
    st["rig_credits"] = rig.get("consumed_credits")
    save_state(name, st)
    log(f"[{name}] rigged.glb скачан")

    # 4. анимации из библиотеки
    wanted = req.get("actions", ["idle", "walk"])
    if "anim_task" not in st:
        # action_ids в запросе — явный выбор пресета по публичному каталогу
        # https://api.meshy.ai/web/public/animations/resources (напр. 0 = Idle, 1 = Walking Woman);
        # без него — подбор по ключевым словам (pick_actions).
        explicit = req.get("action_ids") or {}
        if explicit:
            lib = {}
            for item in mc.library(category="WalkAndRun") + mc.library(category="BodyMovements") + mc.library(category="DailyActions"):
                lib.setdefault(item.get("action_id"), item)
            chosen = {}
            for w in wanted:
                if w in explicit:
                    aid = int(explicit[w])
                    item = lib.get(aid) or {"action_id": aid, "name": f"action {aid}", "key": f"action_{aid}"}
                    chosen[w] = item
                else:
                    chosen[w] = pick_actions([w])[w]
        else:
            chosen = pick_actions(wanted)
        st["actions"] = {w: {"action_id": c["action_id"], "name": c.get("name"), "key": c.get("key")} for w, c in chosen.items()}
        st["anim_task"] = mc.create("/animations", {"rig_task_id": st["rig_task"], "action_ids": [c["action_id"] for c in chosen.values()]})
        save_state(name, st)
        log(f"[{name}] создана задача анимаций {st['anim_task']}: {st['actions']}")
    anim = mc.wait("/animations", st["anim_task"], log=log)
    mc.download(anim["result"]["animation_glb_url"], out / "animations.glb")
    st["anim_credits"] = anim.get("consumed_credits")
    save_state(name, st)

    manifest = {
        "character": name,
        "sheet": req["sheet"],
        "height_m": req.get("height_m"),
        "tasks": {k: st[k] for k in ("model_task", "rig_task", "anim_task")},
        "actions": st.get("actions"),
        "credits": {k: st.get(k) for k in ("model_credits", "rig_credits", "anim_credits")},
        "files": {"model": "model.glb", "rigged": "rigged.glb", "animations": "animations.glb"},
        "note": "animations.glb содержит по одному клипу на action в порядке actions; клипы называть по ключам Meshy",
    }
    (out / "meshy_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    log(f"[{name}] готово: {out}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except mc.MeshyError as e:
        print("MESHY ERROR:", e, file=sys.stderr)
        sys.exit(2)
