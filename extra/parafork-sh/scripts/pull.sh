#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

strategy="ff-only"
no_fetch="false"
allow_drift="false"
yes="false"
iam="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strategy)
      strategy="${2:-}"
      shift 2
      ;;
    --no-fetch)
      no_fetch="true"
      shift
      ;;
    --allow-config-drift)
      allow_drift="true"
      shift
      ;;
    --yes)
      yes="true"
      shift
      ;;
    --i-am-maintainer)
      iam="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash <PARAFORK_SCRIPTS>/pull.sh [options]

Default: ff-only (refuse if not fast-forward)

High-risk strategies require approval + CLI gates:
- rebase: PARAFORK_APPROVE_PULL_REBASE=1 (or git config parafork.approval.pull.rebase=true) + --yes --i-am-maintainer
- merge:  PARAFORK_APPROVE_PULL_MERGE=1  (or git config parafork.approval.pull.merge=true)  + --yes --i-am-maintainer

Options:
  --strategy ff-only|rebase|merge
  --no-fetch                 Skip fetch (requires --yes --i-am-maintainer when remote is available)
  --allow-config-drift        Override session config drift checks (requires --yes --i-am-maintainer)
  --yes --i-am-maintainer     Confirmation gates for risky flags
EOF
      exit 0
      ;;
    *)
      parafork_die "unknown arg: $1"
      ;;
  esac
done

case "$strategy" in
  ff-only|rebase|merge) ;;
  *) parafork_die "invalid --strategy: $strategy" ;;
esac

if ! parafork_guard_worktree_root "pull.sh" "$@"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
BASE_ROOT="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || echo "")"
BASE_BRANCH="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
REMOTE_NAME="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || echo "")"
REMOTE_NAME_SOURCE="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME_SOURCE" || echo "")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "pull.sh" --strategy "$strategy"

if [[ -n "$BASE_ROOT" ]]; then
  parafork_check_config_drift "$BASE_ROOT" "$allow_drift" "$yes" "$iam" "$symbol_path"
fi

remote_available="false"
if [[ -n "$BASE_ROOT" ]] && parafork_is_remote_available "$BASE_ROOT" "$REMOTE_NAME"; then
  remote_available="true"
fi

if [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
  parafork_require_yes_i_am_maintainer_for_flag "--no-fetch" "$yes" "$iam"
fi

upstream="$BASE_BRANCH"
if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
  git -C "$BASE_ROOT" fetch "$REMOTE_NAME"
  upstream="$REMOTE_NAME/$BASE_BRANCH"
fi

parafork_print_kv STRATEGY "$strategy"
parafork_print_kv UPSTREAM "$upstream"

approve_rebase="false"
if [[ "${PARAFORK_APPROVE_PULL_REBASE:-0}" == "1" ]] || [[ "$(git -C "$BASE_ROOT" config --bool --default false parafork.approval.pull.rebase 2>/dev/null)" == "true" ]]; then
  approve_rebase="true"
fi

approve_merge="false"
if [[ "${PARAFORK_APPROVE_PULL_MERGE:-0}" == "1" ]] || [[ "$(git -C "$BASE_ROOT" config --bool --default false parafork.approval.pull.merge 2>/dev/null)" == "true" ]]; then
  approve_merge="true"
fi

if [[ "$strategy" == "rebase" ]]; then
  if [[ "$approve_rebase" != "true" ]]; then
    echo "REFUSED: pull rebase not approved"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "ask maintainer then rerun with PARAFORK_APPROVE_PULL_REBASE=1 and --yes --i-am-maintainer"
    exit 1
  fi
  parafork_require_yes_i_am_maintainer_for_flag "--strategy rebase" "$yes" "$iam"
  if ! git rebase "$upstream"; then
    echo "REFUSED: rebase stopped (likely conflicts)"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "resolve then git rebase --continue (or git rebase --abort)"
    exit 1
  fi
elif [[ "$strategy" == "merge" ]]; then
  if [[ "$approve_merge" != "true" ]]; then
    echo "REFUSED: pull merge not approved"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "ask maintainer then rerun with PARAFORK_APPROVE_PULL_MERGE=1 and --yes --i-am-maintainer"
    exit 1
  fi
  parafork_require_yes_i_am_maintainer_for_flag "--strategy merge" "$yes" "$iam"
  if ! git merge --no-ff "$upstream"; then
    echo "REFUSED: merge stopped (likely conflicts)"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "resolve then git merge --continue (or git merge --abort)"
    exit 1
  fi
else
  if ! git merge --ff-only "$upstream"; then
    echo "REFUSED: cannot fast-forward"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "ask maintainer to approve rebase/merge strategy"
    exit 1
  fi
fi

  parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "bash \"$SCRIPT_DIR/status.sh\""
