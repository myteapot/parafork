#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

phase="merge"
strict="false"

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
      cat <<'EOF'
Usage: bash <PARAFORK_SCRIPTS>/check.sh [--phase plan|exec|merge] [--strict]
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

if ! parafork_guard_worktree_root "check.sh" --phase "$phase"; then
  exit 1
fi

pwd="$(pwd -P)"
symbol_path="$pwd/.worktree-symbol"

WORKTREE_ID="$(parafork_symbol_get "$symbol_path" "WORKTREE_ID" || echo "UNKNOWN")"
WORKTREE_ROOT="$(parafork_symbol_get "$symbol_path" "WORKTREE_ROOT" || echo "$pwd")"
BASE_ROOT="$(parafork_symbol_get "$symbol_path" "BASE_ROOT" || echo "")"

parafork_enable_worktree_logging "$WORKTREE_ROOT" "check.sh" --phase "$phase"

errors=()

plan_file="$WORKTREE_ROOT/paradoc/Plan.md"
exec_file="$WORKTREE_ROOT/paradoc/Exec.md"
merge_file="$WORKTREE_ROOT/paradoc/Merge.md"
log_file="$WORKTREE_ROOT/paradoc/Log.txt"

config_path=""
autoformat="true"
autoplan="true"
if [[ -n "$BASE_ROOT" ]]; then
  config_path="$(parafork_config_path_from_base "$BASE_ROOT")"
fi

if [[ -n "$config_path" && -f "$config_path" ]]; then
  autoformat="$(parafork_toml_get_bool "$config_path" "custom" "autoformat" "true")"
  autoplan="$(parafork_toml_get_bool "$config_path" "custom" "autoplan" "true")"
fi

if [[ "$strict" == "true" ]]; then
  autoformat="true"
  autoplan="true"
fi

required_files=("$exec_file" "$merge_file" "$log_file")
if [[ "$autoplan" == "true" ]]; then
  required_files+=("$plan_file")
fi

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
  for e in "${errors[@]}"; do
    echo "FAIL: $e"
  done
  parafork_print_output_block "$WORKTREE_ID" "$pwd" "FAIL" "fix issues and rerun: bash \"$SCRIPT_DIR/check.sh\" --phase $phase"
  exit 1
fi

echo "CHECK_RESULT=PASS"
parafork_print_output_block "$WORKTREE_ID" "$pwd" "PASS" "bash \"$SCRIPT_DIR/status.sh\""
