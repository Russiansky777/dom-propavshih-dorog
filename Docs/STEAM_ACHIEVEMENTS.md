# Steam: достижения — заготовка (12.11.2026)

Основа — 18 «следов выборов», которые игра уже показывает на экране конца («Что осталось от выборов»): `data/story/achievements.json`.
В Steam достижения заводятся в App Admin (по умолчанию не больше 100; названия и иконки — для всех возрастов: https://partner.steamgames.com/doc/features/achievements), игра сообщает о них через GodotSteam — это делается, когда будет AppID.

**Решения Директора:** (1) брать ли все 18 или сократить (в наборе ChatGPT «Steam Narrator Kit v1» было 10 достижений, 2 скрытых, с иконками — `Docs/STEAM_KIT_PLAN.md`); (2) названия ниже — это подписи с экрана конца, для Steam их можно оставить или переименовать; (3) описания (вторая строка в Steam) — их пока нет; (4) иконки 256×256 — художнику.

| API-имя (id) | Название RU (как в игре) | Название EN (как в игре) | Когда выдаётся (флаги сюжета) |
| --- | --- | --- | --- |
| `board` | Мама ответила на доске | Mama's reply on the blackboard | `nina_answered_board + один из: board_here, board_mama, board_ilya` |
| `mitten` | Варежка нашлась на дороге домой | My mitten on the road home | `mitten_found_on_path` |
| `bird` | Синица на плакате: шапка, сапоги и мой рисунок | Poster bird: cap, boots and my drawing | `v03_marked` |
| `promise` | Слово Павлу сдержано | My word to Pavel kept | `pavel_answer_promise` |
| `family` | «Там моя матушка и брат» — Павел понял | "My mother and brother are there" — Pavel understood | `pavel_answer_family` |
| `tikhon_nina` | Тихон зовёт маму хозяйкой | Tikhon calls Mama the mistress | `tikhon_told_nina` |
| `tikhon_agata` | Тихон спит у Агатиной лежанки | Tikhon sleeps by Agata's ledge | `tikhon_told_agata` |
| `beam` | Надпись на торце первого прогона | An inscription on the first beam | ` + один из: beam_dunya, beam_roads, beam_date` |
| `cup` | Мама узнала свою чашку | Mama recognised her cup | ` + один из: v01_cup_blue, v01_cup_white` |
| `ribbon` | Мамина лента снова в косе | Mama's ribbon in my braid again | `ribbon_braided` |
| `letters` | Письма за двадцать зим | Letters from twenty winters | `nina_letters_read` |
| `q01` | Аксинья получает письма брата | Aksinya gets her brother's letters | `done_Q01` |
| `q02` | Сад Ильи — на старой карте | Ilya's garden on the old map | `done_Q02` |
| `q03` | Рукав Дуниного пальто зашит | Dunya's coat sleeve mended | `done_Q03` |
| `q04` | У Тихона своя полка | Tikhon has his own shelf | `done_Q04` |
| `q06` | Второй верстак | Second workbench | `done_Q06` |
| `q07` | Двадцать зарубок Мити | Mitya's twenty notches | `done_Q07` |
| `q08` | Первый общий чай | Our first tea together | `done_Q08` |
