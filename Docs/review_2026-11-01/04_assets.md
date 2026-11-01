# Ревью ассетов, звука и документации (агент, 01.11; скрипты и json-выводы в /home/claude/work/review_assets/)

| № | Важность | Где | Что не так | Как чинить |
|---|---|---|---|---|
| 1 | важно | game/assets/characters/{ilya,ilya_wife,mitya,nina,pavel,pelageya,ulyana,tamara_v3}/idle.png, talk.png | 109,7 МБ листов v1 (Meshy 23.10): на них ссылаются только их же sprites.json; все game/data/actors/*.json → `*_v2` + rt3d/*.glb. Ни один пресет export_presets.cfg их не исключает → едут в веб-сборку (предел 1 ГБ, сайт 939 МБ) и в exe | Удалить из game/assets (исходники остаются в assets/characters) или exclude_filter всех пресетов |
| 2 | важно | game/assets/voice/ru_takes/ (333 ogg + manifest, 30 МБ, 667 файлов в git) | Дубли для страницы прослушивания; игра их не читает, но tools/sync_voice.sh копирует любой assets/voice/*/ с manifest.json → в каждой сборке | В sync_voice.sh пропускать ru_takes, удалить копию из game/, exclude_filter |
| 3 | важно | tools/validate_actor_actions.py (шаг run_tests.sh) | На чистом HEAD: `FAIL слой кадра не совпадает: game/assets/rooms/EP_dinner/agata.png`, exit 1; `make_frame_layers.py --check`: DIFF ещё и F_span_done/agata.png | Перегенерировать слои (tools/make_frame_layers.py) и закоммитить, либо чинить сверку |
| 4 | важно | Docs/ASSET_PROVENANCE.md | Последние записи — 23.10. Нет записей: партии 10а–10д, 11, листы жителей v2, живые модели rt3d (9 GLB, 112 МБ), nina_mirror, рот Тихона, trailer/house_*.png, puzzle/M05/wall_behind.png | Дописать по _meta_* README (источник, дата, права), для Meshy — прогон/коммит |
| 5 | важно | assets/manifest.json | 18 заявок «requested», у которых файлы давно в игре (партия 10б и др.) | Проставить delivered/imported |
| 6 | мелочь | game/assets/rooms/S1/ (6,4 МБ); characters/agata/rt3d/agata_rt.glb + jpg (7,2 МБ); rooms/H1 8 слоёв без layer (1,5 МБ); M1/drips_1-3, O1/state_sign, R1/far_lights, O4/state_mitya_board, EP_beam/cut_dunya | Мусор в сборке ≈ 155 МБ вместе с п. 1–2 | Удалить; import_room_art копировать только файлы с layer |
| 7 | мелочь | game/assets/sfx/amb_stove_fire.ogg | Ступень ≈ 5 дБ на стыке петли каждые 18,5 с | Перерезать с кроссфейдом |
| 8 | мелочь | rooms/O1: bg 1672×940, слои 941; H3/state_door_installed.png 1671×941 | Сдвиг ≤ 1 px | Дополнять холст при импорте |
| 9 | мелочь | voice_pending.json; manifest | 5 id с записью всё ещё в pending (K6 adopt); Q05/Q10 в манифесте, Q10_1 без голоса | Почистить pending; решить Q05/Q10 |
| 10 | мелочь | game/**/*.gd.uid | 34 .uid не в git (info/exclude), 187 в git | Закоммитить .uid |
| 11 | мелочь | CLAUDE.md, AGENTS.md, TEST_PLAN.md, MILESTONES.md, CURRENT_STATE.md | «itch.io» vs «не выкладываем (23.10)»; AGENTS устарел; TEST_PLAN 28 строк не перечисляет 41 набор; MILESTONES без дат; CURRENT_STATE 647 строк упоминает удалённые файлы | Обновить; CURRENT_STATE — архив истории |
| 12 | мелочь | game/assets/voice/ru/manifest.json (1,4 МБ) | per-line api.request_id, history_item_id, voice_id, стоимость — лишнее в игре | Обрезать при sync_voice |
| 13 | мелочь | озвучка | 25 записей > 3 LU от медианы персонажа, M12_0 +4,8 | По списку перезаписи |

## Проверено и чисто
Ссылки: 1190 res:// из данных + 50 из кода — 0 отсутствующих. game/assets: 1643 файла, 2197 МБ. Слои комнат RGBA, паразитная альфа невидима; 43 текстуры > 4096 — только ПК-листы, веб их исключает. Озвучка: 804 ожидаемых строк, 807 в манифесте, 0 без записи вне pending, 0 устаревших, Vorbis 44,1 кГц моно, ±3 LU от −17 LUFS. SFX/музыка 48 кГц; шрифты OFL с SHA-256; секретов в дереве и 200 коммитах нет. Валидаторы — код 0, кроме validate_actor_actions (п. 3).
