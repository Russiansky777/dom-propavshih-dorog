#!/usr/bin/env bash
# Commit the playtest results (Docs/playtest only) with [skip ci]; push with retries on a race.
#   tools/ai_playtest/commit_results.sh <run number>
set -u
git config user.name "playtest-bot"
git config user.email "playtest-bot@users.noreply.github.com"
git add Docs/playtest
if git diff --cached --quiet; then echo "нечего коммитить"; exit 0; fi
summary=$(cat build/ai_playtest/*/summary.txt 2>/dev/null | tail -n 1 | tr '\n' ' ')
git commit -q -m "ИИ-плейтест: ${summary:-результаты} (run ${1:-?}) [skip ci]"
for i in 1 2 3 4 5 6 7 8; do
  git fetch -q origin main
  if git rebase --autostash origin/main; then
    if git push origin HEAD:main; then echo "запушено с попытки $i"; exit 0; fi
  else
    git rebase --abort || true
  fi
  sleep $((10 + RANDOM % 20))
done
exit 1
