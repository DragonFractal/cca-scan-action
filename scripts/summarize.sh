#!/usr/bin/env bash
# Compute the scan outcome (status / findings / savings) from a CCA results file.
#
# Usage: summarize.sh <results_file> <scan_exit_code>
#
# Appends findings_count/total_savings/scan_status to $GITHUB_OUTPUT when set,
# and prints a human summary. Always exits 0 — the scan status is data, not a
# failure signal (the action decides whether to fail in a later step).
set -euo pipefail

OUT="${1:?results file required}"
RC="${2:-0}"

# Distinguish "scan failed to run" from "scan ran, found nothing" — a nonzero
# exit or missing/invalid JSON means we have no real result and must NOT report
# it as zero findings (that would fail silently).
SCAN_STATUS=ok
if [ "$RC" -ne 0 ]; then
  SCAN_STATUS=failed
  echo "::error title=CCA scan failed::CCA exited $RC — the scan did not complete (check credentials, service-url, and image version)."
elif ! { [ -s "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; }; then
  SCAN_STATUS=failed
  echo "::error title=CCA scan failed::CCA produced no parseable results at $OUT — treating as a failed scan, not zero findings."
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

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "findings_count=$FINDINGS"
    echo "total_savings=$SAVINGS"
    echo "scan_status=$SCAN_STATUS"
  } >> "$GITHUB_OUTPUT"
fi

echo "=== CCA Scan Summary ==="
echo "  Status: $SCAN_STATUS"
echo "  Findings: $FINDINGS"
echo "  Potential savings: \$$SAVINGS/mo"
