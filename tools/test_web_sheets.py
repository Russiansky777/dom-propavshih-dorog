#!/usr/bin/env python3
"""I-T4b: самопроверка веб-копий листов (tools/make_web_sheets.py) и пресетов экспорта — код 0, если всё сходится.

1. Синтетический атлас 2,25× (две страницы, куски разного цвета вплотную через зазор) → веб-копия 1×: размер кадра,
   texture_scale, прямоугольники в доле 1/2,25, поле не выводит кусок за кадр, цвет каждого куска не смешан с соседом.
2. export_presets.cfg: веб — фича web_atlas и без полных листов k× (жители v2, Агата); Linux и Windows — без
   assets/characters_web (настольные сборки остаются в 2,25×); Windows Lite (I-T7) — как веб, один exe.
3. Таблица SCALES покрывает всех жителей v2 и Агату, и веб-разрешение меньше исходного.

  python3 tools/test_web_sheets.py [--quiet]
"""
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("mws", ROOT / "tools" / "make_web_sheets.py")
mws = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mws)

fails = []


def check(ok: bool, msg: str) -> None:
    if not ok:
        fails.append(msg)


def synthetic() -> None:
    with tempfile.TemporaryDirectory() as td:
        src, dst = Path(td) / "src", Path(td) / "dst"
        sid = "test_v2"
        (src / sid).mkdir(parents=True)
        fw, fh = 648, 864
        colors = [(200, 30, 30, 255), (30, 200, 30, 255), (30, 30, 200, 255), (200, 200, 30, 255)]
        p0 = Image.new("RGBA", (600, 800), (0, 0, 0, 0))
        p1 = Image.new("RGBA", (300, 800), (0, 0, 0, 0))
        rects = []
        for i, c in enumerate(colors):
            page = 0 if i < 3 else 1
            x = (i % 3) * 200 if page == 0 else 0
            w, h = 192, 760
            (p0 if page == 0 else p1).paste(Image.new("RGBA", (w, h), c), (x, 0))
            rects.append([x, 0, w, h, 228, 52, page])
        p0.save(src / sid / "talk.png")
        p1.save(src / sid / "talk_p1.png")
        sp = {"name": sid, "frame_w": fw, "frame_h": fh, "texture_scale": 2.25, "directions": 2, "actions": {
            "talk": {"sheet": "talk.png", "frames": 2, "atlas": {"rects": rects, "size": [600, 800], "gap": 8,
                     "pages": ["talk.png", "talk_p1.png"], "page_sizes": [[600, 800], [300, 800]]}}}}
        (src / sid / "sprites.json").write_text(json.dumps(sp), encoding="utf-8")
        mws.SRC, mws.DST = src, dst
        res = mws.make(sid, 1.0)
        check(res.startswith("сделано"), f"синтетика: {res}")
        out = json.loads((dst / sid / "sprites.json").read_text(encoding="utf-8"))
        check(out["frame_w"] == 288 and out["frame_h"] == 384, f"кадр {out['frame_w']}×{out['frame_h']} ≠ 288×384")
        check(out["texture_scale"] == 1.0, "texture_scale веб-копии ≠ 1.0")
        check(abs(fh / 2.25 - out["frame_h"] / out["texture_scale"]) < 0.01, "рост фигуры на экране изменился бы")
        imgs = [Image.open(dst / sid / p).convert("RGBA") for p in out["actions"]["talk"]["atlas"]["pages"]]
        for c, r in zip(colors, out["actions"]["talk"]["atlas"]["rects"]):
            x, y, w, h, ox, oy, pg = r
            check(ox + w <= out["frame_w"] and oy + h <= out["frame_h"], f"кусок {r} выходит за кадр")
            check(abs(w - 192 / 2.25) <= 1 and abs(h - 760 / 2.25) <= 1, f"кусок {r}: не в доле 1/2,25")
            piece = imgs[pg].crop((x, y, x + w, y + h))
            px = [piece.getpixel((i, j)) for i in (0, w // 2, w - 1) for j in (0, h // 2, h - 1)]
            check(all(max(abs(a - b) for a, b in zip(p[:3], c[:3])) < 40 and p[3] > 200 for p in px),
                  f"кусок {r}: цвет смешан с соседом или прозрачный край ({px[:3]})")
        check((dst / sid / "talk.png.import").exists(), "нет .import веб-копии")
        imp = (dst / sid / "talk.png.import").read_text(encoding="utf-8")
        check("compress/mode=2" in imp and "mipmaps/generate=true" in imp, "веб-копия не BPTC с мипмапами")
        check(mws.make(sid, 1.0).startswith("ok"), "повторный запуск пересобрал готовую копию")


def presets() -> None:
    txt = (ROOT / "game" / "export_presets.cfg").read_text(encoding="utf-8")
    blocks = {}
    for part in txt.split("[preset.")[1:]:
        name = next((ln.split("=", 1)[1].strip('"') for ln in part.splitlines() if ln.startswith("name=")), "")
        if name:
            last = name
            blocks[name] = part
        elif blocks:
            blocks[last] += part   # [preset.N.options]
    web = blocks.get("Web", "")
    check('custom_features="web_atlas"' in web, "веб-пресет без фичи web_atlas")
    check("assets/characters/*_v2/*.png" in web, "веб-пресет везёт полные листы жителей v2")
    check("assets/characters/agata/idle*.png" in web, "веб-пресет везёт полные листы Агаты")
    for n in ("Linux", "Windows"):
        check("assets/characters_web/*" in blocks.get(n, ""), f"{n}: везёт веб-копии листов")
        check("web_atlas" not in blocks.get(n, "").split("custom_features=")[1].splitlines()[0], f"{n}: фича web_atlas")
    # I-T7: полная Windows — PCK рядом (вшитый с листами 2,25× > 2 ГиБ); Lite — один exe на веб-копиях, как сайт
    check("binary_format/embed_pck=false" in blocks.get("Windows", ""), "Windows: PCK вшит (с листами 2,25× > 2 ГиБ)")
    lite = blocks.get("Windows Lite", "")
    check('custom_features="web_atlas"' in lite, "Windows Lite: нет фичи web_atlas")
    check("binary_format/embed_pck=true" in lite, "Windows Lite: PCK не вшит")
    check("assets/characters/*_v2/*.png" in lite and "assets/characters/agata/idle*.png" in lite,
          "Windows Lite везёт полные листы")
    check('export_path="../build/windows/DomPropavshihDorog.exe"' in lite, "Windows Lite: не тот путь exe (его выкладывает workflow)")


def scales() -> None:
    for sid in ["nina_v2", "ilya_v2", "ilya_wife_v2", "ulyana_v2", "mitya_v2", "pelageya_v2", "pavel_v2", "tamara_v2", "agata"]:
        sc = mws.target_scale(sid)
        check(sc is not None and sc < 2.25, f"{sid}: нет веб-разрешения меньше 2,25× ({sc})")


def main() -> int:
    synthetic()
    presets()
    scales()
    quiet = "--quiet" in sys.argv
    if fails:
        for f in fails:
            print("FAIL test_web_sheets:", f)
        return 1
    if not quiet:
        print("test_web_sheets: OK")
    else:
        print("[data] test_web_sheets.py: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
