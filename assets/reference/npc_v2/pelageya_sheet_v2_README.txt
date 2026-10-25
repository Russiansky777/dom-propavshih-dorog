Пелагея — лист персонажа v2
Файл: pelageya_sheet_v2.png
Размер: 3264×2448 пикселей, PNG RGB, непрозрачный.
Фон: #DEDEDC / RGB(222, 222, 220).
Виды: анфас; профиль вправо 90°; спина.
Верх каждого силуэта y=184, высота 2080 пикселей, нижняя линия подошв y=2263.

Пелагея — 40 лет по канону и ТЗ.
Сохранены крепкое телосложение, обветренное лицо с тёплым тоном кожи, волосы с центральным пробором под однотонным ржаво-красным платком, горчично-охристая стёганая куртка с серо-бежевыми отворотами манжет, кожаный пояс, оливковая юбка ниже колен и тёмные кожаные сапоги.
Пряжка и свободный конец пояса расположены справа у персонажа, слева для зрителя в анфасе. Коричневый кожаный предмет на левом бедре сохранён по видимому силуэту. Он похож на рукавицу; точное число перекрывающихся деталей и крепление нельзя надёжно установить по исходнику. Новой сумки, противоположного дубликата или других предметов не добавлено.

Что не получилось точно / ограничения
1. В исходном pelageya_sheet.png два анфаса и спина. Профиль восстановлен генератором: отдельного авторского профиля для прямой сверки нет.
2. В профиле кисть отделена от одежды видимым просветом, однако рука выдвинута вперёд сильнее, чем в остальных видах. Это различие поз, а не одна строго общая поза во всех проекциях.
3. Большой палец и дальняя рука частично скрыты ракурсом. Одновременная видимость всех пяти пальцев на каждой кисти не подтверждена; явных лишних пальцев при визуальной проверке не обнаружено.
4. На исходном анфасе платок завязан под подбородком, на спине показан узел на затылке. Эти признаки сохранены; единая согласованная конструкция одного платка не установлена. В профиле видны оба признака. Перед 3D-моделированием эту схему требуется уточнить.
5. Две верхние петли застёжки подтверждаются исходником. Небольшая третья петля под поясом выражена в генерации чётче, чем позволяет проверить исходный участок, частично закрытый пряжкой и ремнём. Эту деталь следует сверить.
6. Лицо, отдельные волосы, стёжка, швы, складки, края кожаного предмета на поясе и фактуры заново отрисованы. Их точное совпадение с исходником и между видами не гарантировано; конструкция и крепление предмета сбоку реконструированы.
7. Нативный результат генератора — 1448×1086. При сборке фигуры увеличены примерно в 2,27–2,28 раза. Это увеличение, а не нативная генерация в 3264×2448; само увеличение не создаёт настоящих новых мелких деталей.
8. Лист — иллюстрированный референс, а не метрически согласованные проекции одной готовой 3D-модели.

Создание
Встроенный image_gen, один вызов по исходному листу.
Техническая подготовка ImageMagick: однотонный фон, одинаковая высота трёх силуэтов без изменения пропорций каждого вида, общая линия подошв и экспорт 3264×2448. Художественные детали программно не дорисовывались.
Проверены чтение PNG, размер, цвет фона и итоговый вид. Исходные файлы не изменены.

