Митя — лист персонажа v2
Файл: mitya_sheet_v2.png
Размер: 3264×2448 пикселей, PNG RGB, непрозрачный.
Фон: #DEDEDC / RGB(222, 222, 220).
Виды: анфас; профиль вправо 90°; спина.
Верх каждого силуэта y=184, высота 2080 пикселей, нижняя линия подошв y=2263.

Митя — 37 лет по канону и ТЗ, взрослый сын Пелагеи.
Сохранены крепкое телосложение, обветренное румяное лицо, густая тёмная борода с проседью, тёмно-серая ушанка с опущенными наушниками, светлый овчинный тулуп с широкими меховыми отворотами и отделкой, двойной верёвочный пояс, две серо-коричневые вязаные варежки на поясе, тёмные брюки и высокие серые валенки. Варежки висят у бёдер, кисти голые. Узел пояса — слева у персонажа, справа для зрителя в анфасе; сзади узел не добавлен. Новые инструменты, сумки, карманы и другие предметы не добавлены.

Что не получилось точно / ограничения
1. Исходный mitya_sheet.png содержит два анфаса и спину. Профиль вправо восстановлен генератором; отдельного авторского профиля для прямой сверки нет.
2. Кисть в профиле частично перекрывает передний контур тулупа. Полного просвета между всеми пальцами и одеждой не получилось. Дальняя рука и часть пальцев скрыты ракурсом. Одновременная проверка всех пяти пальцев на каждой кисти невозможна; явных лишних пальцев при визуальной проверке не обнаружено.
3. Мелкие черты лица, отдельные пряди бороды и меха, вязка варежек, витки верёвки, швы и фактуры замши/войлока перерисованы; точное совпадение с исходником и между видами не гарантировано.
4. Крепления варежек сбоку и их объём в профиле восстановлены по переднему и заднему видам. Их конструкция не подтверждена отдельным боковым эталоном.
5. Нативный результат выбранной генерации — 1448×1086. При сборке фигуры увеличены примерно в 2,24–2,25 раза. Это увеличение, а не нативная генерация в 3264×2448; само увеличение не создаёт настоящей дополнительной детализации.
6. Положение рук различается между видами. Лист является иллюстрированным референсом, а не метрически согласованными проекциями одной готовой 3D-модели.

Создание
Встроенный image_gen, два вызова. В итог вошёл первый вариант. Попытка отвести кисть в профиле добавила нежелательные декоративные фактуры на тулупе, мехе и валенках; второй вариант отклонён.
Техническая подготовка ImageMagick: однотонный фон, выравнивание высоты трёх силуэтов без изменения пропорций каждого вида, общая линия подошв, экспорт 3264×2448. Художественные детали программно не дорисовывались.
Проверены чтение PNG, размер, цвет фона и итоговый вид. Исходные файлы не изменены.

