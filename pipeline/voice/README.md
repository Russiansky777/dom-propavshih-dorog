# pipeline/voice/ — озвучка реплик (ElevenLabs)

Сеть сессии Claude не пропускает `api.elevenlabs.io`, поэтому всё внешнее идёт в **GitHub Actions**
(`.github/workflows/pipeline_voice.yml`); ключ — секрет репозитория `Eleven_API` (в workflow
`${{ secrets.ELEVEN_API }}`: имена секретов GitHub нечувствительны к регистру). Ключ не печатается и в репозиторий
не попадает: скрипт сообщает только «есть / длина / похож ли на `sk_…`».

```
pipeline/requests/voice_<набор>.json  запрос; изменение файла запускает workflow (или workflow_dispatch)
pipeline/voice/eleven_voice.py        клиент ElevenLabs + обработка ffmpeg (stdlib Python)
pipeline/voice/voices.json            голоса аккаунта (режим list): имя, voice_id, категория, метки — без ключа
pipeline/voice/cast.json              персонаж → голос, модель, настройки голоса, громкость
pipeline/voice/state/<набор>.json     журнал прогонов: сколько реплик и символов ушло, баланс до/после
assets/voice/ru/<scene>_<index>.ogg   реплика для игры (OGG Vorbis q7, моно 44,1 кГц, −17 LUFS, тишина по краям срезана);
                                      слова варианта выбора в разговоре — <scene>_<index>_<вариант>.ogg (M13_1_family)
pipeline/voice/design/<персонаж>/     превью Voice Design (режим design) и <персонаж>.json — параметры, замеры, выбор
assets/voice/ru/narrator/<ключ>.ogg   закадровая фраза (голос narrator = «ZAKADR»): осмотр, действие, закрытый выход,
                                      вопрос выбора, сообщение крупного плана, строка предмета сумки; id — ключ текста
assets/voice/ru/src/<id>.mp3          ответ API как есть — переобработка без новых кредитов
assets/voice/ru/manifest.json         id → персонаж, текст, sha1 текста, голос, модель, настройки, длительность, громкость
```

Игра читает копию: `tools/sync_voice.sh` → `game/assets/voice/ru/` (Claude Code не правит `assets/` руками).
Проверка — `tools/validate_voice.py` (в `tools/run_tests.sh`), `game/tests/test_voice.gd`.

## Запуск

| запрос | что делает | кредиты |
|---|---|---|
| `{"mode": "list"}` | проверить ключ, баланс, сохранить `voices.json` | 0 |
| `{"mode": "generate", "set": "e0e1_probe", "probe": true, "scenes": ["M01", …, "Q04"]}` | озвучить реплики сцен | ≈ число символов текста |
| `{"mode": "generate", "set": "e0e1_narration", "probe": true, "narration": {"texts": ["ru_E0_E1", "ru_bag"]}, "order": {…}}` | закадровые фразы из файлов `data/story/text/<имя>.json` (какие ключи — правила `data/story/voice.json` → `narration`; ключи без ссылок в данных игры пропускаются); `"keys": [...]` — только эти | ≈ число символов текста |
| `"redo": ["M01_1"]` | перегенерировать указанные реплики, даже если текст не менялся | за эти реплики |
| `"reprocess": true` | заново обрезать/выровнять из `src/*.mp3` (поменяли громкость) | 0 |
| `"prune_stale": true` | после запроса убрать записи, которые остались `stale` (ключа/реплики нет; запасная запись под старым текстом; ключ без ссылок) — запись манифеста, OGG и `src` | 0 |
| `{"mode": "design", "voices": [{speaker, voice_name, description, text, …}]}` | Voice Design: три превью нового голоса → `pipeline/voice/design/<персонаж>/preview_<n>.mp3` и `design/<персонаж>.json` | символы текста превью, один раз |
| `{"mode": "create_voice", "voices": [{speaker, generated_voice_id, voice_name, labels, selection}]}` | выбранное превью → голос в My Voices (`voice_id` в `design/<персонаж>.json`), затем список голосов (`voices.json`) | 0 |
| `cast.<id>.alternates.<вариант>` в `cast.json` | те же реплики вторым голосом в `assets/voice/ru_alt/<id>_<вариант>/` (для сравнения на слух; сейчас не используется — Директор выбрал голоса) | за реплики персонажа |

