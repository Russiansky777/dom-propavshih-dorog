# Техническая проба M0 — отчёт

Дата: 2026-10-17. Среда: Linux-контейнер без GPU и без дисплея (root), Python 3.13 (Pillow 12.3.0), Node v22.22.0 / npm 10.9.4, Chromium 141.0.7390.37 из `/opt/pw-browsers/chromium-1194`.

Всё, что ниже, запускалось и проверялось в этой сессии. Чего не проверял — отмечено отдельно в разделе «Ограничения».

## 1. Итог в двух строках

- Пройдено: headless-тесты (10/10 PASS), веб-экспорт и Linux-экспорт собираются, Linux-сборка запускается headless без ошибок, веб-сборка открывается в headless Chromium (SwiftShader) и проходит сценарий из 9 кликов с проверкой состояния игры после каждого шага; 9 скриншотов + чистый `console.log`.
- Не пройдено / не делалось: ничего из обязательного списка не провалилось. Не проверено на реальном GPU и в реальном браузере с клавиатурой человека (см. §8).

## 2. Инструменты и версии

| Что | Версия / значение | SHA256 |
| --- | --- | --- |
| Godot (редактор, headless) | `4.7.2.stable.official.ed1daf0bf` — `/home/claude/tools-cache/Godot_v4.7.2-stable_linux.x86_64` (77 860 424 байт в zip) | `cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4` (`Godot_v4.7.2-stable_linux.x86_64.zip`) |
| Шаблоны экспорта | `Godot_v4.7.2-stable_export_templates.tpz`, 1 281 349 702 байт; `templates/version.txt` = `4.7.2.stable` | `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011` |
| Куда распакованы шаблоны | `~/.local/share/godot/export_templates/4.7.2.stable/` — только `web_*.zip` и `linux_*` (остальные платформы не распаковывал, экономия диска) | — |
| Playwright | `1.56.1` (закреплён точно в `tools/package.json`), браузер — предустановленный `chromium-1194` (`playwright install` не запускался) | — |
| WebGL в headless Chromium | `WebGL 2.0 (OpenGL ES 3.0 Chromium)`, рендерер `ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)))` — флаги `--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist` | — |

Команды загрузки:

```
curl -L --max-time 600 -o Godot_v4.7.2-stable_linux.x86_64.zip https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
curl -L -C - --max-time 900 --retry 2 -o Godot_v4.7.2-stable_export_templates.tpz https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip -o Godot_v4.7.2-stable_export_templates.tpz "templates/version.txt" "templates/web_*" "templates/linux_*" -d tpz_extract
cp tpz_extract/templates/* ~/.local/share/godot/export_templates/4.7.2.stable/
```

Оба файла скачались с первого раза (шаблоны — 47 с).

## 3. Что построено (`game/`)

Это не выбрасываемый прототип, а каркас, на котором будет строиться игра: содержимое комнат описано в сценах и экспортируемых полях, а не в if-ветках.

```
game/
  project.godot            1920x1080, stretch canvas_items/keep, рендерер gl_compatibility,
                           автозагрузки GameState и RoomManager, действия quick_save (F5) / quick_load (F9)
  export_presets.cfg       пресеты "Web" (threads выключены) и "Linux" (x86_64)
  scenes/Main.tscn         World (комната + Player) + Hud
  scenes/actors/Player.tscn, Echo.tscn
  scenes/rooms/RoomHouse.tscn, RoomOffice.tscn, RoomOfficeView.tscn
  scenes/ui/Hud.tscn
  scripts/core/game_state.gd      флаги, инвентарь, current_room, player_pos, save/load JSON (version=1)
  scripts/core/room_manager.gd    change_room(room_id, spawn_id), автосейв в слот "auto", save_game/load_game/new_game
  scripts/rooms/room.gd           class_name Room: Background/Walkable/Hotspots/Exits/Spawns/Occluders,
                                  depth_top_y/depth_bottom_y/scale_top/scale_bottom, flag_visibility, apply_flags(), pick()
  scripts/rooms/hotspot.gd        class_name Hotspot (Area2D): hotspot_id, sets_flag, hint, hint_flag/hint_when_flag, StandPoint, signal interact
  scripts/rooms/room_exit.gd      class_name RoomExit (Area2D): target_room, target_spawn, requires_flag, StandPoint
  scripts/rooms/mirror.gd         SubViewport 480x320 с RoomOfficeView → ViewportTexture на Sprite2D "Glass"
  scripts/actors/player.gd        class_name Player: клик-ходьба через NavigationAgent2D, 260 px/s, масштаб и z_index по y,
                                  двухкадровый шаг от пройденного расстояния, walk_to_and_interact(узел)
  scripts/actors/echo.gd          Эхо: y-сортировка; анимация "loop" в Echo.tscn (AnimationPlayer, 4 с, туда-обратно)
  scripts/ui/hud.gd               имя комнаты, флаги, Save (F5) / Load (F9) / New game, строка подсказки
  scripts/main.gd                 связывает RoomManager с миром, стартует новую игру, на web публикует window.probeReady/probeState
  shaders/mirror_glass.gdshader   холодная тонировка + UV-колебание, пока флаг mirror_mounted = false
  tests/run_tests.gd              headless-раннер (extends SceneTree)
  assets/placeholders/*.png       10 заглушек, 44 КБ суммарно, генерируются tools/make_placeholders.py (Pillow)
```

