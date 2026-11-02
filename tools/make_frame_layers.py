#!/usr/bin/env python3
"""Слои-«вклейки» кадров и комнат по данным: персонажи и вещи в готовых картинах (блоки 3–5, 22.10).

Источник истины — поле `compose` у слоя в data/story/rooms/<ID>.json (комнаты и кадры `"frame": true`). Инструмент
рисует для каждого такого слоя полноформатный PNG размера фона (холст 1672×941, слой ставится в (0, 0), масштаб 1:1 —
как все слои поставок) и пишет его по пути из поля `image` (res://… → game/…). В игре слой обычный: if / unless по
флагам, порядок по месту в списке (фигуры за столом — до слоя переднего плана).

compose — персонаж:
  {"char": "nina",            — id персонажа; лист берётся из assets/characters/<набор>/ (набор: CHAR_SET ниже,
                                  tamara → tamara_v3), пока набора нет — заглушка: вид спереди из assets/incoming/cast_v3/
                                  <char>_v1.png (как плоские NPC блока 2);
   "feet": [x, y],            — середина подошв на холсте фона;
   "height": h,               — рост фигуры на холсте, px (по ориентирам картины: дверь, стол, перила);
   "dir": 0..7,               — строка листа (0 анфас, против часовой: 1 — вправо-вниз … как у Агаты);
   "action": "idle", "frame": 0, — действие и столбец листа (у Нины, Ильи, Ульяны, жены Ильи, управляющего —
                                  "talk", 0: их Idle — застывший шаг, ИИ-осмотр спрайтов 22.10; кадр 0 talk — стойка),
   "tint": [r, g, b],         — умножение цвета (свет картины: тёплая свеча, зимний день, сумерки);
   "shadow": 0.35,            — контактная тень (непрозрачность эллипса у ног), 0 — без тени;
   "mirror": false,           — отразить по горизонтали;
   "cut_below": y,            — обрезать ниже этой строки холста (ноги за столом / скамьёй);
   "hide": [[[x, y], …], …],  — многоугольники холста, где фигура скрыта: то, что на картине перед ней (столешница,
                                  кувшин, чашка) — слой под фигурой проступает (G53: Агата сидит за столом);
   "hide_feather": 1.0}       — мягкость края скрытия, px.
compose — вещь (кусок другой картинки):
  {"src": "game/assets/rooms/H1/state_cup_table_blue.png", "crop": [x, y, w, h], "at": [x, y], "width": w,
   "tint": [...], "rotate": градусы, "alpha": 0..1, "shadow": 0, "mirror": false,
   "mask": {"poly": [[[x, y], …]], "lines": [{"pts": [[x, y], …], "width": px}], "feather": px}}
                                — вырезать вещь из картинки без прозрачности (пиксели источника, до crop)
Фигура кадра — не картинка, а клипы листа (Директор 01.11, стр. 61: «на кадрах с Ниной она статична», стр. 68: «никто
не двигается, когда говорит»): у compose персонажа
   "sheet": "nina_v2",        — набор листов (assets/characters/<набор>/; без поля — CHAR_SET; v2 — те же модели, что
                                  живые жители в комнатах, со стойкой listen/idle и жестом реплики talk),
   "anim": {"rest": "listen", "talk": "talk",   — клип покоя (туда-обратно) и клип реплики (вперёд по кругу);
            "fps": {"talk": 3.4}, "blend": ["talk"],   — темп клипа (иначе темп листа) и клипы с плавным переходом
                                  между соседними кадрами (редкие кадры: лист v1 — 16 кадров на 9 с жеста);
            "align": "head"}   — как клип реплики сводится с клипом покоя (clip_shift: низ подошв — всегда, по
                                  горизонтали — голова; "feet", "none").
Тогда рядом с картинкой слоя пишутся <image>_anim.png — атлас кадров обоих клипов, каждый собран как сам слой
(тот же масштаб и опорная точка, что у кадра покоя action/frame: рост height, середина подошв feet; тот же tint,
та же тень, hide и cut_below — рука не проходит сквозь стол) и обрезан общей рамкой, — и <image>_anim.json (рамка на
холсте, сетка, клипы). Картинка слоя (image) — первый кадр клипа покоя; StateLayer играет атлас
(game/scripts/rooms/state_layer.gd, game/shaders/frame_anim.gdshader).
Повторный запуск с теми же исходниками даёт те же файлы; --check сверяет без записи (код 1 — расходятся или нет файла).
Когда приходят листы 3D (assets/characters/<имя>/), запуск без правки данных заменяет заглушки фигурами из листов.
Нужен Pillow. Запуск: python3 tools/make_frame_layers.py [--check] [ID | ID.слой …]
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter
Image.MAX_IMAGE_PIXELS = None  # листы Агаты 2,25× (G56): сетка pick 34 560 × 6 912 px — свой файл, не «бомба»

ROOT = Path(__file__).resolve().parent.parent
ROOMS = ROOT / "data" / "story" / "rooms"
CHARS = ROOT / "assets" / "characters"
STUBS = ROOT / "assets" / "incoming" / "cast_v3"
GAME_CHARS = ROOT / "game" / "assets" / "characters"
CHAR_SET = {"tamara": "tamara_v3"}
ALPHA_MIN = 128
ATLAS_MAX = 8192   # сторона атласа кадров (как у листов игры)
ATLAS_GAP = 4      # пустота между кадрами атласа: линейная выборка не берёт соседа


def res_to_path(res: str) -> Path:
    if not res.startswith("res://"):
        raise SystemExit(f"путь {res} должен начинаться с res://")
    return ROOT / "game" / res[len("res://"):]


def canvas_of(room: dict) -> tuple[int, int]:
    bg = room.get("background", {}).get("image", "")
    with Image.open(res_to_path(bg)) as im:
        return im.size


def sheet_set(c: dict) -> str:
    return str(c.get("sheet") or CHAR_SET.get(c["char"], c["char"]))


_CELLS: dict = {}
_SHEET: list = [None, None]   # [путь, картинка] — один лист в памяти (листы v2 — до 23 328 × 6 912 px)


_MD5: dict = {}


def _md5(p: Path) -> str:
    if p not in _MD5:
        _MD5[p] = hashlib.md5(p.read_bytes()).hexdigest()
    return _MD5[p]


def _sheet_image(p: Path) -> Image.Image:
    if _SHEET[0] != p:
        _SHEET[0], _SHEET[1] = None, None
        im = Image.open(p)
        im.load()
        _SHEET[0], _SHEET[1] = p, im if im.mode == "RGBA" else im.convert("RGBA")
    return _SHEET[1]


def sheet_cell(cset: str, action: str, row: int, col: int) -> Image.Image:
    """Кадр листа (строка — направление, столбец — кадр) полного размера frame_w × frame_h. Источник истины — сетка
    assets/characters/<набор>/; если копия игры (game/assets/characters/<набор>, tools/pack_sheets.py) упакована из
    этой самой сетки (atlas.src_md5), кадр берётся из неё — те же пиксели, в памяти вчетверо меньше."""
    key = (cset, action, row, col)
    if key in _CELLS:
        return _CELLS[key]
    src = CHARS / cset
    meta = json.loads((src / "sprites.json").read_text(encoding="utf-8"))
    fw, fh = int(meta["frame_w"]), int(meta["frame_h"])
    act = meta["actions"][action]
    n = int(act["frames"])
    grid = src / str(act.get("sheet", f"{action}.png"))
    cell = None
    gmeta_p = GAME_CHARS / cset / "sprites.json"
    if gmeta_p.exists():
        gact = json.loads(gmeta_p.read_text(encoding="utf-8")).get("actions", {}).get(action, {})
        atl = gact.get("atlas")
        if atl and atl.get("src_md5") == _md5(grid):
            r = atl["rects"][row * n + col]
            pages = atl.get("pages") or [gact.get("sheet", f"{action}.png")]
            page = _sheet_image(GAME_CHARS / cset / pages[r[6] if len(r) > 6 else 0])
            cell = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            cell.paste(page.crop((r[0], r[1], r[0] + r[2], r[1] + r[3])), (r[4], r[5]))
    if cell is None:
        cell = _sheet_image(grid).crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
    _CELLS[key] = cell
    return cell


def figure(c: dict) -> Image.Image:
    """The character's picture, cropped to its silhouette (feet at the bottom edge)."""
    cid = c["char"]
    cset = sheet_set(c)
    sheet_dir = CHARS / cset
    action = c.get("action", "idle")
    sprites = sheet_dir / "sprites.json"
    if sprites.exists() and (sheet_dir / f"{action}.png").exists():
        im = sheet_cell(cset, action, int(c.get("dir", 0)), int(c.get("frame", 0)))
    else:
        im = Image.open(STUBS / f"{cid}_v1.png").convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0)
    box = a.getbbox()
    if box is None:
        raise SystemExit(f"{cid}: пустой силуэт")
    return im.crop((box[0], box[1], box[2], box[3]))


