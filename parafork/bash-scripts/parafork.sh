#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

INVOCATION_PWD="$(pwd -P)"
ENTRY_CMD="bash \"$SCRIPT_DIR/parafork.sh\""

parafork_fallback_output_block() {
  local code="$1"
  if [[ "$code" -ne 0 && "${PARAFORK_OUTPUT_BLOCK_PRINTED:-0}" != "1" ]]; then
    parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "FAIL" "$ENTRY_CMD debug"
  fi
}

trap 'parafork_fallback_output_block $?' EXIT

parafork_usage() {
  cat <<EOF

Parafork — safe worktree contribution workflow (single entry)

Usage:
  $ENTRY_CMD [cmd] [args...]

Commands:
  help
  debug
  init [--new|--reuse] [--base-branch <branch>] [--remote <name>] [--no-remote] [--no-fetch] [--yes] [--i-am-maintainer]
  watch [--once] [--interval <sec>] [--phase exec|merge] [--new]

  status
  check --phase plan|exec|merge [--strict]
  commit --message "<msg>" [--no-check]
  pull [--strategy ff-only|rebase|merge] [--no-fetch] [--allow-config-drift] [--yes] [--i-am-maintainer]
  diff
  log [--limit <n>]
  review
  merge [--message "<msg>"] [--no-fetch] [--allow-config-drift] [--yes] [--i-am-maintainer]

Notes:
  - Default (no cmd): watch
  - watch does not auto-commit/merge; it only prints NEXT when safe.
EOF
}

cmd_help() {
  parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "PASS" "$ENTRY_CMD watch"
  parafork_usage
}

cmd_debug() {
  local pwd
  pwd="$(pwd -P)"

  local symbol_path=""
  if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
    local worktree_id worktree_root
    worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
    worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "")"

    if [[ -n "$worktree_root" ]]; then
      debug_body() {
        parafork_print_kv SYMBOL_PATH "$symbol_path"
        parafork_print_output_block "$worktree_id" "$INVOCATION_PWD" "PASS" "$ENTRY_CMD watch"
      }
      parafork_invoke_logged "$worktree_root" "parafork debug" "$ENTRY_CMD debug" -- debug_body
      return 0
    fi

    parafork_print_kv SYMBOL_PATH "$symbol_path"
    parafork_print_output_block "$worktree_id" "$INVOCATION_PWD" "PASS" "$ENTRY_CMD watch"
    return 0
  fi

  local base_root=""
  base_root="$(parafork_git_toplevel || true)"
  if [[ -z "$base_root" ]]; then
    parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "FAIL" "$ENTRY_CMD help"
    parafork_die "not in a git repo and no .worktree-symbol found"
  fi

  local container
  container="$(parafork_worktree_container "$base_root")"
  if [[ ! -d "$container" ]]; then
    parafork_print_kv BASE_ROOT "$base_root"
    parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "PASS" "$ENTRY_CMD init --new"
    echo
    echo "No worktree container found at: $container"
    return 0
  fi

  local -a roots=()
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    roots+=("$d")
  done < <(parafork_list_worktrees_newest_first "$base_root")

  if [[ "${#roots[@]}" -eq 0 ]]; then
    parafork_print_kv BASE_ROOT "$base_root"
    parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "PASS" "$ENTRY_CMD init --new"
    echo
    echo "No worktrees found under: $container"
    return 0
  fi

  echo "Found worktrees (newest first):"
  for d in "${roots[@]}"; do
    local id
    id="$(parafork_symbol_get "$d/.worktree-symbol" "WORKTREE_ID" || echo "UNKNOWN")"
    echo "- $id  $d"
  done

  local chosen="${roots[0]}"
  local chosen_id
  chosen_id="$(parafork_symbol_get "$chosen/.worktree-symbol" "WORKTREE_ID" || echo "UNKNOWN")"

  parafork_print_kv BASE_ROOT "$base_root"
  parafork_print_output_block "$chosen_id" "$INVOCATION_PWD" "PASS" "cd \"$chosen\" && $ENTRY_CMD init --reuse"
}

