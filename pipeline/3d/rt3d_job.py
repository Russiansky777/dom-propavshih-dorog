#!/usr/bin/env python3
"""Агата в реальном 3D: подготовка исходников без новой модели.

  python3 pipeline/3d/rt3d_job.py --request pipeline/requests/rt3d_agata.json

Запрос (JSON):
  character      — имя (state: pipeline/3d/state/<имя>.json — оттуда rig_task)
  from_run       — прогон pipeline-character, чей артефакт glb-<id> уже разложен в pipeline/3d/out (делает workflow)
  base_glb       — какой GLB из out/<имя>/ стать основой игры (обычно animations.glb: сетка + скелет + клипы)
  previews       — id действий каталога Meshy: скачать превью-GIF (бесплатно, публичный каталог) → полосы кадров
  new_actions    — {ключ: action_id}: новые клипы на СУЩЕСТВУЮЩИЙ риг (POST /animations, 3 кредита за действие)
  max_credits    — потолок на этот запрос; больше — задача не создаётся
Состояние новых задач — pipeline/3d/state/<имя>_rt3d.json (повторный запуск не создаёт задачу заново).
Результат: assets/characters/<имя>/rt3d/{<имя>.glb, <имя>_extra.glb}, pipeline/3d/catalog/meshy_animations.json,
Docs/evidence/M1/agata_v2/catalog/<id>_<имя>.jpg (+ metrics.json: насколько клип «живой» по пикселям превью).
"""
from __future__ import annotations

import argparse
import io
import json
import shutil
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshy_client as mc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "pipeline" / "3d" / "state"
OUT = ROOT / "pipeline" / "3d" / "out"
CATALOG_URL = "https://api.meshy.ai/web/public/animations/resources"


def log(m: str) -> None:
    print(m, flush=True)


