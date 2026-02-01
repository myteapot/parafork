#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_lib.sh"

pwd="$(pwd -P)"

parafork_print_output_block "UNKNOWN" "$pwd" "PASS" "bash \"$SCRIPT_DIR/init.sh\""

cat <<EOF

Parafork v13 — safe worktree contribution workflow

Base-allowed scripts:
- bash "$SCRIPT_DIR/init.sh"
- bash "$SCRIPT_DIR/debug.sh"
- bash "$SCRIPT_DIR/help.sh"

Worktree-only scripts (must run in worktree root):
- bash "$SCRIPT_DIR/status.sh"
- bash "$SCRIPT_DIR/check.sh" --phase plan|exec|merge
- bash "$SCRIPT_DIR/commit.sh" --message "..."
- bash "$SCRIPT_DIR/pull.sh"
- bash "$SCRIPT_DIR/merge.sh" --yes --i-am-maintainer

Merge requirements (maintainer only):
- Local approval: PARAFORK_APPROVE_MERGE=1 (or git config parafork.approval.merge=true)
- CLI gate: --yes --i-am-maintainer

Pull high-risk strategy approvals (maintainer only):
- Rebase: PARAFORK_APPROVE_PULL_REBASE=1 (or git config parafork.approval.pull.rebase=true) + --yes --i-am-maintainer
- Merge:  PARAFORK_APPROVE_PULL_MERGE=1  (or git config parafork.approval.pull.merge=true)  + --yes --i-am-maintainer

If you are unsure where you are:
- bash "$SCRIPT_DIR/debug.sh"
EOF
