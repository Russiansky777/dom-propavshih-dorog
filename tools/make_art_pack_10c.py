#!/usr/bin/env python3
"""Партия 10в для ChatGPT (задание T8, решения Директора 24.10): лодка у поворота и причал без лодки (H36), стойка почты,
зеркало конторы в стойке «ЗМ», дощечка Мити, снимок школы. Текст заказа, основы, кропы с рамками, zip, заявки в manifest.

Запуск из корня репозитория:
    python3 tools/make_art_pack_10c.py             # текст + кропы (Docs/art_pack_10c) + основы и zip (build/gpt-pack-10c)
    python3 tools/make_art_pack_10c.py --manifest  # ещё и дописать заявки batch 10c в assets/manifest.json (один раз)

Образец — tools/make_art_pack_10b.py. Единственный источник координат — список ITEMS ниже: из него пишутся текст для
ChatGPT, кропы и заявки manifest. Прямоугольники — [x1, y1, x2, y2) в пикселях основы (x2, y2 не входят).
Кадры «как сейчас в игре» (_сейчас_в_игре_*.jpg) — снимки экрана 1920×1080 из tools/shots_t8.sh (Docs/art_pack_10c/now/).
"""
import json
import shutil
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "Docs" / "art_pack_10c"
CROPS = DOCS / "crops"
NOW = DOCS / "now"
BUILD = ROOT / "build" / "gpt-pack-10c"
BASES = BUILD / "bases"
ZIP = BUILD / "Партия_10в_для_ChatGPT.zip"
TEXT_NAME = "00_ТЕКСТ_для_ChatGPT.txt"
INC = "assets/incoming/"
GAME = "game/assets/rooms/"

BLOCK = "Партия 10в (ChatGPT, задание T8, 24.10)"

BASE_FILES = {
    "Z3_bg.png": INC + "Z3_bg.png",
    "Z3_state_water_low.png": INC + "Z3_state_water_low.png",
    "Z3_state_water_low_day.png": INC + "Z3_state_water_low_day.png",
    "R1_bg.png": INC + "R1_bg.png",
    "R1_dusk.png": INC + "R1_dusk.png",
    "R1_fg_water.png": INC + "R1_fg_water.png",
    "R1_state_water_low_day.png": INC + "R1_state_water_low_day.png",
    "Z1_bg.png": INC + "Z1_bg.png",
    "Z1_fg_counter_old.png": INC + "Z1_fg_counter.png",
    "H2_bg.png": INC + "H2_bg.png",
    "H2_state_office_mirror_center_v2_old.png": INC + "H2_state_office_mirror_center_v2.png",
    "H2_state_wedges_loose_old.png": INC + "H2_state_wedges_loose.png",
    "O4_bg.png": INC + "O4_bg.png",
    "O4_state_mitya_board_fence_old.png": INC + "O4_state_mitya_board_fence.png",
    "closeup_mitya_board.png": INC + "closeup_mitya_board.png",
    "H3_bg.png": INC + "H3_bg.png",
    "O2_bg.png": INC + "O2_bg.png",
}
COMPOSITES = {
    "_сведено_Z3_сумерки.png": [INC + "Z3_bg.png", INC + "Z3_state_water_low.png"],
    "_сведено_Z3_день.png": [INC + "Z3_bg.png", INC + "Z3_state_water_low_day.png"],
    "_сведено_Z3_временная_лодка.png": [INC + "Z3_bg.png", INC + "Z3_state_water_low_day.png", GAME + "Z3/state_boat.png"],
    "_сведено_R1_сумерки.png": [INC + "R1_bg.png", INC + "R1_fg_water.png", INC + "R1_dusk.png"],
    "_сведено_H2_зеркало_сейчас.png": [INC + "H2_bg.png", INC + "H2_state_office_mirror_center_v2.png", INC + "H2_state_wedges_loose.png"],
}

