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


def split_sheet(sheet: Path, out_dir: Path, min_width: int = 60, pad: int = 24, bg_tol: int = 10) -> list[Path]:
    """Режет лист по пустым (прозрачным) столбцам на отдельные фигуры, выравнивает высоту кадров.
    Лист без прозрачности (agata_sheet_v2: ровный фон #DEDEDC) — фон по углу, допуск bg_tol; кадры остаются с фоном."""
    im = Image.open(sheet).convert("RGBA")
    a = np.array(im)[..., 3]
    if (a < 10).sum() == 0:
        rgb = np.array(im)[..., :3].astype(int)
        a = np.where(np.abs(rgb - rgb[0, 0]).max(axis=2) > bg_tol, 255, 0)
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


def run_stages(req: dict) -> int:
    """T5b (24.10): этапы по уже готовой модели, без новой генерации. Поле "stages" запроса — список из
    retexture | text_motion | rig | motion | local_glb, выполняются по порядку; id задач — в состоянии (повтор не тратит кредиты).
      retexture:   {"input_task_id", ...тело POST /retexture}            → state/<name>_retexture.json (ответ задачи без ключа)
      text_motion: {"prompt","mode","duration"}                           → state/<name>_text_motion.json
      rig:         {"model_url" (https) , "height_meters"}                → out/<name>/rigged.glb, state/<name>_rig.json
      motion:      анимация по motion_task_id задачи text_motion на риг   → out/<name>/motion.glb, state/<name>_motion.json
      actions:     {"action_ids": [...]} — пресеты библиотеки на риг      → out/<name>/actions.glb, state/<name>_actions.json
      local_glb:   {"url"} — готовый GLB (после правок в Blender)         → out/<name>/animations.glb;
                   поле запроса "clips" {роль: клип} → out/<name>/clips.txt (клипы уже перенесены — "retarget": false)
    """
    name = req["character"]
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    st = load_state(name)
    log = lambda m: print(m, flush=True)
    stages = req["stages"]
    meshy = any(s != "local_glb" for s in stages)
    if meshy:
        log(f"[{name}] баланс: {mc.balance()}")

    def dump(stage: str, task: dict) -> None:
        (STATE / f"{name}_{stage}.json").write_text(json.dumps(task, ensure_ascii=False, indent=2), encoding="utf-8")
        st[f"{stage}_credits"] = task.get("consumed_credits")
        save_state(name, st)
        log(f"[{name}] {stage}: задача {st[stage + '_task']}, кредитов: {task.get('consumed_credits')}")

    for stage in stages:
        cfg = req.get(stage) or {}
        if stage == "retexture":
            if "retexture_task" not in st:
                st["retexture_task"] = mc.create("/retexture", cfg)
                st["retexture_body"] = cfg
                save_state(name, st)
            dump(stage, mc.wait("/retexture", st["retexture_task"], log=log))
        elif stage == "text_motion":
            if "text_motion_task" not in st:
                st["text_motion_task"] = mc.create("/text-to-motion", cfg)
                st["text_motion_body"] = cfg
                save_state(name, st)
            t = mc.wait("/text-to-motion", st["text_motion_task"], log=log)
            dump(stage, t)
            mc.download(t["result"]["motion_url"], out / f"text_motion.{t['result'].get('motion_format', 'fbx')}")
        elif stage == "rig":
            if "rig_task" not in st:
                st["rig_task"] = mc.create("/rigging", {"model_url": cfg["model_url"], "height_meters": cfg.get("height_meters", req.get("height_m", 1.65))})
                save_state(name, st)
            t = mc.wait("/rigging", st["rig_task"], log=log)
            dump(stage, t)
            mc.download(t["result"]["rigged_character_glb_url"], out / "rigged.glb")
        elif stage == "motion":
            if "motion_task" not in st:
                st["motion_task"] = mc.create("/animations", {"rig_task_id": st["rig_task"], "motion_task_id": st["text_motion_task"]})
                save_state(name, st)
            t = mc.wait("/animations", st["motion_task"], log=log)
            dump(stage, t)
            mc.download(t["result"]["animation_glb_url"], out / "motion.glb")
        elif stage == "actions":
            if "actions_task" not in st:
                st["actions_task"] = mc.create("/animations", {"rig_task_id": st["rig_task"], "action_ids": cfg["action_ids"]})
                save_state(name, st)
            t = mc.wait("/animations", st["actions_task"], log=log)
            dump(stage, t)
            mc.download(t["result"]["animation_glb_url"], out / "actions.glb")
        elif stage == "local_glb":
            mc.download(cfg["url"], out / "animations.glb")
            if req.get("clips"):
                (out / "clips.txt").write_text(" ".join(f"{r}={c}" for r, c in req["clips"].items()) + "\n", encoding="utf-8")
            log(f"[{name}] animations.glb из {cfg['url'].split('?')[0]}")
        else:
            raise SystemExit(f"неизвестный этап {stage}")
    if meshy:
        log(f"[{name}] баланс после: {mc.balance()}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    if req.get("stages"):
        return run_stages(req)
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
        for k in ("geometry_resolution", "enable_pbr", "should_remesh", "target_polycount", "multi_view_thumbnails"):
            if k in req:
                body[k] = req[k]
        st["model_task"] = mc.create("/multi-image-to-3d", body)
        st["model_body"] = {k: v for k, v in body.items() if k != "image_urls"}
        save_state(name, st)
        log(f"[{name}] создана задача модели {st['model_task']} c {st['model_body']}")
    try:
        model = mc.wait("/multi-image-to-3d", st["model_task"], log=log)
    except mc.MeshyError as e:
        # повышенная детальность могла не пройти — один повтор без geometry_resolution/enable_pbr (текстуры 4k остаются)
        # model_only — без автоповтора: вторую генерацию решает человек (бюджет кредитов)
        if req.get("model_only") or not any(k in st.get("model_body", {}) for k in ("geometry_resolution", "enable_pbr")):
            raise
        log(f"[{name}] модель с повышенной детальностью не удалась: {e}; повтор без geometry_resolution/enable_pbr")
        body = {"image_urls": [mc.data_uri(v) for v in views], **{k: v for k, v in st["model_body"].items() if k not in ("geometry_resolution", "enable_pbr")}}
        st["model_error"] = str(e)[:500]
        st["model_task"] = mc.create("/multi-image-to-3d", body)
        st["model_body"] = {k: v for k, v in body.items() if k != "image_urls"}
        save_state(name, st)
        model = mc.wait("/multi-image-to-3d", st["model_task"], log=log)
    # model_only (T5a, 24.10): только модель — Директор смотрит её на сайте Meshy; ответ задачи (без ключа) —
    # в pipeline/3d/state/<name>_model.json, риг и движения — отдельным запуском по id задачи
    if req.get("model_only"):
        st["model_credits"] = model.get("consumed_credits")
        save_state(name, st)
        (STATE / f"{name}_model.json").write_text(json.dumps(model, ensure_ascii=False, indent=2), encoding="utf-8")
        log(f"[{name}] модель готова (только модель): задача {st['model_task']}, кредитов: {st['model_credits']}")
        log(f"[{name}] баланс после: {mc.balance()}")
        return 0
    glb_url = model["model_urls"]["glb"]
    mc.download(glb_url, out / "model.glb")
    st["model_credits"] = model.get("consumed_credits")
    save_state(name, st)
    log(f"[{name}] model.glb скачан, кредитов: {st['model_credits']}")

    # 2б. детальная модель (геометрия 2k) — сотни тысяч граней, а риг Meshy принимает не больше 320 000:
    #      Remesh до remesh_polycount (по умолчанию 300 000), текстуры сохраняются; риг — по задаче Remesh
    rig_input = st["model_task"]
    if "geometry_resolution" in req or req.get("remesh_polycount"):
        if "remesh_task" not in st:
            st["remesh_task"] = mc.create("/remesh", {"input_task_id": st["model_task"],
                                                      "target_polycount": int(req.get("remesh_polycount", 300000)),
                                                      "topology": "triangle", "target_formats": ["glb"]})
            save_state(name, st)
            log(f"[{name}] создана задача Remesh {st['remesh_task']}")
        rm = mc.wait("/remesh", st["remesh_task"], log=log)
        mc.download(rm["model_urls"]["glb"], out / "model.glb")
        st["remesh_credits"] = rm.get("consumed_credits")
        save_state(name, st)
        rig_input = st["remesh_task"]
        log(f"[{name}] Remesh готов, кредитов: {st['remesh_credits']}")

    # 3. авториг (сначала по id задачи, при отказе — по data URI файла)
    if "rig_task" not in st:
        try:
            st["rig_task"] = mc.create("/rigging", {"input_task_id": rig_input, "height_meters": req.get("height_m", 1.7)})
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
    # ответы задач (ссылки живут 3 дня) — для сборки в Blender вне конвейера (I-T4, 25.10)
    for stage, task in (("model", model), ("rig", rig), ("anim", anim)):
        (STATE / f"{name}_{stage}.json").write_text(json.dumps(task, ensure_ascii=False, indent=2), encoding="utf-8")

    # 5. Text to Motion по ролям (I-T4): {"роль": {"prompt", "mode": "prime", "duration"}} → out/<name>/motion_<роль>.glb
    #    10 кредитов за движение + 3 за перенос на риг; id задач в состоянии — повтор не тратит кредиты
    for role, cfg in (req.get("text_motions") or {}).items():
        tk, ak = f"tm_{role}_task", f"tm_{role}_anim_task"
        if tk not in st:
            st[tk] = mc.create("/text-to-motion", cfg)
            save_state(name, st)
            log(f"[{name}] Text to Motion «{role}»: задача {st[tk]}")
        tm = mc.wait("/text-to-motion", st[tk], log=log)
        st[f"tm_{role}_credits"] = tm.get("consumed_credits")
        if ak not in st:
            st[ak] = mc.create("/animations", {"rig_task_id": st["rig_task"], "motion_task_id": st[tk]})
            save_state(name, st)
        am = mc.wait("/animations", st[ak], log=log)
        st[f"tm_{role}_anim_credits"] = am.get("consumed_credits")
        save_state(name, st)
        mc.download(am["result"]["animation_glb_url"], out / f"motion_{role}.glb")
        (STATE / f"{name}_tm_{role}.json").write_text(json.dumps({"text_motion": tm, "animation": am}, ensure_ascii=False, indent=2), encoding="utf-8")
        log(f"[{name}] «{role}» готово, кредитов: {tm.get('consumed_credits')} + {am.get('consumed_credits')}")

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
