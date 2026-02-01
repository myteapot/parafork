#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

limit="20"
if [[ "${1:-}" == "--limit" ]]; then
  limit="${2:-20}"
  shift 2 || true
fi

if ! parafork_guard_worktree_root "log.sh" "$@"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "log.sh" "$@"

git log --oneline --decorate -n "$limit"

parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "bash \"$SCRIPT_DIR/status.sh\""
