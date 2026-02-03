#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

message=""
no_check="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)
      message="${2:-}"
      shift 2
      ;;
    --no-check)
      no_check="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash <PARAFORK_SCRIPTS>/commit.sh --message "<msg>" [--no-check]
EOF
      exit 0
      ;;
    *)
      parafork_die "unknown arg: $1"
      ;;
  esac
done

if [[ -z "$message" ]]; then
  parafork_die "missing --message"
fi

if ! parafork_guard_worktree_root "commit.sh" --message "<msg>"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "commit.sh" --message "$message"

if [[ "$no_check" != "true" ]]; then
  bash "$SCRIPT_DIR/check.sh" --phase exec
fi

git add -A -- .

if git diff --cached --name-only -- | grep -E '^(paradoc/|\.worktree-symbol$)' >/dev/null; then
  echo "REFUSED: git pollution staged"
  echo "HINT: ensure worktree exclude contains '/paradoc/' and '/.worktree-symbol'"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "unstage pollution and retry: git reset -q && bash \"$SCRIPT_DIR/commit.sh\" --message \"...\""
  exit 1
fi

if git diff --cached --quiet --; then
  echo "REFUSED: nothing staged"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "edit files then retry: bash \"$SCRIPT_DIR/commit.sh\" --message \"...\""
  exit 1
fi

git commit -m "$message"
head="$(git rev-parse --short HEAD)"

parafork_print_kv COMMIT "$head"
parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "bash \"$SCRIPT_DIR/status.sh\""