def tinted(im: Image.Image, tint) -> Image.Image:
    if not tint:
        return im
    r, g, b, a = im.split()
    r = r.point(lambda v: min(255, int(v * float(tint[0]))))
    g = g.point(lambda v: min(255, int(v * float(tint[1]))))
    b = b.point(lambda v: min(255, int(v * float(tint[2]))))
    return Image.merge("RGBA", (r, g, b, a))


def shadow_ellipse(canvas: Image.Image, cx: float, cy: float, w: float, alpha: float) -> None:
    if alpha <= 0:
        return
    h = max(4.0, w * 0.22)
    sh = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(sh)
    d.ellipse((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), fill=int(255 * alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(max(2.0, h * 0.35)))
    dark = Image.new("RGBA", canvas.size, (12, 8, 4, 0))
    dark.putalpha(sh)
    canvas.alpha_composite(dark)


def _hidden(layer: Image.Image, c: dict, keep: Image.Image | None) -> Image.Image:
    """cut_below и hide (то, что на картине перед фигурой) — общие для картинки слоя и всех кадров атласа."""
    size = layer.size
    if "cut_below" in c:
        cut = int(c["cut_below"])
        ImageDraw.Draw(layer).rectangle((0, cut, size[0], size[1]), fill=(0, 0, 0, 0))
    if keep is not None:
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), keep))
    return layer


