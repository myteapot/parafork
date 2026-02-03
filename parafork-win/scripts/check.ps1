Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$phase = 'merge'
$strict = $false

for ($i = 0; $i -lt $args.Count; ) {
  $a = $args[$i]
  switch ($a) {
    '--phase' {
      if ($i + 1 -ge $args.Count) {
        ParaforkDie 'missing value for --phase'
      }
      $phase = $args[$i + 1]
      $i += 2
      continue
    }
    '--strict' {
      $strict = $true
      $i++
      continue
    }
    '--help' {
      Write-Output "Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\\check.ps1 [--phase plan|exec|merge] [--strict]"
      exit 0
    }
    '-h' {
      Write-Output "Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\\check.ps1 [--phase plan|exec|merge] [--strict]"
      exit 0
    }
    default {
      ParaforkDie ("unknown arg: {0}" -f $a)
    }
  }
}

if ($phase -ne 'plan' -and $phase -ne 'exec' -and $phase -ne 'merge') {
  ParaforkDie ("invalid --phase: {0}" -f $phase)
}

try {
  $guard = ParaforkGuardWorktreeRoot 'check.ps1' @('--phase', $phase)
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot

  $errors = New-Object System.Collections.Generic.List[string]

  $planFile = Join-Path $worktreeRoot 'paradoc/Plan.md'
  $execFile = Join-Path $worktreeRoot 'paradoc/Exec.md'
  $mergeFile = Join-Path $worktreeRoot 'paradoc/Merge.md'
  $logFile = Join-Path $worktreeRoot 'paradoc/Log.txt'

  $configPath = ParaforkConfigPath
  $autoformat = 'true'
  $autoplan = 'false'
  if (Test-Path -LiteralPath $configPath) {
    $autoformat = ParaforkTomlGetBool $configPath 'custom' 'autoformat' 'true'
    $autoplan = ParaforkTomlGetBool $configPath 'custom' 'autoplan' 'false'
  }

  if ($strict) {
    $autoformat = 'true'
    $autoplan = 'true'
  }

  $requiredFiles = @($execFile, $mergeFile, $logFile)
  if ($autoplan -eq 'true') {
    $requiredFiles += $planFile
  }

  foreach ($f in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
      $errors.Add(("missing file: {0}" -f $f))
    }
  }

  if ($autoplan -eq 'true' -and $autoformat -eq 'true' -and (Test-Path -LiteralPath $planFile -PathType Leaf)) {
    if (-not (Select-String -LiteralPath $planFile -SimpleMatch '## Milestones' -Quiet)) {
      $errors.Add('Plan.md missing heading: ## Milestones')
    }
    if (-not (Select-String -LiteralPath $planFile -SimpleMatch '## Tasks' -Quiet)) {
      $errors.Add('Plan.md missing heading: ## Tasks')
    }
    if (-not (Select-String -LiteralPath $planFile -Pattern '^- \\[.\\] ' -Quiet)) {
      $errors.Add('Plan.md has no checkboxes')
    }
    if ($phase -eq 'merge') {
      if (Select-String -LiteralPath $planFile -Pattern '^- \\[ \\] T[0-9]+' -Quiet) {
        $errors.Add('Plan.md has incomplete tasks (merge phase requires tasks done)')
      }
    }
  }

  if ($autoformat -eq 'true' -and (Test-Path -LiteralPath $mergeFile -PathType Leaf)) {
    if (-not (Select-String -LiteralPath $mergeFile -Pattern 'Acceptance|Repro' -CaseSensitive:$false -Quiet)) {
      $errors.Add('Merge.md missing Acceptance/Repro section keywords')
    }
  }

  if ($phase -eq 'merge' -or $strict) {
    foreach ($f in @($execFile, $mergeFile)) {
      if ((Test-Path -LiteralPath $f -PathType Leaf) -and (Select-String -LiteralPath $f -Pattern 'PARAFORK_TBD|TODO_TBD' -Quiet)) {
        $errors.Add(("placeholder remains: {0}" -f $f))
      }
    }

    if ($autoplan -eq 'true' -and (Test-Path -LiteralPath $planFile -PathType Leaf) -and (Select-String -LiteralPath $planFile -Pattern 'PARAFORK_TBD|TODO_TBD' -Quiet)) {
      $errors.Add(("placeholder remains: {0}" -f $planFile))
    }
  }

  if ($phase -eq 'merge') {
    $trackedParadoc = & git ls-files -- 'paradoc/' 2>$null
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git ls-files failed'
    }
    if ($trackedParadoc -and ($trackedParadoc | Measure-Object).Count -gt 0) {
      $errors.Add("git pollution: tracked files under paradoc/ (must be empty: git ls-files -- 'paradoc/')")
    }

    $trackedSymbol = & git ls-files -- '.worktree-symbol' 2>$null
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git ls-files failed'
    }
    if ($trackedSymbol -and ($trackedSymbol | Measure-Object).Count -gt 0) {
      $errors.Add("git pollution: .worktree-symbol is tracked (must be empty: git ls-files -- '.worktree-symbol')")
    }

    $staged = & git diff --cached --name-only -- 2>$null
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git diff --cached failed'
    }
    if ($staged) {
      $pollution = $staged | Where-Object { $_ -match '^(paradoc/|\\.worktree-symbol$)' }
      if ($pollution -and ($pollution | Measure-Object).Count -gt 0) {
        $errors.Add('git pollution: staged includes paradoc/ or .worktree-symbol')
      }
    }
  }

  $statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()
  $rerunCmd = ParaforkPsFileCmd (ParaforkScriptPath 'check.ps1') @('--phase', $phase)

  $body = {
    if ($errors.Count -gt 0) {
      Write-Output 'CHECK_RESULT=FAIL'
      foreach ($e in $errors) {
        Write-Output ("FAIL: {0}" -f $e)
      }
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues and rerun: " + $rerunCmd)
      throw 'check failed'
    }

    Write-Output 'CHECK_RESULT=PASS'
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' $statusCmd
  }

  ParaforkInvokeLogged $worktreeRoot 'check.ps1' @('--phase', $phase) $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}