ITEMS = [
    {
        "n": "1", "g": "H36", "title": "Лодка Пелагеи у поворота, причал без лодки",
        "priority": "высокий (1а–1г)",
        "crop_base": [INC + "Z3_bg.png", INC + "Z3_state_water_low.png"], "crop_box": [820, 330, 1320, 640],
        "rects": [("1а/1б лодка", [930, 440, 1120, 585], (255, 220, 0)), ("кольцо плиты", [1097, 488, 1128, 518], (255, 60, 60))],
        "extra_crops": [
            ("01_Z3_день_то_же_место", [INC + "Z3_bg.png", INC + "Z3_state_water_low_day.png"], [820, 330, 1320, 640],
             [("1а/1б лодка", [930, 440, 1120, 585], (255, 220, 0))]),
            ("01_Z3_временная_лодка_в_игре", [INC + "Z3_bg.png", INC + "Z3_state_water_low_day.png", GAME + "Z3/state_boat.png"], [820, 330, 1320, 640], []),
            ("01_R1_сумерки_заплата", [INC + "R1_bg.png", INC + "R1_fg_water.png", INC + "R1_dusk.png"], [1150, 330, 1672, 800],
             [("1в/1г без лодки", [1340, 460, 1672, 745], (255, 60, 60))]),
            ("01_R1_день_заплата", [INC + "R1_state_water_low_day.png"], [1150, 330, 1672, 800],
             [("1в/1г без лодки", [1340, 460, 1672, 745], (255, 60, 60))]),
        ],
        "text": """Решение Директора 24.10: после того как Агата ставит скобу на треснувшую плиту опоры у берегового поворота (сцена M15s), Пелагея снимает канат моста со своего стопора и привозит его на лодке к плите. С этой минуты лодка стоит у поворота — привязана у плиты на малой опоре в воде, под канатом, — а на причале Пелагеи (R1) лодки больше нет. От поворота Пелагея пускает пустую лодку по канату (лодка на кольце скользит по канату и уходит в туман — это анимация игры) и от поворота же Агата садится в лодку.

Сейчас в игре — временно: та же лодка, вырезанная с причала R1, уменьшена и поставлена у плиты (кроп 01_Z3_временная_лодка_в_игре), а на причале лодка закрыта заплаткой из воды. Нужна нарисованная лодка у поворота и чистая вода на причале.

Порядок слоёв в игре у поворота (снизу вверх): Z3_bg.png → Z3_state_water_low.png (сумерки) ИЛИ Z3_state_water_low_day.png (день, снег на берегах) → лодка 1а (сумерки) или 1б (день). Канат рисует игра сама — линией от кольца плиты (≈ 1115, 498) вверх-влево к тому берегу (≈ 1001, 350).

1а. Z3_state_boat_dusk.png — слой к сведённой основе _сведено_Z3_сумерки.png (Z3_bg + Z3_state_water_low), 1672×941, прозрачно вне [930, 440, 1120, 585).
- Деревянная лодка Пелагеи — та же, что на причале R1_bg.png (x ≈ 1360–1660, y ≈ 475–620 на основе R1): старые доски, банка, вёсла внутри. Пустая, без людей.
- Стоит на мелкой воде перед камнями опор, носом к малой опоре с плитой: нос — у кольца плиты (≈ 1112, 503), корма — левее (≈ x 940). Короткий швартов от носа к кольцу. Длина лодки ≈ 3 м: по камням опор (камень ≈ 55 px ≈ 1 м) это ≈ 160–175 px.
- Под лодкой — её отражение и мокрая тень на воде; свет и цвет — сумерки основы (тёплые отсветы заката на воде, синеватые тени).
- ВАЖНО: в слое только лодка, швартов и её отражение — без воды вокруг и без камней: игра двигает этот слой целиком (лодка уходит по канату), и под ним должна оставаться основа.

1б. Z3_state_boat_day.png — та же лодка на том же месте, 1672×941, к _сведено_Z3_день.png (Z3_bg + Z3_state_water_low_day): ясный зимний день, лёгкий снег на банке и бортах, холодный свет основы. Те же границы [930, 440, 1120, 585), то же правило: только лодка, швартов и отражение.

1в. R1_state_no_boat_dusk.png — заплата к сведённой основе _сведено_R1_сумерки.png (R1_bg + R1_fg_water + R1_dusk), 1672×941, непрозрачно во всём прямоугольнике [1340, 460, 1672, 745), снаружи прозрачно.
- Та же вода у причала вечером, но без лодки, без её отражения и без швартова. Столбы причала с мотком каната (x < 1350) и берег внизу — как на основе (по краям прямоугольника — пиксель в пиксель с основой, без шва). Свет фонаря на воде, рябь — как вокруг.

1г. R1_state_no_boat_day.png — то же днём: заплата к R1_state_water_low_day.png (низкая вода, первый снег, на том берегу зима), непрозрачно во всём [1340, 460, 1672, 745).
""",
        "manifest": [
            ("Z3_state_boat_dusk", "layer_moving", "Z3_state_boat_dusk.png", "Z3_bg.png + Z3_state_water_low.png", "1672×941",
             "полный холст в (0, 0), 1:1; только лодка, швартов и отражение в x 930–1120, y 440–585",
             "Лодка Пелагеи у плиты на опоре (нос у кольца ≈ 1112, 503), сумерки; слой двигается в M17 (layer_go)",
             "Z3.json → слои boat_dusk, boat_shuttle_dusk: image вместо state_boat.png, без modulate"),
            ("Z3_state_boat_day", "layer_moving", "Z3_state_boat_day.png", "Z3_bg.png + Z3_state_water_low_day.png", "1672×941",
             "полный холст в (0, 0), 1:1; x 930–1120, y 440–585",
             "Та же лодка днём (дни 3–4), снег на банке",
             "Z3.json → слой boat_day"),
            ("R1_state_no_boat_dusk", "background_fix", "R1_state_no_boat_dusk.png", "R1_bg.png + R1_fg_water.png + R1_dusk.png", "1672×941",
             "полный холст в (0, 0), 1:1; непрозрачно в x 1340–1672, y 460–745",
             "Вода у причала вечером без лодки, отражения и швартова",
             "R1.json → слои no_boat_dusk и no_boat_d3_evening (z 2, над рябью)"),
            ("R1_state_no_boat_day", "background_fix", "R1_state_no_boat_day.png", "R1_state_water_low_day.png", "1672×941",
             "полный холст в (0, 0), 1:1; непрозрачно в x 1340–1672, y 460–745",
             "То же днём дней 3–4 (низкая вода)",
             "R1.json → слой no_boat_day"),
        ],
    },
    {
        "n": "2", "g": "T8", "title": "Стойка почты в рост (Z1)",
        "priority": "средний",
        "crop_base": [INC + "Z1_bg.png"], "crop_box": [380, 300, 1400, 860],
        "rects": [("проекция стойки на пол", [521, 642, 1239, 775], (255, 220, 0)), ("Тамара (ноги y≈610)", [846, 183, 1018, 610], (120, 255, 120))],
        "text": """ИИ-осмотр 24.10: стойка почты низкая — по колено Агате, Тамара за ней как за журнальным столиком. Старый слой Z1_fg_counter_old.png нарисован огромным столом посреди почты, в игре он уменьшен до 0,7 — и стал низким (кадр _сейчас_в_игре_Z1.jpg, экран 1920×1080).

2. Z1_fg_counter_v2.png — та же почтовая стойка-прилавок (тёмное дерево, филёнки, на столешнице два рисунка опоры моста — как на старом слое), 1672×941 к Z1_bg.png, в масштабе фона 1:1 (игра больше не уменьшает).
- Место на полу — как сейчас: проекция стойки на пол — четырёхугольник: передние ножки на линии y ≈ 775 от x ≈ 521 до x ≈ 1239, задний край на линии y ≈ 642 от x ≈ 586 до x ≈ 1167 (жёлтая рамка — его габарит).
- Высота ≈ 1 м: столешница на уровне пояса взрослого. Тамара стоит за стойкой (ноги y ≈ 610, рост в кадре ≈ 427 px — зелёная рамка) и видна от пояса и выше. Агата (1,66 м) рядом со стойкой — столешница ей по пояс.
- Камера и перспектива — как у фона (точка схода ≈ (864, 75)); свет — из окна слева.
- Вне стойки — прозрачно; без людей.
""",
        "extra_crops": [],
        "manifest": [
            ("Z1_fg_counter_v2", "occluder", "Z1_fg_counter_v2.png", "Z1_bg.png", "1672×941",
             "полный холст в (0, 0), 1:1, без масштаба; проекция на пол x 521–1239, y 642–775",
             "Стойка почты высотой ≈ 1 м, Тамара за ней от пояса",
             "Z1.json → слой counter: image, scale 1 (убрать scale 0.7 и offset), z по передним ножкам; проверить clearance и хотспот рисунков"),
        ],
    },
    {
        "n": "3", "g": "T8", "title": "Зеркало конторы во весь проём стойки «ЗМ» (H2)",
        "priority": "средний",
        "crop_base": [INC + "H2_bg.png", INC + "H2_state_office_mirror_center_v2.png", INC + "H2_state_wedges_loose.png"], "crop_box": [940, 120, 1250, 600],
        "rects": [("проём стойки", [1015, 198, 1172, 522], (255, 220, 0)), ("зеркало сейчас", [1035, 214, 1147, 498], (255, 60, 60))],
        "text": """ИИ-осмотр 24.10: зеркало конторы в тётиной резной стойке «ЗМ» заметно меньше её проёма — висит посередине с зазорами, своя рамка другого вида (кадр _сейчас_в_игре_H2.jpg). Нужно зеркало, которое встаёт в проём стойки.

3а. H2_state_office_mirror_center_v3.png — 1672×941 к H2_bg.png: зеркало конторы (простая тёмная деревянная рама, старое стекло без отражений, ровный тусклый блик) вписано в проём стойки [1015, 198, 1172, 522) — рама зеркала по краям касается внутреннего края резной стойки, без зазоров. Вне проёма — прозрачно.
3б. H2_state_wedges_loose_v3.png, H2_state_wedges_half_v3.png, H2_state_wedges_driven_v3.png — четыре деревянных клина в стыке рамы зеркала и стойки (по два сверху и снизу, у углов): вставлены (торчат), наполовину, забиты вровень. Те же места во всех трёх. 1672×941, прозрачно вне проёма стойки с запасом 20 px.
- В README укажите стекло (четырёхугольник, пиксели основы) и центры четырёх клиньев — игра ставит по ним мини-игру.
""",
        "extra_crops": [],
        "manifest": [
            ("H2_state_office_mirror_center_v3", "prop_states", "H2_state_office_mirror_center_v3.png", "H2_bg.png", "1672×941",
             "полный холст в (0, 0), 1:1; в проёме стойки x 1015–1172, y 198–522",
             "Зеркало конторы во весь проём стойки «ЗМ», без зазоров",
             "H2.json → слой office_mirror и mechanic.frame (images, glass_polygon из README)"),
            ("H2_state_wedges_v3", "prop_states", ["H2_state_wedges_loose_v3.png", "H2_state_wedges_half_v3.png", "H2_state_wedges_driven_v3.png"],
             "H2_bg.png + H2_state_office_mirror_center_v3.png", "1672×941",
             "полный холст в (0, 0), 1:1; у углов рамы",
             "Четыре клина: вставлены / наполовину / забиты",
             "H2.json → слои wedges_*, мини-игра клиньев (центры из README)"),
        ],
    },
    {
        "n": "4", "g": "T8", "title": "Дощечка Мити с зарубками у забора (O4)",
        "priority": "низкий",
        "crop_base": [INC + "O4_bg.png", INC + "O4_state_mitya_board_fence.png"], "crop_box": [980, 480, 1220, 680],
        "rects": [("дощечка", [1080, 550, 1114, 616], (255, 220, 0))],
        "extra_crops": [("04_образец_closeup_mitya_board", [INC + "closeup_mitya_board.png"], [0, 0, 1672, 941], [])],
        "text": """ИИ-осмотр 24.10: дощечка Мити у забора — гладкая серая плашка, без дерева и без снега. По сюжету на ней двадцать зарубок — двадцать зим дежурства у фонаря (крупный план — closeup_mitya_board.png).

4. O4_state_mitya_board_fence_v2.png — 1672×941 к O4_bg.png, та же дощечка на том же месте, прислонена к забору слева от калитки, прозрачно вне [1080, 550, 1114, 616).
- Старая обветренная доска с текстурой дерева, по краю — ряд тёмных зарубок (читаются даже в малом размере ≈ 27×60 px: короткие тёмные засечки), шапка снега сверху, тень на снегу у основания. Как на крупном плане.
""",
        "manifest": [
            ("O4_state_mitya_board_fence_v2", "prop_states", "O4_state_mitya_board_fence_v2.png", "O4_bg.png", "1672×941",
             "полный холст в (0, 0), 1:1; x 1080–1114, y 550–616",
             "Дощечка Мити: дерево, ряд зарубок, снег сверху",
             "O4.json → слой mitya_board: image"),
        ],
    },
    {
        "n": "5", "g": "T8", "title": "Снимок школы в рамке (H3)",
        "priority": "низкий (временный кроп уже в игре)",
        "crop_base": [INC + "H3_bg.png"], "crop_box": [880, 190, 1100, 370],
        "rects": [("снимок", [938, 236, 1035, 325], (255, 220, 0))],
        "extra_crops": [("05_образец_крыльцо_школы_O2", [INC + "O2_bg.png"], [0, 0, 900, 700], [])],
        "text": """ИИ-осмотр 24.10: подпись «Снимок школы», а в рамке на стене галереи нарисованы озеро и пристань. Сейчас в игре временно — кроп крыльца школы с фона O2 в сепии.

5. H3_state_photo_school.png — 1672×941 к H3_bg.png, непрозрачно ТОЛЬКО в проёме паспарту [938, 236, 1035, 325): старый выцветший снимок (сепия) школьного крыльца Ольховки с дверью — как на O2_bg.png (крыльцо, дверь, перила), чтобы различались петли двери. Рамка и паспарту — с основы, не перерисовывать.
""",
        "manifest": [
            ("H3_state_photo_school", "background_fix", "H3_state_photo_school.png", "H3_bg.png", "1672×941",
             "полный холст в (0, 0), 1:1; непрозрачно в x 938–1035, y 236–325",
             "Старый снимок школьного крыльца с дверью в рамке на стене",
             "H3.json → слой photo_school: image"),
        ],
    },
]

