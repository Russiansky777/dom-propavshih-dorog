#!/usr/bin/env bash
# Экспорт Windows-сборки (embed_pck=true → один .exe). Требует windows_release_x86_64.exe в шаблонах.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/godot_env.sh
mkdir -p build/windows build/logs
godot_import   # не полагаться на импорт из тестов или веба: их могут пропустить
"$GODOT" --headless --path game --export-release "Windows" ../build/windows/DomPropavshihDorog.exe 2>&1 | tee build/logs/export_windows.log | grep -Ei 'error|warn|done|export' | head -20
ls -la build/windows
