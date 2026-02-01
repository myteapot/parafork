#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

yes="false"
iam="false"
no_fetch="false"
allow_drift="false"
message=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      yes="true"
      shift
      ;;
    --i-am-maintainer)
      iam="true"
      shift
      ;;
    --no-fetch)
      no_fetch="true"
      shift
      ;;
    --allow-config-drift)
      allow_drift="true"
      shift
      ;;
    --message)
      message="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash <PARAFORK_SCRIPTS>/merge.sh [options]

Preview-only unless all gates are satisfied:
- local approval: PARAFORK_APPROVE_MERGE=1 or git config parafork.approval.merge=true
- CLI gate: --yes --i-am-maintainer

Options:
  --message "<msg>"         Override merge commit message (squash mode)
  --no-fetch                Skip fetch + remote-base alignment (requires --yes --i-am-maintainer)
  --allow-config-drift       Override session config drift checks (requires --yes --i-am-maintainer)
EOF
      exit 0
      ;;
    *)
      parafork_die "unknown arg: $1"
      ;;
  esac
done

if ! parafork_guard_worktree_root "merge.sh" "$@"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
BASE_ROOT="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || echo "")"
BASE_BRANCH="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
REMOTE_NAME="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || echo "")"
WORKTREE_BRANCH="$(parafork_symbol_get "$symbol_path" "WORKTREE_BRANCH" || echo "")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "merge.sh" "$@"

if [[ -n "$BASE_ROOT" ]]; then
  parafork_check_config_drift "$BASE_ROOT" "$allow_drift" "$yes" "$iam" "$symbol_path"
fi

if [[ -z "$message" ]]; then
  message="parafork: merge $WORKTREE_ID"
fi

remote_available="false"
if [[ -n "$BASE_ROOT" ]] && parafork_is_remote_available "$BASE_ROOT" "$REMOTE_NAME"; then
  remote_available="true"
fi

if [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
  parafork_require_yes_i_am_maintainer_for_flag "--no-fetch" "$yes" "$iam"
fi

approved="false"
if [[ "${PARAFORK_APPROVE_MERGE:-0}" == "1" ]]; then
  approved="true"
elif [[ "$(git -C "$BASE_ROOT" config --bool --default false parafork.approval.merge 2>/dev/null)" == "true" ]]; then
  approved="true"
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ -n "$WORKTREE_BRANCH" && "$current_branch" != "$WORKTREE_BRANCH" ]]; then
  echo "REFUSED: wrong worktree branch"
  parafork_print_kv EXPECTED_WORKTREE_BRANCH "$WORKTREE_BRANCH"
  parafork_print_kv CURRENT_BRANCH "$current_branch"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "checkout correct branch and retry"
  exit 1
  fi

  bash "$SCRIPT_DIR/check.sh" --phase merge

base_tracked_dirty="$(git -C "$BASE_ROOT" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
base_untracked_count="$(git -C "$BASE_ROOT" status --porcelain | awk '/^\\?\\?/ {c++} END {print c+0}')"

if [[ "$base_tracked_dirty" != "0" ]]; then
  echo "REFUSED: base repo not clean (tracked)"
  parafork_print_kv BASE_TRACKED_DIRTY "$base_tracked_dirty"
  parafork_print_kv BASE_UNTRACKED_COUNT "$base_untracked_count"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "clean base repo tracked changes then retry"
  exit 1
fi

base_current_branch="$(git -C "$BASE_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ "$base_current_branch" != "$BASE_BRANCH" ]]; then
  echo "REFUSED: base branch mismatch"
  parafork_print_kv BASE_BRANCH "$BASE_BRANCH"
  parafork_print_kv BASE_CURRENT_BRANCH "$base_current_branch"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "cd \"$BASE_ROOT\" && git checkout \"$BASE_BRANCH\""
  exit 1
fi

if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
  git -C "$BASE_ROOT" fetch "$REMOTE_NAME"
  git -C "$BASE_ROOT" rev-parse --verify "$REMOTE_NAME/$BASE_BRANCH^{commit}" >/dev/null 2>&1 || \
    parafork_die "missing remote base ref: $REMOTE_NAME/$BASE_BRANCH"

  if ! git -C "$BASE_ROOT" merge --ff-only "$REMOTE_NAME/$BASE_BRANCH"; then
    echo "REFUSED: cannot fast-forward base to remote base"
    parafork_print_kv REMOTE_BASE "$REMOTE_NAME/$BASE_BRANCH"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "resolve base/remote divergence manually, then retry"
    exit 1
  fi
elif [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
  echo "WARN: --no-fetch used; merge may target an out-of-date base"
fi

echo "PREVIEW_COMMITS=$BASE_BRANCH..$WORKTREE_BRANCH"
git -C "$BASE_ROOT" log --oneline "$BASE_BRANCH..$WORKTREE_BRANCH" || true

echo "PREVIEW_FILES=$BASE_BRANCH...$WORKTREE_BRANCH"
git -C "$BASE_ROOT" diff --name-status "$BASE_BRANCH...$WORKTREE_BRANCH" || true

if [[ "$approved" != "true" ]]; then
  echo "REFUSED: merge not approved"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "set PARAFORK_APPROVE_MERGE=1 (or git config parafork.approval.merge=true) and rerun"
  exit 1
fi

if [[ "$yes" != "true" || "$iam" != "true" ]]; then
  echo "REFUSED: missing CLI gate"
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "rerun with --yes --i-am-maintainer"
  exit 1
fi

config_path="$(parafork_config_path_from_base "$BASE_ROOT")"
squash="$(parafork_toml_get_bool "$config_path" "control" "squash" "true")"

parafork_print_kv SQUASH "$squash"
parafork_print_kv BASE_UNTRACKED_COUNT "$base_untracked_count"

if [[ "$squash" == "true" ]]; then
  if ! git -C "$BASE_ROOT" merge --squash "$WORKTREE_BRANCH"; then
    echo "REFUSED: squash merge stopped (likely conflicts)"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "resolve conflicts in \"$BASE_ROOT\" then commit (or git -C \"$BASE_ROOT\" merge --abort)"
    exit 1
  fi
  git -C "$BASE_ROOT" commit -m "$message"
else
  if ! git -C "$BASE_ROOT" merge --no-ff "$WORKTREE_BRANCH" -m "$message"; then
    echo "REFUSED: merge stopped (likely conflicts)"
    parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "resolve then git -C \"$BASE_ROOT\" merge --continue (or git -C \"$BASE_ROOT\" merge --abort)"
    exit 1
  fi
fi

  merged_commit="$(git -C "$BASE_ROOT" rev-parse --short HEAD)"
  parafork_print_kv MERGED_COMMIT "$merged_commit"

parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "run acceptance steps in paradoc/Merge.md"