GENERAL = """ДОМ ПРОПАВШИХ ДОРОГ — ПАРТИЯ 10в (задание T8, 24 октября 2026)
Заказ для ChatGPT (image_gen). Текст самодостаточный: всё, что нужно, — здесь, в bases/ и в crops/.

ОБЩИЕ ПРАВИЛА (как в партиях 8–10б)
1. Холсты. Слои к фонам комнат — ровно 1672×941 px (как основа), RGBA.
2. Слой ставится на основу в точку (0, 0), масштаб 1:1, обычное альфа-наложение, непрозрачность 100 %. Ничего не обрезать: прозрачные поля сохраняются, размер холста — как у основы.
3. Всё, что вне указанного прямоугольника, — полностью прозрачно (альфа 0). Внутри прямоугольника непрозрачно только сам предмет и его тень/отражение, если не сказано «непрозрачно во всём прямоугольнике» (заплаты фона).
4. Альфа прямая (straight), не premultiplied; цвет sRGB. Без ореолов и цветной каймы по краю альфы.
5. Прямоугольники — [x1, y1, x2, y2) в пикселях основы: x от x1 до x2−1, y от y1 до y2−1, начало (0, 0) — левый верхний угол основы.
6. Стиль — как у существующих фонов игры (bases/): живописный реализм, мягкий свет, старое дерево, русская деревня; тот же масштаб, перспектива и направление света, что на основе. Детали должны выглядеть нарисованными вместе с фоном, а не вклеенными.
7. Людей и животных не рисовать. Надписей, букв и цифр не рисовать.
8. Заплаты фона (background_fix): по краям прямоугольника — пиксель в пиксель с основой, без шва; вне прямоугольника — прозрачно.
9. Сдайте PNG с ровно такими именами файлов, как в пунктах. Приложите README (как в партиях 8–10б): по каждому файлу — размер, основа, габарит непустой альфы, отклонения от задания. И превью-наложения (JPEG) на основу для проверки.

ПРИЛОЖЕНИЯ
- bases/ — основы, к которым рисуются слои (полные исходники), и образцы. «_сведено_…» — несколько слоёв сведены для сверки; «…_old» — старые слои, которые заменяются; «_сейчас_в_игре_…» — снимки экрана игры 1920×1080 (координаты в них экранные, не основы — только чтобы видеть, как сейчас).
- crops/ — увеличенные фрагменты основ, на них цветной рамкой с подписью показан каждый прямоугольник из задания. Рамки — только на кропах, не в основах.

ПРИОРИТЕТ: сначала п. 1 (лодка и причал), потом 3 (зеркало), 2 (стойка), 4 (дощечка), 5 (снимок).
"""

