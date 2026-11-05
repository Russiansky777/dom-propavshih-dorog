#!/usr/bin/env python3
"""Жители v3 — новые модели в Meshy (блок 3, Директор 05.11 22:51: «давай всё сделаем… у Meshy 1100 кредитов… не
жертвовать реалистичностью или качеством»; Павел первым). Только модели-кандидаты и риг: в игру ничего не идёт, файлы
ложатся в релиз npc-v3-work; координатор рендерит их локально, выбирает лучший и собирает игровой GLB.

Вызов (workflow meshy_npc_v3.yml, секрет MESHY_API_KEY):
  python3 tools/meshy_npc_v3.py generate --who pavel --samples 2 --out _v3 [--resume 1=<task_id>,2=<task_id>]
  python3 tools/meshy_npc_v3.py rig --who pavel --sample 1 --out _v3 [--resume <task_id>]

Постановка — по уроку Агаты v5 (DECISIONS 01.11): Multi-Image только фронт и профиль (вид со спины удваивает
предметы на боку), meshy-7.1, геометрия 2k (4k у Multi-Image нет), текстура 4K PBR по тем же видам
(texture_image_urls), A-поза. Выборка у Meshy случайна — по 2 пробы на жителя, лучшую выбирают глазами.
Цена (docs.meshy.ai/api/changelog, сверено 05.11): модель с 4K-текстурой 30 + 5 за 2k = 35; риг 5.
Задача создаётся один раз; --resume продолжает без новых кредитов.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pipeline" / "3d"))
import meshy_client as mc  # noqa: E402
from meshy_character import split_sheet  # noqa: E402

REF = ROOT / "assets" / "reference" / "npc_v2"
# рост — как у моделей v2 (pipeline/requests/npc_<who>.json)
HEIGHT = {"pavel": 1.74, "nina": 1.63, "ilya": 1.82, "ilya_wife": 1.71, "mitya": 1.80, "pelageya": 1.59,
          "tamara": 1.68, "ulyana": 1.28, "manager": 1.76}
SHEET = {w: REF / f"{w}_sheet_v2.png" for w in HEIGHT}
SHEET["manager"] = ROOT / "assets" / "incoming" / "cast_v3" / "manager_sheet.png"
URL = "https://github.com/Russiansky777/dom-propavshih-dorog/releases/download/npc-v3-work/{who}_v3_{s}_rig_input.glb"


def jpeg(v: Path) -> Path:
    from PIL import Image
    j = v.with_suffix(".jpg")
    Image.open(v).convert("RGB").save(j, quality=95)
    return j


def body(views: list[Path]) -> dict:
    two = views[:2]  # фронт и профиль
    # большой лист (Нина — 15 МБ) даёт виды по 4–5 МБ: тело запроса — JPEG 95 (фон листа сплошной, прозрачности нет)
    img = [mc.data_uri(v if v.stat().st_size < 3_000_000 else jpeg(v)) for v in two]
    return {"image_urls": img, "texture_image_urls": [mc.data_uri(jpeg(v)) for v in two],
            "ai_model": "meshy-7.1", "geometry_resolution": "2k", "should_remesh": False, "should_texture": True,
            "enable_pbr": True, "texture_resolution": "4k", "pose_mode": "a-pose", "target_formats": ["glb"],
            "auto_size": True, "origin_at": "bottom", "multi_view_thumbnails": True, "alpha_thumbnail": True}


def generate(a) -> int:
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    views = split_sheet(SHEET[a.who], out / f"{a.who}_views")
    print(f"{a.who}: ракурсов {len(views)} → {[v.name for v in views]}", flush=True)
    if len(views) < 2:
        print("нужны хотя бы фронт и профиль", flush=True)
        return 1
    resume = dict(kv.split("=", 1) for kv in a.resume.split(",") if "=" in kv)
    b = body(views)
    print(f"баланс: {mc.balance()}", flush=True)
    tasks = {}
    for s in range(1, a.samples + 1):
        k = str(s)
        if k in resume:
            tasks[k] = resume[k]
            continue
        try:
            tasks[k] = mc.create("/multi-image-to-3d", b)
        except mc.MeshyError as e:
            print(f"проба {k}: не создана — {e}", flush=True)
            continue
        print(f"проба {k}: задача {tasks[k]}", flush=True)
        (out / f"{a.who}_v3_{k}_body.json").write_text(json.dumps(
            {"task": tasks[k], **{x: y for x, y in b.items() if "url" not in x}}, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = 0
    for k, tid in tasks.items():
        stem = f"{a.who}_v3_{k}"
        try:
            t = mc.wait("/multi-image-to-3d", tid, poll_s=15, max_s=3600, log=lambda m: print(m, flush=True))
        except mc.MeshyError as e:
            print(f"проба {k}: {e}", flush=True)
            (out / f"{stem}_error.txt").write_text(str(e), encoding="utf-8")
            continue
        mc.download(t["model_urls"]["glb"], out / f"{stem}.glb")
        for side, url in (t.get("thumbnail_urls") or {}).items():
            mc.download(url, out / f"{stem}_{side}.png")
        keep = {x: t.get(x) for x in ("id", "type", "status", "consumed_credits", "created_at", "finished_at")}
        (out / f"{stem}_task.json").write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"проба {k}: готово, кредитов {t.get('consumed_credits')}, GLB {(out / f'{stem}.glb').stat().st_size // 1024} КБ", flush=True)
        ok += 1
    print(f"баланс после: {mc.balance()}", flush=True)
    return 0 if ok else 1


def rig(a) -> int:
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = f"{a.who}_v3_{a.sample}"
    print(f"баланс: {mc.balance()}", flush=True)
    tid = a.resume or mc.create("/rigging", {"model_url": URL.format(who=a.who, s=a.sample), "height_meters": HEIGHT[a.who]})
    print(f"риг {stem}: задача {tid}", flush=True)
    t = mc.wait("/rigging", tid, poll_s=10, max_s=3600, log=lambda m: print(m, flush=True))
    res = t.get("result") or {}
    mc.download(res["rigged_character_glb_url"], out / f"{stem}_rigged.glb")
    keep = {x: t.get(x) for x in ("id", "status", "consumed_credits", "created_at", "finished_at")}
    (out / f"{stem}_rig_task.json").write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"риг {stem}: готово, кредитов {t.get('consumed_credits')}", flush=True)
    print(f"баланс после: {mc.balance()}", flush=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["generate", "rig"])
    ap.add_argument("--who", required=True, choices=sorted(HEIGHT))
    ap.add_argument("--samples", type=int, default=2)
    ap.add_argument("--sample", default="1")
    ap.add_argument("--out", default="_v3")
    ap.add_argument("--resume", default="")
    a = ap.parse_args()
    return generate(a) if a.mode == "generate" else rig(a)


if __name__ == "__main__":
    sys.exit(main())