def _keep_mask(c: dict, size: tuple[int, int]) -> Image.Image | None:
    if not c.get("hide"):
        return None
    keep = Image.new("L", size, 255)
    dk = ImageDraw.Draw(keep)
    for poly in c["hide"]:
        dk.polygon([(float(x), float(y)) for x, y in poly], fill=0)
    fe = float(c.get("hide_feather", 1.0))
    if fe > 0:
        keep = keep.filter(ImageFilter.GaussianBlur(fe))
    return keep


def _silhouette(cell: Image.Image):
    return cell.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0).getbbox()


class Placement:
    """Кадр листа → холст кадра одним и тем же отображением для всех кадров слоя: масштаб k и опорная точка (середина
    низа силуэта) — по кадру покоя compose.action/frame (рост height, подошвы в feet), как у картинки слоя; рука,
    поднятая в жесте, не меняет ни масштаба, ни места фигуры."""
    PAD = 8

    def __init__(self, c: dict):
        self.c = c
        self.cset = sheet_set(c)
        self.row = int(c.get("dir", 0))
        base = sheet_cell(self.cset, c.get("action", "idle"), self.row, int(c.get("frame", 0)))
        self.fw = base.size[0]
        box = _silhouette(base)
        if box is None:
            raise SystemExit(f"{c['char']}: пустой силуэт")
        self.k = float(c["height"]) / (box[3] - box[1])
        self.ax, self.ay = (box[0] + box[2]) / 2.0, float(box[3])
        self.mirror = bool(c.get("mirror"))
        if self.mirror:
            self.ax = self.fw - self.ax
        self.fx, self.fy = float(c["feet"][0]), float(c["feet"][1])
        self.shadow_w = round((box[2] - box[0]) * self.k) * 0.75

    def place(self, cell: Image.Image, size: tuple[int, int], shift=(0.0, 0.0)) -> Image.Image:
        """Кадр, уменьшенный (LANCZOS, без ореола: Pillow сводит по предумноженной альфе) и поставленный на холст;
        shift — сдвиг кадра в px листа (клип реплики сведён с клипом покоя, clip_shift)."""
        if self.mirror:
            cell = cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if shift != (0.0, 0.0):
            sh = Image.new("RGBA", cell.size, (0, 0, 0, 0))
            sh.paste(cell, (round(shift[0]), round(shift[1])))
            cell = sh
        sb = cell.getchannel("A").getbbox()
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        if sb is None:
            return layer
        P, k = self.PAD, self.k
        padded = Image.new("RGBA", (cell.size[0] + 2 * P, cell.size[1] + 2 * P), (0, 0, 0, 0))
        padded.paste(cell, (P, P))
        X0 = math.floor(self.fx + (sb[0] - self.ax) * k)
        Y0 = math.floor(self.fy + (sb[1] - self.ay) * k)
        X1 = math.ceil(self.fx + (sb[2] - self.ax) * k)
        Y1 = math.ceil(self.fy + (sb[3] - self.ay) * k)
        src = (self.ax + (X0 - self.fx) / k + P, self.ay + (Y0 - self.fy) / k + P,
               self.ax + (X1 - self.fx) / k + P, self.ay + (Y1 - self.fy) / k + P)
        fig = padded.resize((X1 - X0, Y1 - Y0), Image.LANCZOS, box=src)
        fig = tinted(fig, self.c.get("tint"))
        layer.paste(fig, (X0, Y0), fig)
        return layer