def load_rgba(p):
    return Image.open(ROOT / p).convert("RGBA")


def compose(spec):
    img = load_rgba(spec[0])
    for p in spec[1:]:
        img = Image.alpha_composite(img, load_rgba(p))
    return img


def font(size):
    for f in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def render_crop(name, img, box, rects, scale=None, circle=False):
    x1, y1, x2, y2 = box
    c = img.crop(box).convert("RGB")
    if scale is None:
        scale = min(3.0, 1400.0 / c.width, 1000.0 / c.height)
    c = c.resize((round(c.width * scale), round(c.height * scale)), Image.LANCZOS)
    d = ImageDraw.Draw(c)
    f = font(max(14, round(16 * min(scale, 1.6))))
    fs = font(13)
    placed = []
    for label, r, col in rects:
        rx1, ry1 = (r[0] - x1) * scale, (r[1] - y1) * scale
        rx2, ry2 = (r[2] - x1) * scale - 1, (r[3] - y1) * scale - 1
        d.rectangle([rx1, ry1, rx2, ry2], outline=col, width=3)
        txt = f"{label} [{r[0]},{r[1]},{r[2]},{r[3]})"
        tw = d.textlength(txt, font=f)
        tx = min(max(rx1, 2), c.width - tw - 6)
        th = f.size + 4
        cands = [ry1 - th - 2, ry2 + 3, ry1 + 4] + [ry1 + 4 + k * (th + 2) for k in range(1, 8)]
        ty = cands[-1]
        for cy in cands:
            if cy < 0 or cy + th > c.height - 22:
                continue
            box_t = (tx - 2, cy - 1, tx + tw + 3, cy + th)
            if not any(box_t[0] < b[2] and b[0] < box_t[2] and box_t[1] < b[3] and b[1] < box_t[3] for b in placed):
                ty = cy
                break
        placed.append((tx - 2, ty - 1, tx + tw + 3, ty + th))
        d.rectangle([tx - 2, ty - 1, tx + tw + 3, ty + f.size + 3], fill=(0, 0, 0))
        d.text((tx, ty), txt, fill=col, font=f)
    cap = f"{name}: фрагмент основы x {x1}–{x2}, y {y1}–{y2}, увеличение ×{scale:.2f}"
    d.rectangle([0, c.height - 20, d.textlength(cap, font=fs) + 10, c.height], fill=(0, 0, 0))
    d.text((5, c.height - 18), cap, fill=(255, 255, 255), font=fs)
    out = CROPS / f"{name}.jpg"
    c.save(out, quality=85, optimize=True)
    return out


