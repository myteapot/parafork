#!/usr/bin/env bash
set -euo pipefail

parafork_now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

parafork_die() {
  echo "ERROR: $*" >&2
  exit 1
}

parafork_warn() {
  echo "WARN: $*" >&2
}

PARAFORK_OUTPUT_BLOCK_PRINTED="0"

parafork_script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P
}

parafork_root_dir() {
  local script_dir
  script_dir="$(parafork_script_dir)"
  cd -- "$script_dir/.." && pwd -P
}

parafork_script_path() {
  local script_name="$1"
  local script_dir
  script_dir="$(parafork_script_dir)"
  echo "$script_dir/$script_name"
}

parafork_entry_path() {
  local script_dir
  script_dir="$(parafork_script_dir)"
  echo "$script_dir/parafork.sh"
}

parafork_entry_cmd() {
  local p
  p="$(parafork_entry_path)"
  printf 'bash "%s"' "$p"
}

parafork_config_path_from_base() {
  local _base_root="${1:-}"

  local skill_root
  skill_root="$(parafork_root_dir)"
  echo "$skill_root/settings/config.toml"
}

parafork_print_kv() {
  printf '%s=%s\n' "$1" "$2"
}

parafork_print_output_block() {
  local worktree_id="$1"
  local pwd="$2"
  local status="$3"
  local next="$4"

  PARAFORK_OUTPUT_BLOCK_PRINTED="1"
  parafork_print_kv WORKTREE_ID "$worktree_id"
  parafork_print_kv PWD "$pwd"
  parafork_print_kv STATUS "$status"
  parafork_print_kv NEXT "$next"
}

