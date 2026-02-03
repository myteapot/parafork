Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$yes = $false
$iam = $false
$noFetch = $false
$allowDrift = $false
$message = $null

$usageText = @"
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\merge.ps1 [options]

Preview-only unless all gates are satisfied:
- local approval: PARAFORK_APPROVE_MERGE=1 or git config parafork.approval.merge=true
- CLI gate: --yes --i-am-maintainer

Options:
  --message "<msg>"         Override merge commit message (squash mode)
  --no-fetch                Skip fetch + remote-base alignment (requires --yes --i-am-maintainer)
  --allow-config-drift       Override session config drift checks (requires --yes --i-am-maintainer)
"@

for ($i = 0; $i -lt $args.Count; ) {
  $a = $args[$i]
  switch ($a) {
    '--yes' {
      $yes = $true
      $i++
      continue
    }
    '--i-am-maintainer' {
      $iam = $true
      $i++
      continue
    }
    '--no-fetch' {
      $noFetch = $true
      $i++
      continue
    }
    '--allow-config-drift' {
      $allowDrift = $true
      $i++
      continue
    }
    '--message' {
      if ($i + 1 -ge $args.Count) {
        ParaforkDie 'missing value for --message'
      }
      $message = $args[$i + 1]
      $i += 2
      continue
    }
    '--help' {
      Write-Output $usageText
      exit 0
    }
    '-h' {
      Write-Output $usageText
      exit 0
    }
    default {
      ParaforkDie ("unknown arg: {0}" -f $a)
    }
  }
}

