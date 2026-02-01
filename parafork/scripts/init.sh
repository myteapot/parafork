#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

invocation_pwd="$(pwd -P)"

base_branch_override=""
remote_override=""
no_remote="false"
no_fetch="false"
yes="false"
iam="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-branch)
      base_branch_override="${2:-}"
      shift 2
      ;;
    --remote)
      remote_override="${2:-}"
      shift 2
      ;;
    --no-remote)
      no_remote="true"
      shift
      ;;
    --no-fetch)
      no_fetch="true"
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
Usage: bash <PARAFORK_SCRIPTS>/init.sh [options]

Options:
  --base-branch <branch>   Override base branch for this session (untracked; recorded in .worktree-symbol)
  --remote <name>          Override remote name for this session (untracked; recorded in .worktree-symbol)
  --no-remote              Force REMOTE_NAME empty for this session
  --no-fetch               Skip fetch (requires --yes --i-am-maintainer when remote is available)
  --yes                    Confirmation gate for risky flags
  --i-am-maintainer        Confirmation gate for risky flags
EOF
      exit 0
      ;;
    *)
      parafork_die "unknown arg: $1"
      ;;
  esac
done

BASE_ROOT="$(parafork_git_toplevel || true)"
if [[ -z "$BASE_ROOT" ]]; then
  parafork_print_output_block "UNKNOWN" "$invocation_pwd" "FAIL" "cd <BASE_ROOT> && bash \"$SCRIPT_DIR/init.sh\""
  parafork_die "not in a git repo"
fi

PARAFORK_ROOT="$(parafork_root_dir)"
CONFIG_PATH="$(parafork_config_path_from_base "$BASE_ROOT")"
if [[ ! -f "$CONFIG_PATH" ]]; then
  parafork_die "missing config: $CONFIG_PATH (parafork skill package incomplete?)"
fi

config_base_branch="$(parafork_toml_get_str "$CONFIG_PATH" "base" "branch" "main")"
config_remote_name="$(parafork_toml_get_str "$CONFIG_PATH" "remote" "name" "")"
workdir_root="$(parafork_toml_get_str "$CONFIG_PATH" "workdir" "root" ".parafork")"
workdir_rule="$(parafork_toml_get_str "$CONFIG_PATH" "workdir" "rule" "{YYMMDD}-{HEX4}")"

BASE_BRANCH_SOURCE="config"
BASE_BRANCH="$config_base_branch"
if [[ -n "$base_branch_override" ]]; then
  BASE_BRANCH_SOURCE="cli"
  BASE_BRANCH="$base_branch_override"
fi

REMOTE_NAME_SOURCE="config"
REMOTE_NAME="$config_remote_name"
if [[ "$no_remote" == "true" ]]; then
  REMOTE_NAME_SOURCE="none"
  REMOTE_NAME=""
elif [[ -n "$remote_override" ]]; then
  REMOTE_NAME_SOURCE="cli"
  REMOTE_NAME="$remote_override"
elif [[ -z "$REMOTE_NAME" ]]; then
  REMOTE_NAME_SOURCE="none"
fi

remote_available="false"
if parafork_is_remote_available "$BASE_ROOT" "$REMOTE_NAME"; then
  remote_available="true"
fi

if [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
  parafork_require_yes_i_am_maintainer_for_flag "--no-fetch" "$yes" "$iam"
fi

if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
  git -C "$BASE_ROOT" fetch "$REMOTE_NAME"
fi

WORKTREE_START_POINT="$BASE_BRANCH"
if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
  WORKTREE_START_POINT="$REMOTE_NAME/$BASE_BRANCH"
fi

git -C "$BASE_ROOT" rev-parse --verify "$WORKTREE_START_POINT^{commit}" >/dev/null 2>&1 || \
  parafork_die "invalid WORKTREE_START_POINT: $WORKTREE_START_POINT"

hex4() {
  od -An -N2 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]'
}

expand_rule() {
  local rule="$1"
  local yymmdd
  yymmdd="$(date +%y%m%d)"
  local h
  h="$(hex4)"
  rule="${rule//\{YYMMDD\}/$yymmdd}"
  rule="${rule//\{HEX4\}/$h}"
  echo "$rule"
}

mkdir -p "$BASE_ROOT/$workdir_root"

WORKTREE_ID=""
WORKTREE_ROOT=""

