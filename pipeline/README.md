# pipeline/ — конвейер ассетов

Прочитать `AGENTS.md` и `CLAUDE.md`. Здесь скрипты; результат попадает в `assets/` по `assets/manifest.json`.
Пока Codex на паузе, конвейер пишет и запускает Claude Code (решение 17.10). Сеть облачной сессии Claude не пропускает
api.meshy.ai, поэтому **запуски идут в GitHub Actions** (`.github/workflows/pipeline_character.yml`): у раннеров полный
интернет, ключи — в секретах репозитория (`MESHY_API_KEY`, позже `ELEVENLABS_API_KEY`), результаты коммитятся обратно.

```
pipeline/requests/<character>.json   маркер: изменение файла запускает воркфлоу
pipeline/3d/meshy_client.py          клиент Meshy OpenAPI v1 (stdlib)
pipeline/3d/meshy_character.py       лист (3 ракурса) → multi-image-to-3d → rigging → animations → GLB
pipeline/3d/state/<character>.json   id задач Meshy — повтор не создаёт задачи заново (кредиты не списываются дважды)
pipeline/render/render_sprites.py    GLB → спрайт-листы (bpy 5.2.2, Cycles CPU, 8 направлений, прозрачный фон)
assets/characters/<character>/       результат: walk.png, idle.png, sprites.json, meshy_manifest.json, view_*.png
```

Проверено локально 17.10: нарезка листа Агаты (3 фигуры по 1063 px), рендер 8×6 кадров с тестовой модели за 29 с.
Запуск вручную на компьютере с сетью: `MESHY_API_KEY=... python3 pipeline/3d/meshy_character.py --request pipeline/requests/agata.json`
затем `python3 pipeline/render/render_sprites.py --glb pipeline/3d/out/agata/animations.glb --name agata --out assets/characters/agata --frames walk=12 idle=8`.

Стоимость одного персонажа (Meshy 7.1, 2K текстуры): модель 30 + риг 5 + 2 анимации × 3 = ~41 кредит.

Позже здесь же: `pipeline/2d/` (предметы и состояния через Meshy text-to-image), `pipeline/voice/` (озвучка, после text_freeze).
