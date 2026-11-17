# Steam: достижения (заготовка 12.11.2026; состав — Директор 17.11)

## В Steam — 8 (Директор 17.11)

«меньше 18 достижений, может до 10» → «может по окончанию дней и игры? плюс сад плюс рукав плюс письма мамы» →
«Старая карта, Рукав пальто, мамина лента в косе — поправить имена достижений». В игре — `game/data/steam.json`
(`skip` — 14 следов, что в Steam не идут; `extra` — дни и конец игры, на экране конца их нет); тест S16-3 сверяет
этот список с игрой. **Названия RU** — от Директора (5, 6, 8) и из названий сцен (1–4); **EN и описания — черновик**,
на утверждение. Скрытые (описание видно только после получения) — 7 и 8: не выдавать сюжет заранее.

| № | API-имя в Steam | Название RU | Название EN (черновик) | Описание RU (черновик) | Описание EN (черновик) | Скрытое | Когда выдаётся |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `ACH_DAY1` | День первый: ночь у печи | Day One: A Night by the Stove | Пройти первый день | Finish the first day | нет | `night_day1` (N01 «Ночь у печи») |
| 2 | `ACH_DAY2` | День второй: ночь в Ольховке | Day Two: A Night in Olkhovka | Пройти второй день | Finish the second day | нет | `morning_day3` (N02 «Ночь в Ольховке») |
| 3 | `ACH_DAY3` | День третий | Day Three | Пройти третий, свободный день | Finish the third, free day | нет | `day3_done` (M24 «Вечер третьего дня») |
| 4 | `ACH_FINALE` | Три недели спустя | Three Weeks Later | Пройти игру до конца | Finish the game | нет | `game_finished` (M26, эпилог) |
| 5 | `ACH_Q02` | Старая карта | The Old Map | Помочь Ульяне найти отцовский сад на старой карте Ольховки | Help Ulyana find her father's garden on the old map of Olkhovka | нет | `done_Q02` |
| 6 | `ACH_Q03` | Рукав пальто | The Coat Sleeve | Зашить рукав Дуниного пальто | Mend the sleeve of Dunya's coat | нет | `done_Q03` |
| 7 | `ACH_LETTERS` | Письма за двадцать зим | Letters from Twenty Winters | Прочитать мамины письма | Read Mama's letters | да | `nina_letters_read` |
| 8 | `ACH_RIBBON` | Мамина лента в косе | Mama's Ribbon in My Braid | Отдать маме её ленту | Give Mama her ribbon | да | `ribbon_braided` |

Лента (8): пустая лодка вечером второго дня (M17) приносит мамину ленту в сумку; в горнице, пока мама там (вечер второго
дня — утро третьего, до школы), выбрать ленту и щёлкнуть по маме → рассказчик (с голосом): «Мамина лента. Нина молча
вплетает её в Агатину косу — как бывало в праздник.» Анимации нет, на Агате лента не рисуется, лента остаётся в сумке;
повторный щелчок — Агата: «В косе лента. Как прежде.» Подсказки в дневнике нет — находка по догадке.

## Все 18 следов выборов (экран конца) — для справки

Основа — 18 «следов выборов», которые игра уже показывает на экране конца («Что осталось от выборов»): `data/story/achievements.json`.
В Steam достижения заводятся в App Admin (по умолчанию не больше 100; названия и иконки — для всех возрастов: https://partner.steamgames.com/doc/features/achievements), игра сообщает о них через GodotSteam.

**16.11 (Директор: «так надо чтобы и достижения и оверлей и сохранения»): в игре сделано.** `SteamService`
(`game/scripts/core/steam_service.gd`) выдаёт достижение в тот момент, когда его флаги сюжета выполнены, под API-именем
`ACH_<ID>` из первого столбца; список и имена — `game/data/steam.json` (`skip` — не выдавать в Steam, `names` — своё
имя). В Steamworks достижения заводятся **с теми же API-именами** (тест S16-3 сверяет этот столбец с игрой).

**Решения Директора (12.11; состав решён 17.11 — 8, таблица выше):** (1) брать ли все 18 или сократить (в наборе ChatGPT «Steam Narrator Kit v1» было 10 достижений, 2 скрытых, с иконками — `Docs/STEAM_KIT_PLAN.md`); (2) названия ниже — это подписи с экрана конца, для Steam их можно оставить или переименовать; (3) описания (вторая строка в Steam) — их пока нет; (4) иконки 256×256 — художнику.

| API-имя в Steam (id в игре) | Название RU (как в игре) | Название EN (как в игре) | Когда выдаётся (флаги сюжета) |
| --- | --- | --- | --- |
| `ACH_BOARD` (board) | Мама ответила на доске | Mama's reply on the blackboard | `nina_answered_board + один из: board_here, board_mama, board_ilya` |
| `ACH_MITTEN` (mitten) | Варежка нашлась на дороге домой | My mitten on the road home | `mitten_found_on_path` |
| `ACH_BIRD` (bird) | Синица на плакате: шапка, сапоги и мой рисунок | Poster bird: cap, boots and my drawing | `v03_marked` |
| `ACH_PROMISE` (promise) | Слово Павлу сдержано | My word to Pavel kept | `pavel_answer_promise` |
| `ACH_FAMILY` (family) | «Там моя матушка и брат» — Павел понял | "My mother and brother are there" — Pavel understood | `pavel_answer_family` |
| `ACH_TIKHON_NINA` (tikhon_nina) | Тихон зовёт маму хозяйкой | Tikhon calls Mama the mistress | `tikhon_told_nina` |
| `ACH_TIKHON_AGATA` (tikhon_agata) | Тихон спит у Агатиной лежанки | Tikhon sleeps by Agata's ledge | `tikhon_told_agata` |
| `ACH_BEAM` (beam) | Надпись на торце первого прогона | An inscription on the first beam | ` + один из: beam_dunya, beam_roads, beam_date` |
| `ACH_CUP` (cup) | Мама узнала свою чашку | Mama recognised her cup | ` + один из: v01_cup_blue, v01_cup_white` |
| `ACH_RIBBON` (ribbon) | Мамина лента снова в косе | Mama's ribbon in my braid again | `ribbon_braided` |
| `ACH_LETTERS` (letters) | Письма за двадцать зим | Letters from twenty winters | `nina_letters_read` |
| `ACH_Q01` (q01) | Аксинья получает письма брата | Aksinya gets her brother's letters | `done_Q01` |
| `ACH_Q02` (q02) | Сад Ильи — на старой карте | Ilya's garden on the old map | `done_Q02` |
| `ACH_Q03` (q03) | Рукав Дуниного пальто зашит | Dunya's coat sleeve mended | `done_Q03` |
| `ACH_Q04` (q04) | У Тихона своя полка | Tikhon has his own shelf | `done_Q04` |
| `ACH_Q06` (q06) | Второй верстак | Second workbench | `done_Q06` |
| `ACH_Q07` (q07) | Двадцать зарубок Мити | Mitya's twenty notches | `done_Q07` |
| `ACH_Q08` (q08) | Первый общий чай | Our first tea together | `done_Q08` |
