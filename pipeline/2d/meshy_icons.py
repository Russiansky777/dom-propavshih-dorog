#!/usr/bin/env python3
"""Иконки предметов через Meshy text-to-image (POST /openapi/v1/text-to-image, remove_background → RGBA PNG).

Запрос: pipeline/requests/icons_<набор>.json (или images_<набор>.json)
  {"set": "icons_e0e1", "ai_model": "nano-banana-2", "style": "<общий стиль>",
   "items": {"<item_id>": "<описание предмета>"}, "redo": ["<item_id>", ...],
   "out_dir": "assets/icons",            # необязательно
   "options": {"aspect_ratio": "1:1", "remove_background": true, "pose_mode": "a-pose", "generate_multi_view": false}}
Результат: <out_dir>/<item_id>.png (при generate_multi_view — <item_id>_v1..3.png) + <out_dir>/_contact_<набор>.png;
состояние задач — pipeline/2d/state/<набор>.json.
Повторный запуск не тратит кредиты на уже готовые предметы (кроме перечисленных в redo).
"""
import argparse, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline" / "3d"))
import meshy_client as mc  # noqa: E402

OUT_DEFAULT = ROOT / "assets" / "icons"
STATE = ROOT / "pipeline" / "2d" / "state"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    name = req["set"]
    OUT = ROOT / req["out_dir"] if req.get("out_dir") else OUT_DEFAULT
    opts = {"aspect_ratio": "1:1", "remove_background": True}
    opts.update(req.get("options", {}))
    if opts.get("generate_multi_view"):
        opts.pop("aspect_ratio", None)  # по документации нельзя вместе с generate_multi_view
    OUT.mkdir(parents=True, exist_ok=True); STATE.mkdir(parents=True, exist_ok=True)
    sp = STATE / f"{name}.json"
    st = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {}
    for rid in req.get("redo", []):
        st.pop(rid, None)
    model = req.get("ai_model", "nano-banana-2")
    print(f"[{name}] баланс: {mc.balance()}", flush=True)
    # 1. создать недостающие задачи
    for item, desc in req["items"].items():
        if item in st and st[item].get("task"):
            continue
        prompt = f"{desc}. {req['style']}"
        tid = mc.create("/text-to-image", {"ai_model": model, "prompt": prompt, **opts})
        st[item] = {"task": tid, "prompt": prompt, "model": model}
        sp.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[{name}] {item}: задача {tid}", flush=True)
    # 2. дождаться и скачать
    for item in req["items"]:
        r = mc.wait("/text-to-image", st[item]["task"], log=lambda m: print(f"  {item}: {m}", flush=True))
        urls = r.get("image_urls") or []
        if not urls:
            print(f"[{name}] {item}: нет image_urls — {r.get('task_error')}", file=sys.stderr); continue
        if len(urls) == 1:
            mc.download(urls[0], OUT / f"{item}.png")
        else:
            for k, u in enumerate(urls, 1):
                mc.download(u, OUT / f"{item}_v{k}.png")
        st[item]["credits"] = r.get("consumed_credits")
        sp.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[{name}] {item}: готово ({r.get('consumed_credits')} кр.)", flush=True)
    # 3. контактный лист для приёмки глазами
    try:
        from PIL import Image
        files = []
        for i in req["items"]:
            files += [OUT / f"{i}.png"] if (OUT / f"{i}.png").exists() else sorted(OUT.glob(f"{i}_v*.png"))
        ims = [Image.open(f).convert("RGBA") for f in files]
        if ims:
            s = 256; cols = min(len(ims), 4); rows = (len(ims) + cols - 1) // cols
            sheet = Image.new("RGBA", (cols * s, rows * s), (58, 52, 46, 255))
            for k, im in enumerate(ims):
                im.thumbnail((s - 16, s - 16)); sheet.alpha_composite(im, ((k % cols) * s + (s - im.width) // 2, (k // cols) * s + (s - im.height) // 2))
            sheet.save(OUT / f"_contact_{name}.png")
    except Exception as e:  # контактный лист не обязателен
        print("контактный лист не собран:", e, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