Повторный запуск генерирует только новые и изменённые реплики: сравниваются sha1 текста, голос, модель и настройки
с записью манифеста. Реплики, которых больше нет в сценах, или с изменённым текстом помечаются `"stale"` — игра их
не играет (сверяет sha1 сама), валидатор перечисляет.

**Массовая запись запрещена до `text_freeze: true`** в `data/story/meta.json` (решение Директора 17.10): пока текст
не заморожен, скрипт принимает только запрос с `"probe": true` и не больше 40 реплик.

**Больше пробы до заморозки — только по явному заданию Директора:** поле `order` запроса
(`by`, `date`, `what`, `max_lines`, `max_chars`) поднимает потолок файлов до `max_lines`; если к синтезу больше
`max_chars` символов, скрипт не запускается. Задание записывается в `Docs/DECISIONS.md` (первое — закадровый голос
E0–E1, 18.10: 90 фраз, потолок 100 файлов / 6 000 символов).

## Закадровый голос (narrator)
- Голос — `cast.json` → `narrator` («ZAKADR»); роль задана в `data/story/voice.json` → `narration.speaker`, в
  `characters.json` её нет (это не персонаж).
- Какие ключи текста озвучиваются, решают правила `narration` в `data/story/voice.json`: не озвучиваются секции
  `skip_sections` (`ui` — интерфейс и подсказки, `map` — подписи плана), поля `skip_fields` (`label*` — подписи
  хотспотов и выходов, `opt_*` — варианты выбора, `slot_*`/`marks`/`drawing`/`title`/`hinge`/`check` — подписи
  крупного плана загадки) и ключи `skip_keys` (служебные по смыслу). Одни и те же правила применяют скрипт (что
  синтезировать), валидатор (в манифесте нет лишнего) и игра (`VoiceDirector` не играет подпись даже при файле).
- Теги подачи — поле `tags` у записи текста (`"tags": ["softly"]`), в субтитры не попадают; sha1 запроса с тегами
  (`voice_sha1`) — смена тегов перегенерирует только эту фразу; sha1 текста (`text_sha1`) сверяет игра.
- **Мысли персонажа** (`narration.by_speaker.<персонаж>`): ключи от первого лица читает сам персонаж (Агата), а не
  закадровый голос — id `<персонаж>:<ключ>`, файл `<subdir>/<ключ>.ogg` (`agata_thoughts/`), настройки
  `cast.json` → `<персонаж>.inner_voice`, теги — `by_speaker.<персонаж>.tags`, `hold` — не записывать пока.
  Закадровая запись такого ключа остаётся запасной (не stale: устаревание сверяется только с текстом ключа);
  в запросе `"narration": {"speakers": ["agata"]}` — только мысли. Валидатор не пропускает первое лицо у
  закадрового голоса (`narration.first_person`: местоимения и формы вне кавычек).
- **Слова персонажа рядом с Агатой** (поле `line` {speaker, text[, tags]} у записи текста — повторный разговор
  с Тамарой/Пелагеей, реплика Тихона после V01): показ как реплика (имя говорящего, прямая речь без ремарки), голос
  и настройки — его реплик из `cast.json`; id `<персонаж>:<ключ>`, файл `character_lines/<ключ>.ogg`
  (`narration.character_lines.subdir`). Закадровая запись прежнего `text` (с ремаркой) — запасная. Валидатор не
  пропускает у закадрового голоса ключи повторного разговора (`.after`, `.again`, `.before`) и цитаты «…» с
  атрибуцией (`narration.character_speech`).