Состояние — данные:
- флаги со смысловыми именами: `mirror_mounted`, `office_latch_open`;
- какая нода видна при каком флаге — экспортируемый словарь `flag_visibility` на комнате (`"Hotspots/Door/DoorOpen": "office_latch_open"`, `"…/DoorClosed": "!office_latch_open"`); `apply_flags()` вызывается при входе в комнату и по сигналу `GameState.flag_changed`;
- что делает хотспот — его экспортируемые поля (`sets_flag`, `hint`, `hint_when_flag`), не код.

Комнаты:
- `RoomHouse` (тёплая): зеркало `Mirror` (живой вид `RoomOfficeView` через SubViewport), хотспот `mirror_frame` → `mirror_mounted` (колебание стекла останавливается), дверь `office_door` с двумя визуальными состояниями по `office_latch_open`, стол-окклюдер `Occluders/Table` (z_index = 1000 = y его ножек; игрок при y < 1000 рисуется позади), выход направо в `RoomOffice`, спауны `start`, `from_office`.
- `RoomOffice` (холодная): `Echo` (AnimationPlayer, петля 4 с), хотспот `office_latch` → `office_latch_open` (два спрайта щеколды), выход налево в `RoomHouse`, спаун `from_house`.
- `RoomOfficeView`: облегчённая копия кабинета без игрока и без Walkable: фон, щеколда (та же привязка к флагу — в зеркале видно, что щеколда откинута), `Echo`.

Сохранение: `user://saves/<slot>.json` вида `{"version":1,"saved_at":…,"flags":{…},"inventory":[…],"current_room":"RoomHouse","player_pos":{"x":…,"y":…}}`. Слоты: `auto` (после каждой смены комнаты), `quick` (F5/F9). `load_game` отключает автосейв на время перестройки сцены, чтобы не затереть слот самим собой.

## 4. Headless-тесты — `tools/run_tests.sh`

```
tools/run_tests.sh
# внутри: godot --headless --path game --import   (один раз: импорт PNG + кэш классов)
#         godot --headless --path game -s res://tests/run_tests.gd
```

Вывод (`build/logs/tests.log`):

```
PASS  GameState save → modify → load restores flags/inventory/room  (0 ms)
PASS  RoomManager.change_room loads RoomOffice and places player at spawn  (12 ms)
PASS  RoomManager autosaves to slot after room change  (9 ms)
PASS  Room.apply_flags toggles door state nodes on office_latch_open  (3 ms)
        nav map ready after 5 physics frames (iteration 3)
PASS  NavigationServer2D returns a path inside RoomHouse.Walkable  (73 ms)
PASS  Room.pick finds hotspot/exit under a point  (35 ms)
PASS  Mirror shows RoomOfficeView through a ViewportTexture with Echo looping  (303 ms)
PASS  Player walks to the exit and RoomManager switches rooms  (1120 ms)
PASS  Save/load round-trip survives room change and restores player position  (14 ms)
PASS  InputMap: F5 → quick_save, F9 → quick_load  (1 ms)

==== 10 tests, 10 passed, 0 failed ====
[godot] tests exit code: 0
```

