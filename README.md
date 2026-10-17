# Дом пропавших дорог

Сюжетная 2D point-and-click игра: Агата приезжает в дом пропавшей тёти, через старую школьную дверь находит путь в исчезнувшую деревню и узнаёт, что снаружи прошёл год, а внутри — двадцать лет. Прожитое не стирается; восстанавливаются дороги и общее будущее.

Godot 4.7.x · GDScript · браузер + Windows/macOS/Linux.

## Начало работы
1. Агентам: `CLAUDE.md` (Claude Code), `AGENTS.md` (Codex), затем `Docs/CURRENT_STATE.md`.
2. Людям: `story_source/reading_scenario.md` — сценарий для чтения; `Docs/MILESTONES.md` — что считается готовым.

## Команды
```
python3 tools/validate_story.py     # данные сценария, код 0 обязателен
tools/run_tests.sh                  # headless-тесты Godot
tools/export_web.sh                 # build/web/
node tools/screenshots.mjs          # build/shots/
```

## Структура
`game/` проект Godot · `data/story/` сценарий как данные · `tools/` проверки и сборки · `pipeline/` конвейер ассетов (Codex) · `assets/` готовые ассеты и манифест · `Docs/` состояние, решения, вехи, тесты · `story_source/` исходный сценарий и концепты.