def fetch(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "dom-propavshih-dorog-pipeline"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def catalog() -> list[dict]:
    raw = json.loads(fetch(CATALOG_URL).decode("utf-8"))
    items = raw if isinstance(raw, list) else raw.get("result", raw.get("data", raw.get("items", [])))
    return items


def strip_from_gif(data: bytes, n: int = 12, h: int = 200):
    """GIF → полоса из n равномерных кадров + метрики движения (доля изменённых пикселей между соседними
    кадрами и сдвиг центра силуэта) — грубая мера: «живой» idle — мелкое ровное движение, поворот — большой сдвиг."""
    from PIL import Image, ImageSequence
    import numpy as np
    im = Image.open(io.BytesIO(data))
    frames = [f.convert("RGB") for f in ImageSequence.Iterator(im)]
    if not frames:
        return None, {}
    idx = [round(i * (len(frames) - 1) / max(n - 1, 1)) for i in range(n)]
    w = round(frames[0].width * h / frames[0].height)
    strip = Image.new("RGB", (w * n, h), (40, 40, 40))
    for k, i in enumerate(idx):
        strip.paste(frames[i].resize((w, h)), (k * w, 0))
    arr = [np.asarray(f.resize((w, h)).convert("L"), dtype=np.float32) for f in frames]
    bg = np.median(np.stack(arr[:: max(1, len(arr) // 8)]), axis=0)
    diffs, cx = [], []
    for a, b in zip(arr, arr[1:]):
        diffs.append(float((np.abs(a - b) > 12).mean()))
    for a in arr:
        mask = np.abs(a - bg) > 18
        ys, xs = np.nonzero(mask)
        cx.append(float(xs.mean() / w) if len(xs) else 0.5)
    met = {"frames": len(frames), "duration_s": round(sum(f.info.get("duration", 40) for f in ImageSequence.Iterator(Image.open(io.BytesIO(data)))) / 1000.0, 2),
           "motion_mean": round(sum(diffs) / max(len(diffs), 1), 4), "motion_max": round(max(diffs) if diffs else 0.0, 4),
           "centroid_x_range": round(max(cx) - min(cx), 3) if cx else 0.0}
    return strip, met


def do_previews(ids: list[int], evid: Path, cat_path: Path) -> None:
    items = catalog()
    cat_path.parent.mkdir(parents=True, exist_ok=True)
    slim = [{k: it.get(k) for k in ("id", "key", "name", "category", "subCategory", "rigType", "previewUrl", "isFree")} for it in items]
    cat_path.write_text(json.dumps(slim, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"каталог: {len(slim)} действий → {cat_path}")
    by_id = {int(it["id"]): it for it in slim if it.get("id") is not None}
    evid.mkdir(parents=True, exist_ok=True)
    metrics = {}
    for aid in ids:
        it = by_id.get(int(aid))
        if not it or not it.get("previewUrl"):
            log(f"  {aid}: нет в каталоге или нет превью")
            continue
        try:
            data = fetch(it["previewUrl"])
        except Exception as e:  # превью — не критично
            log(f"  {aid}: превью не скачалось: {e}")
            continue
        strip, met = strip_from_gif(data)
        safe = "".join(ch if ch.isalnum() else "_" for ch in str(it.get("key") or it.get("name")))
        if strip is not None:
            strip.save(evid / f"{int(aid):03d}_{safe}.jpg", quality=82)
        met.update({"name": it.get("name"), "key": it.get("key"), "category": it.get("category"), "subCategory": it.get("subCategory")})
        metrics[str(aid)] = met
        log(f"  {aid} {it.get('name')}: {met}")
    (evid / "metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=1), encoding="utf-8")


def do_new_actions(name: str, req: dict, out_dir: Path) -> None:
    acts: dict = req.get("new_actions") or {}
    if not acts:
        return
    st_path = STATE / f"{name}_rt3d.json"
    st = json.loads(st_path.read_text(encoding="utf-8")) if st_path.exists() else {}
    base = json.loads((STATE / f"{name}.json").read_text(encoding="utf-8"))
    cost = 3 * len(acts)
    cap = int(req.get("max_credits", 0))
    tag = str(req.get("rev", 1))
    tasks = st.setdefault("tasks", {})
    if tag not in tasks:
        if cost > cap:
            raise SystemExit(f"новые действия стоят {cost} кредитов > max_credits {cap} — задача не создана")
        log(f"баланс до: {mc.balance()}")
        body = {"rig_task_id": base["rig_task"], "action_ids": [int(v) for v in acts.values()]}
        tid = mc.create("/animations", body)
        tasks[tag] = {"task": tid, "actions": acts, "rig_task": base["rig_task"]}
        st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        log(f"создана задача анимаций {tid}: {acts}")
    t = tasks[tag]
    res = mc.wait("/animations", t["task"], log=log)
    t["credits"] = res.get("consumed_credits")
    t["expires_at"] = res.get("expires_at")
    st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
    url = (res.get("result") or {}).get("animation_glb_url")
    dest = out_dir / f"{name}_extra_r{tag}.glb"
    mc.download(url, dest)
    log(f"новые клипы: {dest} ({dest.stat().st_size} байт), кредитов {t['credits']}; баланс после: {mc.balance()}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    name = req["character"]
    out_dir = ROOT / "assets" / "characters" / name / "rt3d"
    out_dir.mkdir(parents=True, exist_ok=True)
    base = req.get("base_glb", "animations.glb")
    src = OUT / name / base
    if src.exists():
        dest = out_dir / f"{name}.glb"
        if src.stat().st_size > 95 * 1024 * 1024:
            raise SystemExit(f"{src} больше 95 МБ — в git не положить")
        if not dest.exists() or dest.read_bytes() != src.read_bytes():
            shutil.copyfile(src, dest)
        log(f"основа: {src} → {dest} ({dest.stat().st_size} байт)")
    else:
        log(f"нет {src} (артефакт не разложен?) — основа не обновлена")
    for f in sorted((OUT / name).glob("*.glb")) if (OUT / name).exists() else []:
        log(f"  в артефакте: {f.name} {f.stat().st_size} байт")
    if req.get("previews"):
        do_previews([int(x) for x in req["previews"]], ROOT / "Docs" / "evidence" / "M1" / "agata_v2" / "catalog", ROOT / "pipeline" / "3d" / "catalog" / "meshy_animations.json")
    do_new_actions(name, req, out_dir)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except mc.MeshyError as e:
        print("MESHY ERROR:", e, file=sys.stderr)
        sys.exit(2)
