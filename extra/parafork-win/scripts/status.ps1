Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

try {
  $guard = ParaforkGuardWorktreeRoot 'status.ps1' $args
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $remoteName = ParaforkSymbolGet $symbolPath 'REMOTE_NAME'
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

  $checkCmd = ParaforkPsFileCmd (ParaforkScriptPath 'check.ps1') @('--phase', 'exec')

  $body = {
    $branch = (& git rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git rev-parse failed (branch)'
    }

    $head = (& git rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git rev-parse failed (head)'
    }

    $changes = (& git status --porcelain 2>$null | Measure-Object).Count

    ParaforkPrintKv 'BRANCH' $branch
    ParaforkPrintKv 'HEAD' $head
    ParaforkPrintKv 'CHANGES' $changes
    ParaforkPrintKv 'BASE_BRANCH' $baseBranch
    ParaforkPrintKv 'REMOTE_NAME' $remoteName
    ParaforkPrintKv 'WORKTREE_BRANCH' $worktreeBranch

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' $checkCmd
  }

  ParaforkInvokeLogged $worktreeRoot 'status.ps1' $args $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}