cmd_init() {
  local invocation_pwd="$INVOCATION_PWD"
  local original_args=("$@")

  local mode="auto" # auto|new|reuse
  local base_branch_override=""
  local remote_override=""
  local no_remote="false"
  local no_fetch="false"
  local yes="false"
  local iam="false"

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
        cat <<EOF
Usage: $ENTRY_CMD init [--new|--reuse] [options]

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

  local pwd
  pwd="$(pwd -P)"
  local symbol_path=""
  local in_worktree="false"
  local symbol_worktree_id=""
  local symbol_worktree_root=""
  local symbol_base_root=""

  if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
    local parafork_worktree
    parafork_worktree="$(parafork_symbol_get "$symbol_path" "PARAFORK_WORKTREE" || true)"
    if [[ "$parafork_worktree" != "1" ]]; then
      parafork_print_output_block "UNKNOWN" "$invocation_pwd" "FAIL" "$ENTRY_CMD debug"
      parafork_die "found .worktree-symbol but not a parafork worktree: $symbol_path"
    fi
    in_worktree="true"
    symbol_worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || true)"
    symbol_worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || true)"
    symbol_base_root="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || true)"
  fi

  if [[ "$in_worktree" == "true" && "$mode" == "auto" ]]; then
    local wt_id="${symbol_worktree_id:-UNKNOWN}"
    echo "REFUSED: init called from inside a worktree without --reuse or --new"
    parafork_print_kv SYMBOL_PATH "$symbol_path"
    parafork_print_kv WORKTREE_ID "$wt_id"
    parafork_print_kv WORKTREE_ROOT "$symbol_worktree_root"
    parafork_print_kv BASE_ROOT "$symbol_base_root"
    echo
    echo "Choose one:"
    echo "- Reuse current worktree: $ENTRY_CMD init --reuse"
    echo "- Create new worktree:    $ENTRY_CMD init --new"
    parafork_print_output_block "$wt_id" "$invocation_pwd" "FAIL" "$ENTRY_CMD init --new"
    return 1
  fi

  if [[ "$in_worktree" != "true" && "$mode" == "reuse" ]]; then
    parafork_print_output_block "UNKNOWN" "$invocation_pwd" "FAIL" "$ENTRY_CMD debug"
    parafork_die "--reuse requires being inside an existing parafork worktree"
  fi

  if [[ "$mode" == "auto" ]]; then
    mode="new"
  fi

  if [[ "$mode" == "reuse" ]]; then
    if [[ -n "$base_branch_override" || -n "$remote_override" || "$no_remote" == "true" || "$no_fetch" == "true" || "$yes" == "true" || "$iam" == "true" ]]; then
      parafork_die "--reuse cannot be combined with worktree creation options"
    fi

    local worktree_id worktree_root
    worktree_id="${symbol_worktree_id:-UNKNOWN}"
    worktree_root="$symbol_worktree_root"
    [[ -n "$worktree_root" ]] || parafork_die "missing WORKTREE_ROOT in .worktree-symbol: $symbol_path"

    parafork_symbol_set "$symbol_path" "WORKTREE_USED" "1"

    init_reuse_body() {
      echo "MODE=reuse"
      parafork_print_kv WORKTREE_USED "1"
      parafork_print_output_block "$worktree_id" "$invocation_pwd" "PASS" "cd \"$worktree_root\" && $ENTRY_CMD status"
    }

    parafork_invoke_logged "$worktree_root" "parafork init" "$ENTRY_CMD init --reuse" -- init_reuse_body
    return 0
  fi

  local base_root=""
  if [[ "$in_worktree" == "true" ]]; then
    base_root="$symbol_base_root"
  else
    base_root="$(parafork_git_toplevel || true)"
  fi

  if [[ -z "$base_root" ]]; then
    parafork_print_output_block "UNKNOWN" "$invocation_pwd" "FAIL" "cd <BASE_ROOT> && $ENTRY_CMD init --new"
    parafork_die "not in a git repo"
  fi

  local config_path
  config_path="$(parafork_config_path_from_base "$base_root")"
  if [[ ! -f "$config_path" ]]; then
    parafork_die "missing config: $config_path (parafork skill package incomplete?)"
  fi

  local config_base_branch config_remote_name workdir_root workdir_rule autoplan
  config_base_branch="$(parafork_toml_get_str "$config_path" "base" "branch" "main")"
  config_remote_name="$(parafork_toml_get_str "$config_path" "remote" "name" "")"
  workdir_root="$(parafork_toml_get_str "$config_path" "workdir" "root" ".parafork")"
  workdir_rule="$(parafork_toml_get_str "$config_path" "workdir" "rule" "{YYMMDD}-{HEX4}")"
  autoplan="$(parafork_toml_get_bool "$config_path" "custom" "autoplan" "true")"

  local base_branch_source="config"
  local base_branch="$config_base_branch"
  if [[ -n "$base_branch_override" ]]; then
    base_branch_source="cli"
    base_branch="$base_branch_override"
  fi

  local remote_name_source="config"
  local remote_name="$config_remote_name"
  if [[ "$no_remote" == "true" ]]; then
    remote_name_source="none"
    remote_name=""
  elif [[ -n "$remote_override" ]]; then
    remote_name_source="cli"
    remote_name="$remote_override"
  elif [[ -z "$remote_name" ]]; then
    remote_name_source="none"
  fi

  mkdir -p "$base_root/$workdir_root"

  local remote_available="false"
  if parafork_is_remote_available "$base_root" "$remote_name"; then
    remote_available="true"
  fi

  if [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
    parafork_require_yes_i_am_maintainer_for_flag "--no-fetch" "$yes" "$iam"
  fi

  if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
    git -C "$base_root" fetch "$remote_name"
  fi

  local worktree_start_point="$base_branch"
  if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
    worktree_start_point="$remote_name/$base_branch"
  fi

  git -C "$base_root" rev-parse --verify "$worktree_start_point^{commit}" >/dev/null 2>&1 || \
    parafork_die "invalid WORKTREE_START_POINT: $worktree_start_point"

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

  local worktree_id="" worktree_root=""
  for _i in 1 2 3; do
    local candidate candidate_root
    candidate="$(expand_rule "$workdir_rule")"
    candidate_root="$base_root/$workdir_root/$candidate"
    if [[ -e "$candidate_root" ]]; then
      continue
    fi
    worktree_id="$candidate"
    worktree_root="$candidate_root"
    break
  done

  if [[ -z "$worktree_id" || -z "$worktree_root" ]]; then
    parafork_die "failed to allocate WORKTREE_ID under $base_root/$workdir_root (too many collisions)"
  fi

  local worktree_branch="parafork/$worktree_id"

  git -C "$base_root" worktree add "$worktree_root" -b "$worktree_branch" "$worktree_start_point"

  local created_at
  created_at="$(parafork_now_utc)"
  local symbol_path_new="$worktree_root/.worktree-symbol"

  cat >"$symbol_path_new" <<EOF
PARAFORK_WORKTREE=1
WORKTREE_ID=$worktree_id
BASE_ROOT=$base_root
WORKTREE_ROOT=$worktree_root
WORKTREE_BRANCH=$worktree_branch
WORKTREE_START_POINT=$worktree_start_point
WORKTREE_USED=1
BASE_BRANCH=$base_branch
REMOTE_NAME=$remote_name
BASE_BRANCH_SOURCE=$base_branch_source
REMOTE_NAME_SOURCE=$remote_name_source
CREATED_AT=$created_at
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

  local base_exclude_path worktree_exclude_path
  base_exclude_path="$(parafork_git_path_abs "$base_root" "info/exclude")"
  append_unique_line "$base_exclude_path" "/$workdir_root/"

  worktree_exclude_path="$(parafork_git_path_abs "$worktree_root" "info/exclude")"
  append_unique_line "$worktree_exclude_path" "/.worktree-symbol"
  append_unique_line "$worktree_exclude_path" "/paradoc/"

  mkdir -p "$worktree_root/paradoc"

  local parafork_root
  parafork_root="$(parafork_root_dir)"
  for doc in Exec Merge; do
    local src dst
    src="$parafork_root/assets/$doc.md"
    dst="$worktree_root/paradoc/$doc.md"
    [[ -f "$src" ]] || parafork_die "missing template: $src"
    [[ ! -f "$dst" ]] || parafork_die "refuse to overwrite: $dst"
    cp "$src" "$dst"
  done

  if [[ "$autoplan" == "true" ]]; then
    local src dst
    src="$parafork_root/assets/Plan.md"
    dst="$worktree_root/paradoc/Plan.md"
    [[ -f "$src" ]] || parafork_die "missing template: $src"
    [[ ! -f "$dst" ]] || parafork_die "refuse to overwrite: $dst"
    cp "$src" "$dst"
  fi

  local start_commit base_commit
  start_commit="$(git -C "$worktree_root" rev-parse --short HEAD)"
  base_commit="$(git -C "$base_root" rev-parse --short "$worktree_start_point")"

  echo "MODE=new"
  parafork_print_kv AUTOPLAN "$autoplan"
  parafork_print_kv WORKTREE_ROOT "$worktree_root"
  parafork_print_kv WORKTREE_START_POINT "$worktree_start_point"
  parafork_print_kv START_COMMIT "$start_commit"
  parafork_print_kv BASE_COMMIT "$base_commit"
  parafork_print_output_block "$worktree_id" "$invocation_pwd" "PASS" "cd \"$worktree_root\" && $ENTRY_CMD status"
}