def item_box(it, size):
    if "crop_box" in it:
        return it["crop_box"]
    m = it.get("crop_margin", 80)
    xs = [r[1][0] for r in it["rects"]] + [r[1][2] for r in it["rects"]]
    ys = [r[1][1] for r in it["rects"]] + [r[1][3] for r in it["rects"]]
    return [max(0, min(xs) - m), max(0, min(ys) - m), min(size[0], max(xs) + m), min(size[1], max(ys) + m)]


def files_of(entry):
    f = entry[2]
    return f if isinstance(f, list) else [f]


def write_text():
    parts = [GENERAL]
    parts.append("ОСНОВЫ В АРХИВЕ (bases/ ← путь в репозитории проекта)")
    for k, v in BASE_FILES.items():
        parts.append(f"- {k} ← {v}")
    for k in COMPOSITES:
        parts.append(f"- {k} (сведено для сверки)")
    parts.append("")
    for it in ITEMS:
        parts.append("=" * 78)
        parts.append(f"ПУНКТ {it['n']} ({it['g']}). {it['title']}")
        parts.append(f"Приоритет: {it['priority']}")
        crops = [c for c in sorted(p.name for p in CROPS.glob(f"{int(it['n']):02d}_*.jpg"))]
        parts.append("Кропы: " + ", ".join("crops/" + c for c in crops))
        parts.append("Сдать файлы:")
        for e in it["manifest"]:
            parts.append(f"  - {', '.join(files_of(e))} — {e[4]}; основа: {e[3]}; {e[5]}")
        parts.append("")
        parts.append(it["text"].strip())
        parts.append("")
    parts.append("=" * 78)
    parts.append("ИТОГО ФАЙЛОВ: " + str(sum(len(files_of(e)) for it in ITEMS for e in it["manifest"])))
    parts.append("Если что-то в задании невозможно сделать точно (масштаб, место, рамка) — сделайте ближайшее и напишите отклонение в README.")
    (DOCS / TEXT_NAME).write_text("\n".join(parts) + "\n", encoding="utf-8")


