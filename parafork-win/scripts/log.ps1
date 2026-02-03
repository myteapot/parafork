Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$limit = '20'
if ($args.Count -ge 2 -and $args[0] -eq '--limit') {
  $limit = $args[1]
}

try {
  $guard = ParaforkGuardWorktreeRoot 'log.ps1' $args
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot

  $statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()

  $body = {
    & git log --oneline --decorate -n $limit 2>$null | ForEach-Object { $_ }
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' $statusCmd
  }

  ParaforkInvokeLogged $worktreeRoot 'log.ps1' $args $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}

