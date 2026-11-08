#!/usr/bin/env python3
"""Оживление нарисованного кадра: image-to-video через fal.ai, несколько моделей на один кадр для сравнения
(Директор 08.11, 21:57–22:06: «из статичных кадров типа с объятиями сделаем видео… через несколько моделей и
сравнить»). Запускается в GitHub Actions (.github/workflows/pipeline_video.yml), ключ — секрет FAL_API; отсюда
(из сессии Claude Code) сеть к fal.ai закрыта.

Запрос — JSON (pipeline/requests/video_<проба>.json):
  {"trial": "hug_1", "attempts": 1,
   "frames": [{"id": "F_hug_pelageya", "image": "game/assets/rooms/F_hug_pelageya/bg.png", "prompt": "..."}],
   "models": [{"id": "fal-ai/kling-video/v3/standard/image-to-video", "args": {"duration": "5"}}]}
Результат: assets/incoming/video/<trial>/<frame>__<model>_<n>.mp4 + report.json (модель, длительность, секунды,
ошибка) + last_run.log. Ключ в журнал не попадает.

  python3 tools/video_trial.py --request pipeline/requests/video_hug_1.json [--out assets/incoming/video]
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request


def slug(model_id: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", model_id.lower()).strip("-")


def find_video_url(res) -> str:
    if isinstance(res, dict):
        v = res.get("video")
        if isinstance(v, dict) and v.get("url"):
            return str(v["url"])
        if isinstance(v, str) and v.startswith("http"):
            return v
        for k in ("videos", "outputs", "output"):
            x = res.get(k)
            if isinstance(x, list) and x and isinstance(x[0], dict) and x[0].get("url"):
                return str(x[0]["url"])
        for x in res.values():
            u = find_video_url(x)
            if u:
                return u
    if isinstance(res, list):
        for x in res:
            u = find_video_url(x)
            if u:
                return u
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    ap.add_argument("--out", default="assets/incoming/video")
    a = ap.parse_args()
    if not os.environ.get("FAL_KEY"):
        print("нет FAL_KEY (секрет FAL_API)", file=sys.stderr)
        return 2
    import fal_client  # pip install fal-client

    req = json.load(open(a.request, encoding="utf-8"))
    trial = req["trial"]
    out_dir = os.path.join(a.out, trial)
    os.makedirs(out_dir, exist_ok=True)
    attempts = int(req.get("attempts", 1))
    report_p = os.path.join(out_dir, "report.json")
    report = json.load(open(report_p, encoding="utf-8")) if os.path.exists(report_p) else {"trial": trial, "runs": []}
    for fr in req["frames"]:
        print(f"== кадр {fr['id']}: {fr['image']}")
        t0 = time.time()
        image_url = fal_client.upload_file(fr["image"])
        print(f"   загружен за {time.time() - t0:.1f} с")
        for m in req["models"]:
            mid = m["id"]
            for n in range(1, attempts + 1):
                name = f"{fr['id']}__{slug(mid)}_{n}.mp4"
                dst = os.path.join(out_dir, name)
                if os.path.exists(dst):
                    print(f"   {name}: уже есть")
                    continue
                args = {"prompt": fr["prompt"], "image_url": image_url}
                args.update(m.get("args", {}))
                row = {"frame": fr["id"], "model": mid, "attempt": n, "file": name, "args": {k: v for k, v in args.items() if k != "image_url"}}
                t1 = time.time()
                try:
                    res = fal_client.subscribe(mid, arguments=args, with_logs=False)
                    url = find_video_url(res)
                    if not url:
                        raise RuntimeError("в ответе нет video.url: %s" % json.dumps(res)[:400])
                    urllib.request.urlretrieve(url, dst)
                    row["seconds"] = round(time.time() - t1, 1)
                    row["bytes"] = os.path.getsize(dst)
                    print(f"   {mid} #{n}: OK {row['seconds']} с, {row['bytes'] // 1024} КБ")
                except Exception as e:  # noqa: BLE001 — одна модель не должна валить остальные
                    msg = str(e)
                    msg = re.sub(r"(?i)key [a-z0-9:_-]+", "key …", msg)
                    row["error"] = msg[:800]
                    row["seconds"] = round(time.time() - t1, 1)
                    print(f"   {mid} #{n}: ОШИБКА {msg[:300]}")
                report["runs"].append(row)
                json.dump(report, open(report_p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    ok = sum(1 for r in report["runs"] if "error" not in r)
    print(f"готово: {ok} клипов, {len(report['runs']) - ok} ошибок → {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
