#!/usr/bin/env python3
"""J (Директор 29.10, стр. 203; ответ в PLAN_J: «Дверь сначала без неё, потом она входит с главной двери»): последний кадр
ужина EP_dinner начинается с закрытой главной двери и пустого стула; Ульяна появляется в открытой двери на строке
«Ульяна по новому мосту прибежала…» (M26/lines[35]). Нового арта нет: слой family_closed — это слой family партии 8
(Нина, Илья, Варвара, Ульяна в открытой двери), где проём с Ульяной заменён тем же местом фона ep_dinner (дверь закрыта,
перед ней стул). Прямоугольники подобраны по кадрам: проём двери, ноги Ульяны под ним, тёмный пол справа от них —
до кромки мисок и пальцев Нины.
Запуск: python3 tools/make_ep_dinner_closed.py  (пишет game/assets/rooms/EP_dinner/family_closed.png)"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
D = ROOT / "game" / "assets" / "rooms" / "EP_dinner"
BOXES = [(787, 170, 969, 484), (796, 484, 893, 530), (893, 484, 969, 511)]   # холст 1672×941


def main() -> None:
    bg = Image.open(D / "bg.png").convert("RGBA")
    fam = Image.open(D / "family.png").convert("RGBA")
    out = fam.copy()
    for box in BOXES:
        out.paste(bg.crop(box), box[:2])
    out.save(D / "family_closed.png", optimize=True)
    print(D / "family_closed.png", out.size)


if __name__ == "__main__":
    main()