do_status() {
  local print_block="$1"
  shift || true

  local pwd
  pwd="$(pwd -P)"
  local symbol_path="$pwd/.worktree-symbol"

  local worktree_id worktree_root base_branch remote_name worktree_branch
  worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
  worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
  base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
  remote_name="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || echo "")"
  worktree_branch="$(parafork_symbol_get "$symbol_path" "WORKTREE_BRANCH" || echo "")"

  local branch head changes
  branch="$(git rev-parse --abbrev-ref HEAD)"
  head="$(git rev-parse --short HEAD)"
  changes="$(git status --porcelain | wc -l | tr -d ' ')"

  parafork_print_kv BRANCH "$branch"
  parafork_print_kv HEAD "$head"
  parafork_print_kv CHANGES "$changes"
  parafork_print_kv BASE_BRANCH "$base_branch"
  parafork_print_kv REMOTE_NAME "$remote_name"
  parafork_print_kv WORKTREE_BRANCH "$worktree_branch"

  if [[ "$print_block" == "true" ]]; then
    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$ENTRY_CMD check --phase exec"
  fi
}

cmd_status() {
  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"
  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork status" "$ENTRY_CMD status" -- do_status "true"
}

do_check() {
  local phase="$1"
  local strict="$2" # true|false
  local mode="$3"   # cli|watch

  local pwd
  pwd="$(pwd -P)"
  local symbol_path="$pwd/.worktree-symbol"

  local worktree_id worktree_root base_root
  worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
  worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
  base_root="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || echo "")"

  local errors=()

  local plan_file="$worktree_root/paradoc/Plan.md"
  local exec_file="$worktree_root/paradoc/Exec.md"
  local merge_file="$worktree_root/paradoc/Merge.md"
  local log_file="$worktree_root/paradoc/Log.txt"

  local config_path="" autoformat="true" autoplan="true"
  if [[ -n "$base_root" ]]; then
    config_path="$(parafork_config_path_from_base "$base_root")"
  fi
  if [[ -n "$config_path" && -f "$config_path" ]]; then
    autoformat="$(parafork_toml_get_bool "$config_path" "custom" "autoformat" "true")"
    autoplan="$(parafork_toml_get_bool "$config_path" "custom" "autoplan" "true")"
  fi
  if [[ "$strict" == "true" ]]; then
    autoformat="true"
    autoplan="true"
  fi

  local -a required_files=("$exec_file" "$merge_file" "$log_file")
  if [[ "$autoplan" == "true" ]]; then
    required_files+=("$plan_file")
  fi

  local f
  for f in "${required_files[@]}"; do
    if [[ ! -f "$f" ]]; then
      errors+=("missing file: $f")
    fi
  done

  if [[ -f "$plan_file" && "$autoplan" == "true" && "$autoformat" == "true" ]]; then
    grep -Fq "## Milestones" "$plan_file" || errors+=("Plan.md missing heading: ## Milestones")
    grep -Fq "## Tasks" "$plan_file" || errors+=("Plan.md missing heading: ## Tasks")
    grep -Eq '^- \[.\] ' "$plan_file" || errors+=("Plan.md has no checkboxes")

    if [[ "$phase" == "merge" ]]; then
      if grep -Eq '^- \[ \] T[0-9]+' "$plan_file"; then
        errors+=("Plan.md has incomplete tasks (merge phase requires tasks done)")
      fi
    fi
  fi

  if [[ -f "$merge_file" && "$autoformat" == "true" ]]; then
    if ! grep -Ei 'Acceptance|Repro' "$merge_file" >/dev/null; then
      errors+=("Merge.md missing Acceptance/Repro section keywords")
    fi
  fi

  if [[ "$phase" == "merge" || "$strict" == "true" ]]; then
    for f in "$exec_file" "$merge_file"; do
      if [[ -f "$f" ]] && grep -Eq 'PARAFORK_TBD|TODO_TBD' "$f"; then
        errors+=("placeholder remains: $f")
      fi
    done

    if [[ "$autoplan" == "true" && -f "$plan_file" ]] && grep -Eq 'PARAFORK_TBD|TODO_TBD' "$plan_file"; then
      errors+=("placeholder remains: $plan_file")
    fi
  fi

  if [[ "$phase" == "merge" ]]; then
    if git ls-files -- 'paradoc/' | grep -q .; then
      errors+=("git pollution: tracked files under paradoc/ (must be empty: git ls-files -- 'paradoc/')")
    fi
    if git ls-files -- '.worktree-symbol' | grep -q .; then
      errors+=("git pollution: .worktree-symbol is tracked (must be empty: git ls-files -- '.worktree-symbol')")
    fi
    if git diff --cached --name-only -- | grep -E '^(paradoc/|\.worktree-symbol$)' >/dev/null; then
      errors+=("git pollution: staged includes paradoc/ or .worktree-symbol")
    fi
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    echo "CHECK_RESULT=FAIL"
    local e
    for e in "${errors[@]}"; do
      echo "FAIL: $e"
    done
    if [[ "$mode" == "cli" ]]; then
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "fix issues and rerun: $ENTRY_CMD check --phase $phase"
    fi
    return 1
  fi

  if [[ "$mode" == "cli" ]]; then
    echo "CHECK_RESULT=PASS"
    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$ENTRY_CMD status"
  fi
  return 0
}

