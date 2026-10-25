Павел — лист персонажа v2
Файл: pavel_sheet_v2.png
Размер: 3264×2448 пикселей, PNG RGB, непрозрачный.
Фон: #DEDEDC / RGB(222, 222, 220).
Виды: анфас; профиль вправо 90°; спина.
Верх каждого силуэта y=184, высота 2080 пикселей, нижняя линия подошв y=2263.

Павел — 48 лет по канону и ТЗ.
Сохранены зрелое обветренное лицо, короткая борода с сединой, кепка с небольшим козырьком, серо-синяя рубаха с закатанными рукавами, тёмный жилет с отворотами и двумя нижними карманами, бежевый поясной тканевый фартук, тёмные брюки и коричневые кожаные сапоги. Задний хлястик с небольшой пряжкой остаётся частью жилета, а не отдельным кожаным поясом. Подол рубахи сзади виден ниже жилета. Белые следы муки сохранены как нерегулярные пятна, без намеренного превращения их в орнамент. Новые инструменты, сумки, украшения и другие предметы не добавлены.

Что не получилось точно / ограничения
1. Исходный pavel_sheet.png содержит только анфас и спину. Профиль вправо восстановлен генератором, отдельного авторского профиля для прямой сверки нет.
2. Кисть в профиле частично перекрывает фартук; полного просвета между всеми пальцами и одеждой нет. Дальняя рука и часть пальцев скрыты ракурсом. Все пять пальцев на каждой кисти одновременно проверить невозможно; явных лишних пальцев при визуальной проверке не обнаружено.
3. Боковой объём фартука, скрытые крепления и видимая между ногами часть фартука сзади реконструированы, не подтверждены отдельными авторскими видами.
4. Пятна муки, мелкие черты лица, волосы и борода, пуговицы, швы, складки и фактуры перерисованы. Точное расположение мучных пятен и мелких деталей не совпадает с исходником; их согласованность между ракурсами не гарантирована.
5. Нативный результат выбранной генерации — 1448×1086. При сборке фигуры увеличены примерно в 2,29–2,30 раза. Это увеличение, а не нативная генерация в 3264×2448; само увеличение не создаёт настоящих дополнительных деталей.
6. Положение рук различается между видами. Лист является иллюстрированным референсом, а не метрически согласованными проекциями одной готовой 3D-модели.

Создание
Встроенный image_gen, два вызова. В итог вошёл первый вариант. Локальная попытка отвести кисть добавила нежелательные декоративные фактуры на жилете, фартуке и брюках; второй вариант отклонён.
Техническая подготовка ImageMagick: однотонный фон, доработка маски на светлых мучных участках рукавов с восстановлением пикселей выбранной генерации, одинаковая высота трёх силуэтов без изменения пропорций каждого вида, общая линия подошв, экспорт 3264×2448. Художественные детали программно не дорисовывались.
Проверены чтение PNG, размер, цвет фона и итоговый вид. Исходные файлы не изменены.

