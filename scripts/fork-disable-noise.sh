#!/usr/bin/env bash
# Disable all upstream Fleet-Inc-only workflows on the fork.
#
# Keep a small allow-list of workflows that are useful for the fork and
# disable everything else. Safe to re-run — only disables what's currently
# enabled, no-op for already-disabled or missing workflows.
#
# Usage: ./scripts/fork-disable-noise.sh
#
# Requires: gh CLI authenticated with repo:write on this fork.

set -euo pipefail

# Workflows to KEEP enabled. Everything else gets disabled.
# Match by workflow file name (the .yml/.yaml at .github/workflows/).
KEEP=(
  # Custom fork workflows
  "ci-pr.yml"
  "docker-build.yml"
  "sync-upstream.yml"
  "deploy-vps.yml"

  # Useful upstream workflows that work without Fleet Inc secrets
  "codeql-analysis.yml"
  "dependency-review.yml"
  "scorecards-analysis.yml"
)

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
echo "Disabling noise workflows on $REPO"
echo "Keeping enabled: ${KEEP[*]}"
echo

# Fetch all workflows (state: active|disabled_manually|disabled_inactivity)
mapfile -t WORKFLOWS < <(
  gh api "repos/$REPO/actions/workflows" --paginate \
    --jq '.workflows[] | "\(.id)\t\(.state)\t\(.path)"'
)

disabled=0
skipped=0
already=0

for row in "${WORKFLOWS[@]}"; do
  id=$(echo "$row" | cut -f1)
  state=$(echo "$row" | cut -f2)
  path=$(echo "$row" | cut -f3)
  file=$(basename "$path")

  # Skip if in keep-list
  keep_match=false
  for k in "${KEEP[@]}"; do
    if [ "$file" = "$k" ]; then
      keep_match=true
      break
    fi
  done

  if $keep_match; then
    echo "KEEP   $file"
    skipped=$((skipped+1))
    continue
  fi

  if [ "$state" != "active" ]; then
    echo "ALREADY DISABLED  $file"
    already=$((already+1))
    continue
  fi

  if gh api -X PUT "repos/$REPO/actions/workflows/$id/disable" >/dev/null 2>&1; then
    echo "DISABLED  $file"
    disabled=$((disabled+1))
  else
    echo "FAILED    $file (id=$id)"
  fi
done

echo
echo "Summary: $disabled newly disabled, $already already disabled, $skipped kept."
echo
echo "To re-enable a specific workflow later:"
echo "  gh workflow enable <name>"
