"""Полка Тихона у печи (H1, партия 12, слой state_shelf_A) и гнёзда под её кронштейны (state_holes_stove).
Директор 02.11, стр. 6: «она направлена выше слева и ниже справа, а должна — ровно наоборот» — полка
отражена слева направо на своём месте (ось — середина доски, x 355–515 холста), затем по снимку
shelf_mirror2 («вариант выше 30 теперь норм») сдвинута на 30 px холста вверх и на 15 px влево.
Гнёзда отражены по той же оси и сдвинуты так же — кронштейны по-прежнему закрывают свои гнёзда."""
from __future__ import annotations

from PIL import Image

AXIS_SUM = 355 + 514   # x' = AXIS_SUM - x: ось — середина доски слоя полки (alpha_bbox 355..515)
DX, DY = -15, -30


def retouch(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    bb = im.getbbox()
    piece = im.crop(bb).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    x0 = AXIS_SUM - (bb[2] - 1)
    out.paste(piece, (x0 + DX, bb[1] + DY))
    return out
