#!/usr/bin/env python3
"""I-T7: кадр жителя так, как его везёт сборка (BPTC из pck, раскодирован Godot — tools/decode_pack_textures.gd):
ПК полная (build/windows/full/*.pck, лист 2,25×) / ПК Lite = сайт (build/windows/DomPropavshihDorog.exe, веб-копия) /
прежний ПК 24.10 (житель v1, исходный лист). Один экранный размер: верх — кадр 576 px (окно 1080p), низ — 864 px.
  python3 tools/i_t7_frames.py nina_v2 pelageya_v2 agata  → Docs/evidence/i_t7/pc_vs_lite_<id>.jpg
Нужны готовые сборки (tools/export_windows.sh) и $GODOT."""
import json, os, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent
FULL = ROOT / "build/windows/full/DomPropavshihDorog.pck"
LITE = ROOT / "build/windows/DomPropavshihDorog.exe"
OUT = ROOT / "Docs/evidence/i_t7"
try:
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
except OSError:
    FONT = ImageFont.load_default()
V1 = {"nina_v2": "nina", "pelageya_v2": "pelageya", "ilya_v2": "ilya", "mitya_v2": "mitya", "pavel_v2": "pavel"}


def pick(sp: dict) -> tuple[str, int, int]:
    action = "talk" if "talk" in sp["actions"] else "idle"
    return action, 1, 3 if action == "talk" else 0


def decode(pack: Path, res: str, tmp: Path) -> Image.Image:
    out = tmp / (pack.stem + "_" + res.replace("/", "_").replace(":", ""))
    if not out.exists():
        subprocess.run([os.environ["GODOT"], "--headless", "--main-pack", str(pack), "-s",
                        str(ROOT / "tools/decode_pack_textures.gd"), "--", res, str(out)],
                       check=True, capture_output=True, cwd=tmp)
    return Image.open(out).convert("RGBA")


def frame(base: str, sid: str, pack: Path, tmp: Path) -> Image.Image:
    d = ROOT / "game/assets" / base / sid
    sp = json.loads((d / "sprites.json").read_text(encoding="utf-8"))
    action, row, i = pick(sp)
    act = sp["actions"][action]
    at = act["atlas"]
    r = at["rects"][row * act["frames"] + i]
    page = at.get("pages", [act["sheet"]])[r[6] if len(r) > 6 else 0]
    im = decode(pack, f"res://assets/{base}/{sid}/{page}", tmp).crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
    out = Image.new("RGBA", (sp["frame_w"], sp["frame_h"]), (0, 0, 0, 0))
    out.paste(im, (r[4], r[5]))
    return out


def frame_v1(sid: str) -> Image.Image | None:
    d = ROOT / "game/assets/characters" / sid
    if not (d / "sprites.json").exists():
        return None
    sp = json.loads((d / "sprites.json").read_text(encoding="utf-8"))
    act = sp["actions"]["talk"]
    r = act["atlas"]["rects"][1 * act["frames"] + 3]
    im = Image.open(d / act["sheet"]).convert("RGBA").crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
    out = Image.new("RGBA", (sp["frame_w"], sp["frame_h"]), (0, 0, 0, 0))
    out.paste(im, (r[4], r[5]))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for sid in sys.argv[1:]:
            cols = [(frame("characters", sid, FULL, tmp), "ПК полная (zip), лист 2,25×"),
                    (frame("characters_web", sid, LITE, tmp), "ПК Lite = сайт, веб-копия")]
            old = frame_v1(V1.get(sid, "")) if sid in V1 else None
            if old is not None:
                cols.append((old, "прежний ПК 24.10 (житель v1)"))
            rows = []
            for h in (576, 864):
                tiles = []
                for im, label in cols:
                    tile = Image.new("RGBA", (round(h * 0.75), h), (96, 92, 86, 255))
                    s = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
                    tile.alpha_composite(s, ((tile.width - s.width) // 2, 0))
                    ImageDraw.Draw(tile).text((8, 8), f"{label}, кадр {h} px", fill=(255, 255, 255, 255), font=FONT)
                    tiles.append(tile)
                row = Image.new("RGBA", (sum(x.width for x in tiles), h))
                x = 0
                for tile in tiles:
                    row.paste(tile, (x, 0)); x += tile.width
                rows.append(row)
            sheet = Image.new("RGBA", (max(r.width for r in rows), sum(r.height for r in rows)), (40, 40, 40, 255))
            y = 0
            for r in rows:
                sheet.paste(r, (0, y)); y += r.height
            out = OUT / f"pc_vs_lite_{sid}.jpg"
            sheet.convert("RGB").save(out, quality=88)
            print(out)


if __name__ == "__main__":
    main()
