#!/bin/sh
# Запуск стенда: ./run.sh  (Godot 4.7.2 в PATH как `godot`, или GODOT=/путь/к/godot ./run.sh)
cd "$(dirname "$0")" || exit 1
G="${GODOT:-godot}"
# первый запуск: импорт моделей и текстур в .godot/ (~15 с), дальше — сразу
[ -d .godot/imported ] || "$G" --headless --path . --import || exit 1
exec "$G" --path . "$@"
