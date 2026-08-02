#!/usr/bin/env bash
# Build the PR-comment markdown from a results file + the computed summary.
#
# Usage: render-comment.sh <results_file> <findings> <savings> <scan_status> <dest_md>
#
# Writes the comment body to <dest_md>. Posting it to the PR is the caller's job.
set -euo pipefail

OUT="${1:?results file required}"
FINDINGS="${2:?findings required}"
SAVINGS="${3:?savings required}"
SCAN_STATUS="${4:?scan_status required}"
DEST="${5:?destination markdown path required}"

# Hidden marker so re-runs update this comment instead of stacking new ones.
# Kept as the first line of the body.
MARKER="<!-- cca-scan-results -->"

if [ "$SCAN_STATUS" = "failed" ]; then
  # Be explicit that this is a failed scan, not a clean bill of health.
  {
    echo "$MARKER"
    echo "## Cloud Cost Analyzer — ⚠️ Scan Failed"
    echo ""
    echo "The scan did not complete, so **no cost findings are available** for this PR."
    echo "Check the workflow logs — usually credentials, \`service-url\`, or the image \`version\`."
    echo ""
    echo "---"
    echo "*[Cloud Cost Analyzer](https://cca.dragonfractal.com)*"
  } > "$DEST"
else
  # Top findings table, rendered declaratively from the JSON with jq.
  if [ -s "$OUT" ] && jq -e . "$OUT" >/dev/null 2>&1; then
    TOP=$(jq -r '
      (.findings // []) | sort_by(-(.estimated_monthly_savings // 0)) | .[:10] as $t
      | if ($t | length) == 0 then "No detailed findings available (upgrade for full details)."
        else (
          ["| Severity | Category | Resource | Savings |", "|---|---|---|---|"]
          + ($t | map("| \(.severity // "?") | \(.category // "?") | `\((.resource_id // "?")[0:40])` | $\(((.estimated_monthly_savings // 0) * 100 | round / 100))/mo |"))
        ) | join("\n")
        end
    ' "$OUT")
  else
    TOP="No detailed findings available."
  fi

  {
    echo "$MARKER"
    echo "## Cloud Cost Analyzer — Scan Results"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Findings | **$FINDINGS** |"
    echo "| Potential Savings | **\$$SAVINGS/mo** |"
    echo ""
    echo "### Top Findings"
    echo ""
    echo "$TOP"
    echo ""
    echo "---"
    echo "*Scanned by [Cloud Cost Analyzer](https://cca.dragonfractal.com)*"
  } > "$DEST"
fi
