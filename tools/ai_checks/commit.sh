#!/usr/bin/env bash
# Commit the AI check results (only the given paths) with [skip ci]; push with retries on a race.
#   tools/ai_checks/commit.sh "<message>" <path>...
set -u
msg="$1"; shift
git config user.name "ai-checks-bot"
git config user.email "ai-checks-bot@users.noreply.github.com"
git add -- "$@"
if git diff --cached --quiet; then echo "нечего коммитить"; exit 0; fi
git commit -q -m "$msg [skip ci]"
for i in 1 2 3 4 5 6; do
  git fetch -q origin main
  if git rebase --autostash origin/main; then
    if git push origin HEAD:main; then echo "запушено с попытки $i"; exit 0; fi
  else
    git rebase --abort || true
  fi
  sleep 15
done
exit 1
