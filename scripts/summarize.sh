#!/usr/bin/env bash
# Compute the scan outcome (status / findings / savings) from a CCA results file.
#
# Usage: summarize.sh <results_file> <scan_exit_code> [scan_log_file]
#
# Appends findings_count/total_savings/scan_status/scan_error to $GITHUB_OUTPUT when
# set, and prints a human summary. Always exits 0 — the scan status is data, not a
# failure signal (the action decides whether to fail in a later step).
#
# When the scan failed and a log of the CLI's output is given, the CLI's first
# "Error:" / "Fix:" lines are passed through (after stripping colour codes and masking
# credential values) to the scan_error output, the job step summary
# ($GITHUB_STEP_SUMMARY) and the error annotation, so the reason is visible without
# opening the log. Without a log, behaviour is unchanged.
set -euo pipefail

OUT="${1:?results file required}"
RC="${2:-0}"
LOG="${3:-}"

# Credential values that must never reach an output or the summary. Names only here; the
# values come from the environment the scan ran in. Values under 4 characters are skipped.
MASK_VARS="${CCA_MASK_VARS:-CCA_API_KEY AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN}"

# stdin -> stdout: colour codes removed, each masked value replaced by ***. awk reads the
# values through ENVIRON and uses index(), so special characters in a secret are safe.
clean_and_mask() {
  sed -E "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" | MASK_VARS="$MASK_VARS" awk '
    BEGIN { n = split(ENVIRON["MASK_VARS"], names, " ") }
    {
      for (i = 1; i <= n; i++) {
        v = ENVIRON[names[i]]
        if (length(v) >= 4) {
          while ((p = index($0, v)) > 0) $0 = substr($0, 1, p - 1) "***" substr($0, p + length(v))
        }
      }
      print
    }'
}

# The CLI's own diagnosis: its first Error:/Fix: lines, trimmed, at most four.
SCAN_ERROR=""
if [ -n "$LOG" ] && [ -s "$LOG" ]; then
  SCAN_ERROR="$(clean_and_mask < "$LOG" | grep -E '^[[:space:]]*(Error|Fix):' | head -n 4 | sed -E 's/^[[:space:]]+//' || true)"
fi
# One line for the annotation (workflow commands need %, CR and LF escaped).
FIRST_ERROR="$(printf '%s' "$SCAN_ERROR" | head -n 1 | tr -d '\r' | sed -e 's/%/%25/g')"

# Distinguish "scan failed to run" from "scan ran, found nothing" — a nonzero
# exit or missing/invalid JSON means we have no real result and must NOT report
# it as zero findings (that would fail silently).
SCAN_STATUS=ok
if [ "$RC" -ne 0 ]; then
  SCAN_STATUS=failed
  echo "::error title=CCA scan failed::CCA exited $RC — the scan did not complete (check credentials, service-url, and image version).${FIRST_ERROR:+ $FIRST_ERROR}"
elif ! { [ -s "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; }; then
  SCAN_STATUS=failed
  echo "::error title=CCA scan failed::CCA produced no parseable results at $OUT — treating as a failed scan, not zero findings.${FIRST_ERROR:+ $FIRST_ERROR}"
fi

if [ "$SCAN_STATUS" = ok ]; then
  # total_findings includes gated findings on the community tier.
  FINDINGS=$(jq -r '.summary.total_findings // (.findings | length) // 0' "$OUT")
  SAVINGS=$(jq -r '(.summary.total_monthly_savings // 0) * 100 | round / 100' "$OUT")
else
  FINDINGS=0
  SAVINGS=0
fi
SAVINGS=$(printf '%.2f' "$SAVINGS")

# scan_error is only meaningful for a failed scan; it is empty when the scan ran.
[ "$SCAN_STATUS" = ok ] && SCAN_ERROR=""

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "findings_count=$FINDINGS"
    echo "total_savings=$SAVINGS"
    echo "scan_status=$SCAN_STATUS"
    # Multi-line value: a random delimiter so the text can never end the block early.
    DELIM="CCA_ERROR_$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || echo "$$")"
    echo "scan_error<<$DELIM"
    [ -n "$SCAN_ERROR" ] && echo "$SCAN_ERROR"
    echo "$DELIM"
  } >> "$GITHUB_OUTPUT"
fi

if [ "$SCAN_STATUS" = failed ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### CCA scan failed"
    echo
    echo "The scan did not complete (provider: \`${PROVIDER:-aws}\`, image: \`dragonfractal/cca:${VERSION:-latest}\`, exit code $RC)."
    echo
    if [ -n "$SCAN_ERROR" ]; then
      echo "**What the scan reported**"
      echo
      echo '```'
      echo "$SCAN_ERROR"
      echo '```'
    elif [ -n "$LOG" ] && [ -s "$LOG" ]; then
      echo "**What the scan reported.** No \`Error:\` line in its output; the last lines were:"
      echo
      echo '```'
      clean_and_mask < "$LOG" | tail -n 8
      echo '```'
    else
      echo "The scan output was not captured; see this step's log."
    fi
    echo
    echo "**What to do next.** Follow the \`Fix:\` line if one is shown. The full output is in this step's log. If it is not enough, see [When a scan fails](https://github.com/DragonFractal/cca-scan-action#when-a-scan-fails)."
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "=== CCA Scan Summary ==="
echo "  Status: $SCAN_STATUS"
echo "  Findings: $FINDINGS"
echo "  Potential savings: \$$SAVINGS/mo"
