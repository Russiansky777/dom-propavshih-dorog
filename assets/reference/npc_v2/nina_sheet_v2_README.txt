Нина — лист персонажа v2
25.10.2026

Файл: nina_sheet_v2.png
Размер: 3264 × 2448 пикселей. PNG RGB, непрозрачный.
Фон: ровный #DEDEDC / RGB(222, 222, 220).
Три вида: анфас, профиль вправо 90°, со спины.
Виды выровнены по высоте и нижней линии подошв: y=2323, верх голов y=124.
Нина — 67 лет. Сохранены седой центральный пробор и низкий пучок, тёмное платье со стойкой и мелкими пуговицами, серо-коричневая вязаная шаль, круглые очки на шнурке, чёрные шнурованные ботинки. Посторонние предметы не добавлялись.

Что не получилось точно / границы достоверности
1. Нативный результат генератора — 1448 × 1086. Финальный файл увеличен до требуемых 3264 × 2448; увеличение само по себе не добавляет настоящих мелких деталей. Это не нативная генерация в целевом разрешении.
2. В исходном nina_sheet.png в центре второй анфас, а не профиль. Поэтому боковой объём лица, одежды и пучка восстановлен генератором по анфасу и спинке, а не подтверждён отдельным авторским профилем. Лицо и объёмы близки к исходнику, но не являются точным переносом пикселей.
3. В профиле ближняя кисть читается на фоне юбки: отдельного просвета между её силуэтом и одеждой не получилось. Дальняя рука перекрыта ближней. Для 3D-модели нельзя считать этот участок проверенным зазором между кистью и тканью.
4. Вязка шали и складки платья заново отрисованы; совпадение отдельных петель и складок между видами не гарантируется.

Способ создания
Встроенная генерация изображений (image_gen), два вызова: лист по двум эталонам; затем отделение от фона. Техническая подготовка: удаление малопрозрачного краевого шума, приведение трёх видов к одинаковой высоте без изменения пропорций каждого вида, совмещение подошв, компоновка на сплошном фоне #DEDEDC, увеличение до заданного размера. Художественные детали получены генератором, не дорисованы программно. Исходные вложения не изменялись.

Точные запросы генератору

ЗАПРОС 1
Use case: identity-preserve.
Create the final improved 3D reconstruction character turnaround sheet for NINA from the game “Дом пропавших дорог”, file nina_sheet_v2.png.
INPUT 1 nina_sheet.png is the STRICT character identity and costume reference. INPUT 2 OBRAZEC_agata_sheet_v2.png is ONLY a reference for rendering detail, clean full-length turnaround presentation, scale and canvas layout. Do not transfer Agata's face, youth, costume, colors, bag, scarf pattern or hairstyle to Nina.
OUTPUT: one landscape PNG sheet, exactly 3264 × 2448 pixels (4:3), flat completely uniform light gray RGB(222,222,220), hex #DEDEDC. Exactly THREE complete full-body views of the SAME Nina, arranged in one horizontal row: LEFT strict front facing the viewer; MIDDLE strict right-facing 90-degree side profile, nose points to the right edge; RIGHT strict rear, no visible face. Orthographic presentation, no three-quarter view. Equal anatomical height and scale in all three, tops of heads aligned, ALL soles on the SAME baseline, generous clear margins, no cropping or touching figures. Full head-to-boot coverage.
IDENTITY LOCK: Nina is a 67-year-old woman, the exact recognizably same slender older woman shown in input1, long narrow mature face, brown eyes, prominent natural nose, fine lips, same ears and brows, sober calm expression, clear age lines, natural warm living skin, not pale wax or younger. Gray/silver center-parted hair smoothly pulled back into the SAME small compact round low bun at the back of her head; individual strands and coiled bun clear from all relevant views, no loose braid or new hairstyle.
COSTUME LOCK: exactly the source outfit. Plain nearly black charcoal long-sleeved high-standing-collar button-front dress, fitted natural waist seam and flowing long skirt ending just above the source black lace-up ankle boots. Same very small dark front buttons, same silhouette and lengths. Taupe-gray knitted shoulder shawl, thick detailed fine knit, draped naturally around both shoulders, two long narrow front ends lying down to the hips, back forms the same simple broad softly curved shawl hem across the upper back as in input1. All shawl edges neatly lying/tucked with no sticking-out corners. Preserve the small round bronze/dark spectacles hanging at upper chest on the thin neck cord exactly as in the source; keep those spectacles and cord geometrically consistent, not on her face. Plain black/dark boots with proper laces, no new jewelry, apron, bag, belts, tools, props or designs.
STANCE: upright relaxed neutral anatomical stance. Feet shoulder width, both feet supported naturally at the common baseline. Arms down and gently abducted just enough that bare hands are fully clear of skirt and shawl in every view. Natural hands with five anatomically correct individually readable fingers each, fingers slightly separated, thumbs correctly placed, not fused; palms inward, not a T-pose or raised arms. Maintain anatomical placement in the true side view.
RENDERING: refined realistic game character sheet, match the material clarity and hair/hand detail of input2 while preserving all details and subdued colors from input1. Soft even neutral studio light on the characters, very mild form shading, no hard directional shadows, no floor shadow, no background gradient or vignette.
Absolutely no captions, lettering, numbers, watermark, frames, panel borders, added objects, portraits, extra limbs or extra figures. Do not duplicate the front pose in the middle: the middle MUST be a true 90° right-facing profile. Preserve the SAME dress, shawl construction, glasses, bun, height and body proportions across all three.

ЗАПРОС 2
Use case: background-extraction. Edit input1, the newly generated Nina character turnaround, preserving the character render and three-view layout. Input2 is Nina's original identity reference for fidelity only. Remove ONLY the gray background and any background shading. Return the same complete three character views on REAL transparent alpha, no gray, white, black, checkerboard drawing, ground plane, shadows or backdrop. Keep every visible detail of Nina's face, her 67-year-old age, natural warm complexion, anatomy, gray center-parted hair and low compact bun, same gray knit shawl, black buttoned high-collar dress, round glasses on neck cord, black lace-up boots, colors, lighting, front / strict90degree right-facing profile / rear, pose, finger count, character proportions, aligned soles and relative locations UNCHANGED. Do not add props, text or any new outfit details. Preserve individual hair and garment edges with clean antialiasing. Exactly three full-body views, not cropped, same scale. Deliver a PNG at 3264 × 2448 pixels, landscape4:3. This is a technical cutout of the existing sheet for placement on a precise solid-color modeling background, not a character redesign.

