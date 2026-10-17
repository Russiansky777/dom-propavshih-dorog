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