do_review() {
  local print_block="$1"
  shift || true

  local pwd symbol_path worktree_id base_branch worktree_branch
  pwd="$(pwd -P)"
  symbol_path="$pwd/.worktree-symbol"
  worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
  base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
  worktree_branch="$(parafork_symbol_get "$symbol_path" "WORKTREE_BRANCH" || echo "")"

  echo "### Review material (copy into paradoc/Merge.md)"
  echo
  echo "#### Commits ($base_branch..$worktree_branch)"
  git log --oneline "$base_branch..$worktree_branch" || true
  echo
  echo "#### Files ($base_branch...$worktree_branch)"
  git diff --name-status "$base_branch...$worktree_branch" || true
  echo
  echo "#### Notes"
  echo "- Ensure Merge.md contains Acceptance / Repro steps."
  echo "- Mention risks and rollback plan if relevant."

  if [[ "$print_block" == "true" ]]; then
    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "edit paradoc/Merge.md then $ENTRY_CMD check --phase merge"
  fi
}

cmd_check() {
  local phase="merge"
  local strict="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --phase)
        phase="${2:-}"
        shift 2
        ;;
      --strict)
        strict="true"
        shift
        ;;
      -h|--help)
        cat <<EOF
Usage: $ENTRY_CMD check [--phase plan|exec|merge] [--strict]
EOF
        exit 0
        ;;
      *)
        parafork_die "unknown arg: $1"
        ;;
    esac
  done

  case "$phase" in
    plan|exec|merge) ;;
    *) parafork_die "invalid --phase: $phase" ;;
  esac

  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"
  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork check" "$ENTRY_CMD check --phase $phase" -- do_check "$phase" "$strict" "cli"
}

