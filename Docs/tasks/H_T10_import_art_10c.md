# T10: вставить арт партии 10в в игру

Арт от ChatGPT уже в `assets/incoming/`, README и превью — в `assets/incoming/_meta_p10c/` (README.txt, manifest.json, previews/). Заказ, по которому рисовали, — `Docs/art_pack_10c/00_ТЕКСТ_для_ChatGPT.txt`. Прочитай также отчёт T8 `Docs/agent_reports/run_40111723963.md` (что сейчас временно).

## Вставить, заменив временное и старое
- **Лодка у поворота.** `Z3_state_boat_dusk.png`, `Z3_state_boat_day.png` вместо временной лодки T8 (`tools/make_boat_layers.py`). Анимация M17 (`layer_go`) — с новым слоем.
- **Причал без лодки.** `R1_state_no_boat_dusk.png`, `R1_state_no_boat_day.png` вместо временных заплаток воды.
- **Зеркало конторы.** `H2_state_office_mirror_center_v3.png` вместо `…center_v2`; клинья `H2_state_wedges_loose/half/driven_v3.png` — под новое зеркало и стойку.
- **Почта.** Прилавок `Z1_fg_counter_v2.png`. Хотспоты и позиции Тамары и Агаты у прилавка — по новому габариту.
- **Дощечка Мити.** `O4_state_mitya_board_fence_v2.png`; крупный план — если в README есть.
- **Снимок школы.** `H3_state_photo_school.png` — если он лучше нынешнего кода из T8 (`tools/make_school_photo.py`); иначе оставить код и записать в отчёт почему.
- **Мост эпилога (замечание Директора I1 — снег без узора, мост без клонов).** `ep_tamara_bridge.png` — фон EP_tamara. `EP_beam_bg.png` — фон EP_beam: торец бревна на месте, надписи на нём проверь.

Каждый слой: проверь посадку на основу (наложение, шов, ореол, масштаб по перспективе). Если файл с дефектом — не вставляй, опиши в отчёте и сделай заявку на исправление.

В `assets/manifest.json` у записей batch10c — статус «imported».

## Готово, когда
- validate_story, validate_rooms и tools/run_tests.sh — код 0.
- Веб-кадры каждого места: Z3 сумерки и день с лодкой, M17, R1 без лодки, H2 зеркало и клинья, Z1, O4, H3, EP_tamara, EP_beam — в `Docs/evidence/H/T10_*.jpg`.
- Раздел T10 в Docs/ACCEPTANCE_H.md.
- Короткий отчёт.

Коммиты [skip ci], без лишних сводок.
