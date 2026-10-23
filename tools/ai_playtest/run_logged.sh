#!/usr/bin/env bash
# Run the playtester, keep its console (step numbers, actions, rooms, costs — never the key, the workspace or
# model text) and, when it fails, leave the tail in Docs/playtest/failures/ so the cause is readable from the
# repository (the Actions logs are not reachable from the agents' sessions).
#   tools/ai_playtest/run_logged.sh <label> <playtest.mjs args…>
set -u
label="$1"; shift
mkdir -p build/ai_playtest
log="build/ai_playtest/console_${label}.txt"
node tools/ai_playtest/playtest.mjs "$@" > >(tee "$log") 2>&1
rc=$?
sleep 1
if [ "$rc" -ne 0 ] || ! grep -q "report: " "$log"; then
  mkdir -p Docs/playtest/failures
  f="Docs/playtest/failures/$(date -u +%Y-%m-%d_%H%M)_${label}_r${GITHUB_RUN_NUMBER:-local}.txt"
  { echo "exit $rc; args: $*"; echo "---"; tail -n 80 "$log" | sed -E 's/sk-ant-[A-Za-z0-9_-]+/sk-ant-…/g; s/wrkspc_[A-Za-z0-9]+/wrkspc_…/g'; } > "$f"
  echo "сбой плейтеста записан: $f"
fi
exit $rc
