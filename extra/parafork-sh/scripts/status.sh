#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

if ! parafork_guard_worktree_root "status.sh" "$@"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
BASE_BRANCH="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
REMOTE_NAME="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || echo "")"
WORKTREE_BRANCH="$(parafork_symbol_get "$symbol_path" "WORKTREE_BRANCH" || echo "")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "status.sh" "$@"

branch="$(git rev-parse --abbrev-ref HEAD)"
head="$(git rev-parse --short HEAD)"
changes="$(git status --porcelain | wc -l | tr -d ' ')"

parafork_print_kv BRANCH "$branch"
parafork_print_kv HEAD "$head"
parafork_print_kv CHANGES "$changes"
parafork_print_kv BASE_BRANCH "$BASE_BRANCH"
parafork_print_kv REMOTE_NAME "$REMOTE_NAME"
parafork_print_kv WORKTREE_BRANCH "$WORKTREE_BRANCH"

parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "bash \"$SCRIPT_DIR/check.sh\" --phase exec"