parafork_toml_get_raw() {
  local file="$1"
  local section="$2"
  local key="$3"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  awk -v section="$section" -v key="$key" '
    BEGIN { in_section=0; found=0 }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*\[/ {
      s=$0
      sub(/^[[:space:]]*\[/, "", s)
      sub(/\][[:space:]]*$/, "", s)
      in_section = (s == section)
      next
    }
    in_section {
      line=$0
      sub(/[[:space:]]*#.*$/, "", line)
      if (match(line, /^[[:space:]]*([A-Za-z0-9_.-]+)[[:space:]]*=[[:space:]]*(.*)$/, m)) {
        if (m[1] == key) {
          v=m[2]
          sub(/^[[:space:]]+/, "", v)
          sub(/[[:space:]]+$/, "", v)
          print v
          found=1
          exit
        }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

parafork_toml_get_str() {
  local file="$1"
  local section="$2"
  local key="$3"
  local default="$4"

  local raw=""
  if raw="$(parafork_toml_get_raw "$file" "$section" "$key" 2>/dev/null)"; then
    :
  else
    echo "$default"
    return 0
  fi

  if [[ "$raw" =~ ^\".*\"$ ]] || [[ "$raw" =~ ^\'.*\'$ ]]; then
    raw="${raw:1:${#raw}-2}"
  fi

  if [[ -z "$raw" ]]; then
    echo "$default"
    return 0
  fi

  echo "$raw"
}

parafork_toml_get_bool() {
  local file="$1"
  local section="$2"
  local key="$3"
  local default="$4"

  local raw=""
  if raw="$(parafork_toml_get_raw "$file" "$section" "$key" 2>/dev/null)"; then
    :
  else
    echo "$default"
    return 0
  fi

  raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    true) echo "true" ;;
    false) echo "false" ;;
    *) echo "$default" ;;
  esac
}

parafork_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

parafork_git_path_abs() {
  local repo_root="$1"
  local git_path="$2"

  local p
  p="$(git -C "$repo_root" rev-parse --git-path "$git_path")"

  if [[ "$p" == /* ]]; then
    echo "$p"
    return 0
  fi

  echo "$repo_root/$p"
}

parafork_is_remote_available() {
  local base_root="$1"
  local remote_name="$2"

  [[ -n "$remote_name" ]] || return 1
  git -C "$base_root" remote get-url "$remote_name" >/dev/null 2>&1
}

parafork_agent_id() {
  if [[ -n "${PARAFORK_AGENT_ID:-}" ]]; then
    printf '%s' "$PARAFORK_AGENT_ID"
    return 0
  fi

  if [[ -n "${CODEX_THREAD_ID:-}" ]]; then
    printf 'codex:%s' "$CODEX_THREAD_ID"
    return 0
  fi

  local user host
  user="${USER:-unknown}"
  host="$(hostname 2>/dev/null || echo "unknown-host")"
  printf '%s@%s' "$user" "$host"
}

parafork_is_reuse_approved() {
  local base_root="$1"

  if [[ "${PARAFORK_APPROVE_REUSE:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -n "$base_root" ]] && [[ "$(git -C "$base_root" config --bool --default false parafork.approval.reuse 2>/dev/null || true)" == "true" ]]; then
    return 0
  fi

  return 1
}

parafork_write_worktree_lock() {
  local symbol_path="$1"
  local agent_id lock_at

  agent_id="$(parafork_agent_id)"
  lock_at="$(parafork_now_utc)"

  parafork_symbol_set "$symbol_path" "WORKTREE_LOCK" "1"
  parafork_symbol_set "$symbol_path" "WORKTREE_LOCK_OWNER" "$agent_id"
  parafork_symbol_set "$symbol_path" "WORKTREE_LOCK_AT" "$lock_at"
}

parafork_symbol_find_upwards() {
  local start="$1"
  local cur="$start"

  while true; do
    if [[ -f "$cur/.worktree-symbol" ]]; then
      echo "$cur/.worktree-symbol"
      return 0
    fi
    if [[ "$cur" == "/" ]]; then
      return 1
    fi
    cur="$(cd -- "$cur/.." && pwd -P)"
  done
}

parafork_symbol_get() {
  local symbol_path="$1"
  local wanted_key="$2"

  [[ -f "$symbol_path" ]] || return 1

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^# ]] && continue
    [[ "$line" == *"="* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    if [[ "$key" == "$wanted_key" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done <"$symbol_path"

  return 1
}

parafork_symbol_set() {
  local symbol_path="$1"
  local key="$2"
  local value="$3"

  [[ -f "$symbol_path" ]] || return 1

  local tmp
  tmp="$(mktemp)"

  local found="false"
  local line k
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"="* ]]; then
      k="${line%%=*}"
      if [[ "$k" == "$key" ]]; then
        printf '%s=%s\n' "$key" "$value" >>"$tmp"
        found="true"
        continue
      fi
    fi

    printf '%s\n' "$line" >>"$tmp"
  done <"$symbol_path"

  if [[ "$found" != "true" ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi

  cat "$tmp" >"$symbol_path"
  rm -f "$tmp"
}

parafork_worktree_container() {
  local base_root="$1"
  local config_path workdir_root
  config_path="$(parafork_config_path_from_base "$base_root")"
  workdir_root=".parafork"
  if [[ -f "$config_path" ]]; then
    workdir_root="$(parafork_toml_get_str "$config_path" "workdir" "root" ".parafork")"
  fi
  echo "$base_root/$workdir_root"
}

parafork_list_worktrees_newest_first() {
  local base_root="$1"
  local container
  container="$(parafork_worktree_container "$base_root")"

  [[ -d "$container" ]] || return 0

  local d
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/.worktree-symbol" ]] || continue
    printf '%s\n' "$d"
  done < <(ls -1dt "$container"/* 2>/dev/null || true)
}

parafork_guard_worktree() {
  local pwd
  pwd="$(pwd -P)"

  PARAFORK_WORKTREE_ID=""
  PARAFORK_WORKTREE_ROOT=""
  PARAFORK_BASE_ROOT=""
  PARAFORK_SYMBOL_PATH=""

  local entry_cmd
  entry_cmd="$(parafork_entry_cmd)"

  local debug_next init_next
  debug_next="$entry_cmd debug"
  init_next="cd <BASE_ROOT> && $entry_cmd init --new"

  local symbol_path=""
  if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
    :
  else
    local base_root=""
    if base_root="$(parafork_git_toplevel)"; then
      parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "$debug_next"
      return 1
    fi
    parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "$init_next"
    return 1
  fi

  local parafork_worktree=""
  parafork_worktree="$(parafork_symbol_get "$symbol_path" "PARAFORK_WORKTREE" || true)"
  if [[ "$parafork_worktree" != "1" ]]; then
    parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "$debug_next"
    return 1
  fi

  local worktree_id=""
  worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || true)"
  [[ -n "$worktree_id" ]] || worktree_id="UNKNOWN"

  local worktree_root=""
  worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || true)"

  if [[ -z "$worktree_root" ]]; then
    parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "$debug_next"
    return 1
  fi

  local worktree_used=""
  worktree_used="$(parafork_symbol_get "$symbol_path" "WORKTREE_USED" || true)"
  if [[ "$worktree_used" != "1" ]]; then
    echo "REFUSED: worktree not entered (WORKTREE_USED!=1)"
    parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "$entry_cmd init --reuse"
    return 1
  fi

  local lock_enabled lock_owner agent_id
  lock_enabled="$(parafork_symbol_get "$symbol_path" "WORKTREE_LOCK" || true)"
  lock_owner="$(parafork_symbol_get "$symbol_path" "WORKTREE_LOCK_OWNER" || true)"
  agent_id="$(parafork_agent_id)"

  if [[ "$lock_enabled" != "1" || -z "$lock_owner" ]]; then
    parafork_write_worktree_lock "$symbol_path"
    lock_enabled="1"
    lock_owner="$agent_id"
  fi

  if [[ "$lock_enabled" == "1" && "$lock_owner" != "$agent_id" ]]; then
    echo "REFUSED: worktree locked by another agent"
    parafork_print_kv LOCK_OWNER "$lock_owner"
    parafork_print_kv AGENT_ID "$agent_id"
    parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "cd \"$worktree_root\" && PARAFORK_APPROVE_REUSE=1 $entry_cmd init --reuse --yes --i-am-maintainer"
    return 1
  fi

  PARAFORK_WORKTREE_ID="$worktree_id"
  PARAFORK_WORKTREE_ROOT="$worktree_root"
  PARAFORK_BASE_ROOT="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || true)"
  PARAFORK_SYMBOL_PATH="$symbol_path"

  return 0
}

parafork_invoke_logged() {
  local worktree_root="$1"
  shift
  local script_name="$1"
  shift
  local argv_line="$1"
  shift

  if [[ "${1:-}" != "--" ]]; then
    parafork_die "internal: parafork_invoke_logged expects -- separator"
  fi
  shift

  local log_file="$worktree_root/paradoc/Log.txt"
  mkdir -p "$worktree_root/paradoc"
  touch "$log_file"

  local ts
  ts="$(parafork_now_utc)"
  {
    echo "===== $ts $script_name ====="
    echo "cmd: $argv_line"
    echo "pwd: $(pwd -P)"
  } >>"$log_file"

  set +e
  (
    set -euo pipefail
    "$@"
  ) 2>&1 | tee -a "$log_file"
  local code="${PIPESTATUS[0]}"
  set -e

  { echo "exit: $code"; echo; } >>"$log_file"
  return "$code"
}

parafork_require_yes_i_am_maintainer_for_flag() {
  local flag_name="$1"
  local yes="$2"
  local iam="$3"

  if [[ "$yes" != "true" || "$iam" != "true" ]]; then
    parafork_die "$flag_name requires --yes --i-am-maintainer"
  fi
}

parafork_remote_autosync_from_symbol_or_config() {
  local base_root="$1"
  local symbol_path="$2"

  local symbol_remote_autosync
  symbol_remote_autosync="$(parafork_symbol_get "$symbol_path" "REMOTE_AUTOSYNC" || true)"
  if [[ "$symbol_remote_autosync" == "true" || "$symbol_remote_autosync" == "false" ]]; then
    echo "$symbol_remote_autosync"
    return 0
  fi

  local config_path
  config_path="$(parafork_config_path_from_base "$base_root")"
  if [[ ! -f "$config_path" ]]; then
    parafork_die "missing config: $config_path"
  fi

  parafork_toml_get_bool "$config_path" "remote" "autosync" "false"
}

parafork_check_config_drift() {
  local base_root="$1"
  local allow_drift="$2"
  local yes="$3"
  local iam="$4"

  local symbol_path="$5"

  local config_path
  config_path="$(parafork_config_path_from_base "$base_root")"

  if [[ ! -f "$config_path" ]]; then
    parafork_die "missing config: $config_path"
  fi

  local base_branch_source remote_name_source remote_autosync_source
  base_branch_source="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH_SOURCE" || true)"
  remote_name_source="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME_SOURCE" || true)"
  remote_autosync_source="$(parafork_symbol_get "$symbol_path" "REMOTE_AUTOSYNC_SOURCE" || true)"

  local symbol_base_branch symbol_remote_name symbol_remote_autosync
  symbol_base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || true)"
  symbol_remote_name="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || true)"
  symbol_remote_autosync="$(parafork_symbol_get "$symbol_path" "REMOTE_AUTOSYNC" || true)"

  local config_base_branch config_remote_name config_remote_autosync
  config_base_branch="$(parafork_toml_get_str "$config_path" "base" "branch" "main")"
  config_remote_name="$(parafork_toml_get_str "$config_path" "remote" "name" "")"
  config_remote_autosync="$(parafork_toml_get_bool "$config_path" "remote" "autosync" "false")"

  if [[ "$base_branch_source" == "config" && "$config_base_branch" != "$symbol_base_branch" ]]; then
    if [[ "$allow_drift" != "true" ]]; then
      parafork_die "config drift detected (base.branch): symbol='$symbol_base_branch' config='$config_base_branch' (rerun with --allow-config-drift --yes --i-am-maintainer to override)"
    fi
    parafork_require_yes_i_am_maintainer_for_flag "--allow-config-drift" "$yes" "$iam"
  fi

  if [[ "$remote_name_source" == "config" && "$config_remote_name" != "$symbol_remote_name" ]]; then
    if [[ "$allow_drift" != "true" ]]; then
      parafork_die "config drift detected (remote.name): symbol='$symbol_remote_name' config='$config_remote_name' (rerun with --allow-config-drift --yes --i-am-maintainer to override)"
    fi
    parafork_require_yes_i_am_maintainer_for_flag "--allow-config-drift" "$yes" "$iam"
  fi

  if [[ "$remote_autosync_source" == "config" && -n "$symbol_remote_autosync" && "$config_remote_autosync" != "$symbol_remote_autosync" ]]; then
    if [[ "$allow_drift" != "true" ]]; then
      parafork_die "config drift detected (remote.autosync): symbol='$symbol_remote_autosync' config='$config_remote_autosync' (rerun with --allow-config-drift --yes --i-am-maintainer to override)"
    fi
    parafork_require_yes_i_am_maintainer_for_flag "--allow-config-drift" "$yes" "$iam"
  fi
}
