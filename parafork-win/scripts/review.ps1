Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

try {
  $guard = ParaforkGuardWorktreeRoot 'review.ps1' $args
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

  $checkCmd = ParaforkPsFileCmd (ParaforkScriptPath 'check.ps1') @('--phase', 'merge')

  $body = {
    Write-Output '### Review material (copy into paradoc/Merge.md)'
    Write-Output ""
    Write-Output ("#### Commits ({0}..{1})" -f $baseBranch, $worktreeBranch)
    & git log --oneline "$baseBranch..$worktreeBranch" 2>$null | ForEach-Object { $_ }
    Write-Output ""
    Write-Output ("#### Files ({0}...{1})" -f $baseBranch, $worktreeBranch)
    & git diff --name-status "$baseBranch...$worktreeBranch" 2>$null | ForEach-Object { $_ }
    Write-Output ""
    Write-Output '#### Notes'
    Write-Output '- Ensure Merge.md contains Acceptance / Repro steps.'
    Write-Output '- Mention risks and rollback plan if relevant.'

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' ("edit paradoc/Merge.md then " + $checkCmd)
  }

  ParaforkInvokeLogged $worktreeRoot 'review.ps1' $args $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}

