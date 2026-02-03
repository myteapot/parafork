Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$invocationPwd = (Get-Location).Path
$worktreeId = 'UNKNOWN'
$worktreeRoot = $null

$symbolPath = ParaforkSymbolFindUpwards $invocationPwd
if ($symbolPath) {
  $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
  if ($paraforkWorktree -eq '1') {
    $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
    if ([string]::IsNullOrEmpty($worktreeId)) {
      $worktreeId = 'UNKNOWN'
    }
    $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
    if ([string]::IsNullOrEmpty($worktreeRoot)) {
      $worktreeRoot = $null
    }
  }
}

$scriptDir = ParaforkScriptDir
$initCmd = ParaforkPsFileCmd (ParaforkScriptPath 'init.ps1') @()
$reuseCmd = ParaforkPsFileCmd (ParaforkScriptPath 'init.ps1') @('--reuse')
$statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()
$checkCmd = ParaforkPsFileCmd (ParaforkScriptPath 'check.ps1') @('--phase', 'exec')
$commitCmd = ParaforkPsFileCmd (ParaforkScriptPath 'commit.ps1') @('--message', '...')
$pullCmd = ParaforkPsFileCmd (ParaforkScriptPath 'pull.ps1') @()
$mergeCmd = ParaforkPsFileCmd (ParaforkScriptPath 'merge.ps1') @('--yes', '--i-am-maintainer')
$debugCmd = ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @()

$body = {
  ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' $initCmd

  Write-Output ""
  Write-Output "Parafork - safe worktree contribution workflow (PowerShell)"
  Write-Output ""
  Write-Output "Base-allowed scripts:"
  Write-Output ("- {0}" -f $initCmd)
  Write-Output ("- {0}" -f $debugCmd)
  Write-Output ("- {0}" -f (ParaforkPsFileCmd (ParaforkScriptPath 'help.ps1') @()))
  Write-Output ""
  Write-Output "Worktree-only scripts (must run in WORKTREE_ROOT):"
  Write-Output ("- {0}" -f $statusCmd)
  Write-Output ("- {0}" -f $checkCmd)
  Write-Output ("- {0}" -f $commitCmd)
  Write-Output ("- {0}" -f $pullCmd)
  Write-Output ("- {0}" -f $mergeCmd)
  Write-Output ("- {0}" -f (ParaforkPsFileCmd (ParaforkScriptPath 'diff.ps1') @()))
  Write-Output ("- {0}" -f (ParaforkPsFileCmd (ParaforkScriptPath 'log.ps1') @('--limit', '20')))
  Write-Output ("- {0}" -f (ParaforkPsFileCmd (ParaforkScriptPath 'review.ps1') @()))
  Write-Output ""
  Write-Output "If worktree-only scripts refuse due to WORKTREE_USED gate:"
  Write-Output ("- {0}" -f $reuseCmd)
  Write-Output ""
  Write-Output "Audit log:"
  Write-Output "- Script output is appended to paradoc/Log.txt (when a worktree can be located)."
  Write-Output ""
  Write-Output "Merge requirements (maintainer only):"
  Write-Output "- Local approval: PARAFORK_APPROVE_MERGE=1 (or git config parafork.approval.merge=true)"
  Write-Output "- CLI gate: --yes --i-am-maintainer"
  Write-Output ""
  Write-Output "Pull high-risk strategy approvals (maintainer only):"
  Write-Output "- Rebase: PARAFORK_APPROVE_PULL_REBASE=1 (or git config parafork.approval.pull.rebase=true) + --yes --i-am-maintainer"
  Write-Output "- Merge:  PARAFORK_APPROVE_PULL_MERGE=1  (or git config parafork.approval.pull.merge=true)  + --yes --i-am-maintainer"
  Write-Output ""
  Write-Output "If you are unsure where you are:"
  Write-Output ("- {0}" -f $debugCmd)
}

try {
  if ($worktreeRoot) {
    ParaforkInvokeLogged $worktreeRoot 'help.ps1' $args $body
  } else {
    & $body
  }
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock $worktreeId $invocationPwd 'FAIL' $debugCmd
  }
  exit 1
}
