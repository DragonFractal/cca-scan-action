#!/usr/bin/env bash
# Exercises the action's output rendering (summarize.sh + render-comment.sh)
# against fixtures — no live scan, no cloud creds. Covers what a consumer sees:
#   - scheduled runs / step outputs  -> findings_count / total_savings / scan_status
#   - PR-comment runs                -> the generated comment markdown
# for the success, zero-findings, and failed-scan cases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
FIX="$ROOT/test/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1"; FAILED=1; }

# Run summarize.sh for a fixture + scan RC; echoes "findings|savings|status".
summarize() {
  local results="$1" rc="$2" out="$WORK/gh_output"
  : > "$out"
  GITHUB_OUTPUT="$out" bash "$SCRIPTS/summarize.sh" "$results" "$rc" >/dev/null 2>&1 || true
  local f s st
  f=$(grep '^findings_count=' "$out" | cut -d= -f2-)
  s=$(grep '^total_savings=' "$out" | cut -d= -f2-)
  st=$(grep '^scan_status=' "$out" | cut -d= -f2-)
  echo "$f|$s|$st"
}

assert_eq() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1 ($2)"; else fail "$1: got '$2', want '$3'"; fi
}
assert_contains() { # <label> <file> <needle>
  if grep -qF "$3" "$2"; then pass "$1"; else fail "$1: '$3' not found in $2"; fi
}
assert_not_contains() { # <label> <file> <needle>
  if grep -qF "$3" "$2"; then fail "$1: '$3' unexpectedly found in $2"; else pass "$1"; fi
}

echo "== case: scan with findings (RC=0) =="
IFS='|' read -r f s st <<<"$(summarize "$FIX/with-findings.json" 0)"
assert_eq "findings_count" "$f" "3"
assert_eq "total_savings"  "$s" "142.50"
assert_eq "scan_status"    "$st" "ok"
bash "$SCRIPTS/render-comment.sh" "$FIX/with-findings.json" "$f" "$s" "$st" "$WORK/c1.md"
assert_contains "comment has marker"        "$WORK/c1.md" "<!-- cca-scan-results -->"
assert_contains "comment has results title" "$WORK/c1.md" "Cloud Cost Analyzer — Scan Results"
assert_contains "comment lists top finding" "$WORK/c1.md" "i-0abc1234567890def"
assert_contains "comment shows savings"     "$WORK/c1.md" "**\$142.50/mo**"
assert_contains "comment has dashboard CTA" "$WORK/c1.md" "See it on your dashboard"
assert_contains "CTA is attributable to this action" "$WORK/c1.md" "utm_source=github_action"

echo "== case: scan ran, zero findings (RC=0) =="
IFS='|' read -r f s st <<<"$(summarize "$FIX/zero-findings.json" 0)"
assert_eq "findings_count" "$f" "0"
assert_eq "total_savings"  "$s" "0.00"
assert_eq "scan_status"    "$st" "ok"
bash "$SCRIPTS/render-comment.sh" "$FIX/zero-findings.json" "$f" "$s" "$st" "$WORK/c2.md"
assert_contains "zero-findings comment is a results comment" "$WORK/c2.md" "Cloud Cost Analyzer — Scan Results"
assert_contains "zero-findings notes no detail" "$WORK/c2.md" "No detailed findings available"

echo "== case: scan exited nonzero (RC=1) =="
IFS='|' read -r f s st <<<"$(summarize "$FIX/with-findings.json" 1)"
assert_eq "findings_count" "$f" "0"
assert_eq "scan_status"    "$st" "failed"
bash "$SCRIPTS/render-comment.sh" "$FIX/with-findings.json" "$f" "$s" "$st" "$WORK/c3.md"
assert_contains "failed comment says Scan Failed" "$WORK/c3.md" "Scan Failed"
assert_not_contains "failed comment has no upsell CTA" "$WORK/c3.md" "utm_source=github_action"

echo "== case: scan produced malformed JSON (RC=0) =="
IFS='|' read -r f s st <<<"$(summarize "$FIX/malformed.json" 0)"
assert_eq "malformed -> failed" "$st" "failed"

echo "== case: results file missing (RC=0) =="
IFS='|' read -r f s st <<<"$(summarize "$WORK/does-not-exist.json" 0)"
assert_eq "missing -> failed" "$st" "failed"

# Run summarize.sh with a scan log; leaves outputs in $WORK/gh_output and the step
# summary in $WORK/summary.md, stdout (annotation + summary) in $WORK/stdout.
summarize_with_log() { # <results> <rc> <log>
  : > "$WORK/gh_output"; : > "$WORK/summary.md"
  GITHUB_OUTPUT="$WORK/gh_output" GITHUB_STEP_SUMMARY="$WORK/summary.md" \
    bash "$SCRIPTS/summarize.sh" "$1" "$2" "$3" > "$WORK/stdout" 2>&1 || true
}

