#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

invocation_pwd="$(pwd -P)"
original_args=("$@")

mode="auto" # auto|new|reuse
base_branch_override=""
remote_override=""
no_remote="false"
no_fetch="false"
yes="false"
iam="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new)
      if [[ "$mode" != "auto" && "$mode" != "new" ]]; then
        parafork_die "--new and --reuse are mutually exclusive"
      fi
      mode="new"
      shift
      ;;
    --reuse)
      if [[ "$mode" != "auto" && "$mode" != "reuse" ]]; then
        parafork_die "--new and --reuse are mutually exclusive"
      fi
      mode="reuse"
      shift
      ;;
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
Usage: bash <PARAFORK_SCRIPTS>/init.sh [--new|--reuse] [options]

Entry behavior:
  - In base repo: no args defaults to --new
  - Inside a worktree: no args FAIL (must choose --reuse or --new)

Options:
  --new                    Create a new worktree session
  --reuse                  Mark current worktree as entered (WORKTREE_USED=1)
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

pwd="$(pwd -P)"
symbol_path=""
in_worktree="false"
symbol_worktree_id=""
symbol_worktree_root=""
symbol_base_root=""

if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
  parafork_worktree="$(parafork_symbol_get "$symbol_path" "PARAFORK_WORKTREE" || true)"
  if [[ "$parafork_worktree" != "1" ]]; then
    parafork_print_output_block "UNKNOWN" "$invocation_pwd" "FAIL" "bash \"$SCRIPT_DIR/debug.sh\""
    parafork_die "found .worktree-symbol but not a parafork worktree: $symbol_path"
  fi
  in_worktree="true"
  symbol_worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || true)"
  symbol_worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || true)"
  symbol_base_root="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || true)"
fi

if [[ "$in_worktree" == "true" && "$mode" == "auto" ]]; then
  if [[ -n "$symbol_worktree_root" ]]; then
    parafork_enable_worktree_logging "$symbol_worktree_root" "init.sh" "${original_args[@]}"
  fi
  echo "REFUSED: init.sh called from inside a worktree without --reuse or --new"
  parafork_print_kv SYMBOL_PATH "$symbol_path"
  parafork_print_kv WORKTREE_ID "${symbol_worktree_id:-UNKNOWN}"
  parafork_print_kv WORKTREE_ROOT "$symbol_worktree_root"
  parafork_print_kv BASE_ROOT "$symbol_base_root"
  echo
  echo "Choose one:"
  echo "- Reuse current worktree: bash \"$SCRIPT_DIR/init.sh\" --reuse"
  echo "- Create new worktree:    bash \"$SCRIPT_DIR/init.sh\" --new"
  parafork_print_output_block "${symbol_worktree_id:-UNKNOWN}" "$invocation_pwd" "FAIL" "bash \"$SCRIPT_DIR/init.sh\" --new"
  exit 1
fi

if [[ "$in_worktree" != "true" && "$mode" == "reuse" ]]; then
  parafork_print_output_block "UNKNOWN" "$invocation_pwd" "FAIL" "bash \"$SCRIPT_DIR/debug.sh\""
  parafork_die "--reuse requires being inside an existing parafork worktree"
fi

if [[ "$mode" == "auto" ]]; then
  mode="new"
fi

if [[ "$mode" == "reuse" ]]; then
  if [[ -n "$base_branch_override" || -n "$remote_override" || "$no_remote" == "true" || "$no_fetch" == "true" || "$yes" == "true" || "$iam" == "true" ]]; then
    parafork_die "--reuse cannot be combined with worktree creation options"
  fi

  worktree_id="${symbol_worktree_id:-UNKNOWN}"
  worktree_root="$symbol_worktree_root"
  [[ -n "$worktree_root" ]] || parafork_die "missing WORKTREE_ROOT in .worktree-symbol: $symbol_path"

  parafork_enable_worktree_logging "$worktree_root" "init.sh" "${original_args[@]}"

  parafork_symbol_set "$symbol_path" "WORKTREE_USED" "1"

  echo "MODE=reuse"
  parafork_print_kv WORKTREE_USED "1"
  parafork_print_output_block "$worktree_id" "$invocation_pwd" "PASS" "cd \"$worktree_root\" && bash \"$SCRIPT_DIR/status.sh\""
  exit 0
fi

BASE_ROOT=""
if [[ "$in_worktree" == "true" ]]; then
  BASE_ROOT="$symbol_base_root"
else
  BASE_ROOT="$(parafork_git_toplevel || true)"
fi

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
autoplan="$(parafork_toml_get_bool "$CONFIG_PATH" "custom" "autoplan" "true")"

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

parafork_enable_worktree_logging "$WORKTREE_ROOT" "init.sh" "${original_args[@]}"

cat >"$SYMBOL_PATH" <<EOF
PARAFORK_WORKTREE=1
WORKTREE_ID=$WORKTREE_ID
BASE_ROOT=$BASE_ROOT
WORKTREE_ROOT=$WORKTREE_ROOT
WORKTREE_BRANCH=$WORKTREE_BRANCH
WORKTREE_START_POINT=$WORKTREE_START_POINT
WORKTREE_USED=1
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

for doc in Exec Merge; do
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

if [[ "$autoplan" == "true" ]]; then
  src="$PARAFORK_ROOT/assets/Plan.md"
  dst="$WORKTREE_ROOT/paradoc/Plan.md"
  if [[ ! -f "$src" ]]; then
    parafork_die "missing template: $src"
  fi
  if [[ -f "$dst" ]]; then
    parafork_die "refuse to overwrite: $dst"
  fi
  cp "$src" "$dst"
fi

START_COMMIT="$(git -C "$WORKTREE_ROOT" rev-parse --short HEAD)"
BASE_COMMIT="$(git -C "$BASE_ROOT" rev-parse --short "$WORKTREE_START_POINT")"

echo "MODE=new"
parafork_print_kv AUTOPLAN "$autoplan"
parafork_print_kv WORKTREE_ROOT "$WORKTREE_ROOT"
parafork_print_kv WORKTREE_START_POINT "$WORKTREE_START_POINT"
parafork_print_kv START_COMMIT "$START_COMMIT"
parafork_print_kv BASE_COMMIT "$BASE_COMMIT"
parafork_print_output_block "$WORKTREE_ID" "$invocation_pwd" "PASS" "cd \"$WORKTREE_ROOT\" && bash \"$SCRIPT_DIR/status.sh\""