## Текст изменился — как перезаписать (одним запросом)
Правка текста main не роняет: запись под старым текстом игра не играет (сверяет sha1), `tools/validate_voice.py`
печатает **предупреждение** «к перезаписи N: …» со списком id и выходит с кодом 0 (`test_voice.gd` — так же).
Ошибка (код 1) — только настоящий дефект: запись для подписи/интерфейса, чужая папка или голос у закадровой записи,
первое лицо у закадрового голоса, OGG без записи манифеста, тихая/обрезанная запись.
1. `python3 tools/validate_voice.py` — что устарело (запасные записи другого голоса перечислены отдельно и не
   перезаписываются).
2. `cp pipeline/voice/rerecord_template.json pipeline/requests/voice_rerecord.json` (или поменять дату в `note`
   существующего), проверить без сети:
   `python3 pipeline/voice/eleven_voice.py generate --request pipeline/requests/voice_rerecord.json --dry-run`
   — список и число символов (≈ кредитов × 0,44 у eleven_v4 по прошлым прогонам).
3. Закоммитить **только этот файл отдельным коммитом без `[skip ci]`** и запушить. `"only_changed": true` — в работу
   идёт только изменённое (каждым назначенным голосом: реплики, закадровые фразы, мысли Агаты), старые записи
   помечаются `stale` и заменяются; бот коммитит результат, `tools/sync_voice.sh` (в `tools/run_tests.sh`) кладёт его
   в игру.

Локально без сети: `python3 pipeline/voice/eleven_voice.py generate --request pipeline/requests/voice_e0e1.json --dry-run`
— список реплик и число символов, без запросов к API.

## Выжимка документации ElevenLabs (сверено 17.10.2026)

**Аутентификация.** Заголовок `xi-api-key: <ключ>`, хост `https://api.elevenlabs.io`
([Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)).