for _i in 1 2 3; do
  candidate="$(expand_rule "$workdir_rule")"
  candidate_root="$BASE_ROOT/$workdir_root/$candidate"
  if [[ -e "$candidate_root" ]]; then
    continue
  fi
  WORKTREE_ID="$candidate"
  WORKTREE_ROOT="$candidate_root"
  break
done

if [[ -z "$WORKTREE_ID" || -z "$WORKTREE_ROOT" ]]; then
  parafork_die "failed to allocate WORKTREE_ID under $BASE_ROOT/$workdir_root (too many collisions)"
fi

WORKTREE_BRANCH="parafork/$WORKTREE_ID"

git -C "$BASE_ROOT" worktree add "$WORKTREE_ROOT" -b "$WORKTREE_BRANCH" "$WORKTREE_START_POINT"

CREATED_AT="$(parafork_now_utc)"
SYMBOL_PATH="$WORKTREE_ROOT/.worktree-symbol"

cat >"$SYMBOL_PATH" <<EOF
PARAFORK_WORKTREE=1
PARAFORK_SPEC_VERSION=13
WORKTREE_ID=$WORKTREE_ID
BASE_ROOT=$BASE_ROOT
WORKTREE_ROOT=$WORKTREE_ROOT
WORKTREE_BRANCH=$WORKTREE_BRANCH
WORKTREE_START_POINT=$WORKTREE_START_POINT
BASE_BRANCH=$BASE_BRANCH
REMOTE_NAME=$REMOTE_NAME
BASE_BRANCH_SOURCE=$BASE_BRANCH_SOURCE
REMOTE_NAME_SOURCE=$REMOTE_NAME_SOURCE
CREATED_AT=$CREATED_AT
EOF

append_unique_line() {
  local file="$1"
  local line="$2"
  touch "$file"
  if grep -Fqx -- "$line" "$file" 2>/dev/null; then
    return 0
  fi
  echo "$line" >>"$file"
}

base_exclude_path="$(parafork_git_path_abs "$BASE_ROOT" "info/exclude")"
append_unique_line "$base_exclude_path" "/$workdir_root/"

worktree_exclude_path="$(parafork_git_path_abs "$WORKTREE_ROOT" "info/exclude")"
append_unique_line "$worktree_exclude_path" "/.worktree-symbol"
append_unique_line "$worktree_exclude_path" "/paradoc/"

mkdir -p "$WORKTREE_ROOT/paradoc"

for doc in Plan Exec Merge; do
  src="$PARAFORK_ROOT/assets/$doc.md"
  dst="$WORKTREE_ROOT/paradoc/$doc.md"
  if [[ ! -f "$src" ]]; then
    parafork_die "missing template: $src"
  fi
  if [[ -f "$dst" ]]; then
    parafork_die "refuse to overwrite: $dst"
  fi
  cp "$src" "$dst"
done

LOG_FILE="$WORKTREE_ROOT/paradoc/Log.txt"
touch "$LOG_FILE"
{
  echo "===== $CREATED_AT init.sh ====="
  echo "WORKTREE_ID=$WORKTREE_ID"
  echo "WORKTREE_ROOT=$WORKTREE_ROOT"
  echo "WORKTREE_BRANCH=$WORKTREE_BRANCH"
  echo "WORKTREE_START_POINT=$WORKTREE_START_POINT"
  echo "BASE_BRANCH=$BASE_BRANCH ($BASE_BRANCH_SOURCE)"
  echo "REMOTE_NAME=$REMOTE_NAME ($REMOTE_NAME_SOURCE)"
  echo
} >>"$LOG_FILE"

START_COMMIT="$(git -C "$WORKTREE_ROOT" rev-parse --short HEAD)"
BASE_COMMIT="$(git -C "$BASE_ROOT" rev-parse --short "$WORKTREE_START_POINT")"

parafork_print_kv WORKTREE_ROOT "$WORKTREE_ROOT"
parafork_print_kv WORKTREE_START_POINT "$WORKTREE_START_POINT"
parafork_print_kv START_COMMIT "$START_COMMIT"
parafork_print_kv BASE_COMMIT "$BASE_COMMIT"
parafork_print_output_block "$WORKTREE_ID" "$invocation_pwd" "PASS" "cd \"$WORKTREE_ROOT\" && bash \"$SCRIPT_DIR/status.sh\""