cmd_commit() {
  local message=""
  local no_check="false"

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
        cat <<EOF
Usage: $ENTRY_CMD commit --message "<msg>" [--no-check]
EOF
        exit 0
        ;;
      *)
        parafork_die "unknown arg: $1"
        ;;
    esac
  done

  [[ -n "$message" ]] || parafork_die "missing --message"

  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  local worktree_id="$PARAFORK_WORKTREE_ID"
  local pwd
  pwd="$(pwd -P)"

  commit_body() {
    if [[ "$no_check" != "true" ]]; then
      do_check "exec" "false" "cli"
    fi

    git add -A -- .

    if git diff --cached --name-only -- | grep -E '^(paradoc/|\.worktree-symbol$)' >/dev/null; then
      echo "REFUSED: git pollution staged"
      echo "HINT: ensure worktree exclude contains '/paradoc/' and '/.worktree-symbol'"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "unstage pollution and retry: git reset -q && $ENTRY_CMD commit --message \"...\""
      return 1
    fi

    if git diff --cached --quiet --; then
      echo "REFUSED: nothing staged"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "edit files then retry: $ENTRY_CMD commit --message \"...\""
      return 1
    fi

    git commit -m "$message"
    local head
    head="$(git rev-parse --short HEAD)"
    parafork_print_kv COMMIT "$head"
    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$ENTRY_CMD status"
  }

  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork commit" "$ENTRY_CMD commit --message \"...\"" -- commit_body
}