**Голоса аккаунта.** `GET /v2/voices` — `page_size` до 100 (по умолчанию 10), пагинация `next_page_token` + `has_more`,
фильтры `search`, `category` (`premade`, `cloned`, `generated`, `professional`), `voice_type` (`personal`, `community`,
`default`, `workspace`, `non-default`, `non-community`, `saved`); ответ `voices[]` с `voice_id`, `name`, `category`,
`labels`, `description`, плюс `total_count` ([List voices](https://elevenlabs.io/docs/api-reference/voices/search)).
«My Voices» = `voice_type=personal`.

**Синтез.** `POST /v1/text-to-speech/{voice_id}?output_format=…`, тело JSON:
- `text` (обязательно), `model_id` (по умолчанию `eleven_multilingual_v2`);
- `language_code` (ISO 639-1) — «не поддерживается multilingual_v2»; для других моделей принуждает язык;
- `voice_settings` — переопределяет сохранённые настройки голоса на один запрос: `stability` 0–1 (0,5; ниже — шире
  эмоциональный диапазон, выше — однообразнее), `similarity_boost` 0–1 (0,75), `style` (0), `use_speaker_boost` (true),
  `speed` (1,0) ([настройки по умолчанию](https://elevenlabs.io/docs/api-reference/voices/settings/get-default));
- `seed` 0…4294967295 — детерминизм «по возможности»; `previous_text`/`next_text` — связность соседних кусков;
  `apply_text_normalization` `auto|on|off`;
- `output_format` `codec_частота_битрейт`: `mp3_44100_128` (по умолчанию), `mp3_22050_32` … `mp3_44100_192`
  (192 — от плана Creator), `pcm_8000…48000`, `wav_8000…48000` (44,1 кГц PCM/WAV — от плана Pro), `opus_48000_*`,
  `ulaw_8000`, `alaw_8000`;
- ответ — аудиофайл; ошибка проверки — 422 со списком `detail`.

**Модели с русским** ([Models](https://elevenlabs.io/docs/overview/models)):

| model_id | что говорит документация | лимит символов на запрос |
|---|---|---|
| `eleven_v4` | «Our most emotive, high quality speech synthesis model»; 90+ языков, русский есть; персонажи, эмоциональный диалог | 10 000 |
| `eleven_v4_turbo` | быстрый (~100 мс) вариант для реального времени | — |
| `eleven_v3` | предыдущее поколение, «emotionally rich, expressive»; 70+ языков, русский есть | 5 000 |
| `eleven_multilingual_v2` | «lifelike … rich emotional expression», самый стабильный на длинных текстах; 29 языков, русский есть | 10 000 |
| `eleven_flash_v2_5` | реальное время (~75 мс), дешевле вдвое; 32 языка | 40 000 |

**Eleven v4** ([страница модели](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4),
[FAQ](https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/what-is-eleven-v4)): «the
highest-quality option … character voiceovers»; доступна в Create speech (`/v1/text-to-speech`) с `model_id=eleven_v4`.
Настроек только две — **Stability** («ниже — выразительнее и разнообразнее, выше — ближе к постоянной базовой
подаче») и **Similarity** (выше — ближе к исходному голосу, «ценой некоторой естественности»). Style и Speed **не
поддерживаются**, SSML (в т. ч. `<break>`) — нет; паузы и подача — пунктуацией (многоточие — пауза и вес, заглавные
— ударение) и аудиотегами в квадратных скобках (`[whispers]`, `[sighs]`, `[laughing]`; «следование тегам пока не
идеально»). Оговорка: голоса из Voice Design («generated») с v4 работают, но «may not be as performative or sound as
good» как с прежними моделями — сравнивать на своём материале; поведение может меняться с обновлениями модели.
Аудиотеги одинаково работают в v3 и v4
([аудиотеги](https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/how-do-audio-tags-work-with-eleven-v3-and-v4),
[best practices](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices#prompting-eleven-v4)).

**Баланс.** `GET /v1/user/subscription` — `tier`, `character_count` (израсходовано в периоде), `character_limit`,
`next_character_count_reset_unix` ([Get subscription](https://elevenlabs.io/docs/api-reference/user/subscription/get)).
Скрипт снимает его до и после генерации; разница — фактически списанные кредиты (если ключу разрешено чтение
пользователя; иначе в журнал идёт число символов текста).

## Качество (указание Директора 23.10, 12:49 «где выбор качества — лучшее»; сверено с документацией 23.10.2026)
- **Модель — `eleven_v4`**, без изменений: страница моделей называет её «Our most emotive, high quality speech synthesis
  model», страница Eleven v4 — «our highest-quality model, ideal for … character voiceovers»; русский есть, аудиотеги
  есть (те же, что v3) ([Models](https://elevenlabs.io/docs/overview/models),
  [Eleven v4](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4),
  [What is Eleven v4](https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/what-is-eleven-v4)).
  `eleven_v4_turbo`, `eleven_v3_conversational`, `eleven_flash_*` — варианты для реального времени, не берём.
  Стоимость за символ документация не называет; фактически по заголовку `character-cost` наших прогонов eleven_v4
  списывает ≈0,44 кредита за символ текста (2 362 кредита за 5 372 символа, `state/e0e1_narration.json`).
  Оговорка документации: голоса Voice Design с v4 «may not be as performative or sound as good as with earlier models» —
  на слух Директора v4 принят (кастинг 17.10, приёмка E0–E1), поэтому модель не меняем.
- **Формат ответа — `mp3_44100_192`** (было `mp3_44100_128`): «MP3 at 192kbps requires the Creator tier or above»,
  «PCM and WAV at 44.1kHz require the Pro tier or above» ([Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert));
  у нас Creator — 192 кбит/с MP3 44,1 кГц — лучшее доступное. Формат каждой записи — поле `output_format` манифеста.
- **Кодирование в игру — OGG Vorbis q7** (было q5; `cast.json → loudness.vorbis_quality`); смена качества сама
  переобрабатывает записи из `src/*.mp3` без кредитов. Громкость — как была: −17 LUFS «как слышит игрок»,
  ограничитель −2 dBFS.
- Настройки голоса — по персонажу (`cast.json`), seed — по-прежнему из id и текста реплики.
- Утверждённые на слух записи E0–E1, текст которых не менялся, ради формата не перезаписываются (новый дубль — другое
  исполнение); перезаписать — перечислить в `"redo"`.

## Квота
`cast.json → quota`: перед синтезом скрипт читает подписку (`GET /v1/user/subscription`) и не запускает запрос, если
символов × `credits_per_char_assumed` (1,0 — оценка сверху) больше остатка за вычетом `margin_fraction` (10 %) лимита;
во время синтеза останавливается по фактическому списанию (`character-cost`), не заходя в запас. Лимит Creator —
124 889 кредитов в месяц; докупка — решение Директора.

## Voice Design — новый голос по описанию (сверено 23.10.2026)
1. `POST /v1/text-to-voice/design?output_format=mp3_44100_192` — тело `{voice_description (20–1000), model_id
   ("eleven_ttv_v3" | "eleven_multilingual_ttv_v2"), text (100–1000), guidance_scale (0–100, 5), quality (−1…1: выше —
   лучше звук и меньше разброс), loudness (−1…1, 0,5), seed, should_enhance}` → `previews[]` {`generated_voice_id`,
   `audio_base_64`, `media_type`, `duration_secs`, `language`}
   ([Design a voice](https://elevenlabs.io/docs/api-reference/text-to-voice/design)).
2. `POST /v1/text-to-voice` — `{voice_name, voice_description, generated_voice_id, labels?, played_not_selected_voice_ids?}`
   → `voice_id`, голос появляется в My Voices ([Create a voice](https://elevenlabs.io/docs/api-reference/text-to-voice/create);
   порядок шагов — [guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/voices/voice-design.md)).
3. Описание — по рекомендации [Voice Design](https://elevenlabs.io/docs/eleven-creative/voices/voice-design.md):
   «Native <Language>. <Gender>, <Age range>. <Quality level>.», затем образ (2–5 слов), 2–3 эмоции, 1–2 фразы о тембре,
   темпе и подаче; текст превью — под стать описанию, длиннее — стабильнее. Списание — только символы текста превью,
   один раз за три варианта; сохранённый голос занимает один слот голосов аккаунта.
У нас: запрос `pipeline/requests/voice_design_new.json` (режим `design`) → три превью в `design/<персонаж>/`; выбор —
по замерам превью (высота голоса для возраста и пола, темп, чистота/шум, отсутствие клиппинга) — запрос
`voice_create_new.json` (режим `create_voice`, поле `selection` — почему); `voice_id` → `cast.json`.

## Наш выбор (проба E0–E1)
- Модель `eleven_v4` — документация называет её лучшей для выразительной речи персонажей; русский поддерживается.
  Если голоса Директора окажутся из Voice Design и v4 прозвучит хуже, в `cast.json` можно задать `model_id` персонажу
  (`eleven_v3` или `eleven_multilingual_v2`) — перегенерируются только его реплики.
- `voice_settings`: только `stability` и `similarity_boost` (другие поля v4 не поддерживает) — значения и причины
  в `cast.json`.
- `output_format=mp3_44100_128` — доступен на любом плане и несёт полную полосу 44,1 кГц; WAV 44,1 кГц требует Pro.
  С 23.10 — `mp3_44100_192` (раздел «Качество» выше).
- `language_code=ru` — короткие реплики («Какие?») не уходят в чужой акцент; если модель не примет параметр,
  скрипт повторит запрос без него и запишет это в журнал (отклонённый запрос кредитов не списывает).
- Обработка (ffmpeg): срез тишины по краям до 40 мс в начале и 120 мс в конце (порог −50 dBFS), выравнивание
  громкости линейным усилением к **−17 LUFS** «как слышит игрок» (моно на оба канала, EBU R128 по стерео-дублю),
  ограничитель −2 dBFS на случай пиков, короткие фейды 8/30 мс от щелчков, OGG Vorbis моно 44,1 кГц (q5 до 23.10, с 23.10 — q7). Музыка в
  игре −24…−25 LUFS и под репликой приглушается ещё на 5 dB — голос стоит над ней на ≈12 LU.
- Повторы: 429/5xx — с паузой до 4 раз (такие ответы кредитов не списывают); обрыв связи после отправки — один повтор
  (в журнале помечается как возможное двойное списание).