Точный запрос генератору
Use case: identity-preserve.
Create an improved 3D-model turnaround reference for PELAGEYA from "Дом пропавших дорог": the EXACT SAME40-year-old adult woman in attached pelageya_sheet.png, preserving recognizable face, build, age, clothing, colors and existing objects. No redesign.
Image1 is the STRICT identity/costume reference. It contains two front views and one back. Replace the repeated middle front with a reconstructed STRICT90° RIGHT-FACING full-body profile.
Output ONE landscape4:3 sheet at target3264×2448px. Exactly THREE complete head-to-boot views in ONE row: LEFT strict FRONT, CENTER strict90° SIDE facing RIGHT (nose points RIGHT), RIGHT strict BACK with no face. Same anatomical height and scale, aligned head tops and ALL boot soles on ONE baseline. No3/4, no perspective, no cropping/overlap. Clear margins and figure separation.
Background OPAQUE perfectly UNIFORM light gray EXACT #DEDEDC RGB222,222,220. No gradients/vignette, ground plane or cast/contact floor shadows. Soft even neutral studio light, gentle form shading, warm living skin not bleached.
IDENTITY: source sturdy/robust adult female build with broad shoulders, natural waist, source proportions. Same40-year-old rounded-oblong weathered face, natural lines, strong cheeks, source nose/lips/brows, brown eyes, calm serious neutral expression and warm fair/ruddy complexion. Do not rejuvenate into a young girl, age into an elderly woman, slim or glamorize. Same ash/light brown center-parted hair visible around forehead, mostly covered. No makeup, new bangs or hairstyle.
COSTUME LOCK:
- Same small PLAIN rusty-red/russet headscarf fitted closely over crown/ears, neatly lying edges and short original ties. Preserve source visible front chin knot/ends and rear nape knot/ends, no new extra loose fabric, large corners, prints or decorations.
- Same MUSTARD/OCHRE hip-length padded quilted jacket. Narrow VERTICAL quilting channels on torso; original CROSS/DIAMOND-like quilt pattern across sleeves. Source slightly overlapping front closure, two small original loop-and-knot/toggle fastenings offset to wearer's RIGHT/viewer's LEFT, NOT a new line of metal buttons. Original short peplum/hem below belt, no new pockets or seams. Same gray-beige rolled cuff bands, sleeves ending at source MID-FOREARM position with lower forearms/wrists bare. Do not lengthen sleeves over hands.
- Same narrow worn brown LEATHER BELT around waist; small original buckle and short loose end at wearer's RIGHT/viewer's LEFT in front view. Back shows a plain horizontal belt with no extra buckle/knot. Keep original fit and width.
- Preserve the SAME brown leather MITTEN-SHAPED HANGING OBJECT at wearer's LEFT hip/viewer's RIGHT in front: exactly the source overlapping narrow and broad shapes, short square cuff-like top and rounded lower outline. Do not convert it into a pouch/bag, duplicate on opposite hip, invent extra pieces or change its scale/attachment position. It hangs beside jacket hem/upper skirt, and must be visible in profile/rear only as anatomical occlusion allows.
- Same plain muted OLIVE/KHAKI skirt below knees, soft modest A-line with a few natural broad folds, not a sharply pleated new skirt, same hem.
- Same plain dark worn BROWN/CHARCOAL LEATHER calf boots, round toes, source natural ankle wrinkles and modest flat soles/heels. No laces, buckles, new zips, metal trim, straps, fur or felt boots.
POSE: stands straight with feet shoulder-width and weight even. Arms DOWN, gently separated from torso, hands relaxed and BARE, five anatomically normal individually readable fingers with normal thumbs and slight spaces, no merged/extra digits. Hands must not touch clothing, belt or hanging object.
CENTER PROFILE HAND POSITION IS CRITICAL: angle the near arm diagonally DOWN and FORWARD toward RIGHT about35–40degrees, so the ENTIRE hand and every fingertip/thumb hang in EMPTY GRAY BACKGROUND in front of the jacket/skirt silhouette with a clear gray gap. Do not lay hand on top of skirt or jacket. Hand below waist, natural shoulder/elbow/wrist attachment, no body/head/foot twist, far arm may be occluded. Keep clear space from neighboring figure.
Rendering: refined softly realistic/painterly game reference, fine hair strands, plain headscarf weave, readable original jacket quilting and cuff folds, leather belt/hanging object edges and boot creases. ALL fabric/leather surfaces are PLAIN UNORNAMENTED except the source jacket quilting: no floral, paisley, geometric printed motifs or embossing.
No names, labels, text, numbers, frames, panel lines, watermark, portraits, jewelry, bags, tools or new props. Three equal-scale complete views only.
