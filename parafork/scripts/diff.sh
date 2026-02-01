#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

if ! parafork_guard_worktree_root "diff.sh" "$@"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
BASE_BRANCH="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "diff.sh" "$@"

echo "DIFF_RANGE=$BASE_BRANCH...HEAD"
git diff --stat "$BASE_BRANCH...HEAD" || true
echo
git diff "$BASE_BRANCH...HEAD" || true

parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "bash \"$SCRIPT_DIR/status.sh\""
