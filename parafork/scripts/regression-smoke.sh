#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASH_ENTRY="bash \"$ROOT_DIR/bash-scripts/parafork.sh\""
POWERSHELL_ENTRY="pwsh -NoProfile -File \"$ROOT_DIR/powershell-scripts/parafork.ps1\""

print_section() {
  printf '\n==== %s ====\n' "$1"
}

run_cmd() {
  local title="$1"
  shift
  print_section "$title"
  "$@"
}

run_cmd "bash syntax" bash -n "$ROOT_DIR/bash-scripts/_lib.sh"
run_cmd "bash syntax" bash -n "$ROOT_DIR/bash-scripts/parafork.sh"

if command -v pwsh >/dev/null 2>&1; then
  run_cmd "powershell help" pwsh -NoProfile -File "$ROOT_DIR/powershell-scripts/parafork.ps1" help
  run_cmd "powershell check help" pwsh -NoProfile -File "$ROOT_DIR/powershell-scripts/parafork.ps1" check --help
  run_cmd "powershell do help" pwsh -NoProfile -File "$ROOT_DIR/powershell-scripts/parafork.ps1" do --help
  run_cmd "powershell merge help" pwsh -NoProfile -File "$ROOT_DIR/powershell-scripts/parafork.ps1" merge --help
else
  print_section "powershell skipped"
  echo "pwsh not found; skipped powershell smoke checks"
fi

run_cmd "bash help" bash "$ROOT_DIR/bash-scripts/parafork.sh" help
run_cmd "bash help --debug" bash "$ROOT_DIR/bash-scripts/parafork.sh" help --debug
run_cmd "bash check --help" bash "$ROOT_DIR/bash-scripts/parafork.sh" check --help
run_cmd "bash do --help" bash "$ROOT_DIR/bash-scripts/parafork.sh" do --help
run_cmd "bash merge --help" bash "$ROOT_DIR/bash-scripts/parafork.sh" merge --help

print_section "done"
echo "basic regression smoke passed"
