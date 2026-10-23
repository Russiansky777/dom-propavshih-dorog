#!/usr/bin/env bash
# Tests, three levels (exit code 0 == all PASS):
#   1. python3 tools/validate_story.py   — story data integrity
#      python3 tools/validate_rooms.py   — rooms JSON vs story (test (a) of M1)
#   2. godot --headless -s res://tests/run_tests.gd — GameState/RoomManager/navigation, bot walkthrough
#      godot --headless -s res://tests/test_room_geometry.gd — floor vs art in every room (samples)
# Output is also written to build/logs/tests.log
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/godot_env.sh"

mkdir -p "$BUILD_DIR/logs"
: > "$BUILD_DIR/logs/tests.log"
code=0

echo "[data] validate_story.py" | tee -a "$BUILD_DIR/logs/tests.log"
python3 -I "$ROOT/tools/validate_story.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1
echo "[data] validate_rooms.py" | tee -a "$BUILD_DIR/logs/tests.log"
python3 -I "$ROOT/tools/validate_rooms.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1
python3 -I "$ROOT/tools/validate_ambient.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # живой мир: data/story/ambient
python3 -I "$ROOT/tools/validate_lights.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # свет комнат: data/story/lights
python3 -I "$ROOT/tools/validate_time.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # время суток: data/story/time — сцены по порядку, без хода назад (F17)

"$ROOT/tools/sync_story_data.sh" | tee -a "$BUILD_DIR/logs/tests.log"
"$ROOT/tools/sync_music.sh" | tee -a "$BUILD_DIR/logs/tests.log"  # музыка: assets/music → game/assets/music (импорт loop=false)
"$ROOT/tools/sync_voice.sh" | tee -a "$BUILD_DIR/logs/tests.log"  # голос: assets/voice/ru → game/assets/voice/ru (импорт loop=false)
python3 -I "$ROOT/tools/validate_music.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # музыка: data/story/music.json
python3 -I "$ROOT/tools/validate_sfx.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # звуки: data/story/sfx.json, громкость относительно музыки
python3 -I "$ROOT/tools/validate_voice.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # голос: манифест ↔ сцены (sha1), cast.json, громкость, копия игры
godot_import

echo "[godot] tests: $GODOT --headless --path $GAME_DIR -s res://tests/run_tests.gd"
set +e
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/run_tests.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log"
gcode=${PIPESTATUS[0]}
set -e
[[ "$gcode" -ne 0 ]] && code=1
echo "[godot] tests exit code: $gcode"

# Room geometry against the art: obstacles/water not walkable, floor connected (data: *_samples).
echo "[godot] geometry: $GODOT --headless --path $GAME_DIR -s res://tests/test_room_geometry.gd" | tee -a "$BUILD_DIR/logs/tests.log"
set +e
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_room_geometry.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log"
geo_code=${PIPESTATUS[0]}
set -e
[[ "$geo_code" -ne 0 ]] && code=1
echo "[godot] geometry exit code: $geo_code"
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_lighting.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # свет, огонь, тени актёров
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_ambient.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # живой мир: дождь, ветер, вода, следы
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_world.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # мир 23.10: доска распорядка M1 крупно мышью (F19), вид в зимний класс из открытой двери (F18)
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_time_of_day.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # время суток (F17): сцены по порядку, флаги tod_*, оттенок и окна комнат, журнал
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_music.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # музыка: темы комнат, кроссфейд, цикл, события, приглушение, громкость
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_sfx.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # звуки: шаги на кадрах постановки ноги, двери, огонь, дождь, сумка, громкость
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_closeups.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # крупные планы H3 только мышью: дверь (три петли перетаскиванием, брус, ручка), сохранение посреди загадки, зеркало с отражением и снимком
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_voice.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # голос: реплика с файлом звучит, клик обрывает, без файла — субтитры, громкость, Тихон с панорамой
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_ui_bag.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # сумка: кармашки, иконки, наведение, выбор, «влёт», листание
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_ui_map.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # план Заречья: наезд, «Вы здесь», посещённые, журнал
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_h1.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # H1: клик по печи, Тихон в кресле с начала → на полке, гнёзда полки, M03 один раз
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_exit_cues.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # подсказки выходов: метки у края кадра, обычный курсор над выходом, Пробел — все хотспоты
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_ui_cursors.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # интерфейс 18.10: старорусские курсоры, значок места у подписи выхода, крупная «Подсказка» с советом про Пробел, вывеска «ПОЧТА» в Z4
"$GODOT" --headless --path "$GAME_DIR" -s res://tests/test_items.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # предметы и выборы: ключ на дверь (расход, открыто и после загрузки), фото/чашки меняют кадр, мел на парте, пометка V03
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_day_one.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # день первый по финальному сценарию: ящик (три вещи один раз), скоба после плана, ночь у печи (один раз, «День второй», загрузки), показанная попытка на причале, доска, варежка, «Там зима», Тихон по вопросам
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_day2.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # день второй (блок 2): крюк без наказания, затвор не разом, свет в зеркале в кадр удара, мамино зеркало ровно 20:1, лента один раз, скоба один раз, сохранение посреди дня, весь день ботом от ночи у печи до дальней опоры
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_mechanics.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # общие механики 23.10 (F4–F9): «точный удар», «протянуть узел», «Рассмотреть» у каждого предмета сумки, мамино зеркало — ходики 20× крупно и карманные часы из сумки
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_saves.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # сохранения партии G: слот «День второй · Мастерская · вечер» (G4), автосохранение раз в 5 минут и при входе в день, не посреди реплики/постановки/крупного плана, загрузка ничего не повторяет (G5)
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_day3.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # блоки 3–5: Ольховка, горница Нины, свободный ход, ворот первого пролёта (сигналы, удар без наказания), эпилог кадрами и финальный кадр, точки старта, сохранение на каждой точке, следы выборов, дела жителей
"$GODOT" --headless --audio-driver Dummy --fixed-fps 60 --path "$GAME_DIR" -s res://tests/test_agata_3d.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # Агата в 3D (render "3d"): любой угол поворота без скачков, стопа на полу ≤ 1 см, idle без рывков, старт/стоп, действия, отрисовка
# CI: every failure becomes an annotation (title, test, its messages) — the checks API shows annotations without the
# job log, whose download host agents cannot reach (22.10: two red runs with no way to read why).
if [[ -n "${GITHUB_ACTIONS:-}" && "$code" -ne 0 ]]; then
  { awk '/^FAIL /{if(m)print m; m=$0; next} m && /^ +- /{m=m"%0A"$0; next} {if(m){print m; m=""}} END{if(m)print m}' "$BUILD_DIR/logs/tests.log"
    grep -E "^ERROR |^ERROR: [^0-9]|ОШИБКА|SCRIPT ERROR|Parse Error" "$BUILD_DIR/logs/tests.log" | grep -vE "resources still in use|ObjectDB"
  } | head -10 | while IFS= read -r l; do echo "::error title=tests::${l}"; done || true
fi
echo "[tests] overall exit code: $code"
exit "$code"
