# Провенанс ассетов

Запись обязательна до отметки `delivered` в `assets/manifest.json`.

| Ассет | Источник (модель/версия/задание) | Референсы | Лицензия | Дата | Кто |
| --- | --- | --- | --- | --- | --- |
| story_source/concepts/*.png | Ранние концепты обсуждения (генерация изображений в ChatGPT, 2026) | — | Внутренние референсы, не игровые ассеты | 2026-10 | Директор |
| assets/reference/tikhon_sheet.png | ChatGPT (генерация изображений, 17.10.2026) по Docs/BRIEF_CHATGPT_SAMPLES.md | characters.json, концепты | Директор — владелец; для игры | 2026-10-17 | Директор |
| assets/reference/H1_bg.png, H1_fg_table_chair.png | ChatGPT (17.10.2026) по брифу образцов | концепт «Тёплая комната» | Директор — владелец; для игры | 2026-10-17 | Директор |
| assets/reference/agata_sheet.png | ChatGPT (17.10.2026), правка эпохи | бриф + правка в чате | Директор — владелец; для игры; утверждён | 2026-10-17 | Директор |

## 2026-10-17 — пакет E0–E1 от ChatGPT (v1)
- Источник: ChatGPT, встроенный генератор `image_gen` (версия модели инструментом не сообщена), по `Docs/BRIEF_CHATGPT_E0_E1.md` с референсами `assets/reference/`. Файлы: 36 PNG в `assets/incoming/` (9 фонов со слоями, состояния H1/H3/O1/O2, листы Тамары и Пелагеи, 5 слоёв M05), метаданные и промпты — `assets/incoming/_meta_e0e1_v1/`. Размеры 1672×941 (фоны), 1448×1086 (листы); масштабируются до базы 1920×1080 при импорте.
- Права: сгенерировано по заказу Директора; оригинальные байты сохранены без обработки.
- Текст: `data/story/text/ru_E0_E1.json` — 177 из 220 строк переписаны ChatGPT (владелец текста), `draft: false`; `story_source/full_scenario_v4.md` — сценарий v4 (Агата 18).

## 2026-10-17 — фоновая музыка (Suno)
- Источник: Suno (инструментал), сгенерировано Директором по промптам ChatGPT (лог обсуждения — в чате 17.10, 21:24). Оригиналы WAV 48 кГц/16 бит хранятся у Директора (в репозиторий не кладём из-за размера); в WAV — метка «made with suno», id треков указаны в `data/story/music.json`.
- Права: коммерческое использование треков Suno зависит от плана подписки на момент генерации (по словам ChatGPT в логе — WAV доступен на Pro/Premier). Перед релизом сверить условия Suno для плана Директора.
- Порядок тем — по времени создания (Директор: «первый — дом, последний — последняя нота»): 01 Дом, 02 Деревня и дорога (Quiet Northern Roads), 03 Река и мельница (The Gusli Circle), 04 Школьный класс (Frost in the Schoolroom), 05 Зеркало (перегенерация), 06 Финал «Последняя нота».
- Обработка: `pipeline/audio/prepare_music.sh` — линейная нормализация к −18 LUFS (было −15,2…−16,3), true peak −1,5 dBTP, OGG Vorbis q5; итог `assets/music/*.ogg`, 16,5 МБ на шесть треков.

## 2026-10-17 — звуки (ElevenLabs Sound Effects)
- Источник: ElevenLabs (генерация Директором), WAV 48 кГц стерео; имена по таблице Директора 17.10 22:09. Исходные имена файлов: `FOLYMisc-door_open_and_close` → `sfx_door_passage.wav`; `FEETHmn-foot_steps_on_gravel` → `sfx_steps_gravel.wav`; `FEETHmn-Soft_isolated_foots…` → `sfx_steps_soft.wav`; `A_worn_soft_leather…` → `sfx_bag_leather.wav`; `AMBRoom-A_quiet_old_library…` → `amb_stove_fire.wav` (по таблице — единственный кандидат на «огонь в печи»; судя по имени это тон тихой комнаты — проверить на слух); `RAINWatr-Gentle_relaxing_rai…` → `amb_rain.wav`; `OBJHsehld-opening_old_door` → `sfx_door_variant_01.wav`; `DOORWood-A_subtle_realistic_w…` → `sfx_door_variant_02.wav`.
- Оригиналы в `assets/sfx_src/` (≈20 МБ); в игру идут обработанные версии (нарезка шагов, выравнивание громкости, OGG для петель).
- Обработка: `tools/prepare_sfx.sh` (→ `tools/prepare_sfx.py`) пишет прямо в `game/assets/sfx/` — 24 файла: двери (3), шаги гравий 8 и мягкие 7 (нарезка по атакам), сумка (1 + 3 жеста), петли `amb_rain.ogg` (28 с) и `amb_stove_fire.ogg` (18,5 с); измерения громкости — `game/assets/sfx/levels.json`.
- Права: коммерческое использование звуков ElevenLabs — по условиям плана Директора на момент генерации; сверить перед релизом.

## 2026-10-17 — шрифты интерфейса (SIL OFL 1.1)
- **Old Standard TT** 3.000 (Regular, Bold) — заголовки, название комнаты, кнопки, меню. Воспроизводит «обыкновенную» книжную гарнитуру конца XIX — начала XX века (в том числе русских изданий того времени). Автор — Alexey Kryukov, «Copyright 2011 The Old Standard Project Authors»; зарезервированных имён нет. Файлы: `game/assets/fonts/old_standard_tt/OldStandard-{Regular,Bold}.ttf` + `OFL.txt`.
- **PT Serif** 1.000W OFL (Regular, Italic, Bold) — диалоги, журнал, подсказки, всплывающие подписи. ParaType, «Copyright © 2010 ParaType Ltd», Reserved Font Names «PT Sans», «PT Serif», «ParaType» — файлы не изменять (никакого сабсеттинга), иначе нужно переименование. Файлы: `game/assets/fonts/pt_serif/PT_Serif-Web-{Regular,Italic,Bold}.ttf` + `OFL.txt`.
- Источник: репозиторий Google Fonts на GitHub, `https://raw.githubusercontent.com/google/fonts/main/ofl/{oldstandardtt,ptserif}/` (ветка main, 17.10.2026), файлы взяты байт в байт. SHA-256: `OldStandard-Bold.ttf` 7d831e9d799ad23ee98e889381a9db2a283b2dac7f228dd5c06071decb9c54db; `OldStandard-Regular.ttf` 42717a1280b523a506ca2b0285cca380e77fe214b1f6e3d75a8b925005f19eac; `PT_Serif-Web-Bold.ttf` 038ba7336bd7ea14f12ad155bed51a4345cac5153275d521dec3ba04021c526e; `PT_Serif-Web-Italic.ttf` f57e95ff9dc85691a3b2e193f2028db36f6663939a46c0fc4f286d618b80b7ce; `PT_Serif-Web-Regular.ttf` a4951fade06ff8f09b7673aa81ffb65a8cd409e24d3289a6dc670bc4dda2557a.
- Проверено: лицензия — `OFL.txt` (SIL Open Font License 1.1) в пакете и в метаданных шрифта (name ID 13/14), поэтому лицензия едет и внутри собранной игры; кириллица полная — весь алфавит с «ёЁъЪ», «« » — – … №», дореформенные «ѣ і» (fontTools, cmap). Сравнивался также Lora (OFL) — для текста выбран PT Serif: выше строчные, лучше читается на 1280×720.
- Права: OFL разрешает встраивать в коммерческую игру и распространять вместе с ней; продавать шрифт отдельно нельзя.

## 2026-10-17 — копии иконок предметов в игре
- `game/assets/icons/<item_id>.png` — копии `assets/icons/<item_id>.png` (конвейер Meshy, run 39065730914), обрезанные по видимому предмету и уменьшенные до 192 px скриптом `tools/sync_icons.sh` (Pillow, Lanczos; цвет не меняется). Провенанс исходников — в записи конвейера.
- **Исключение — `door_hinges` (18.10):** набор из трёх петель собран `tools/make_icon_hinges.py` из `assets/incoming/M05_hinge.png` (ChatGPT v1, петля крупного плана двери): три копии веером, мягкая тень, без новых деталей — чтобы иконка совпадала с дверью и петель было видно три. Попытка Meshy text-to-image (run 39087095862, 6 кредитов) рисовала одну-две петли другой формы — отклонена координатором, её файл заменён.

## 2026-10-18 — слои H1, выведенные из арта ChatGPT (замечания Директора по H1)
- `game/assets/rooms/H1/state_shelf_stove.png` — полка A: рисунок ChatGPT `assets/incoming/H1_state_shelf_stove.png` (пакет E0–E1 v1), зеркально и перспективным преобразованием (OpenCV `warpPerspective`) переложен на боковую грань печи фона `H1_bg.png`; мягкая тень и вырез под кочерги — по фону. `state_holes_stove.png` — гнёзда креплений и след опор, нарисованы кодом (Pillow) в тон побелки фона. `fg_chair_arm.png` — вырез подлокотника из `H1_fg_table_chair.png` (тот же холст). `state_shelf_table.png` — полка B: рисунок ChatGPT `assets/incoming/H1_state_shelf_table.png`, масштабом по глубине перенесён с чела печи на заднюю стену у двери на крыльцо, тень — кодом; `state_holes_table.png` — гнёзда под неё (Pillow). Всё строит `tools/make_h1_layers.py` (оригиналы не меняются; `--check` сверяет копии). Права — как у исходного арта ChatGPT.

## 2026-10-17 (ночь) — пакет ChatGPT по брифу v3
- ChatGPT imagegen по `Docs/BRIEF_CHATGPT_v3.md` (коммит f3bc29d) и эталонам `assets/reference/`. Файлы в `assets/incoming/`: Z4 (фон, забор, слои качания), мельница M1 (фон, колесо отдельно, мешки), M2 (фон и полный фон без зеркала), M3 (фон, край стола), M4 (фон, рычаг в двух положениях), Тихон (собранный, голова, хвост — запасной вариант брифа). Размеры, хеши, ограничения и промпты — `assets/incoming/_meta_v3/`.
- Тексты: `ru_bag.json` (8 описаний предметов + 2 подписи), `ru_E0_E1.json` (7 строк переулка) — правки ChatGPT, `draft` сняты.

## 2026-10-17/18 — озвучка реплик E0–E1 (ElevenLabs Text to Speech)
- Источник: ElevenLabs API `POST /v1/text-to-speech/{voice_id}`, модель `eleven_v4`, `output_format=mp3_44100_128`, `language_code=ru`, seed от id реплики; голоса из раздела My Voices Директора (Voice Design, category `generated`): Agata `ReYqW64ePwZHQReEArbt`, TAMARA-1 `GqJPI8zhNM5CF7q8EJ6l`, PELAGEYA `mIbPOSXtLeiaroofXc7O`, CAT-2 `RRgQuGjVvCeyNderlonu` (`pipeline/voice/voices.json`, `pipeline/voice/cast.json`). Запуск — GitHub Actions `pipeline-voice`, прогоны 39072575687 (19 реплик, 274 кредита) и 39074220670 (14 реплик с тегами подачи, 280 кредитов); request-id каждой реплики — в `assets/voice/ru/manifest.json` → `api`.
- Текст — обязательные реплики сцен M01–M08 и Q04 (`data/story/scenes/E0.json`, `E1.json`, `quests.json`), теги подачи — поля `tags`/`voice_text` по `Docs/VOICE_DIRECTION.md`. Ответы API как есть — `assets/voice/ru/src/*.mp3`; в игру идут обработанные OGG (срез тишины, −17 LUFS, ограничитель −2 dBFS) — `game/assets/voice/ru/` через `tools/sync_voice.sh`.
- Права: коммерческое использование — по условиям плана Директора на момент генерации (план Creator, 17.10); сверить перед релизом.
- **Закадровый голос (18.10):** голос «ZAKADR» `kPaCtwsoLpkcqnqv9PyA` (My Voices, Voice Design, `generated`, создан 17.10 22:56 UTC), та же модель и обработка; stability 0,65 / similarity 0,75. Текст — 90 фраз E0–E1 из `data/story/text/ru_E0_E1.json` (82) и `ru_bag.json` (8), ключи по правилам `data/story/voice.json` → `narration`; прогон 39078036562 — 5 372 символа, 2 362 кредита (character-cost; счётчик подписки +2 355). Файлы — `assets/voice/ru/narrator/<ключ>.ogg`, ответы API — `assets/voice/ru/src/narrator/`.