def build():
    DOCS.mkdir(parents=True, exist_ok=True)
    CROPS.mkdir(parents=True, exist_ok=True)
    for old in CROPS.glob("*.jpg"):
        old.unlink()
    if BASES.exists():
        shutil.rmtree(BASES)
    BASES.mkdir(parents=True, exist_ok=True)
    for k, v in BASE_FILES.items():
        shutil.copyfile(ROOT / v, BASES / k)
    for k, spec in COMPOSITES.items():
        compose(spec).convert("RGB").save(BASES / k, optimize=True)
    for p in sorted(NOW.glob("*.jpg")) if NOW.exists() else []:
        shutil.copyfile(p, BASES / p.name)
    for it in ITEMS:
        img = compose(it["crop_base"])
        box = item_box(it, img.size)
        slug = it["title"].split(" ")[0].strip("«»:,").lower()
        render_crop(f"{int(it['n']):02d}_{it['g']}_{slug}", img, box, it["rects"], it.get("crop_scale"), it.get("circle", False))
        for name, base, box2, rects in it.get("extra_crops", []):
            render_crop(name, compose(base), box2, rects, None, False)
    write_text()
    if ZIP.exists():
        ZIP.unlink()
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(DOCS / TEXT_NAME, TEXT_NAME)
        for p in sorted(BASES.iterdir()):
            z.write(p, "bases/" + p.name)
        for p in sorted(CROPS.iterdir()):
            z.write(p, "crops/" + p.name)
    print("zip:", ZIP.relative_to(ROOT), ZIP.stat().st_size, "bytes")
    for p in sorted(CROPS.iterdir()):
        print("crop:", p.name, p.stat().st_size)


