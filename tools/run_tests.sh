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
python3 -I "$ROOT/tools/validate_actor_actions.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # G1/G53: действия Агаты короткие, из стойки в стойку, без размаха рук; сидячая поза в кадре ужина
python3 -I "$ROOT/tools/test_web_sheets.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # I-T4b: веб-копии листов k× (доля, поля, без смешения кусков), пресеты: веб — web_atlas без полных листов, ПК — 2,25×

"$ROOT/tools/sync_story_data.sh" | tee -a "$BUILD_DIR/logs/tests.log"
"$ROOT/tools/sync_music.sh" | tee -a "$BUILD_DIR/logs/tests.log"  # музыка: assets/music → game/assets/music (импорт loop=false)
"$ROOT/tools/sync_voice.sh" | tee -a "$BUILD_DIR/logs/tests.log"  # голос: assets/voice/ru → game/assets/voice/ru (импорт loop=false)
python3 -I "$ROOT/tools/validate_music.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # музыка: data/story/music.json
python3 -I "$ROOT/tools/validate_sfx.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # звуки: data/story/sfx.json, громкость относительно музыки
python3 -I "$ROOT/tools/validate_voice.py" --quiet 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # голос: манифест ↔ сцены (sha1), cast.json, громкость, копия игры
python3 -I "$ROOT/tools/voice_after_h59.py" --check 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || echo "[voice] список перезаписи после H59 устарел — python3 tools/voice_after_h59.py (предупреждение)" | tee -a "$BUILD_DIR/logs/tests.log"  # H5/H44/G57: строки, ждущие финальной записи после H59
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
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_menus.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # главное меню и пауза (23.10): титул при запуске (тесты и ?start — без него), пункты, Esc — пауза над размытой игрой, порядок Esc (крупный план → панель → пауза), «В главное меню» → «Продолжить»
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_day3.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # блоки 3–5: Ольховка, горница Нины, свободный ход, ворот первого пролёта (сигналы, удар без наказания), эпилог кадрами и финальный кадр, точки старта, сохранение на каждой точке, следы выборов, дела жителей
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_q02_q06.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # H47/H48: Q02 — дорога Ульяны по карте кликами по порядку (верные раскрашиваются, ошибка — заново), Q06 — верстак перетаскиванием на подсвеченные места и винт по кругу; оба выбора каждой истории до конца, сохранение посередине
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_g.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия G (замечания Директора 23.10): где канат (G17/G28), лодка назад (G38), Нина уходит в дом (G29), горница (G30/G40), ворот без «Закрыть» (G47), рукописный шрифт и зарубки (G31–G33)
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_h.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия H, T1 (замечания Директора 24.10): одно имя тёти (H1), тексты H3/H22/H23/H51, Тихон после зеркала (H33), доска вовремя (H42), Ульяна (H43), Дунино пальто (H49/H50), финал и титры (H55/H56)
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_h_t2.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия H, T2: кровать — конец дня, окна по времени (H17), язык в сундуке на чердаке (G44), платок над полкой и выбор Тихону (H12/H13), постановка (H15/H24/H28/H29/H36/H37/H39)
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_h_t6.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия H, T6: сон по дням (лежанка у печи, кровать у Нины; кровать на чердаке — Дунина), надпись «День …» один раз на переход, загрузка её не повторяет
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_agata_scale_carry.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # G56: рост Агаты на экране в каждой комнате тот же при листе k× (texture_scale); G10: платок — к лежанке, pick, к вешалке, reach, крючок; клик посреди — тот же итог
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_gloss.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # H59/T7: подсказки к старым словам — каждое [[слово|значение]] в glossary.json, золотое слово с пунктиром, значение при наведении мышью, клик по тексту листает
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_h_t8.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия H, T8: лодка у поворота после скобы (M15s), M17 и «В лодку» оттуда, причал без лодки — по флагам и после загрузки; дом Дуни после Пелагеи (M02); цели свободного дня — только несделанное
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_h_t9.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия H, T9 (вычитка ChatGPT R01–R51): дорога с узла M15 (петли нет, общее время, до переправы Агата сама не идёт), письма и дом сестры в обоих порядках, осмотры по состояниям, след Q06 при обоих фото, Пелагея у поворота и короткая переправа, чай в выбранном месте
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_i_t1.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия I, I-T1: хребет знаний Агаты (нет ранних реплик), Тихон доступен всегда и просит полку, темы по дням, крючок Q06 (журнал, цель, подсветка), подпись двери дома, ответ Тихону, друг, Ульяна
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_i_t2.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия I, I-T2: поворот Агаты 0,25–0,4 с через соседние строки, спокойная стойка, состояния жителей (стоит/слушает/говорит), подпись боковой двери, Тихон всегда, петли из сумки, подсветка Q06, пустое мамино зеркало, Пелагею обходят, голос ворота, мел на доске, стрелки D2
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_i_t5.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия I, I-T5: рисунок (шарф/лодка/мостик/ничего), свободный день a→b→c→d и c→d→a→b, {left}, новые темы Тихона однократно, M10/M26, скоба до/после воды, повтор маминого зеркала при общем времени, слова Директора
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_i_t3.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия I, I-T3: полный экран / окно (меню и F11, сохранение), слои 10г, объятия M18/M19, рот Тихона по голосу, стена за дверью M05, снимок с Агатой
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_batch_i_t6.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # партия I, I-T6: вычитка-3 — 124 строки по решению Директора (внесено / иначе / отклонено), слова Директора на местах, новые реплики в игре
# I-T6: заплатка «канат снят со стопора» R1 собрана с нынешнего кадра (I-T3 сменил дневной кадр R1, заплатка осталась старой); нужен opencv — без него пропуск
if python3 -c "import cv2" 2>/dev/null; then python3 "$ROOT/tools/make_rope_layers.py" --check 2>&1 | tee -a "$BUILD_DIR/logs/tests.log"; [[ "${PIPESTATUS[0]}" -ne 0 ]] && code=1; fi
"$GODOT" --headless --audio-driver Dummy --fixed-fps 60 --path "$GAME_DIR" -s res://tests/test_agata_3d.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # Агата в 3D (render "3d"): любой угол поворота без скачков, стопа на полу ≤ 1 см, idle без рывков, старт/стоп, действия, отрисовка
"$GODOT" --headless --audio-driver Dummy --path "$GAME_DIR" -s res://tests/test_trailer.gd 2>&1 | tee -a "$BUILD_DIR/logs/tests.log" || code=1  # TR1: режим съёмки трейлера (data/trailer) — планы читаются, планы собираются, комната в нужном состоянии, сохранения не пишутся
# CI: every failure becomes an annotation (title, test, its messages) — the checks API shows annotations without the
# job log, whose download host agents cannot reach (22.10: two red runs with no way to read why).
if [[ -n "${GITHUB_ACTIONS:-}" && "$code" -ne 0 ]]; then
  { awk '/^FAIL /{if(m)print m; m=$0; next} m && /^ +- /{m=m"%0A"$0; next} {if(m){print m; m=""}} END{if(m)print m}' "$BUILD_DIR/logs/tests.log"
    grep -E "^ERROR |^ERROR: [^0-9]|ОШИБКА|SCRIPT ERROR|Parse Error" "$BUILD_DIR/logs/tests.log" | grep -vE "resources still in use|ObjectDB"
  } | head -10 | while IFS= read -r l; do echo "::error title=tests::${l}"; done || true
fi
echo "[tests] overall exit code: $code"
exit "$code"
