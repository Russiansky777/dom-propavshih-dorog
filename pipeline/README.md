# pipeline/ — конвейер ассетов (владелец: Codex)

Прочитать `AGENTS.md` и `CLAUDE.md` в корне. Здесь живут скрипты, а не ассеты; результат кладётся в `assets/` по `assets/manifest.json`.

```
pipeline/3d/       Meshy API: image-to-3D, авториг, анимации → GLB (кэш в out/, в git не попадает)
pipeline/render/   Blender из командной строки: GLB → спрайт-листы по направлениям и кадрам
pipeline/2d/       Meshy text-to-image / image-to-image: предметы и состояния по техзаданиям манифеста
pipeline/voice/    TTS: реплики из data/story → assets/voice/<lang>/<line_id>.ogg + manifest с хешем текста
pipeline/qa/       проверки: размер, опорная точка, прозрачность, сравнение с образцом стиля
```

Секреты: `MESHY_API_KEY`, `ELEVENLABS_API_KEY` только из окружения (`.env` в корне, в `.gitignore`).

Первая задача Codex: кастинг голосов — по три реплики Агаты, Тихона и Нины (взять из `data/story/scenes/*.json`, поле `mandatory_lines`) в 2–3 голосах каждый; результат в `assets/voice/casting/<character>/<voice>_<n>.mp3` + таблица в `Docs/VOICE_CASTING.md`. Тихон — первым.