Четыре обязательных теста (a)–(d) — это первые пять строк; остальные добавлены по правилу «каждый найденный дефект превращается в автопроверку» (см. §7). Тест ходьбы дополнительно проверяет, что игрок шёл по навигационному пути, а не по аварийной прямой, что `z_index == int(y)` и что масштаб равен `Room.depth_scale(y)`.

## 5. Экспорт — `tools/export_web.sh`, `tools/export_linux.sh`

```
godot --headless --path game --import
godot --headless --path game --export-release Web   ../build/web/index.html
godot --headless --path game --export-release Linux ../build/linux/game.x86_64
```

| Сборка | Файлы | Размер |
| --- | --- | --- |
| Web (`build/web/`) | `index.wasm` 39 514 754 Б, `index.js` 279 815 Б, `index.pck` 57 960 Б, `index.html` 5 450 Б, worklets и иконки | 39 МБ |
| Linux (`build/linux/`) | `game.x86_64` 73 519 416 Б, `game.pck` 57 960 Б | 71 МБ |

Веб-шаблон — `web_nothreads_release` (`variant/thread_support=false`); в консоли браузера Godot сам пишет `Build configuration: Emscripten 4.0.20, single-threaded, no GDExtension support.` Linux-сборка проверена запуском `./game.x86_64 --headless --quit-after 120` — код 0, ошибок нет, автосейв `auto.json` записан (`build/logs/linux_run.log`).

## 6. Скриншоты — `node tools/screenshots.mjs`

Скрипт поднимает статический сервер на `127.0.0.1:8765`, открывает `index.html` в headless Chromium 1920x1080 (координаты клика = координаты игры 1:1), ждёт `window.probeReady === true` (ставится из `main.gd` через `JavaScriptBridge.eval` после загрузки первой комнаты; заняло 1,7–2,8 с под SwiftShader), затем кликает по реальному холсту и после каждого шага ждёт не фиксированную паузу, а конкретное состояние в `window.probeState` (комната, флаги, `player.walking`, `last_hint`).

| Файл | Шаг | Чем подтверждено |
| --- | --- | --- |
| `build/shots/01_house.png` | старт в `RoomHouse` | зеркало с колебанием, Эхо видно в зеркале, дверь закрыта, стол, стрелка выхода |
| `02_walk_front_of_table.png` | клик по полу (1100, 980) | игрок дошёл, `walking=false`; стоит перед столом, рисуется поверх |
| `03_walk_behind_table.png` | клик (900, 860) | игрок позади стола — ноги скрыты столешницей (окклюдер), разворот влево (маркер «лица» слева) |
| `04_mirror_mounted.png` | клик по раме зеркала (560, 330) | `flags.mirror_mounted=true`, линии в зеркале прямые (колебание выключено), подсказка внизу, игрок у стены мельче (масштаб по глубине) |
| `05_office.png` | клик по выходу (1860, 850) | `room == "RoomOffice"`, холодная комната, Эхо на полу |
| `06_latch_open.png` | клик по щеколде (300, 420) | `flags.office_latch_open=true`, спрайт щеколды сменился, подсказка |
| `07_back_home.png` | клик по выходу (60, 850) | `room == "RoomHouse"`, дверь в открытом состоянии, в зеркале щеколда откинута |
| `08_new_game.png` | F5, затем кнопка «New game» (222, 86) | флаги пусты, игрок на спауне `start`, зеркало снова колеблется |
| `09_after_f9_load.png` | F9 | флаги вернулись, игрок на позиции из сейва (1720, 900), подсказка «Загружено (слот 'quick')» |

`build/shots/console.log` — 24 строки, 0 ошибок, 0 `pageerror`, 0 предупреждений WebGL (после исправления из §7.3). Полный прогон ~35 с. Завершение с кодом 0 только если каждый шаг дошёл до ожидаемого состояния.

Вариант `--use-gl=swiftshader` не пробовал — не понадобился, ANGLE+SwiftShader заработал сразу.

## 7. Что сломалось по дороге и как исправлено

