Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$message = $null
$noCheck = $false

for ($i = 0; $i -lt $args.Count; ) {
  $a = $args[$i]
  switch ($a) {
    '--message' {
      if ($i + 1 -ge $args.Count) {
        ParaforkDie 'missing value for --message'
      }
      $message = $args[$i + 1]
      $i += 2
      continue
    }
    '--no-check' {
      $noCheck = $true
      $i++
      continue
    }
    '--help' {
      Write-Output 'Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\commit.ps1 --message "<msg>" [--no-check]'
      exit 0
    }
    '-h' {
      Write-Output 'Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\commit.ps1 --message "<msg>" [--no-check]'
      exit 0
    }
    default {
      ParaforkDie ("unknown arg: {0}" -f $a)
    }
  }
}

if ([string]::IsNullOrEmpty($message)) {
  ParaforkDie 'missing --message'
}

try {
  $guard = ParaforkGuardWorktreeRoot 'commit.ps1' @('--message', '<msg>')
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot

  $checkPath = ParaforkScriptPath 'check.ps1'
  $checkCmd = ParaforkPsFileCmd $checkPath @('--phase', 'exec')
  $statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()
  $commitCmd = ParaforkPsFileCmd (ParaforkScriptPath 'commit.ps1') @('--message', $message)

  $body = {
    if (-not $noCheck) {
      & powershell -NoProfile -ExecutionPolicy Bypass -File $checkPath --phase exec
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: check failed'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues then retry: " + $commitCmd)
        throw 'check failed'
      }
    }

    & git add -A -- .
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git add failed'
    }

    $staged = & git diff --cached --name-only -- 2>$null
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git diff --cached failed'
    }
    if ($staged) {
      $pollution = $staged | Where-Object { $_ -match '^(paradoc/|\\.worktree-symbol$)' }
      if ($pollution -and ($pollution | Measure-Object).Count -gt 0) {
        Write-Output 'REFUSED: git pollution staged'
        Write-Output "HINT: ensure worktree exclude contains '/paradoc/' and '/.worktree-symbol'"
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("unstage pollution and retry: git reset -q; " + $commitCmd)
        throw 'pollution staged'
      }
    }

    & git diff --cached --quiet --
    if ($LASTEXITCODE -eq 0) {
      Write-Output 'REFUSED: nothing staged'
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("edit files then retry: " + $commitCmd)
      throw 'nothing staged'
    }

    & git commit -m $message
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git commit failed'
    }

    $head = (& git rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
    ParaforkPrintKv 'COMMIT' $head
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' $statusCmd
  }

  ParaforkInvokeLogged $worktreeRoot 'commit.ps1' @('--message', $message) $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}