echo "== case: failed scan, CLI Error:/Fix: passed through =="
summarize_with_log "$WORK/does-not-exist.json" 1 "$FIX/scan-failure.log"
assert_contains "output scan_status failed"   "$WORK/gh_output" "scan_status=failed"
assert_contains "output has Error line"       "$WORK/gh_output" "Error: AZURE_SUBSCRIPTION_ID is set to"
assert_contains "output has Fix line"         "$WORK/gh_output" "Fix: correct or unset AZURE_SUBSCRIPTION_ID"
assert_not_contains "output has no colour codes" "$WORK/gh_output" $'\033'
assert_contains "step summary title"          "$WORK/summary.md" "### CCA scan failed"
assert_contains "step summary has Error line" "$WORK/summary.md" "Error: AZURE_SUBSCRIPTION_ID is set to"
assert_contains "step summary has Fix line"   "$WORK/summary.md" "Fix: correct or unset"
assert_contains "step summary says what next" "$WORK/summary.md" "What to do next"
assert_contains "annotation carries the Error" "$WORK/stdout" "::error title=CCA scan failed::CCA exited 1"
assert_contains "annotation includes reason"   "$WORK/stdout" "Error: AZURE_SUBSCRIPTION_ID is set to"

echo "== case: credential values are masked =="
: > "$WORK/gh_output"; : > "$WORK/summary.md"
# shellcheck disable=SC2016  # the dollar sign is literal in this sample secret
CCA_API_KEY="sample-key-ABCDEF123456" AZURE_CLIENT_SECRET='s3cr3t/with+special.chars$1' \
AZURE_SUBSCRIPTION_ID="00000000-1111-2222-3333-444444444444" \
GITHUB_OUTPUT="$WORK/gh_output" GITHUB_STEP_SUMMARY="$WORK/summary.md" \
  bash "$SCRIPTS/summarize.sh" "$WORK/does-not-exist.json" 1 "$FIX/scan-failure-secret.log" > "$WORK/stdout" 2>&1 || true
for f in gh_output summary.md stdout; do
  assert_not_contains "api key masked in $f"       "$WORK/$f" "sample-key-ABCDEF123456"
  # shellcheck disable=SC2016
  assert_not_contains "client secret masked in $f" "$WORK/$f" 's3cr3t/with+special.chars$1'
done
assert_contains "masked marker present" "$WORK/gh_output" "request rejected for key ***"
: > "$WORK/gh_output"; : > "$WORK/summary.md"
AZURE_SUBSCRIPTION_ID="00000000-1111-2222-3333-444444444444" \
GITHUB_OUTPUT="$WORK/gh_output" GITHUB_STEP_SUMMARY="$WORK/summary.md" \
  bash "$SCRIPTS/summarize.sh" "$WORK/does-not-exist.json" 1 "$FIX/scan-failure.log" > "$WORK/stdout" 2>&1 || true
assert_not_contains "subscription id masked in output"  "$WORK/gh_output"  "00000000-1111-2222-3333-444444444444"
assert_not_contains "subscription id masked in summary" "$WORK/summary.md" "00000000-1111-2222-3333-444444444444"
assert_not_contains "subscription id masked in log"     "$WORK/stdout"     "00000000-1111-2222-3333-444444444444"

echo "== case: failed scan, log has no Error: line =="
summarize_with_log "$WORK/does-not-exist.json" 1 "$FIX/scan-failure-no-error.log"
assert_contains "summary shows last lines" "$WORK/summary.md" "segfault-like crash"

echo "== case: failed scan, no log given (old call shape) =="
summarize_with_log "$WORK/does-not-exist.json" 1 ""
assert_contains "summary still written" "$WORK/summary.md" "### CCA scan failed"
assert_contains "summary notes no capture" "$WORK/summary.md" "output was not captured"

echo "== case: successful scan writes no failure summary and empty scan_error =="
summarize_with_log "$FIX/with-findings.json" 0 "$FIX/scan-failure.log"
assert_eq "no step summary on success" "$(wc -c < "$WORK/summary.md" | tr -d ' ')" "0"
assert_not_contains "scan_error empty on success" "$WORK/gh_output" "Error:"
assert_contains "scan_error key present" "$WORK/gh_output" "scan_error<<"

if [ "$FAILED" -ne 0 ]; then
  echo "TESTS FAILED"; exit 1
fi
echo "ALL TESTS PASSED"
