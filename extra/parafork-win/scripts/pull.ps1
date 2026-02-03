Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$strategy = 'ff-only'
$noFetch = $false
$allowDrift = $false
$yes = $false
$iam = $false

$usageText = @"
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\pull.ps1 [options]

Default: ff-only (refuse if not fast-forward)

High-risk strategies require approval + CLI gates:
- rebase: PARAFORK_APPROVE_PULL_REBASE=1 (or git config parafork.approval.pull.rebase=true) + --yes --i-am-maintainer
- merge:  PARAFORK_APPROVE_PULL_MERGE=1  (or git config parafork.approval.pull.merge=true)  + --yes --i-am-maintainer

Options:
  --strategy ff-only|rebase|merge
  --no-fetch                 Skip fetch (requires --yes --i-am-maintainer when remote is available)
  --allow-config-drift        Override session config drift checks (requires --yes --i-am-maintainer)
  --yes --i-am-maintainer     Confirmation gates for risky flags
"@

for ($i = 0; $i -lt $args.Count; ) {
  $a = $args[$i]
  switch ($a) {
    '--strategy' {
      if ($i + 1 -ge $args.Count) {
        ParaforkDie 'missing value for --strategy'
      }
      $strategy = $args[$i + 1]
      $i += 2
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

if ($strategy -ne 'ff-only' -and $strategy -ne 'rebase' -and $strategy -ne 'merge') {
  ParaforkDie ("invalid --strategy: {0}" -f $strategy)
}

try {
  $guard = ParaforkGuardWorktreeRoot 'pull.ps1' $args
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

  $allowDriftStr = if ($allowDrift) { 'true' } else { 'false' }

  $statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()

  $body = {
    if (-not [string]::IsNullOrEmpty($baseRoot)) {
      ParaforkCheckConfigDrift $allowDriftStr $yes $iam $symbolPath
    }

    $remoteAvailable = $false
    if (-not [string]::IsNullOrEmpty($baseRoot) -and (ParaforkIsRemoteAvailable $baseRoot $remoteName)) {
      $remoteAvailable = $true
    }

    if ($remoteAvailable -and $noFetch) {
      ParaforkRequireYesIam '--no-fetch' $yes $iam
    }

    $upstream = $baseBranch
    if ($remoteAvailable -and -not $noFetch) {
      & git -C $baseRoot fetch $remoteName
      if ($LASTEXITCODE -ne 0) {
        ParaforkDie "git fetch failed: $remoteName"
      }
      $upstream = "$remoteName/$baseBranch"
    }

    ParaforkPrintKv 'STRATEGY' $strategy
    ParaforkPrintKv 'UPSTREAM' $upstream

    $approveRebase = $false
    if ($env:PARAFORK_APPROVE_PULL_REBASE -eq '1') {
      $approveRebase = $true
    } elseif ($baseRoot) {
      $v = (& git -C $baseRoot config --bool --default false parafork.approval.pull.rebase 2>$null | Select-Object -First 1).Trim()
      if ($v -eq 'true') {
        $approveRebase = $true
      }
    }

    $approveMerge = $false
    if ($env:PARAFORK_APPROVE_PULL_MERGE -eq '1') {
      $approveMerge = $true
    } elseif ($baseRoot) {
      $v = (& git -C $baseRoot config --bool --default false parafork.approval.pull.merge 2>$null | Select-Object -First 1).Trim()
      if ($v -eq 'true') {
        $approveMerge = $true
      }
    }

    if ($strategy -eq 'rebase') {
      if (-not $approveRebase) {
        Write-Output 'REFUSED: pull rebase not approved'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'ask maintainer then rerun with PARAFORK_APPROVE_PULL_REBASE=1 and --yes --i-am-maintainer'
        throw 'pull rebase not approved'
      }
      ParaforkRequireYesIam '--strategy rebase' $yes $iam
      & git rebase $upstream
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: rebase stopped (likely conflicts)'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'resolve then git rebase --continue (or git rebase --abort)'
        throw 'rebase failed'
      }
    } elseif ($strategy -eq 'merge') {
      if (-not $approveMerge) {
        Write-Output 'REFUSED: pull merge not approved'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'ask maintainer then rerun with PARAFORK_APPROVE_PULL_MERGE=1 and --yes --i-am-maintainer'
        throw 'pull merge not approved'
      }
      ParaforkRequireYesIam '--strategy merge' $yes $iam
      & git merge --no-ff $upstream
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: merge stopped (likely conflicts)'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'resolve then git merge --continue (or git merge --abort)'
        throw 'merge failed'
      }
    } else {
      & git merge --ff-only $upstream
      if ($LASTEXITCODE -ne 0) {
        Write-Output 'REFUSED: cannot fast-forward'
        ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' 'ask maintainer to approve rebase/merge strategy'
        throw 'ff-only failed'
      }
    }

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' $statusCmd
  }

  ParaforkInvokeLogged $worktreeRoot 'pull.ps1' @('--strategy', $strategy) $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' (Get-Location).Path 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}
