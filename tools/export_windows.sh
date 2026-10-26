#!/usr/bin/env bash
# Экспорт Windows (I-T7, 26.10). Требует windows_release_x86_64.exe в шаблонах. Две сборки:
#   1. «Windows Lite» → build/windows/DomPropavshihDorog.exe — один exe (PCK вшит), листы жителей и Агаты — веб-копии
#      (tools/make_web_sheets.py, фича web_atlas), размер ≈ как у сайта. Этот файл выкладывает workflow.
#   2. «Windows» (полное качество, листы 2,25×) → build/windows/full/ (exe + .pck рядом, не вшит: PCK > 2 ГиБ)
#      → zip build/windows/DomPropavshihDorog_win.zip, предел 1,9 ГБ (ассет релиза GitHub ≤ 2 ГиБ).
# Падение полной сборки не мешает Lite (код 0), если не задано WIN_FULL_REQUIRED=1; WIN_FULL=0 — только Lite.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/godot_env.sh
mkdir -p build/windows build/logs
python3 -I tools/make_web_sheets.py   # веб-копии листов для Lite (готовые пропускаются)
t0=$(date +%s)
godot_import   # не полагаться на импорт из тестов или веба: их могут пропустить
echo "[godot] import: $(( $(date +%s) - t0 )) s"

# Без `| head`: обрезанный вывод закрывал трубу, и Godot получал SIGPIPE посреди экспорта.
export_preset() {  # $1 — пресет, $2 — путь от game/, $3 — журнал
  local t=$(date +%s) code
  set +e
  "$GODOT" --headless --path game --export-release "$1" "$2" >"$3" 2>&1
  code=$?
  set -e
  echo "[godot] export «$1»: код $code, $(( $(date +%s) - t )) s; журнал $3"
  grep -Ei 'error|fail' "$3" | grep -v 'Mesh "' | head -20 || true
  return $code
}

rm -f build/windows/DomPropavshihDorog.exe build/windows/DomPropavshihDorog.console.exe
if ! export_preset "Windows Lite" ../build/windows/DomPropavshihDorog.exe build/logs/export_windows.log \
    || [[ ! -s build/windows/DomPropavshihDorog.exe ]]; then
  echo "[godot] Windows Lite export FAILED; see build/logs/export_windows.log" >&2
  exit 1
fi
lite_mb=$(( $(stat -c %s build/windows/DomPropavshihDorog.exe) / 1000000 ))
echo "[godot] Windows Lite: build/windows/DomPropavshihDorog.exe ${lite_mb} MB"
if [[ "$lite_mb" -gt 1900 ]]; then
  echo "[godot] Windows Lite ${lite_mb} MB > 1900 MB (release asset limit 2 GiB)" >&2
  exit 1
fi

[[ "${WIN_FULL:-1}" == "0" ]] && { ls -la build/windows; exit 0; }

full_fail() {
  echo "[godot] Windows full: $1" >&2
  if [[ "${WIN_FULL_REQUIRED:-0}" == "1" ]]; then exit 1; fi
  echo "::warning title=Windows full build::$1"
  ls -la build/windows
  exit 0
}
rm -rf build/windows/full build/windows/DomPropavshihDorog_win.zip
mkdir -p build/windows/full
export_preset "Windows" ../build/windows/full/DomPropavshihDorog.exe build/logs/export_windows_full.log \
  || full_fail "export failed, see build/logs/export_windows_full.log"
[[ -s build/windows/full/DomPropavshihDorog.exe && -s build/windows/full/DomPropavshihDorog.pck ]] \
  || full_fail "no exe/pck in build/windows/full"
t=$(date +%s)
(cd build/windows/full && zip -q -6 ../DomPropavshihDorog_win.zip DomPropavshihDorog.exe DomPropavshihDorog.pck \
  $(ls DomPropavshihDorog.console.exe 2>/dev/null))
zip_mb=$(( $(stat -c %s build/windows/DomPropavshihDorog_win.zip) / 1000000 ))
echo "[godot] Windows full: zip ${zip_mb} MB за $(( $(date +%s) - t )) s; pck $(( $(stat -c %s build/windows/full/DomPropavshihDorog.pck) / 1000000 )) MB"
if [[ "$zip_mb" -gt 1900 ]]; then
  rm -f build/windows/DomPropavshihDorog_win.zip
  full_fail "zip ${zip_mb} MB > 1900 MB (release asset limit 2 GiB)"
fi
ls -la build/windows build/windows/full
