#!/usr/bin/env bash
# Экспорт macOS (Директор 26.11: «Сделай версию для мак»). Пресет «macOS» → build/macos/DomPropavshihDorog_mac.zip:
#   внутри «Dom propavshih dorog.app» — universal (Apple Silicon и Intel), подпись ad-hoc встроенным подписчиком Godot,
#   PCK в Contents/Resources, GodotSteam (game/addons/godotsteam/osx) в Contents/Frameworks. Нотаризации нет: для неё
#   нужен платный аккаунт Apple Developer — при первом запуске Mac спросит разрешение (Docs/ACCEPTANCE_mac.md).
#
# Godot 4.7.2 не выпускает universal/arm64 без импорта ETC2/ASTC (platform/macos/export/export_plugin.cpp,
# has_valid_export_configuration), хотя в пакет universal кладёт только S3TC/BPTC (get_preset_features). Включить
# импорт ETC2/ASTC в проекте насовсем — это ASTC для 44 восьмитысячных листов жителей (1,79 Гпикс, ~1,8 ГБ в .godot у
# каждого агента и в каждом CI) ради проверки, которой эти листы не нужны: пресет их и так не берёт (exclude_filter).
# Поэтому только здесь и только на время экспорта:
#   1. PNG, которые пресет исключает, и их .import уходят из game/ в build/macos/_parked (ни одна сцена и ни один
#      ресурс на них не ссылается — проверено 26.11; Windows Lite собирается без них так же);
#   2. в project.godot import_etc2_astc=false → true.
# Обе правки откатывает ловушка (и при ошибке). На своей машине — только с MAC_EXPORT_LOCAL=1 (повторный импорт листов
# после возврата займёт время); в CI (GITHUB_ACTIONS=true) — всегда.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${GITHUB_ACTIONS:-}" != "true" && "${MAC_EXPORT_LOCAL:-0}" != "1" ]]; then
  echo "[mac] export_macos.sh временно меняет game/ (см. шапку) — запуск в CI (build_mac.yml) или MAC_EXPORT_LOCAL=1" >&2
  exit 2
fi
source tools/godot_env.sh
mkdir -p build/macos build/logs
for f in osx/libgodotsteam.macos.template_release.universal.dylib osx/libsteam_api.dylib; do
  [[ -s "game/addons/godotsteam/$f" ]] || { echo "[mac] нет game/addons/godotsteam/$f (Steam для Mac)" >&2; exit 1; }
done

python3 -I tools/make_web_sheets.py   # веб-копии листов (фича web_atlas) — из исходных листов, до того как они уйдут
tools/sync_story_data.sh >/dev/null
tools/sync_voice.sh >/dev/null
tools/sync_music.sh >/dev/null
python3 tools/validate_story.py >/dev/null

PARK=build/macos/_parked
PROJECT=game/project.godot
restore() {
  local code=$?
  if [[ -f "$PARK/project.godot" ]]; then cp "$PARK/project.godot" "$PROJECT"; fi
  if [[ -f "$PARK/list.txt" ]]; then
    while IFS= read -r rel; do
      [[ -n "$rel" && -e "$PARK/game/$rel" ]] || continue
      mkdir -p "game/$(dirname "$rel")"
      mv "$PARK/game/$rel" "game/$rel"
    done < "$PARK/list.txt"
  fi
  rm -rf "$PARK"
  exit $code
}
rm -rf "$PARK"
mkdir -p "$PARK/game"
trap restore EXIT

# 1. исключённые пресетом PNG (и их .import) — в сторону
python3 -I - "$PARK/list.txt" <<'EOF'
import configparser, fnmatch, os, sys
cfg = open("game/export_presets.cfg", encoding="utf-8").read()
pats = None
for block in cfg.split("\n[preset."):
    if '\nname="macOS"' in block or block.startswith('0]\n\nname="macOS"'):
        for line in block.splitlines():
            if line.startswith("exclude_filter="):
                pats = [p.strip() for p in line.split("=", 1)[1].strip('"').split(",") if p.strip()]
if not pats:
    sys.exit("no exclude_filter in preset macOS")
out = []
for root, dirs, files in os.walk("game"):
    dirs[:] = [d for d in dirs if d != ".godot"]
    for f in files:
        if not f.endswith(".png"):
            continue
        rel = os.path.relpath(os.path.join(root, f), "game").replace(os.sep, "/")
        if any(fnmatch.fnmatch(rel, p) for p in pats):
            out.append(rel)
            if os.path.exists(os.path.join("game", rel + ".import")):
                out.append(rel + ".import")
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(out) + "\n")
print("[mac] в сторону на время экспорта: %d файлов (исключённые пресетом листы и их .import)" % len(out))
EOF
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  mkdir -p "$PARK/game/$(dirname "$rel")"
  mv "game/$rel" "$PARK/game/$rel"
done < "$PARK/list.txt"

# 2. ETC2/ASTC — только на время экспорта
cp "$PROJECT" "$PARK/project.godot"
if grep -q '^textures/vram_compression/import_etc2_astc=false' "$PROJECT"; then
  sed -i 's/^textures\/vram_compression\/import_etc2_astc=false/textures\/vram_compression\/import_etc2_astc=true/' "$PROJECT"
else
  echo "[mac] в project.godot нет строки import_etc2_astc=false — проверить пресет и проект" >&2
  exit 1
fi

t0=$(date +%s)
godot_import
echo "[godot] import: $(( $(date +%s) - t0 )) s"

OUT=build/macos/DomPropavshihDorog_mac.zip
rm -f "$OUT"
t=$(date +%s)
set +e
"$GODOT" --headless --path game --export-release "macOS" ../$OUT >build/logs/export_macos.log 2>&1
code=$?
set -e
echo "[godot] export «macOS»: код $code, $(( $(date +%s) - t )) s; журнал build/logs/export_macos.log"
grep -Ei 'error|fail|warn' build/logs/export_macos.log | grep -v 'Mesh "' | head -30 || true
if [[ $code -ne 0 || ! -s "$OUT" ]]; then
  echo "[mac] экспорт не удался — build/logs/export_macos.log" >&2
  tail -40 build/logs/export_macos.log >&2
  exit 1
fi
mb=$(( $(stat -c %s "$OUT") / 1000000 ))
echo "[mac] $OUT: ${mb} MB"
if [[ "$mb" -gt 1900 ]]; then
  echo "[mac] ${mb} MB > 1900 MB (предел ассета релиза GitHub — 2 ГиБ)" >&2
  exit 1
fi

# Что внутри: .app, universal-бинарник (x86_64 + arm64), PCK с GodotSteam, библиотеки Steam, подпись
python3 -I tools/check_mac_zip.py "$OUT"
