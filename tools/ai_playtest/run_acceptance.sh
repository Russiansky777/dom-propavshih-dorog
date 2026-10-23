#!/usr/bin/env bash
# The acceptance part of a gate or a request: one playtest run per segment of the request (segments.mjs —
# each from its own start point), or one run when the request has none. The report folders of the runs go
# to build/ai_playtest/acceptance_outs.txt (comma-separated) for changed_items.mjs --verdicts.
# Results are committed after each run (commit_results.sh), so a later failure keeps the earlier reports.
# DOC_SHA (gates): the checklist is read as published at that commit; main's copy is put back for each commit,
# so the rebase in commit_results.sh never carries the published text into the working tree.
#   [DOC_SHA=<sha>] tools/ai_playtest/run_acceptance.sh <label> <request.json> <items | ""> <run number>
set -u
label="$1"; req="$2"; items="$3"; runno="$4"
status=0
outs=""
ran=0
mkdir -p build/ai_playtest
doc=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).doc||"")}catch(e){console.log("")}' "$req")

one() {   # one() <console label> <playtest args…>
  local lbl="$1"; shift
  rm -f build/ai_playtest/last_out.txt build/ai_playtest/*/summary.txt
  if [ -n "${DOC_SHA:-}" ] && [ -n "$doc" ]; then git show "$DOC_SHA:$doc" > "$doc" 2>/dev/null || true; fi
  tools/ai_playtest/run_logged.sh "$lbl" --request "$req" --mode acceptance "$@" || status=1
  if [ -n "${DOC_SHA:-}" ] && [ -n "$doc" ]; then git checkout -- "$doc" 2>/dev/null || true; fi
  local out
  out=$(cat build/ai_playtest/last_out.txt 2>/dev/null || true)
  [ -n "$out" ] && [ -f "$out/log.json" ] && outs="${outs:+$outs,}$out"
  tools/ai_playtest/commit_results.sh "$runno" || status=1
  ran=1
}

plan=$(node tools/ai_playtest/segments.mjs "$req" "$items") || status=1
while IFS=$'\t' read -r seg segitems; do
  [ -n "${segitems:-}" ] || continue
  if [ "$seg" = "-" ]; then
    echo "=== $label: пункты $segitems"
    one "$label" --items "$segitems"
  else
    echo "=== $label, часть $((seg + 1)): пункты $segitems"
    one "${label}_s$((seg + 1))" --segment "$seg" --items "$segitems"
  fi
done <<< "$plan"
# nothing to split (a request without items): one run — the report says what was missing
[ "$ran" = 1 ] || one "$label"
echo "$outs" > build/ai_playtest/acceptance_outs.txt
exit $status