cmd_pull() {
  local strategy="ff-only"
  local no_fetch="false"
  local allow_drift="false"
  local yes="false"
  local iam="false"

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
        cat <<EOF
Usage: $ENTRY_CMD pull [options]

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

  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  pull_body() {
    local pwd worktree_id symbol_path worktree_root base_root base_branch remote_name
    pwd="$(pwd -P)"
    symbol_path="$pwd/.worktree-symbol"
    worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
    worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
    base_root="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || echo "")"
    base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
    remote_name="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || echo "")"

    if [[ -n "$base_root" ]]; then
      parafork_check_config_drift "$base_root" "$allow_drift" "$yes" "$iam" "$symbol_path"
    fi

    local remote_available="false"
    if [[ -n "$base_root" ]] && parafork_is_remote_available "$base_root" "$remote_name"; then
      remote_available="true"
    fi
    if [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
      parafork_require_yes_i_am_maintainer_for_flag "--no-fetch" "$yes" "$iam"
    fi

    local upstream="$base_branch"
    if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
      git -C "$base_root" fetch "$remote_name"
      upstream="$remote_name/$base_branch"
    fi

    parafork_print_kv STRATEGY "$strategy"
    parafork_print_kv UPSTREAM "$upstream"

    local approve_rebase="false"
    if [[ "${PARAFORK_APPROVE_PULL_REBASE:-0}" == "1" ]] || [[ "$(git -C "$base_root" config --bool --default false parafork.approval.pull.rebase 2>/dev/null)" == "true" ]]; then
      approve_rebase="true"
    fi

    local approve_merge="false"
    if [[ "${PARAFORK_APPROVE_PULL_MERGE:-0}" == "1" ]] || [[ "$(git -C "$base_root" config --bool --default false parafork.approval.pull.merge 2>/dev/null)" == "true" ]]; then
      approve_merge="true"
    fi

    if [[ "$strategy" == "rebase" ]]; then
      if [[ "$approve_rebase" != "true" ]]; then
        echo "REFUSED: pull rebase not approved"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "ask maintainer then rerun with PARAFORK_APPROVE_PULL_REBASE=1 and --yes --i-am-maintainer"
        return 1
      fi
      parafork_require_yes_i_am_maintainer_for_flag "--strategy rebase" "$yes" "$iam"
      if ! git rebase "$upstream"; then
        echo "REFUSED: rebase stopped (likely conflicts)"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "resolve then git rebase --continue (or git rebase --abort)"
        return 1
      fi
    elif [[ "$strategy" == "merge" ]]; then
      if [[ "$approve_merge" != "true" ]]; then
        echo "REFUSED: pull merge not approved"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "ask maintainer then rerun with PARAFORK_APPROVE_PULL_MERGE=1 and --yes --i-am-maintainer"
        return 1
      fi
      parafork_require_yes_i_am_maintainer_for_flag "--strategy merge" "$yes" "$iam"
      if ! git merge --no-ff "$upstream"; then
        echo "REFUSED: merge stopped (likely conflicts)"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "resolve then git merge --continue (or git merge --abort)"
        return 1
      fi
    else
      if ! git merge --ff-only "$upstream"; then
        echo "REFUSED: cannot fast-forward"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "ask maintainer to approve rebase/merge strategy"
        return 1
      fi
    fi

    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$ENTRY_CMD status"
  }

  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork pull" "$ENTRY_CMD pull --strategy $strategy" -- pull_body
}

cmd_diff() {
  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  diff_body() {
    local pwd symbol_path worktree_id base_branch
    pwd="$(pwd -P)"
    symbol_path="$pwd/.worktree-symbol"
    worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
    base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"

    echo "DIFF_RANGE=$base_branch...HEAD"
    git diff --stat "$base_branch...HEAD" || true
    echo
    git diff "$base_branch...HEAD" || true

    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$ENTRY_CMD status"
  }

  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork diff" "$ENTRY_CMD diff" -- diff_body
}

cmd_log() {
  local limit="20"
  if [[ "${1:-}" == "--limit" ]]; then
    limit="${2:-20}"
    shift 2 || true
  fi

  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  log_body() {
    local pwd symbol_path worktree_id
    pwd="$(pwd -P)"
    symbol_path="$pwd/.worktree-symbol"
    worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"

    git log --oneline --decorate -n "$limit"
    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$ENTRY_CMD status"
  }

  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork log" "$ENTRY_CMD log --limit $limit" -- log_body
}

cmd_review() {
  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork review" "$ENTRY_CMD review" -- do_review "true"
}

cmd_merge() {
  local yes="false"
  local iam="false"
  local no_fetch="false"
  local allow_drift="false"
  local message=""

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
        cat <<EOF
Usage: $ENTRY_CMD merge [options]

Preview-only unless all gates are satisfied:
- local approval: PARAFORK_APPROVE_MERGE=1 or git config parafork.approval.merge=true
- CLI gate: --yes --i-am-maintainer

Options:
  --message "<msg>"          Override merge commit message (squash mode)
  --no-fetch                 Skip fetch + remote-base alignment (requires --yes --i-am-maintainer)
  --allow-config-drift        Override session config drift checks (requires --yes --i-am-maintainer)
EOF
        exit 0
        ;;
      *)
        parafork_die "unknown arg: $1"
        ;;
    esac
  done

  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  merge_body() {
    local pwd symbol_path worktree_id worktree_root base_root base_branch remote_name worktree_branch
    pwd="$(pwd -P)"
    symbol_path="$pwd/.worktree-symbol"
    worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
    worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
    base_root="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || echo "")"
    base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || echo "")"
    remote_name="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || echo "")"
    worktree_branch="$(parafork_symbol_get "$symbol_path" "WORKTREE_BRANCH" || echo "")"

    if [[ -n "$base_root" ]]; then
      parafork_check_config_drift "$base_root" "$allow_drift" "$yes" "$iam" "$symbol_path"
    fi

    if [[ -z "$message" ]]; then
      message="parafork: merge $worktree_id"
    fi

    local remote_available="false"
    if [[ -n "$base_root" ]] && parafork_is_remote_available "$base_root" "$remote_name"; then
      remote_available="true"
    fi
    if [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
      parafork_require_yes_i_am_maintainer_for_flag "--no-fetch" "$yes" "$iam"
    fi

    local approved="false"
    if [[ "${PARAFORK_APPROVE_MERGE:-0}" == "1" ]]; then
      approved="true"
    elif [[ "$(git -C "$base_root" config --bool --default false parafork.approval.merge 2>/dev/null)" == "true" ]]; then
      approved="true"
    fi

    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ -n "$worktree_branch" && "$current_branch" != "$worktree_branch" ]]; then
      echo "REFUSED: wrong worktree branch"
      parafork_print_kv EXPECTED_WORKTREE_BRANCH "$worktree_branch"
      parafork_print_kv CURRENT_BRANCH "$current_branch"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "checkout correct branch and retry"
      return 1
    fi

    do_check "merge" "false" "cli"

    local base_tracked_dirty base_untracked_count
    base_tracked_dirty="$(git -C "$base_root" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
    base_untracked_count="$(git -C "$base_root" status --porcelain | awk '/^\\?\\?/ {c++} END {print c+0}')"

    if [[ "$base_tracked_dirty" != "0" ]]; then
      echo "REFUSED: base repo not clean (tracked)"
      parafork_print_kv BASE_TRACKED_DIRTY "$base_tracked_dirty"
      parafork_print_kv BASE_UNTRACKED_COUNT "$base_untracked_count"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "clean base repo tracked changes then retry"
      return 1
    fi

    local base_current_branch
    base_current_branch="$(git -C "$base_root" rev-parse --abbrev-ref HEAD)"
    if [[ "$base_current_branch" != "$base_branch" ]]; then
      echo "REFUSED: base branch mismatch"
      parafork_print_kv BASE_BRANCH "$base_branch"
      parafork_print_kv BASE_CURRENT_BRANCH "$base_current_branch"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "cd \"$base_root\" && git checkout \"$base_branch\""
      return 1
    fi

    if [[ "$remote_available" == "true" && "$no_fetch" != "true" ]]; then
      git -C "$base_root" fetch "$remote_name"
      git -C "$base_root" rev-parse --verify "$remote_name/$base_branch^{commit}" >/dev/null 2>&1 || \
        parafork_die "missing remote base ref: $remote_name/$base_branch"

      if ! git -C "$base_root" merge --ff-only "$remote_name/$base_branch"; then
        echo "REFUSED: cannot fast-forward base to remote base"
        parafork_print_kv REMOTE_BASE "$remote_name/$base_branch"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "resolve base/remote divergence manually, then retry"
        return 1
      fi
    elif [[ "$remote_available" == "true" && "$no_fetch" == "true" ]]; then
      echo "WARN: --no-fetch used; merge may target an out-of-date base"
    fi

    echo "PREVIEW_COMMITS=$base_branch..$worktree_branch"
    git -C "$base_root" log --oneline "$base_branch..$worktree_branch" || true

    echo "PREVIEW_FILES=$base_branch...$worktree_branch"
    git -C "$base_root" diff --name-status "$base_branch...$worktree_branch" || true

    if [[ "$approved" != "true" ]]; then
      echo "REFUSED: merge not approved"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "set PARAFORK_APPROVE_MERGE=1 (or git config parafork.approval.merge=true) and rerun"
      return 1
    fi

    if [[ "$yes" != "true" || "$iam" != "true" ]]; then
      echo "REFUSED: missing CLI gate"
      parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "rerun with --yes --i-am-maintainer"
      return 1
    fi

    local config_path squash
    config_path="$(parafork_config_path_from_base "$base_root")"
    squash="$(parafork_toml_get_bool "$config_path" "control" "squash" "true")"

    parafork_print_kv SQUASH "$squash"
    parafork_print_kv BASE_UNTRACKED_COUNT "$base_untracked_count"

    if [[ "$squash" == "true" ]]; then
      if ! git -C "$base_root" merge --squash "$worktree_branch"; then
        echo "REFUSED: squash merge stopped (likely conflicts)"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "resolve conflicts in \"$base_root\" then commit (or git -C \"$base_root\" merge --abort)"
        return 1
      fi
      git -C "$base_root" commit -m "$message"
    else
      if ! git -C "$base_root" merge --no-ff "$worktree_branch" -m "$message"; then
        echo "REFUSED: merge stopped (likely conflicts)"
        parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "resolve then git -C \"$base_root\" merge --continue (or git -C \"$base_root\" merge --abort)"
        return 1
      fi
    fi

    local merged_commit
    merged_commit="$(git -C "$base_root" rev-parse --short HEAD)"
    parafork_print_kv MERGED_COMMIT "$merged_commit"
    parafork_print_output_block "$worktree_id" "$pwd" "PASS" "run acceptance steps in paradoc/Merge.md"
  }

  parafork_invoke_logged "$PARAFORK_WORKTREE_ROOT" "parafork merge" "$ENTRY_CMD merge" -- merge_body
}

