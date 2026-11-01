"""План Заречья (партия 12): канат через реку и лодка на нём нарисованы на основе плана — они видны с первого дня,
а канат завязывают только в M15 (Директор 31.10, стр. 10: «сверить с нынешней игрой»; сверка 01.11). Канат от
стопора дальней опоры к лодке, лодка с тенью и канат от лодки к ближнему столбику закрыты водой из соседнего места
(сдвинутая копия того же рисунка под мягкой маской — штрихи воды сохраняются); столбик на берегу остаётся. Сам канат
с лодкой — слой zarechye_plan_rope.png (tools/retouch/zarechye_plan_rope.py), виден с rope_on_ring."""
from __future__ import annotations

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# (маска, сдвиг источника): вода берётся оттуда, где её ничто не пересекает
LONG_ROPE = ((966, 307), (880, 389))      # стопор дальней опоры → нос лодки
SHORT_ROPE = ((838, 408), (794, 425))     # корма → столбик на берегу
BOAT = [(830, 398), (846, 385), (886, 380), (893, 388), (887, 414), (878, 428), (836, 429), (826, 414)]


def _dark(im: Image.Image, thr: int) -> Image.Image:
    return im.convert("L").point(lambda v: 255 if v < thr else 0)


def parts(size, im: Image.Image):
    """[(маска L, сдвиг источника (dx, dy))]."""
    dark = _dark(im, 175)
    out = []
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).line(LONG_ROPE, fill=255, width=9)
    out.append((ImageChops.multiply(m, dark).filter(ImageFilter.MaxFilter(5)), (-6, -7)))
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).line(SHORT_ROPE, fill=255, width=9)
    out.append((ImageChops.multiply(m, dark).filter(ImageFilter.MaxFilter(5)), (-3, -8)))
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(BOAT, fill=255)
    out.append((m.filter(ImageFilter.MaxFilter(5)), (-62, -46)))
    return out


def rope_mask(im: Image.Image) -> Image.Image:
    """Всё, что закрыто водой, одной маской (для слоя каната)."""
    acc = Image.new("L", im.size, 0)
    for m, _ in parts(im.size, im):
        acc = ImageChops.lighter(acc, m)
    return acc


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGB")
    out = im.copy()
    for m, (dx, dy) in parts(im.size, im):
        src = ImageChops.offset(im, -dx, -dy)      # пиксель (x, y) ← исходник (x + dx, y + dy)
        out = Image.composite(src, out, m.filter(ImageFilter.GaussianBlur(1.5)))
    return out
