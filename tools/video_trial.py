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
        # картинка идёт прямо в запросе (data URI, JPEG до 1280 px): загрузка в хранилище fal отвечала 403 на
        # токен хранилища (run 42524225322) — ключу она не нужна
        from PIL import Image
        import base64, io
        im = Image.open(fr["image"]).convert("RGB")
        # Director 09.11, 12:40 («почему мы делали 1280… разве у нас игра в 1280?»): request `image_max` (px of the long
        # side; 0 — the picture as it is) and `jpeg_q`; old requests keep 1280 / 92
        cap = int(req.get("image_max", 1280))
        if cap > 0 and im.width > cap:
            im = im.resize((cap, round(im.height * cap / im.width)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=int(req.get("jpeg_q", 92)))
        image_url = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
        print(f"   картинка {im.width}x{im.height}, {len(buf.getvalue()) // 1024} КБ")
        # все модели разом (Директор 22:40 «почему так долго?»): время прогона — самая медленная модель, не сумма
        from concurrent.futures import ThreadPoolExecutor

        def one(m, n):
            mid = m["id"]
            name = f"{fr['id']}__{slug(mid)}_{n}.mp4"
            dst = os.path.join(out_dir, name)
            if os.path.exists(dst):
                print(f"   {name}: уже есть")
                return None
            keys = m.get("image_key", "image_url")   # Wan 3.0: start_image_url; петля Kling: ["image_url", "tail_image_url"]
            args = {"prompt": fr["prompt"]}
            for k in (keys if isinstance(keys, list) else [keys]):
                args[k] = image_url
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
                print(f"   {mid} #{n}: OK {row['seconds']} с, {row['bytes'] // 1024} КБ", flush=True)
            except Exception as e:  # noqa: BLE001 — одна модель не должна валить остальные
                msg = re.sub(r"(?i)key [a-z0-9:_-]+", "key …", str(e))
                row["error"] = msg[:800]
                row["seconds"] = round(time.time() - t1, 1)
                print(f"   {mid} #{n}: ОШИБКА {msg[:300]}", flush=True)
            return row

        jobs = [(m, n) for m in req["models"] for n in range(1, attempts + 1)]
        with ThreadPoolExecutor(max_workers=max(1, len(jobs))) as ex:
            for row in ex.map(lambda j: one(*j), jobs):
                if row is not None:
                    report["runs"].append(row)
                    json.dump(report, open(report_p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    ok = sum(1 for r in report["runs"] if "error" not in r)
    print(f"готово: {ok} клипов, {len(report['runs']) - ok} ошибок → {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
