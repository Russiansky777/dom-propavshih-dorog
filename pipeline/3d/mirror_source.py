#!/usr/bin/env python3
"""Нина в мамином зеркале (M15а): исходные клипы для поз — без новой модели.

  python3 pipeline/3d/mirror_source.py --request pipeline/requests/mirror_nina.json

Запрос (поля, которые читает этот шаг):
  character    — чей риг (pipeline/3d/state/<character>.json → rig_task); клипы ложатся на ЭТОТ риг
  new_actions  — {ключ: action_id} пресетов библиотеки Meshy (POST /openapi/v1/animations, rig_task_id + action_ids;
                 ≈ 3 кредита за действие). Id — по официальной таблице https://docs.meshy.ai/en/api/animation-library;
                 перед созданием задачи id сверяются с GET /animations/library: имя пресета должно совпасть с
                 expect_keys[ключ], иначе задача не создаётся (кредиты не тратятся)
  expect_keys  — {ключ: имя пресета Meshy} — что должно стоять под id
  max_credits  — потолок; дороже — задача не создаётся
  previews     — id пресетов: превью-GIF каталога (бесплатно) → полосы кадров в Docs/evidence/M2/nina_mirror/catalog/
Состояние — pipeline/3d/state/<character>_mirror.json (повтор с тем же набором id не создаёт задачу заново:
пока файлы задачи живы — 3 суток — GLB скачивается снова за 0 кредитов).
Результат: pipeline/3d/out/<character>/mirror_clips.glb (сетка + риг персонажа + клипы в порядке action_ids).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshy_client as mc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "pipeline" / "3d" / "state"
OUT = ROOT / "pipeline" / "3d" / "out"
EVID = ROOT / "Docs" / "evidence" / "M2" / "nina_mirror" / "catalog"


def log(m: str) -> None:
    print(m, flush=True)


def previews(ids: list[int]) -> None:
    import rt3d_job  # noqa: PLC0415  (каталог и полосы кадров — общий код с превью Агаты)
    items = rt3d_job.catalog()
    by_id = {int(it["id"]): it for it in items if it.get("id") is not None}
    EVID.mkdir(parents=True, exist_ok=True)
    metrics = {}
    for aid in ids:
        it = by_id.get(int(aid))
        if not it or not it.get("previewUrl"):
            log(f"  превью {aid}: нет в каталоге")
            continue
        try:
            strip, met = rt3d_job.strip_from_gif(rt3d_job.fetch(it["previewUrl"]), n=12, h=320)
        except Exception as e:  # превью не критичны
            log(f"  превью {aid}: не скачалось: {e}")
            continue
        safe = "".join(ch if ch.isalnum() else "_" for ch in str(it.get("key") or it.get("name")))
        if strip is not None:
            strip.save(EVID / f"{int(aid):03d}_{safe}.jpg", quality=85)
        met.update({"name": it.get("name"), "key": it.get("key"), "subCategory": it.get("subCategory")})
        metrics[str(aid)] = met
        log(f"  превью {aid} {it.get('key')}: {met}")
    (EVID / "metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=1), encoding="utf-8")


def new_actions(name: str, req: dict) -> Path | None:
    acts: dict = req.get("new_actions") or {}
    if not acts:
        return None
    dest = OUT / name / "mirror_clips.glb"
    st_path = STATE / f"{name}_mirror.json"
    st = json.loads(st_path.read_text(encoding="utf-8")) if st_path.exists() else {}
    base = json.loads((STATE / f"{name}.json").read_text(encoding="utf-8"))
    ids = [int(v) for v in acts.values()]
    if st.get("task") and st.get("action_ids") == ids:
        log(f"набор {ids} уже заказан задачей {st['task']} — 0 кредитов, скачиваю снова")
    else:
        cost = 3 * len(ids)
        if cost > int(req.get("max_credits", 0)):
            raise SystemExit(f"новые клипы стоят ≈{cost} кредитов > max_credits {req.get('max_credits')} — задача не создана")
        lib = {}
        for cat in ("DailyActions", "WalkAndRun", "BodyMovements"):
            for it in mc.library(category=cat):
                lib.setdefault(int(it.get("action_id", -999)), it)
        expect = req.get("expect_keys") or {}
        for k, aid in acts.items():
            it = lib.get(int(aid))
            got = (it or {}).get("name") or (it or {}).get("key")
            log(f"  {k}: action_id {aid} → {got!r} (ждём {expect.get(k)!r})")
            if it is None or (k in expect and expect[k] not in (it.get("name"), it.get("key"))):
                raise SystemExit(f"id {aid} в библиотеке Meshy — {got!r}, а ждали {expect.get(k)!r}: задача не создана")
        log(f"баланс до: {mc.balance()}")
        tid = mc.create("/animations", {"rig_task_id": base["rig_task"], "action_ids": ids})
        st = {"task": tid, "rig_task": base["rig_task"], "actions": acts, "action_ids": ids}
        STATE.mkdir(parents=True, exist_ok=True)
        st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        log(f"создана задача анимаций {tid}: {acts}")
    res = mc.wait("/animations", st["task"], log=log)
    st["credits"] = res.get("consumed_credits")
    st["expires_at"] = res.get("expires_at")
    st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
    mc.download((res.get("result") or {})["animation_glb_url"], dest)
    log(f"клипы: {dest} ({dest.stat().st_size} байт), кредитов {st['credits']}; баланс после: {mc.balance()}")
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    name = req["character"]
    if req.get("previews"):
        try:
            previews([int(x) for x in req["previews"]])
        except Exception:
            import traceback
            log("превью не получены:\n" + traceback.format_exc())
    new_actions(name, req)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except mc.MeshyError as e:
        print("MESHY ERROR:", e, file=sys.stderr)
        sys.exit(2)
