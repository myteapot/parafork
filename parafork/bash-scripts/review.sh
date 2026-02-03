#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

if ! parafork_guard_worktree_root "review.sh" "$@"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
BASE_BRANCH="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
WORKTREE_BRANCH="$(parafork_symbol_get "$symbol_path" "WORKTREE_BRANCH" || echo "")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "review.sh" "$@"

echo "### Review material (copy into paradoc/Merge.md)"
echo
echo "#### Commits ($BASE_BRANCH..$WORKTREE_BRANCH)"
git log --oneline "$BASE_BRANCH..$WORKTREE_BRANCH" || true
echo
echo "#### Files ($BASE_BRANCH...$WORKTREE_BRANCH)"
git diff --name-status "$BASE_BRANCH...$WORKTREE_BRANCH" || true
echo
echo "#### Notes"
echo "- Ensure Merge.md contains Acceptance / Repro steps."
echo "- Mention risks and rollback plan if relevant."

parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "edit paradoc/Merge.md then bash \"$SCRIPT_DIR/check.sh\" --phase merge"