def render_placed(c: dict, size: tuple[int, int], pl: Placement, cell: Image.Image, keep, shift=(0.0, 0.0)) -> Image.Image:
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_ellipse(out, pl.fx, pl.fy, pl.shadow_w, float(c.get("shadow", 0.35)))
    out.alpha_composite(_hidden(pl.place(cell, size, shift), c, keep))
    return out


def _stance(cell: Image.Image, mirror: bool) -> tuple[float, float, float]:
    """(середина подошв по x, низ подошв, середина головы по x — верхняя восьмая силуэта) кадра, px листа."""
    if mirror:
        cell = cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    a = cell.getchannel("A").point(lambda v: 255 if v >= ALPHA_MIN else 0)
    box = a.getbbox()
    band = a.crop((0, box[3] - max(4, (box[3] - box[1]) // 25), a.size[0], box[3])).getbbox()
    head = a.crop((0, box[1], a.size[0], box[1] + max(4, (box[3] - box[1]) // 8))).getbbox()
    return (band[0] + band[2]) / 2.0, float(box[3]), (head[0] + head[2]) / 2.0


def clip_shift(pl: Placement, c: dict, action: str) -> tuple[float, float]:
    """Сдвиг клипа к стойке кадра покоя, px листа. Клип реплики листов v2 (Talk_with_Hands_Open) стоит на другом
    месте рамки рендера: подошвы выше на 2–3 см (floor_shift_m) и ноги на 10–12 см вперёд при той же голове — без
    сдвига на наплыве покой → реплика фигура подпрыгивала (до 10 px холста). Низ подошв сводится точно (стоит на
    том же полу); по горизонтали — голова (compose.anim.align: "head"; на неё смотрят — лицо не двоится, ноги
    переступают в наплыве), "feet" — середина подошв (голова двоится — проверено на кадрах), "none" — без сдвига."""
    base = sheet_cell(pl.cset, c.get("action", "idle"), pl.row, int(c.get("frame", 0)))
    first = sheet_cell(pl.cset, action, pl.row, 0)
    if first is base:
        return (0.0, 0.0)
    b, f = _stance(base, pl.mirror), _stance(first, pl.mirror)
    mode = c["anim"].get("align", "head")
    dx = 0.0 if mode == "none" else (b[0] - f[0] if mode == "feet" else b[2] - f[2])
    return (dx, b[1] - f[1])


def anim_clips(c: dict) -> list:
    """[(роль, действие листа, кадров, кадр/с, туда-обратно, сглаживать)] — клипы атласа фигуры по compose.anim."""
    an = c["anim"]
    meta = json.loads((CHARS / sheet_set(c) / "sprites.json").read_text(encoding="utf-8"))
    out = []
    for role in ("rest", "talk"):
        action = an.get(role)
        if not action:
            continue
        act = meta["actions"][action]
        fps = float(an.get("fps", {}).get(role, act.get("fps", 12.0)))
        pp = role == "rest" and act.get("playback") == "pingpong"
        out.append((role, action, int(act["frames"]), fps, pp, role in an.get("blend", [])))
    return out


def anim_key(c: dict) -> str:
    """Отпечаток данных атласа: compose слоя и описания листов — атлас устарел, если он не совпадает."""
    cset = sheet_set(c)
    h = hashlib.md5(json.dumps(c, sort_keys=True, ensure_ascii=False).encode("utf-8"))
    h.update((CHARS / cset / "sprites.json").read_bytes())
    h.update(b"frame_anim v2")
    return h.hexdigest()


def render_anim(c: dict, size: tuple[int, int], image_res: str):
    """→ (картинка слоя = первый кадр покоя, атлас кадров, описание атласа)."""
    pl = Placement(c)
    keep = _keep_mask(c, size)
    clips = anim_clips(c)
    pieces, union = [], None
    shifts = {}
    for role, action, n, fps, pp, blend in clips:
        shifts[role] = clip_shift(pl, c, action)
        for i in range(n):
            im = render_placed(c, size, pl, sheet_cell(pl.cset, action, pl.row, i), keep, shifts[role])
            bb = im.getchannel("A").getbbox() or (0, 0, 1, 1)
            pieces.append(im.crop(bb))
            pieces[-1].info["at"] = bb[:2]
            union = bb if union is None else (min(union[0], bb[0]), min(union[1], bb[1]), max(union[2], bb[2]), max(union[3], bb[3]))
    cw, ch = union[2] - union[0], union[3] - union[1]
    cols = max(1, min(len(pieces), (ATLAS_MAX + ATLAS_GAP) // (cw + ATLAS_GAP)))
    rows = math.ceil(len(pieces) / cols)
    W, H = cols * (cw + ATLAS_GAP) - ATLAS_GAP, rows * (ch + ATLAS_GAP) - ATLAS_GAP
    if H > ATLAS_MAX:
        raise SystemExit(f"{c['char']}: атлас {W}×{H} больше {ATLAS_MAX} px — меньше кадров или клипов")
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for j, pc in enumerate(pieces):
        ax, ay = pc.info["at"]
        atlas.paste(pc, ((j % cols) * (cw + ATLAS_GAP) + ax - union[0], (j // cols) * (ch + ATLAS_GAP) + ay - union[1]))
    still = render_placed(c, size, pl, sheet_cell(pl.cset, c.get("action", "idle"), pl.row, int(c.get("frame", 0))), keep)
    meta = {
        "_comment": "tools/make_frame_layers.py (compose.anim): кадры фигуры для StateLayer — клип покоя и клип реплики, "
                    "каждый кадр собран как картинка слоя; не править руками.",
        "image": image_res,
        "key": anim_key(c),
        "char": c["char"], "sheet": sheet_set(c), "dir": pl.row,
        "origin": [union[0], union[1]], "cell": [cw, ch], "cols": cols, "gap": ATLAS_GAP, "size": [W, H],
        "feet": [round(pl.fx - union[0], 2), round(pl.fy - union[1], 2)], "height": float(c["height"]),
        "clips": {},
    }
    first = 0
    for role, action, n, fps, pp, blend in clips:
        meta["clips"][role] = {"action": action, "first": first, "frames": n, "fps": fps,
                               "playback": "pingpong" if pp else "loop", "blend": blend,
                               "shift_sheet_px": [round(shifts[role][0]), round(shifts[role][1])]}
        first += n
    return still, atlas, meta


def anim_paths(image_res: str) -> tuple[Path, Path]:
    p = res_to_path(image_res)
    return p.with_name(p.stem + "_anim.png"), p.with_name(p.stem + "_anim.json")


def render(c: dict, size: tuple[int, int]) -> Image.Image:
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if "char" in c and "anim" in c:
        pl = Placement(c)
        cell = sheet_cell(pl.cset, c.get("action", "idle"), pl.row, int(c.get("frame", 0)))
        return render_placed(c, size, pl, cell, _keep_mask(c, size))
    if "char" in c:
        fig = figure(c)
        h = float(c["height"])
        k = h / fig.size[1]
        fig = fig.resize((max(1, round(fig.size[0] * k)), max(1, round(h))), Image.LANCZOS)
        if c.get("mirror"):
            fig = fig.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        fig = tinted(fig, c.get("tint"))
        fx, fy = float(c["feet"][0]), float(c["feet"][1])
        shadow_ellipse(out, fx, fy, fig.size[0] * 0.75, float(c.get("shadow", 0.35)))
        x0, y0 = round(fx - fig.size[0] / 2), round(fy - fig.size[1])
        layer = Image.new("RGBA", size, (0, 0, 0, 0))
        layer.paste(fig, (x0, y0), fig)
        if "cut_below" in c:
            cut = int(c["cut_below"])
            ImageDraw.Draw(layer).rectangle((0, cut, size[0], size[1]), fill=(0, 0, 0, 0))
        if c.get("hide"):
            keep = Image.new("L", size, 255)
            dk = ImageDraw.Draw(keep)
            for poly in c["hide"]:
                dk.polygon([(float(x), float(y)) for x, y in poly], fill=0)
            fe = float(c.get("hide_feather", 1.0))
            if fe > 0:
                keep = keep.filter(ImageFilter.GaussianBlur(fe))
            layer.putalpha(ImageChops.multiply(layer.getchannel("A"), keep))
        out.alpha_composite(layer)
        return out
    src = Image.open(ROOT / c["src"]).convert("RGBA")
    if "mask" in c:
        # a thing cut out of a picture without alpha (01.11, стр. 49: Mitya's lantern from the lantern close-up):
        # mask {poly: [[[x, y], …], …], lines: [{pts: [[x, y], …], width: px}], feather: px} in the source's pixels
        mk = Image.new("L", src.size, 0)
        dm = ImageDraw.Draw(mk)
        for poly in c["mask"].get("poly", []):
            dm.polygon([(float(x), float(y)) for x, y in poly], fill=255)
        for ln in c["mask"].get("lines", []):
            dm.line([(float(x), float(y)) for x, y in ln["pts"]], fill=255, width=int(ln.get("width", 8)), joint="curve")
        if float(c["mask"].get("feather", 1.5)) > 0:
            mk = mk.filter(ImageFilter.GaussianBlur(float(c["mask"].get("feather", 1.5))))
        src.putalpha(ImageChops.multiply(src.getchannel("A"), mk))
    if "crop" in c:
        x, y, w, h = (int(v) for v in c["crop"])
        src = src.crop((x, y, x + w, y + h))
    if "width" in c:
        k = float(c["width"]) / src.size[0]
        src = src.resize((max(1, round(src.size[0] * k)), max(1, round(src.size[1] * k))), Image.LANCZOS)
    if c.get("mirror"):
        src = src.transpose(Image.Transpose.FLIP_LEFT_RIGHT)   # J (стр. 199): Тихон на ужине — лицом к людям
    if c.get("rotate"):
        src = src.rotate(float(c["rotate"]), resample=Image.BICUBIC, expand=True)
    src = tinted(src, c.get("tint"))
    if "alpha" in c:
        a = src.getchannel("A").point(lambda v: int(v * float(c["alpha"])))
        src.putalpha(a)
    ax, ay = (int(v) for v in c["at"])
    if c.get("shadow"):
        shadow_ellipse(out, ax + src.size[0] / 2, ay + src.size[1], src.size[0] * 0.9, float(c["shadow"]))
    out.alpha_composite(src, (ax, ay)) if ax >= 0 and ay >= 0 else out.paste(src, (ax, ay), src)
    return out


def _same(path: Path, im: Image.Image) -> bool:
    return path.exists() and ImageChops.difference(Image.open(path).convert("RGBA"), im).getbbox() is None


def main() -> int:
    check = "--check" in sys.argv
    only = {a for a in sys.argv[1:] if not a.startswith("--")}
    bad = 0
    for rf in sorted(ROOMS.glob("*.json")):
        if rf.name.startswith("_"):
            continue
        room = json.loads(rf.read_text(encoding="utf-8"))
        rid = room.get("id")
        if only and rid not in only and not any(o.startswith(f"{rid}.") for o in only):
            continue
        todo = [l for l in room.get("layers", []) if "compose" in l
                and (not only or rid in only or f"{rid}.{l.get('id')}" in only)]
        if not todo:
            continue
        size = canvas_of(room)
        for l in todo:
            target = res_to_path(l["image"])
            c = l["compose"]
            if "char" in c and "anim" in c:
                im, atlas, meta = render_anim(c, size, l["image"])
                apng, ajson = anim_paths(l["image"])
                if check:
                    for path, ok in ((target, _same(target, im)), (apng, _same(apng, atlas)),
                                     (ajson, ajson.exists() and json.loads(ajson.read_text(encoding="utf-8")) == meta)):
                        print(f"{'OK  ' if ok else 'DIFF'} {path.relative_to(ROOT)}")
                        bad += 0 if ok else 1
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    im.save(target, optimize=True)
                    atlas.save(apng, optimize=True)
                    ajson.write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                    print(f"wrote {target.relative_to(ROOT)} + {apng.name} {meta['size'][0]}×{meta['size'][1]}, "
                          f"кадр {meta['cell'][0]}×{meta['cell'][1]}, клипы "
                          + ", ".join(f"{r}={v['action']}×{v['frames']}" for r, v in meta["clips"].items())
                          + f" ({rid}.{l.get('id')})")
                continue
            im = render(c, size)
            if check:
                same = _same(target, im)
                print(f"{'OK  ' if same else 'DIFF'} {target.relative_to(ROOT)}")
                bad += 0 if same else 1
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                im.save(target, optimize=True)
                print(f"wrote {target.relative_to(ROOT)} ({rid}.{l.get('id')})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
