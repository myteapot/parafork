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

parafork_guard_worktree_root() {
  local script_basename="$1"
  shift || true

  local pwd
  pwd="$(pwd -P)"

  local debug_path init_path
  debug_path="$(parafork_script_path "debug.sh")"
  init_path="$(parafork_script_path "init.sh")"

  local symbol_path=""
  if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
    :
  else
    local base_root=""
    if base_root="$(parafork_git_toplevel)"; then
      parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "bash \"$debug_path\""
      return 1
    fi
    parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "cd <BASE_ROOT> && bash \"$init_path\""
    return 1
  fi

  local parafork_worktree=""
  parafork_worktree="$(parafork_symbol_get "$symbol_path" "PARAFORK_WORKTREE" || true)"
  if [[ "$parafork_worktree" != "1" ]]; then
    parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "bash \"$debug_path\""
    return 1
  fi

  local spec_version=""
  spec_version="$(parafork_symbol_get "$symbol_path" "PARAFORK_SPEC_VERSION" || true)"
  if [[ "$spec_version" != "13" ]]; then
    parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "bash \"$debug_path\""
    return 1
  fi

  local worktree_id=""
  worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || true)"
  [[ -n "$worktree_id" ]] || worktree_id="UNKNOWN"

  local worktree_root=""
  worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || true)"

  if [[ -z "$worktree_root" ]]; then
    parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "bash \"$debug_path\""
    return 1
  fi

  if [[ "$pwd" != "$worktree_root" ]]; then
    local script_path
    script_path="$(parafork_script_path "$script_basename")"
    parafork_print_output_block "$worktree_id" "$pwd" "FAIL" "cd \"$worktree_root\" && bash \"$script_path\""
    return 1
  fi

  return 0
}

parafork_enable_worktree_logging() {
  local worktree_root="$1"
  shift
  local script_name="$1"
  shift

  local log_file="$worktree_root/paradoc/Log.txt"
  mkdir -p "$worktree_root/paradoc"
  touch "$log_file"

  local ts
  ts="$(parafork_now_utc)"
  {
    echo "===== $ts $script_name ====="
    echo "cmd: $script_name $*"
    echo "pwd: $(pwd -P)"
  } >>"$log_file"

  trap 'code=$?; { echo "exit: $code"; echo; } >>"'"$log_file"'"' EXIT

  exec > >(tee -a "$log_file") 2>&1
}

parafork_require_yes_i_am_maintainer_for_flag() {
  local flag_name="$1"
  local yes="$2"
  local iam="$3"

  if [[ "$yes" != "true" || "$iam" != "true" ]]; then
    parafork_die "$flag_name requires --yes --i-am-maintainer"
  fi
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

  local base_branch_source remote_name_source
  base_branch_source="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH_SOURCE" || true)"
  remote_name_source="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME_SOURCE" || true)"

  local symbol_base_branch symbol_remote_name
  symbol_base_branch="$(parafork_symbol_get "$symbol_path" "BASE_BRANCH" || true)"
  symbol_remote_name="$(parafork_symbol_get "$symbol_path" "REMOTE_NAME" || true)"

  local config_base_branch config_remote_name
  config_base_branch="$(parafork_toml_get_str "$config_path" "base" "branch" "main")"
  config_remote_name="$(parafork_toml_get_str "$config_path" "remote" "name" "")"

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
}
