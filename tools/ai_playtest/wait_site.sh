#!/usr/bin/env bash
# Wait until the published site serves a build: $1 = commit to wait for (a gate on a deploy), or "" = the
# latest successful build-and-publish (a manual request; waits for a running build first). Up to ~25 min.
# Writes SITE_NOTE to $GITHUB_ENV when the site still serves another build (the report says so).
set -u
want="${1:-}"
site="https://russiansky777.github.io/dom-propavshih-dorog/version.txt"
if [ -z "$want" ]; then
  sleep 20
  for i in $(seq 1 60); do
    st=$(gh run list --workflow build_and_publish.yml --branch main --limit 1 --json status -q '.[0].status' 2>/dev/null || echo completed)
    if [ "$st" = "completed" ] || [ -z "$st" ]; then break; fi
    echo "сборка сайта ещё идёт ($st), жду 30 с"; sleep 30
  done
  want=$(gh run list --workflow build_and_publish.yml --branch main --status success --limit 1 --json headSha -q '.[0].headSha' 2>/dev/null || true)
fi
v=""
for i in $(seq 1 45); do
  v=$(curl -fsS "$site?t=$(date +%s)" || true)
  case "$v" in "${want:0:7}"*) echo "сайт отдаёт $v"; exit 0;; esac
  echo "сайт отдаёт: ${v:-?}, жду ${want:0:7}"; sleep 20
done
echo "SITE_NOTE=сайт отдаёт сборку ${v%% *}, а ждали ${want:0:7}" >> "${GITHUB_ENV:-/dev/null}"
exit 0