Точный запрос 1 — выбранная генерация
Use case: identity-preserve.
Make an improved 3D-model turnaround reference for PAVEL, the exact same48-year-old working man in attached pavel_sheet.png from "Дом пропавших дорог". Preserve his recognizable face, age, build, clothing, muted colors, flour dust and all existing details. No redesign.
Image1 contains only FRONT and BACK. Reconstruct the missing STRICT90degree RIGHT-FACING full-body profile from those two views. Do not duplicate front in center.
Output ONE landscape4:3 sheet, target EXACTLY3264×2448px. Exactly THREE complete head-to-sole views in ONE row: LEFT strict FRONT; CENTER strict90° RIGHT PROFILE, nose pointing RIGHT; RIGHT strict BACK, no visible face. Same anatomical height and scale, aligned cap tops and ALL boot soles on ONE common horizontal baseline. No3/4/perspective, no crops, figures never touch, generous clear outer and interfigure margins.
BACKGROUND: OPAQUE PERFECTLY UNIFORM light gray exact #DEDEDC RGB222,222,220. No gradient/vignette, ground plane or cast/contact shadows. Soft even neutral studio lighting, mild form shading only. Skin natural warm living complexion, not washed out.
IDENTITY: same48-year-old adult with source weathered calm/serious face, natural forehead/eye lines, original eyes/brows/nose/lips, short gray/salt-and-pepper full beard and mustache, short graying hair visible under cap at sides/nape. Average/sturdy working man's original proportions, not bulky new physique, not younger/elderly, no dramatic wrinkles, scars or makeup.
OUTFIT STRICT LOCK:
1) Same plain worn OLIVE-BROWN/GRAY tweed flat WORK CAP with soft rounded crown, short dark brim/peak and source panel seams. Not an ushanka, baseball cap or peaked uniform cap. No emblem or badge.
2) Same plain faded BLUE-GRAY coarse linen work SHIRT, open folded pointed collar, original rolled sleeves at elbows with same rolled cuff bands, bare lower forearms. The back shirt hem extends below the waistcoat down to upper thigh as reference, same loose straight shirt tail. No new embroidery, plaid or printed motifs.
3) Same dark CHARCOAL-BROWN/GRAY wool waistcoat, short source notched lapels, existing simple small front buttons, same two small low front pockets and source short pointed front hem. Plain rear with original lower-back fabric ADJUSTER STRAP and small source buckle; this is a waistcoat adjuster, NOT a new wide leather belt or new crossed straps. Preserve seam locations and lengths, no new pockets/tools/jewelry.
4) Same plain worn beige/tan coarse linen WAIST APRON, from natural waist below waistcoat to near knees, flat slightly rounded rectangular front panel with source hems; chest stays uncovered by apron. From rear show ONLY original narrow apron side edges, with source long blue-gray shirt tail visible above dark trousers. Do not turn it into a bib apron, skirt, full wraparound apron or leather apron. Keep apron length and attachment consistent in all views. No new exposed belt/hardware.
5) Same dark charcoal/brown loose work TROUSERS tucked into same dark worn brown LEATHER calf boots, rounded toes, natural ankle creases and modest low soles/heels. No added laces/buckles/metal/zips, no felt boots or rubber boots.
6) Keep the source WHITE FLOUR DUST/PATCHES on sleeve outer shoulders and elbows, waistcoat front, waist apron and trousers (including visible rear thighs/knees). Flour is irregular white powder/soft smudges on plain fabrics, NOT decorative patterns, paint splatter designs, printed logos, mold or snow. Match source approximate density and placement. Clothing remains plainly constructed beneath dust.
POSE: upright straight neutral, feet shoulder-width, even weight, knees straight. Arms DOWN and gently away from sides. Hands BARE and relaxed, five normal anatomically correct individually legible fingers per hand with normal thumbs and small gaps, no fused or extra digits. Hands must not touch shirt, waistcoat, apron or trousers.
CENTER PROFILE HAND IS IMPORTANT: angle near arm diagonally DOWN and FORWARD toward RIGHT about35–40degrees so the ENTIRE near hand/ALL fingers and thumb hang in EMPTY GRAY BACKGROUND fully OUTSIDE the front apron/body outline, with obvious visible gray clearance. Do not put hand over apron or body. Hand remains below waist, natural shoulder/elbow/wrist; slight wrist rotation may reveal thumb. Head/torso/pelvis/feet remain strict90° right profile, far arm may be occluded. Keep hand clear of adjacent figure.
RENDERING: refined softly realistic/painterly game-character sheet. Clear short beard/hair strands, cap weave and seams, linen weave, waistcoat wool, flour dust, apron hem and boot creases without changing design. Source muted earth/blue-gray palette. No floral/paisley/geometric/embossed motifs anywhere.
No captions, names, text, numbers, borders, panel lines, watermark, portraits, bags, tools or new props. Exactly three complete equally sized views only.

Точный запрос 2 — отклонён
Use case: precise-object-edit.
Edit ONLY the near arm of the CENTER right-facing profile. Move the whole arm forward naturally from the shoulder so the relaxed bare hand hangs about100pixels farther to the RIGHT, entirely in empty gray space in front of the apron, with a clear20pixel gap between every finger/thumb and the apron. On this1448x1086sheet, place the hand aroundx870..930,y500..600. Natural elbow/wrist, five normal fingers, no torso twist.
Preserve every other part of the image unchanged, including both other figures, Pavel's same48-year-old face, cap, clothing materials/colors, original flour smudges, body proportions and boots. No other edit. Same complete front / right profile / back layout, same scale and baseline. Opaque uniform gray #DEDEDC background, target3264x2448.
