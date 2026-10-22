# ИИ-плейтест: свежий взгляд новичка — 2026-10-22

- Сборка: `6dd0a45 2026-10-22T20:56Z` — https://russiansky777.github.io/dom-propavshih-dorog/
- Запрос: `pipeline/requests/playtest_smoke.json` — Дымовой прогон: проверка ключа, модели и отчёта (6 шагов).
- Модели: шаги — `claude-haiku-5-5`, когда застряла — `claude-sonnet-5-5`; отчёт — `claude-sonnet-5-5`. Кадр модели 1280×720 JPEG (окно игры 1920×1080).
- Шагов: 0 из 6; время 0 мин. Остановка: API: ошибка 400 invalid_request_error
- Стоимость: **$0.000** из $0.3 (по usage ответов API; подробно — usage.json)
- Где оказалась по факту: Z1; конец — Z1

_Итоговый отчёт сильной модели не составлен (нет бюджета, ключа или ответа) — ниже сырые данные прогона._

---

## Приложение: техника плейтеста

- step 1: HTTP 400 invalid_request_error: This API key is not scoped to a workspace, so this request must include the anthropic-workspace-id header with the ID of the workspace to use. Add the header, or use an…
- report model skipped: estimate $0.093 does not fit (left $0.300)

Полный журнал шагов и дословные реплики — log.json; токены и стоимость каждого вызова — usage.json.
