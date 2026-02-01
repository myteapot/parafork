#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

pwd="$(pwd -P)"

if symbol_path="$(parafork_symbol_find_upwards "$pwd" 2>/dev/null)"; then
  worktree_id="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
  worktree_root="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "")"

  next="bash \"$SCRIPT_DIR/help.sh\""
  if [[ -n "$worktree_root" ]]; then
    next="cd \"$worktree_root\" && bash \"$SCRIPT_DIR/status.sh\""
  fi

  parafork_print_kv SYMBOL_PATH "$symbol_path"
  parafork_print_output_block "$worktree_id" "$pwd" "PASS" "$next"

  if [[ -n "$worktree_root" && -f "$worktree_root/paradoc/Log.txt" ]]; then
    ts="$(parafork_now_utc)"
    {
      echo "===== $ts debug.sh ====="
      echo "pwd: $pwd"
      echo "next: $next"
      echo
    } >>"$worktree_root/paradoc/Log.txt"
  fi

  exit 0
fi

base_root="$(parafork_git_toplevel || true)"
if [[ -z "$base_root" ]]; then
  parafork_print_output_block "UNKNOWN" "$pwd" "FAIL" "cd <BASE_ROOT> && bash \"$SCRIPT_DIR/init.sh\""
  parafork_die "not in a git repo and no .worktree-symbol found"
fi

config_path="$(parafork_config_path_from_base "$base_root")"
workdir_root=".parafork"
if [[ -f "$config_path" ]]; then
  workdir_root="$(parafork_toml_get_str "$config_path" "workdir" "root" ".parafork")"
fi

container="$base_root/$workdir_root"

if [[ ! -d "$container" ]]; then
  parafork_print_kv BASE_ROOT "$base_root"
  parafork_print_output_block "UNKNOWN" "$pwd" "PASS" "bash \"$SCRIPT_DIR/init.sh\""
  echo
  echo "No worktree container found at: $container"
  exit 0
fi

valid_worktrees=()
while IFS= read -r d; do
  [[ -d "$d" ]] || continue
  [[ -f "$d/.worktree-symbol" ]] || continue
  valid_worktrees+=("$d")
done < <(ls -1dt "$container"/* 2>/dev/null || true)

if [[ ${#valid_worktrees[@]} -eq 0 ]]; then
  parafork_print_kv BASE_ROOT "$base_root"
  parafork_print_output_block "UNKNOWN" "$pwd" "PASS" "bash \"$SCRIPT_DIR/init.sh\""
  echo
  echo "No worktrees found under: $container"
  exit 0
fi

echo "Found worktrees (newest first):"
for d in "${valid_worktrees[@]}"; do
  id="$(parafork_symbol_get "$d/.worktree-symbol" "WORKTREE_ID" || echo "UNKNOWN")"
  echo "- $id  $d"
done

chosen="${valid_worktrees[0]}"
chosen_id="$(parafork_symbol_get "$chosen/.worktree-symbol" "WORKTREE_ID" || echo "UNKNOWN")"

parafork_print_kv BASE_ROOT "$base_root"
parafork_print_output_block "$chosen_id" "$pwd" "PASS" "cd \"$chosen\" && bash \"$SCRIPT_DIR/status.sh\""