def manifest_entries():
    out = []
    for it in ITEMS:
        for e in it["manifest"]:
            mid, kind, files, base, size, placement, spec, use = e
            out.append({
                "id": mid, "status": "requested", "kind": kind, "block": BLOCK, "batch": "10c", "g": it["g"],
                "files": ["incoming/" + f for f in (files if isinstance(files, list) else [files])],
                "base": base, "size": size, "placement": placement, "spec": spec,
                "owner": "ChatGPT + Директор", "use": use, "pack": f"Партия 10в, п. {it['n']}",
                "brief": "Docs/art_pack_10c/" + TEXT_NAME,
            })
    return out


def append_manifest():
    path = ROOT / "assets" / "manifest.json"
    src = path.read_text(encoding="utf-8")
    have = {r["id"] for r in json.loads(src)["requests"]}
    new = [e for e in manifest_entries() if e["id"] not in have]
    if not new:
        print("manifest: заявки 10c уже есть")
        return
    end = src.rstrip().rfind("]")
    head = src[:end].rstrip()
    body = ",\n".join("    " + json.dumps(e, ensure_ascii=False, indent=2).replace("\n", "\n    ") for e in new)
    path.write_text(head + ",\n" + body + "\n  ]\n}\n", encoding="utf-8")
    json.loads(path.read_text(encoding="utf-8"))
    print("manifest: добавлено", len(new))


if __name__ == "__main__":
    build()
    if "--manifest" in sys.argv:
        append_manifest()
