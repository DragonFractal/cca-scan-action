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

echo "== case: scan produced malformed JSON (RC=0) =="
IFS='|' read -r f s st <<<"$(summarize "$FIX/malformed.json" 0)"
assert_eq "malformed -> failed" "$st" "failed"

echo "== case: results file missing (RC=0) =="
IFS='|' read -r f s st <<<"$(summarize "$WORK/does-not-exist.json" 0)"
assert_eq "missing -> failed" "$st" "failed"

if [ "$FAILED" -ne 0 ]; then
  echo "TESTS FAILED"; exit 1
fi
echo "ALL TESTS PASSED"
