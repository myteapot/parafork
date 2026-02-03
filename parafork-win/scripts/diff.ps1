Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

try {
  $guard = ParaforkGuardWorktreeRoot 'diff.ps1' $args
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'

  $statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()

  $body = {
    $range = "$baseBranch...HEAD"
    Write-Output ("DIFF_RANGE={0}" -f $range)
    & git diff --stat $range 2>$null | ForEach-Object { $_ }
    Write-Output ""
    & git diff $range 2>$null | ForEach-Object { $_ }
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' $statusCmd
  }

  ParaforkInvokeLogged $worktreeRoot 'diff.ps1' $args $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}