try {
  $guard = ParaforkGuardWorktreeRoot 'merge.ps1' $args
  if (-not $guard) {
    exit 1
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot
  $baseRoot = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $remoteName = ParaforkSymbolGet $symbolPath 'REMOTE_NAME'
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

  $allowDriftStr = if ($allowDrift) { 'true' } else { 'false' }

  if ([string]::IsNullOrEmpty($message)) {
    $message = "parafork: merge $worktreeId"
  }

  $checkPath = ParaforkScriptPath 'check.ps1'
  $checkCmd = ParaforkPsFileCmd $checkPath @('--phase', 'merge')

  $body = {
    if (-not [string]::IsNullOrEmpty($baseRoot)) {
      ParaforkCheckConfigDrift $allowDriftStr $yes $iam $symbolPath
    }

    $remoteAvailable = $false
    if ($baseRoot -and (ParaforkIsRemoteAvailable $baseRoot $remoteName)) {
      $remoteAvailable = $true
    }

    if ($remoteAvailable -and $noFetch) {
      ParaforkRequireYesIam '--no-fetch' $yes $iam
    }

    $approved = $false
    if ($env:PARAFORK_APPROVE_MERGE -eq '1') {
      $approved = $true
    } elseif ($baseRoot) {
      $v = (& git -C $baseRoot config --bool --default false parafork.approval.merge 2>$null | Select-Object -First 1).Trim()
      if ($v -eq 'true') {
        $approved = $true
      }
    }

    $currentBranch = (& git rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git rev-parse failed'
    }
    if (-not [string]::IsNullOrEmpty($worktreeBranch) -and $currentBranch -ne $worktreeBranch) {
      Write-Output 'REFUSED: wrong worktree branch'
      ParaforkPrintKv 'EXPECTED_WORKTREE_BRANCH' $worktreeBranch
      ParaforkPrintKv 'CURRENT_BRANCH' $currentBranch
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'checkout correct branch and retry'
      throw 'wrong worktree branch'
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $checkPath --phase merge
    if ($LASTEXITCODE -ne 0) {
      Write-Output 'REFUSED: check --phase merge failed'
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues then rerun: " + (ParaforkPsFileCmd (ParaforkScriptPath 'merge.ps1') @('--yes', '--i-am-maintainer')))
      throw 'check failed'
    }

    $baseTrackedDirty = (& git -C $baseRoot status --porcelain --untracked-files=no 2>$null | Measure-Object).Count
    $baseUntrackedCount = ((& git -C $baseRoot status --porcelain 2>$null) | Where-Object { $_ -match '^\\?\\?' } | Measure-Object).Count

    if ($baseTrackedDirty -ne 0) {
      Write-Output 'REFUSED: base repo not clean (tracked)'
      ParaforkPrintKv 'BASE_TRACKED_DIRTY' $baseTrackedDirty
      ParaforkPrintKv 'BASE_UNTRACKED_COUNT' $baseUntrackedCount
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'clean base repo tracked changes then retry'
      throw 'base dirty'
    }

    $baseCurrentBranch = (& git -C $baseRoot rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1).Trim()
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie 'git rev-parse failed (base branch)'
    }
    if ($baseCurrentBranch -ne $baseBranch) {
      Write-Output 'REFUSED: base branch mismatch'
      ParaforkPrintKv 'BASE_BRANCH' $baseBranch
      ParaforkPrintKv 'BASE_CURRENT_BRANCH' $baseCurrentBranch
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("cd " + (ParaforkQuotePs $baseRoot) + "; git checkout " + (ParaforkQuotePs $baseBranch))
      throw 'base branch mismatch'
    }

    if ($remoteAvailable -and -not $noFetch) {
      & git -C $baseRoot fetch $remoteName
      if ($LASTEXITCODE -ne 0) {
        ParaforkDie "git fetch failed: $remoteName"
      }

      $remoteBase = "$remoteName/$baseBranch"
      $null = & git -C $baseRoot rev-parse --verify "$remoteBase^{commit}" 2>$null
      if ($LASTEXITCODE -ne 0) {
        ParaforkDie "missing remote base ref: $remoteBase"
      }

      & git -C $baseRoot merge --ff-only $remoteBase
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: cannot fast-forward base to remote base'
        ParaforkPrintKv 'REMOTE_BASE' $remoteBase
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'resolve base/remote divergence manually, then retry'
        throw 'base not ff-only'
      }
    } elseif ($remoteAvailable -and $noFetch) {
      Write-Output 'WARN: --no-fetch used; merge may target an out-of-date base'
    }

    Write-Output ("PREVIEW_COMMITS={0}..{1}" -f $baseBranch, $worktreeBranch)
    & git -C $baseRoot log --oneline "$baseBranch..$worktreeBranch" 2>$null | ForEach-Object { $_ }
    Write-Output ""
    Write-Output ("PREVIEW_FILES={0}...{1}" -f $baseBranch, $worktreeBranch)
    & git -C $baseRoot diff --name-status "$baseBranch...$worktreeBranch" 2>$null | ForEach-Object { $_ }

    if (-not $approved) {
      Write-Output 'REFUSED: merge not approved'
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'set PARAFORK_APPROVE_MERGE=1 (or git config parafork.approval.merge=true) and rerun'
      throw 'merge not approved'
    }

    if (-not $yes -or -not $iam) {
      Write-Output 'REFUSED: missing CLI gate'
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'rerun with --yes --i-am-maintainer'
      throw 'missing cli gate'
    }

    $configPath = ParaforkConfigPath
    $squash = ParaforkTomlGetBool $configPath 'control' 'squash' 'true'

    ParaforkPrintKv 'SQUASH' $squash
    ParaforkPrintKv 'BASE_UNTRACKED_COUNT' $baseUntrackedCount

    if ($squash -eq 'true') {
      & git -C $baseRoot merge --squash $worktreeBranch
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: squash merge stopped (likely conflicts)'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("resolve conflicts in " + (ParaforkQuotePs $baseRoot) + " then commit (or git -C " + (ParaforkQuotePs $baseRoot) + " merge --abort)")
        throw 'squash merge failed'
      }
      & git -C $baseRoot commit -m $message
      if ($LASTEXITCODE -ne 0) {
        ParaforkDie 'git commit failed (base)'
      }
    } else {
      & git -C $baseRoot merge --no-ff $worktreeBranch -m $message
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: merge stopped (likely conflicts)'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("resolve then git -C " + (ParaforkQuotePs $baseRoot) + " merge --continue (or git -C " + (ParaforkQuotePs $baseRoot) + " merge --abort)")
        throw 'merge failed'
      }
    }

    $mergedCommit = (& git -C $baseRoot rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
    ParaforkPrintKv 'MERGED_COMMIT' $mergedCommit

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' 'run acceptance steps in paradoc/Merge.md'
  }

  ParaforkInvokeLogged $worktreeRoot 'merge.ps1' $args $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}
