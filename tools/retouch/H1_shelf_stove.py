"""Полка Тихона у печи (H1, партия 12, слой state_shelf_A) и гнёзда под её кронштейны (state_holes_stove).
Директор 02.11, стр. 6: «она направлена выше слева и ниже справа, а должна — ровно наоборот» — полка
отражена слева направо на своём месте (ось — середина доски, x 355–515 холста), затем по снимку
shelf_mirror2 («вариант выше 30 теперь норм») сдвинута на 30 px холста вверх и на 15 px влево.
Гнёзда отражены по той же оси и сдвинуты так же — кронштейны по-прежнему закрывают свои гнёзда.
Директор 02.11 вечер, № 3 («полку совсем немного выровнять, а то сейчас правая сторона сильно выше левой»): верх доски
поднимался вправо на 9 px на 135 (≈ 3,8°) — оба слоя повёрнуты по часовой на 2° вокруг середины доски (420, 421)."""
from __future__ import annotations

from PIL import Image

AXIS_SUM = 355 + 514   # x' = AXIS_SUM - x: ось — середина доски слоя полки (alpha_bbox 355..515)
DX, DY = -15, -30
LEVEL_DEG = -2.0          # по часовой (PIL: + — против часовой)
PIVOT = (420.0, 421.0)    # середина доски после отражения и сдвига (alpha_bbox 340..500 × 383..459)


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    bb = im.getbbox()
    piece = im.crop(bb).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    x0 = AXIS_SUM - (bb[2] - 1)
    out.paste(piece, (x0 + DX, bb[1] + DY))
    return out.rotate(LEVEL_DEG, resample=Image.Resampling.BICUBIC, center=PIVOT)