Точный запрос 1 — выбранная генерация
Use case: identity-preserve.
Create an improved 3D-model character turnaround reference for MITYA, the exact same adult man in image1 mitya_sheet.png from "Дом пропавших дорог". His canonical age is THIRTY-SEVEN (37), the adult son of Pelageya. Keep the same recognizable mature face and beard from reference, not a17-year-old and not an elderly man.
Image1 is the STRICT identity/costume/color/proportion reference. It repeats two frontal views and one back. Replace the repeated middle front with a reconstructed STRICT RIGHT-FACING90° SIDE PROFILE.
Output ONE landscape4:3 sheet target EXACTLY3264×2448px. THREE complete head-to-felt-boot figures in ONE horizontal row: LEFT FRONT, CENTER STRICT RIGHT PROFILE with nose pointing RIGHT, RIGHT STRICT BACK with no face. Same anatomical height and scale, aligned tops of hats and all boot soles on ONE baseline. No3/4, no perspective, no crops. Clear margins and space between figures; hands do not touch other figures.
Backdrop: OPAQUE PERFECTLY UNIFORM light gray exact #DEDEDC RGB(222,222,220). No gradient, vignette, ground plane or cast/contact floor shadows. Soft even neutral studio lighting, gentle form shading, clear materials.
IDENTITY: preserve the source sturdy stocky broad-shouldered adult man under the heavy winter coat. Same broad serious calm face, natural nose and brow, warm living fair complexion with source pink/reddened cheeks and nose, not bleached or gray. Same thick dark brown/charcoal full beard and mustache with subtle gray hairs already present; not a new white/long beard or a clean shave. Beard strands well defined. Keep age37, face proportions and body proportions; do not add dramatic wrinkles, scars, makeup or new hairstyle.
COSTUME STRICT LOCK:
- Same plain DARK CHARCOAL GRAY FUR USHANKA, broad rounded/flat-ish crown and long EARFLAPS DOWN covering ears and extending along both sides toward neck. Same fur texture and back nape flap. No emblem, badge, star, straps tied on top or new decorations. Hair mostly hidden as in source.
- Same thick PLAIN warm IVORY/CREAM SHEEPSKIN COAT to just ABOVE KNEES, suede exterior, modest broad cream curly shearling collar with source large overlapping lapels, subtle natural seams including center back seam and shoulder seams. Closed overlapping front, original diagonal front opening/lapel line, no visible added buttons, buckles or zips. Same cream wool edge trim at cuffs, front opening edge and bottom hem. Sleeves to wrists. Same long loose/bulky outline, NOT slim tailoring, no new pockets, embroidery, prints or ornament.
- Same plain natural TAN TWISTED ROPE BELT wrapped TWICE horizontally around waist. One knot at the front on HIS LEFT side (viewer's right in front view); two short hanging ends in source position. Back shows ONLY the two horizontal rope lengths, NO back knot or new bow. Keep rope fibers/laying physically readable and consistent.
- EXACTLY TWO gray-brown KNITTED MITTENS hanging from the belt, ONE at each hip as source, fingers down, source simple wool cuffs and thumbs. They are HANGING props at hips, NOT worn on hands. Preserve source length/shape and position; both visible from front, near one visible in profile, rear views show only the portions not occluded by coat. Do NOT add more mittens, pockets, tools, bag or pouch.
- Same small visible sections of dark brown/charcoal trousers between coat hem and tall boots.
- Same plain GRAY WOOL FELT BOOTS (VALENKI), rounded toes and flat felt bottoms, source tall calf/knee height, no laces/buckles, leather panels, straps, black rubber soles or ornamental patterns. Fibrous gray felt, not leather boots.
POSE: upright neutral, knees straight, feet shoulder width, even weight. Arms DOWN and gently away from body, hands relaxed and BARE, five correctly formed individually legible fingers with normal thumbs and slight gaps. All fingertips clear of coat, belt and hanging mittens. In center RIGHT profile, gently swing near arm diagonally down and FORWARD toward RIGHT about30–40degrees so the ENTIRE near hand is in EMPTY GRAY SPACE fully OUTSIDE the coat's front silhouette, with an obvious gap between ALL digits and fabric/mitten. Do not lay hand over coat. Hand stays below waist, anatomically natural shoulder/elbow/wrist, no torso/head twist; far arm may be occluded.
Style: refined softly realistic/painterly game character reference, high material detail without changing design. Fine beard/fur fibers, wool collar, plain suede grain, rope twist, simple knit mittens and felt fibers. Keep subdued reference palette, no decorative surfaces anywhere.
No text, labels, names, captions, numbers, watermark, borders, extra props/portraits/figures. THREE full-body views only.

Точный запрос 2 — отклонён
Make ONE LOCAL ARM-POSE correction to this Mitya three-view sheet. This is the SAME37-year-old man. Preserve all existing character pixels/design as closely as possible. No redesign or new objects.
Only the CENTER right-facing profile: move the near arm and bare hand approximately60–70pixels to the RIGHT at hand level (on this1448x1086canvas), by swinging the arm naturally forward from the shoulder. The coat's front contour is at approximatelyx835. Put the ENTIRE bare hand, thumb and ALL fingers in empty gray background at aboutx865..925, y525..625, with at least15pixels of GRAY GAP between hand and coat/hip mitten. The hand must no longer overlap coat. Arm diagonally DOWN/FORWARD, hand below waist, natural shoulder/elbow/wrist, five relaxed fingers, no stretch or torso twist. Keep nose, chest, pelvis and felt boots strict90degree RIGHT profile. Do not touch the neighboring back-view hand.
Left FRONT and right BACK stay unchanged. Same thick dark beard with subtle gray, broad ruddy face, dark gray ushanka earflaps down, PLAIN ivory sheepskin coat and curly wool lapels/cuffs/hem, same rope belt two wraps and ONE FRONT knot on wearer's LEFT, exactly TWO hanging knitted mittens at hips, dark trousers, PLAIN gray felt boots. Hands remain bare. Preserve clothing lengths, coat fullness, all source muted colors and material textures.
Absolutely NO floral, paisley, geometric, printed, embossed or decorative surface patterns anywhere. Coat is plain suede, boots plain felt; ordinary grain/fibers only. No new pockets, buttons, tools, badges, soles or straps.
ONE sheet3views front/right profile/back, equal full-body height, aligned hat tops and soles, no cropping. Opaque UNIFORM #DEDEDC RGB222,222,220 background, no gradient, floor/shadows. No text/frames. Target3264x2448landscape4:3.