cmd_watch() {
  local once="false"
  local interval="2"
  local phase="exec"
  local force_new="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --once)
        once="true"
        shift
        ;;
      --interval)
        interval="${2:-}"
        shift 2
        ;;
      --phase)
        phase="${2:-}"
        shift 2
        ;;
      --new)
        force_new="true"
        shift
        ;;
      -h|--help)
        cat <<EOF
Usage: $ENTRY_CMD watch [--once] [--interval <sec>] [--phase exec|merge] [--new]
EOF
        exit 0
        ;;
      *)
        parafork_die "unknown arg: $1"
        ;;
    esac
  done

  case "$phase" in
    exec|merge) ;;
    *) parafork_die "invalid --phase: $phase" ;;
  esac

  if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
    parafork_die "invalid --interval: $interval"
  fi

  local pwd
  pwd="$(pwd -P)"

  local symbol_path=""
  local in_worktree="false"
  if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
    local parafork_worktree
    parafork_worktree="$(parafork_symbol_get "$symbol_path" "PARAFORK_WORKTREE" || true)"
    if [[ "$parafork_worktree" == "1" ]]; then
      in_worktree="true"
    fi
  fi

  if [[ "$in_worktree" == "true" ]]; then
    local worktree_root
    worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || true)"
    [[ -n "$worktree_root" ]] || parafork_die "missing WORKTREE_ROOT in $symbol_path"
    cd "$worktree_root"

    local used
    used="$(parafork_symbol_get "$worktree_root/.worktree-symbol" "WORKTREE_USED" || true)"
    if [[ "$used" != "1" ]]; then
      cmd_init --reuse
      cd "$worktree_root"
    fi
  else
    local base_root
    base_root="$(parafork_git_toplevel || true)"
    if [[ -z "$base_root" ]]; then
      parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "FAIL" "$ENTRY_CMD help"
      parafork_die "not in a git repo and no .worktree-symbol found"
    fi

    local chosen=""
    if [[ "$force_new" != "true" ]]; then
      chosen="$(parafork_list_worktrees_newest_first "$base_root" | head -n 1 || true)"
    fi

    if [[ -n "$chosen" ]]; then
      cd "$chosen"
      cmd_init --reuse
      cd "$chosen"
    else
      cd "$base_root"
      cmd_init --new
      # init prints WORKTREE_ROOT; re-find newest after init
      chosen="$(parafork_list_worktrees_newest_first "$base_root" | head -n 1 || true)"
      [[ -n "$chosen" ]] || parafork_die "failed to locate new worktree"
      cd "$chosen"
    fi
  fi

  if ! parafork_guard_worktree; then
    exit 1
  fi
  cd "$PARAFORK_WORKTREE_ROOT"

  local worktree_id="$PARAFORK_WORKTREE_ID"
  local worktree_root="$PARAFORK_WORKTREE_ROOT"

  if [[ "$phase" == "merge" ]]; then
    do_status "false"
    do_review "false"
    if ! do_check "merge" "false" "watch"; then
      parafork_print_output_block "$worktree_id" "$worktree_root" "FAIL" "fix issues then rerun: $ENTRY_CMD watch --phase merge --once"
      exit 1
    fi
    parafork_print_output_block "$worktree_id" "$worktree_root" "PASS" "PARAFORK_APPROVE_MERGE=1 $ENTRY_CMD merge --yes --i-am-maintainer"
    exit 0
  fi

  do_status "false"
  if ! do_check "exec" "false" "watch"; then
    parafork_print_output_block "$worktree_id" "$worktree_root" "FAIL" "fix issues and rerun: $ENTRY_CMD check --phase exec"
    exit 1
  fi

  if [[ "$once" == "true" ]]; then
    local changes
    changes="$(git status --porcelain | wc -l | tr -d ' ')"
    if [[ "$changes" != "0" ]]; then
      parafork_print_output_block "$worktree_id" "$worktree_root" "PASS" "$ENTRY_CMD commit --message \"<msg>\""
    else
      parafork_print_output_block "$worktree_id" "$worktree_root" "PASS" "edit files (watch will re-check on change)"
    fi
    exit 0
  fi

  local last_head last_porcelain
  last_head="$(git rev-parse --short HEAD)"
  last_porcelain="$(git status --porcelain || true)"

  while true; do
    sleep "$interval"

    local head porcelain
    head="$(git rev-parse --short HEAD)"
    porcelain="$(git status --porcelain || true)"

    if [[ "$head" == "$last_head" && "$porcelain" == "$last_porcelain" ]]; then
      continue
    fi

    last_head="$head"
    last_porcelain="$porcelain"

    if ! do_check "exec" "false" "watch"; then
      parafork_print_output_block "$worktree_id" "$worktree_root" "FAIL" "fix issues and rerun: $ENTRY_CMD check --phase exec"
      exit 1
    fi

    do_status "false"

    local changes
    changes="$(git status --porcelain | wc -l | tr -d ' ')"
    if [[ "$changes" != "0" ]]; then
      parafork_print_output_block "$worktree_id" "$worktree_root" "PASS" "$ENTRY_CMD commit --message \"<msg>\""
    else
      parafork_print_output_block "$worktree_id" "$worktree_root" "PASS" "edit files (watch will re-check on change)"
    fi
  done
}

cmd="${1:-watch}"
if [[ "$cmd" == "-h" || "$cmd" == "--help" ]]; then
  cmd="help"
fi
shift || true

case "$cmd" in
  help) cmd_help "$@" ;;
  debug) cmd_debug "$@" ;;
  init) cmd_init "$@" ;;
  watch) cmd_watch "$@" ;;
  status) cmd_status "$@" ;;
  check) cmd_check "$@" ;;
  commit) cmd_commit "$@" ;;
  pull) cmd_pull "$@" ;;
  diff) cmd_diff "$@" ;;
  log) cmd_log "$@" ;;
  review) cmd_review "$@" ;;
  merge) cmd_merge "$@" ;;
  *)
    echo "ERROR: unknown command: $cmd"
    parafork_print_output_block "UNKNOWN" "$INVOCATION_PWD" "FAIL" "$ENTRY_CMD help"
    parafork_usage
    exit 1
    ;;
esac
