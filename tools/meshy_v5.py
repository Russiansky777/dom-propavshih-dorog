#!/usr/bin/env python3
"""Агата v5 — новые модели-кандидаты в Meshy (Директор 31.10: «переделать Агату целиком… идеальная и по модели, и по
движениям»; 22:03 «делай всё и сразу»; кредиты Meshy разрешены). Только генерация кандидатов на выбор — в игру ничего
не идёт: файлы ложатся в релиз agata-v5-work, координатор рендерит их локально и показывает Директору.

Вызов (workflow meshy_agata_v5.yml, секрет MESHY_API_KEY):
  python3 tools/meshy_v5.py --variants A,B,C --out _v5 [--resume A=<task_id>,…]

Варианты (параметры — docs.meshy.ai, сверено 31.10: image-to-3d, multi-image-to-3d):
  A  multi-image-to-3d meshy-7.1, геометрия 2k, текстура 4k PBR, A-поза; texture_image_urls — те же три вида листа
     (текстура по рисунку, а не «по догадке» — лицо и узор платка)
  B  image-to-3d meshy-7.1, геометрия 4k (есть только у одного вида), фронт листа, текстура 4k PBR, A-поза
  C  image-to-3d smart-topology meshy-t2.5 — чистая сетка ≤ 30 тыс. (сгибы юбки и локтей), текстура 4k PBR, A-поза
  D  multi-image-to-3d meshy-7.1, как A, но remesh quad 150 тыс. (ровная сетка под риг при прежней детальности)
Задача создаётся один раз; повторный запуск с --resume id продолжает без новых кредитов.
Модуль-клиент — pipeline/3d/meshy_client.py (только импорт; pipeline/ — зона Codex, не правится).
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

SHEET = ROOT / "assets" / "reference" / "agata_sheet_v2.png"


def jpeg(v: Path) -> Path:
    """Копия вида в JPEG 95 — для texture_image_urls (тело запроса не раздувать: три PNG по 2–3 МБ уже в image_urls)."""
    from PIL import Image
    j = v.with_suffix(".jpg")
    Image.open(v).convert("RGB").save(j, quality=95)
    return j


def bodies(views: list[Path]) -> dict[str, tuple[str, dict]]:
    uris = [mc.data_uri(v) for v in views]
    tex = [mc.data_uri(jpeg(v)) for v in views]
    front = uris[0]
    common_tex = {"should_texture": True, "enable_pbr": True, "texture_resolution": "4k", "pose_mode": "a-pose",
                  "target_formats": ["glb"], "auto_size": True, "origin_at": "bottom", "multi_view_thumbnails": True,
                  "alpha_thumbnail": True}
    return {
        "A": ("/multi-image-to-3d", {"image_urls": uris, "ai_model": "meshy-7.1", "geometry_resolution": "2k",
                                     "should_remesh": False, "texture_image_urls": tex, **common_tex}),
        "B": ("/image-to-3d", {"image_url": front, "ai_model": "meshy-7.1", "geometry_resolution": "4k",
                               "should_remesh": False, **common_tex}),
        "C": ("/image-to-3d", {"image_url": front, "model_type": "smart-topology", "ai_model": "meshy-t2.5",
                               "target_polycount": 30000, **common_tex}),
        "D": ("/multi-image-to-3d", {"image_urls": uris, "ai_model": "meshy-7.1", "geometry_resolution": "2k",
                                     "should_remesh": True, "topology": "quad", "target_polycount": 150000,
                                     "save_pre_remeshed_model": False, "texture_image_urls": tex, **common_tex}),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", default="A,B,C")
    ap.add_argument("--out", default="_v5")
    ap.add_argument("--resume", default="", help="A=<task_id>,B=<task_id>")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    views = split_sheet(SHEET, out / "views")
    print(f"ракурсов: {len(views)} → {[v.name for v in views]}", flush=True)
    resume = dict(kv.split("=", 1) for kv in args.resume.split(",") if "=" in kv)
    want = [v.strip() for v in args.variants.split(",") if v.strip()]
    spec = bodies(views[:4])
    print(f"баланс: {mc.balance()}", flush=True)
    tasks = {}
    for v in want:
        path, body = spec[v]
        if v in resume:
            tasks[v] = (path, resume[v])
            continue
        try:
            tid = mc.create(path, body)
        except mc.MeshyError as e:
            print(f"{v}: не создана — {e}", flush=True)
            (out / f"agata_v5{v}_error.txt").write_text(str(e), encoding="utf-8")
            continue
        tasks[v] = (path, tid)
        print(f"{v}: задача {tid} ({path}) {json.dumps({k: x for k, x in body.items() if 'url' not in k}, ensure_ascii=False)}", flush=True)
        (out / f"agata_v5{v}_body.json").write_text(json.dumps({"path": path, "task": tid, **{k: x for k, x in body.items() if 'url' not in k}}, ensure_ascii=False, indent=1), encoding="utf-8")
    ok = 0
    for v, (path, tid) in tasks.items():
        try:
            t = mc.wait(path, tid, poll_s=15, max_s=3600, log=lambda m: print(m, flush=True))
        except mc.MeshyError as e:
            print(f"{v}: {e}", flush=True)
            (out / f"agata_v5{v}_error.txt").write_text(str(e), encoding="utf-8")
            continue
        mc.download(t["model_urls"]["glb"], out / f"agata_v5{v}.glb")
        for side, url in (t.get("thumbnail_urls") or {}).items():
            mc.download(url, out / f"agata_v5{v}_{side}.png")
        if t.get("alpha_thumbnail_url"):
            mc.download(t["alpha_thumbnail_url"], out / f"agata_v5{v}_alpha.png")
        for i, tex in enumerate(t.get("texture_urls") or []):
            for kind, url in tex.items():
                if url:
                    mc.download(url, out / f"agata_v5{v}_tex{i}_{kind}.png")
        keep = {k: t.get(k) for k in ("id", "type", "status", "consumed_credits", "created_at", "finished_at",
                                      "texture_prompt", "art_style")}
        keep["variant"] = v
        keep["endpoint"] = path
        (out / f"agata_v5{v}_task.json").write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"{v}: готово, кредитов {t.get('consumed_credits')}, GLB {(out / f'agata_v5{v}.glb').stat().st_size // 1024} КБ", flush=True)
        ok += 1
    print(f"баланс после: {mc.balance()}", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