1. **Скрипт `-s` не видит автозагрузки по имени.** `godot -s res://tests/run_tests.gd` компилирует скрипт до регистрации синглтонов: `GameState` → `Identifier not found`. В тестах автозагрузки берутся через `root.get_node("GameState")`; сами сцены игры компилируются позже и видят их как обычно.
2. **NavigationServer2D в 4.7.2: свежий регион становится проходимым только после второй синхронизации карты** (замерено: 5 физических кадров, `map_get_iteration_id` = 3). После первой итерации `map_get_path` возвращает пустой путь, `map_force_update` не помогает. Тест (d) опрашивает путь до 60 кадров и печатает фактическую задержку; `player.gd` при пустом пути перезапрашивает его до 30 кадров и только потом идёт по прямой (тест проверяет, что прямая не понадобилась).
3. **Переключение `visible` у Polygon2D на каждом шаге давало 202 предупреждения `WebGL: INVALID_OPERATION: bindBuffer / bufferSubData` за прогон** (видимость → перерисовка полигона → пересоздание буферов). Кадры шага теперь переключаются через `self_modulate.a`; предупреждений 0.
4. **Коды клавиш.** В 4.7 `KEY_F5 = 4194336`, `KEY_F9 = 4194340`; первая версия `project.godot` указывала на F1/F5. Поймано прогоном в браузере, закреплено тестом `InputMap`.
5. **`priority` — встроенное свойство Area2D**, экспорт с таким именем не компилируется → переименовано в `pick_priority`.
6. **Сообщения HUD должны идти через `GameState.show_hint`**, иначе их не видит ни проба, ни будущие тесты. Исправлено.
7. **Смена комнаты из обработчика ввода** (кнопка Load / New game, F9) — перестройка сцены вызывается через `call_deferred`, выход из комнаты тоже (`RoomExit.trigger` вызывается из физического шага игрока).

Проверено заодно: клавиша F5 в Chromium не перезагружает страницу — холст Godot её перехватывает (состояние `probeState` пережило нажатие, сейв записался). В Firefox/Safari не проверял.

## 8. Ограничения и что не проверено

- Рендер только через SwiftShader: картинка верная, но FPS не показателен; на реальном GPU/в реальном браузере сборку не открывал.
- `user://` на web — IndexedDB: сейв/лоад подтверждены внутри одной сессии страницы; сохранность после перезагрузки вкладки не проверялась.
- Walkable — выпуклый четырёхугольник, заданный вершинами в `.tscn`; стол не вырезан из проходимой зоны (игрок ходит «сквозь» ножки — для пробы допустимо).
- Эхо в кабинете и Эхо в зеркале — две независимые копии одной анимации, стартуют при создании сцен, поэтому не синхронны между собой.
- `data/story/` к комнатам ещё не подключён: хотспоты описаны полями в сценах, не в JSON.
- Папка `build/` в `.gitignore`: доказательства (скриншоты, логи) лежат локально, в репозиторий не попадают.

## 9. Воспроизведение

```
python3 tools/make_placeholders.py     # заглушки (уже в репозитории)
tools/run_tests.sh                     # код 0
tools/export_web.sh                    # build/web/
tools/export_linux.sh                  # build/linux/
(cd tools && npm install)              # playwright 1.56.1, браузер не качает
PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node tools/screenshots.mjs   # build/shots/, код 0
```

Путь к Godot берётся из `GODOT=`, иначе из `~/tools-cache/` или `PATH` (`tools/godot_env.sh`).

## 10. Следующий шаг

1. Директор открывает `build/web/index.html` через любой статический сервер (или собранную сборку на itch.io) и проходит те же 9 шагов руками — это приёмка M0.
2. После приёмки: читать комнаты/хотспоты/подсказки из `data/story/*.json` (сейчас это поля в `.tscn`), прогонять `tools/validate_story.py` в `run_tests.sh`.
3. Подготовить `assets/manifest.json` для H1 и кабинета (фон, стол, дверь, зеркало, Агата) — заменять заглушки без правки сцен.
4. Перевести тесты на GdUnit4 только если появится нужда в фикстурах; текущий раннер (`extends SceneTree`) покрывает M0.
