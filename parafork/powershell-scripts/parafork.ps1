Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$invocationPwd = (Get-Location).Path
$entryPath = Join-Path $PSScriptRoot 'parafork.ps1'
$ENTRY_CMD = ParaforkPsFileCmd $entryPath @()

function ParaforkEntryCmd {
  param([string[]]$CmdArgs = @())
  return ParaforkPsFileCmd $entryPath $CmdArgs
}

function ParaforkUsage {
  @"

Parafork — safe worktree contribution workflow (single entry)

Usage:
  $ENTRY_CMD [cmd] [args...]

Commands:
  help
  debug
  init [--new|--reuse] [--base-branch <branch>] [--remote <name>] [--no-remote] [--no-fetch] [--yes] [--i-am-maintainer]
  watch [--once] [--interval <sec>] [--phase exec|merge] [--new]
  check [topic] [args...]
  do <action> [args...]
  merge [--message "<msg>"] [--no-fetch] [--allow-config-drift] [--yes] [--i-am-maintainer]

check topics:
  exec [--strict]    (default)
  merge [--strict]
  plan [--strict]
  status
  diff
  log [--limit <n>]
  review

do actions:
  commit --message "<msg>" [--no-check]
  pull [--strategy ff-only|rebase|merge] [--no-fetch] [--allow-config-drift] [--yes] [--i-am-maintainer]

Compatibility (deprecated but supported):
  status, check --phase <phase>, commit, pull, diff, log, review

Notes:
  - Default (no cmd): watch
  - watch does not auto-commit/merge; it only prints NEXT when safe.
"@
}

function ParaforkDeprecated {
  param(
    [Parameter(Mandatory = $true)][string]$Old,
    [Parameter(Mandatory = $true)][string]$New
  )
  [Console]::Error.WriteLine(("DEPRECATED: {0} -> {1}" -f $Old, $New))
}

function ParaforkWorkdirRoot {
  $configPath = ParaforkConfigPath
  $workdirRoot = '.parafork'
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $workdirRoot = ParaforkTomlGetStr $configPath 'workdir' 'root' '.parafork'
  }
  return $workdirRoot
}

function ParaforkWorktreeContainer {
  param([Parameter(Mandatory = $true)][string]$BaseRoot)
  return (Join-Path $BaseRoot (ParaforkWorkdirRoot))
}

function ParaforkListWorktreesNewestFirst {
  param([Parameter(Mandatory = $true)][string]$BaseRoot)

  $container = ParaforkWorktreeContainer $BaseRoot
  if (-not (Test-Path -LiteralPath $container -PathType Container)) {
    return @()
  }

  $roots = @()
  $children = Get-ChildItem -LiteralPath $container -Directory -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending
  foreach ($c in $children) {
    $candidate = $c.FullName
    if (Test-Path -LiteralPath (Join-Path $candidate '.worktree-symbol') -PathType Leaf) {
      $roots += $candidate
    }
  }

  return $roots
}

function ParaforkHex4 {
  ([System.Guid]::NewGuid().ToString('N').Substring(0, 4)).ToUpperInvariant()
}

function ParaforkExpandRule {
  param([Parameter(Mandatory = $true)][string]$Rule)
  $yymmdd = (Get-Date).ToUniversalTime().ToString('yyMMdd')
  $h = ParaforkHex4
  return $Rule.Replace('{YYMMDD}', $yymmdd).Replace('{HEX4}', $h)
}

function ParaforkAppendUniqueLine {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Line)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    ParaforkWriteTextUtf8NoBom $Path ""
  }

  foreach ($l in [System.IO.File]::ReadAllLines($Path)) {
    if ($l -eq $Line) {
      return
    }
  }

  ParaforkAppendTextUtf8NoBom $Path ($Line + "`n")
}

function ParaforkGuardWorktree {
  $pwdNow = (Get-Location).Path

  $symbolPath = ParaforkSymbolFindUpwards $pwdNow
  if (-not $symbolPath) {
    $baseRoot = ParaforkGitToplevel
    if ($baseRoot) {
      ParaforkPrintOutputBlock 'UNKNOWN' $pwdNow 'FAIL' (ParaforkEntryCmd @('debug'))
      return $null
    }
    ParaforkPrintOutputBlock 'UNKNOWN' $pwdNow 'FAIL' ("cd <BASE_ROOT>; " + (ParaforkEntryCmd @('init', '--new')))
    return $null
  }

  $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
  if ($paraforkWorktree -ne '1') {
    ParaforkPrintOutputBlock 'UNKNOWN' $pwdNow 'FAIL' (ParaforkEntryCmd @('debug'))
    return $null
  }

  $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($worktreeId)) {
    $worktreeId = 'UNKNOWN'
  }

  $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
  if ([string]::IsNullOrEmpty($worktreeRoot)) {
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' (ParaforkEntryCmd @('debug'))
    return $null
  }

  $worktreeUsed = ParaforkSymbolGet $symbolPath 'WORKTREE_USED'
  if ($worktreeUsed -ne '1') {
    Write-Output 'REFUSED: worktree not entered (WORKTREE_USED!=1)'
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' (ParaforkEntryCmd @('init', '--reuse'))
    return $null
  }

  $baseRootValue = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
  return @{
    Ok          = $true
    WorktreeId  = $worktreeId
    WorktreeRoot = $worktreeRoot
    BaseRoot    = $baseRootValue
    SymbolPath  = $symbolPath
  }
}

function EnsureWorktreeUsed {
  param(
    [Parameter(Mandatory = $true)][string]$WorktreeRoot,
    [Parameter(Mandatory = $true)][string]$SymbolPath
  )

  $used = ParaforkSymbolGet $SymbolPath 'WORKTREE_USED'
  if ($used -eq '1') {
    return
  }

  $body = {
    $ok = ParaforkSymbolSet $SymbolPath 'WORKTREE_USED' '1'
    if (-not $ok) {
      ParaforkDie "failed to update .worktree-symbol: $SymbolPath"
    }
    Write-Output 'MODE=reuse'
    ParaforkPrintKv 'WORKTREE_USED' '1'
  }

  ParaforkInvokeLogged $WorktreeRoot 'parafork init' @('--reuse') $body
}

function InitNewWorktree {
  param(
    [string]$BaseBranchOverride = $null,
    [string]$RemoteOverride = $null,
    [bool]$NoRemote = $false,
    [bool]$NoFetch = $false,
    [bool]$Yes = $false,
    [bool]$Iam = $false
  )

  $pwdNow = (Get-Location).Path
  $symbolPath = ParaforkSymbolFindUpwards $pwdNow
  $inWorktree = $false
  $symbolBaseRoot = $null

  if ($symbolPath) {
    $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
    if ($paraforkWorktree -eq '1') {
      $inWorktree = $true
      $symbolBaseRoot = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
    }
  }

  $baseRoot = if ($inWorktree -and $symbolBaseRoot) { $symbolBaseRoot } else { ParaforkGitToplevel }
  if (-not $baseRoot) {
    ParaforkDie 'not in a git repo'
  }

  $configPath = ParaforkConfigPath
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    ParaforkDie "missing config: $configPath (parafork skill package incomplete?)"
  }

  $configBaseBranch = ParaforkTomlGetStr $configPath 'base' 'branch' 'main'
  $configRemoteName = ParaforkTomlGetStr $configPath 'remote' 'name' ''
  $configRemoteAutosync = ParaforkTomlGetBool $configPath 'remote' 'autosync' 'false'
  $workdirRoot = ParaforkTomlGetStr $configPath 'workdir' 'root' '.parafork'
  $workdirRule = ParaforkTomlGetStr $configPath 'workdir' 'rule' '{YYMMDD}-{HEX4}'
  $autoplan = ParaforkTomlGetBool $configPath 'custom' 'autoplan' 'false'

  $baseBranchSource = 'config'
  $baseBranch = $configBaseBranch
  if ($BaseBranchOverride) {
    $baseBranchSource = 'cli'
    $baseBranch = $BaseBranchOverride
  }

  $remoteNameSource = 'config'
  $remoteName = $configRemoteName
  $remoteAutosyncSource = 'config'
  $remoteAutosync = $configRemoteAutosync
  if ($NoRemote) {
    $remoteNameSource = 'none'
    $remoteName = ''
  } elseif ($RemoteOverride) {
    $remoteNameSource = 'cli'
    $remoteName = $RemoteOverride
  } elseif ([string]::IsNullOrEmpty($remoteName)) {
    $remoteNameSource = 'none'
  }

  $remoteAvailable = ParaforkIsRemoteAvailable $baseRoot $remoteName
  $remoteSyncEnabled = ($remoteAvailable -and $remoteAutosync -eq 'true')

  if ($remoteSyncEnabled -and $NoFetch) {
    ParaforkRequireYesIam '--no-fetch' $Yes $Iam
  }

  if ($remoteSyncEnabled -and -not $NoFetch) {
    & git -C $baseRoot fetch $remoteName
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie "git fetch failed: $remoteName"
    }
  }

  if ($remoteAutosync -ne 'true') {
    $baseChanges = (& git -C $baseRoot status --porcelain 2>$null | Measure-Object).Count
    if ($baseChanges -ne 0) {
      Write-Output ("WARN: base repo has uncommitted changes; init uses committed local '{0}' only" -f $baseBranch)
    }
  }

  $worktreeStartPoint = $baseBranch
  if ($remoteSyncEnabled -and -not $NoFetch) {
    $worktreeStartPoint = "$remoteName/$baseBranch"
  }

  $null = & git -C $baseRoot rev-parse --verify "$worktreeStartPoint^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) {
    ParaforkDie "invalid WORKTREE_START_POINT: $worktreeStartPoint"
  }

  $containerRoot = Join-Path $baseRoot $workdirRoot
  $null = New-Item -ItemType Directory -Force -Path $containerRoot

  $worktreeId = $null
  $worktreeRoot = $null
  for ($attempt = 0; $attempt -lt 3; $attempt++) {
    $candidate = ParaforkExpandRule $workdirRule
    $candidateRoot = Join-Path $containerRoot $candidate
    if (Test-Path -LiteralPath $candidateRoot) {
      continue
    }
    $worktreeId = $candidate
    $worktreeRoot = $candidateRoot
    break
  }

  if (-not $worktreeId -or -not $worktreeRoot) {
    ParaforkDie "failed to allocate WORKTREE_ID under $containerRoot (too many collisions)"
  }

  $worktreeBranch = "parafork/$worktreeId"

  & git -C $baseRoot worktree add $worktreeRoot -b $worktreeBranch $worktreeStartPoint
  if ($LASTEXITCODE -ne 0) {
    ParaforkDie "git worktree add failed (root: $worktreeRoot branch: $worktreeBranch start: $worktreeStartPoint)"
  }

  $paraforkRoot = ParaforkRootDir
  $body = {
    $createdAt = ParaforkNowUtc
    $symbolPathNew = Join-Path $worktreeRoot '.worktree-symbol'
    $symbolText = @(
      'PARAFORK_WORKTREE=1'
      ("WORKTREE_ID={0}" -f $worktreeId)
      ("BASE_ROOT={0}" -f $baseRoot)
      ("WORKTREE_ROOT={0}" -f $worktreeRoot)
      ("WORKTREE_BRANCH={0}" -f $worktreeBranch)
      ("WORKTREE_START_POINT={0}" -f $worktreeStartPoint)
      'WORKTREE_USED=1'
      ("BASE_BRANCH={0}" -f $baseBranch)
      ("REMOTE_NAME={0}" -f $remoteName)
      ("REMOTE_AUTOSYNC={0}" -f $remoteAutosync)
      ("BASE_BRANCH_SOURCE={0}" -f $baseBranchSource)
      ("REMOTE_NAME_SOURCE={0}" -f $remoteNameSource)
      ("REMOTE_AUTOSYNC_SOURCE={0}" -f $remoteAutosyncSource)
      ("CREATED_AT={0}" -f $createdAt)
    ) -join "`n"

    ParaforkWriteTextUtf8NoBom $symbolPathNew ($symbolText + "`n")

    $baseExcludePath = ParaforkGitPathAbs $baseRoot 'info/exclude'
    if (-not $baseExcludePath) {
      ParaforkDie "failed to locate base exclude file for repo: $baseRoot"
    }
    ParaforkAppendUniqueLine $baseExcludePath ("/{0}/" -f $workdirRoot)

    $worktreeExcludePath = ParaforkGitPathAbs $worktreeRoot 'info/exclude'
    if (-not $worktreeExcludePath) {
      ParaforkDie "failed to locate worktree exclude file for repo: $worktreeRoot"
    }
    ParaforkAppendUniqueLine $worktreeExcludePath '/.worktree-symbol'
    ParaforkAppendUniqueLine $worktreeExcludePath '/paradoc/'

    $paradocDir = Join-Path $worktreeRoot 'paradoc'
    $null = New-Item -ItemType Directory -Force -Path $paradocDir

    foreach ($doc in @('Exec', 'Merge')) {
      $src = Join-Path $paraforkRoot ("assets/{0}.md" -f $doc)
      $dst = Join-Path $paradocDir ("{0}.md" -f $doc)
      if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        ParaforkDie "missing template: $src"
      }
      if (Test-Path -LiteralPath $dst -PathType Leaf) {
        ParaforkDie "refuse to overwrite: $dst"
      }
      Copy-Item -LiteralPath $src -Destination $dst
    }

    if ($autoplan -eq 'true') {
      $src = Join-Path $paraforkRoot 'assets/Plan.md'
      $dst = Join-Path $paradocDir 'Plan.md'
      if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        ParaforkDie "missing template: $src"
      }
      if (Test-Path -LiteralPath $dst -PathType Leaf) {
        ParaforkDie "refuse to overwrite: $dst"
      }
      Copy-Item -LiteralPath $src -Destination $dst
    }

    Write-Output 'MODE=new'
    ParaforkPrintKv 'AUTOPLAN' $autoplan
    ParaforkPrintKv 'WORKTREE_ROOT' $worktreeRoot
    ParaforkPrintKv 'WORKTREE_START_POINT' $worktreeStartPoint
  }

  ParaforkInvokeLogged $worktreeRoot 'parafork init' @('--new') $body

  return @{
    WorktreeId = $worktreeId
    WorktreeRoot = $worktreeRoot
    BaseRoot = $baseRoot
    WorktreeBranch = $worktreeBranch
    WorktreeStartPoint = $worktreeStartPoint
  }
}

function DoStatus {
  param([bool]$PrintBlock)

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($worktreeId)) {
    $worktreeId = 'UNKNOWN'
  }
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $remoteName = ParaforkSymbolGet $symbolPath 'REMOTE_NAME'
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

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

  if ($PrintBlock) {
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('check', 'exec'))
  }
}

function DoCheck {
  param(
    [Parameter(Mandatory = $true)][string]$Phase,
    [bool]$Strict,
    [Parameter(Mandatory = $true)][string]$Mode # cli|watch
  )

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($worktreeId)) {
    $worktreeId = 'UNKNOWN'
  }

  $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
  if ([string]::IsNullOrEmpty($worktreeRoot)) {
    $worktreeRoot = $pwdNow
  }

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

  if ($Strict) {
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
    if ($Phase -eq 'merge') {
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

  if ($Phase -eq 'merge' -or $Strict) {
    foreach ($f in @($execFile, $mergeFile)) {
      if ((Test-Path -LiteralPath $f -PathType Leaf) -and (Select-String -LiteralPath $f -Pattern 'PARAFORK_TBD|TODO_TBD' -Quiet)) {
        $errors.Add(("placeholder remains: {0}" -f $f))
      }
    }

    if ($autoplan -eq 'true' -and (Test-Path -LiteralPath $planFile -PathType Leaf) -and (Select-String -LiteralPath $planFile -Pattern 'PARAFORK_TBD|TODO_TBD' -Quiet)) {
      $errors.Add(("placeholder remains: {0}" -f $planFile))
    }
  }

  if ($Phase -eq 'merge') {
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

  if ($errors.Count -gt 0) {
    Write-Output 'CHECK_RESULT=FAIL'
    foreach ($e in $errors) {
      Write-Output ("FAIL: {0}" -f $e)
    }
    return $false
  }

  Write-Output 'CHECK_RESULT=PASS'
  return $true
}

function DoReview {
  param([bool]$PrintBlock)

  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($worktreeId)) {
    $worktreeId = 'UNKNOWN'
  }

  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

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

  if ($PrintBlock) {
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' ("edit paradoc/Merge.md then " + (ParaforkEntryCmd @('check', 'merge')))
  }
}

function CmdHelp {
  ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'PASS' (ParaforkEntryCmd @('watch'))
  Write-Output (ParaforkUsage)
  return 0
}

function CmdDebug {
  $pwdNow = (Get-Location).Path
  $symbolPath = ParaforkSymbolFindUpwards $pwdNow

  $debugCmd = ParaforkEntryCmd @('debug')

  if ($symbolPath) {
    $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
    if ($paraforkWorktree -ne '1') {
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' $debugCmd
      ParaforkDie "found .worktree-symbol but not a parafork worktree: $symbolPath"
    }

    $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
    if ([string]::IsNullOrEmpty($worktreeId)) {
      $worktreeId = 'UNKNOWN'
    }
    $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'

    $body = {
      ParaforkPrintKv 'SYMBOL_PATH' $symbolPath
      ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' (ParaforkEntryCmd @('watch'))
    }

    if (-not [string]::IsNullOrEmpty($worktreeRoot)) {
      ParaforkInvokeLogged $worktreeRoot 'parafork debug' @() $body
    } else {
      & $body
    }
    return 0
  }

  $baseRoot = ParaforkGitToplevel
  if (-not $baseRoot) {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help'))
    ParaforkDie 'not in a git repo and no .worktree-symbol found'
  }

  $container = ParaforkWorktreeContainer $baseRoot
  if (-not (Test-Path -LiteralPath $container -PathType Container)) {
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'PASS' (ParaforkEntryCmd @('init', '--new'))
    Write-Output ""
    Write-Output ("No worktree container found at: {0}" -f $container)
    return 0
  }

  $roots = ParaforkListWorktreesNewestFirst $baseRoot
  if (-not $roots -or $roots.Count -eq 0) {
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'PASS' (ParaforkEntryCmd @('init', '--new'))
    Write-Output ""
    Write-Output ("No worktrees found under: {0}" -f $container)
    return 0
  }

  Write-Output "Found worktrees (newest first):"
  foreach ($d in $roots) {
    $id = ParaforkSymbolGet (Join-Path $d '.worktree-symbol') 'WORKTREE_ID'
    if ([string]::IsNullOrEmpty($id)) {
      $id = 'UNKNOWN'
    }
    Write-Output ("- {0}  {1}" -f $id, $d)
  }

  $chosen = $roots[0]
  $chosenId = ParaforkSymbolGet (Join-Path $chosen '.worktree-symbol') 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($chosenId)) {
    $chosenId = 'UNKNOWN'
  }

  $next = "cd " + (ParaforkQuotePs $chosen) + "; " + (ParaforkEntryCmd @('init', '--reuse'))

  $body = {
    Write-Output ""
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock $chosenId $invocationPwd 'PASS' $next
  }

  ParaforkInvokeLogged $chosen 'parafork debug' @() $body
  return 0
}

function CmdInit {
  param([string[]]$CmdArgs)

  $mode = 'auto' # auto|new|reuse
  $baseBranchOverride = $null
  $remoteOverride = $null
  $noRemote = $false
  $noFetch = $false
  $yes = $false
  $iam = $false

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
    switch ($a) {
      '--new' {
        if ($mode -ne 'auto' -and $mode -ne 'new') {
          ParaforkDie '--new and --reuse are mutually exclusive'
        }
        $mode = 'new'
        $i++
        continue
      }
      '--reuse' {
        if ($mode -ne 'auto' -and $mode -ne 'reuse') {
          ParaforkDie '--new and --reuse are mutually exclusive'
        }
        $mode = 'reuse'
        $i++
        continue
      }
      '--base-branch' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --base-branch'
        }
        $baseBranchOverride = $CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--remote' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --remote'
        }
        $remoteOverride = $CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--no-remote' {
        $noRemote = $true
        $i++
        continue
      }
      '--no-fetch' {
        $noFetch = $true
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
        Write-Output ("
Usage: $ENTRY_CMD init [--new|--reuse] [options]

Options:
  --new                    Create a new worktree session
  --reuse                  Mark current worktree as entered (WORKTREE_USED=1)
  --base-branch <branch>   Override base branch for this session (untracked; recorded in .worktree-symbol)
  --remote <name>          Override remote name for this session (untracked; recorded in .worktree-symbol)
  --no-remote              Force REMOTE_NAME empty for this session
  --no-fetch               Skip remote fetch (requires --yes --i-am-maintainer only when remote.autosync=true and remote is available)
  --yes                    Confirmation gate for risky flags
  --i-am-maintainer        Confirmation gate for risky flags
")
        return 0
      }
      '-h' {
        Write-Output ("
Usage: $ENTRY_CMD init [--new|--reuse] [options]

Options:
  --new                    Create a new worktree session
  --reuse                  Mark current worktree as entered (WORKTREE_USED=1)
  --base-branch <branch>   Override base branch for this session (untracked; recorded in .worktree-symbol)
  --remote <name>          Override remote name for this session (untracked; recorded in .worktree-symbol)
  --no-remote              Force REMOTE_NAME empty for this session
  --no-fetch               Skip remote fetch (requires --yes --i-am-maintainer only when remote.autosync=true and remote is available)
  --yes                    Confirmation gate for risky flags
  --i-am-maintainer        Confirmation gate for risky flags
")
        return 0
      }
      default {
        ParaforkDie ("unknown arg: {0}" -f $a)
      }
    }
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = ParaforkSymbolFindUpwards $pwdNow
  $inWorktree = $false
  $symbolWorktreeId = $null
  $symbolWorktreeRoot = $null
  $symbolBaseRoot = $null

  if ($symbolPath) {
    $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
    if ($paraforkWorktree -ne '1') {
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('debug'))
      ParaforkDie "found .worktree-symbol but not a parafork worktree: $symbolPath"
    }
    $inWorktree = $true
    $symbolWorktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
    $symbolWorktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
    $symbolBaseRoot = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
  }

  if ($inWorktree -and $mode -eq 'auto') {
    $wtId = $symbolWorktreeId
    if ([string]::IsNullOrEmpty($wtId)) {
      $wtId = 'UNKNOWN'
    }

    Write-Output 'REFUSED: init called from inside a worktree without --reuse or --new'
    ParaforkPrintKv 'SYMBOL_PATH' $symbolPath
    ParaforkPrintKv 'WORKTREE_ID' $wtId
    ParaforkPrintKv 'WORKTREE_ROOT' $symbolWorktreeRoot
    ParaforkPrintKv 'BASE_ROOT' $symbolBaseRoot
    Write-Output ""
    Write-Output "Choose one:"
    Write-Output ("- Reuse current worktree: {0}" -f (ParaforkEntryCmd @('init', '--reuse')))
    Write-Output ("- Create new worktree:    {0}" -f (ParaforkEntryCmd @('init', '--new')))
    ParaforkPrintOutputBlock $wtId $invocationPwd 'FAIL' (ParaforkEntryCmd @('init', '--new'))
    return 1
  }

  if (-not $inWorktree -and $mode -eq 'reuse') {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('debug'))
    ParaforkDie '--reuse requires being inside an existing parafork worktree'
  }

  if ($mode -eq 'auto') {
    $mode = 'new'
  }

  if ($mode -eq 'reuse') {
    if ($baseBranchOverride -or $remoteOverride -or $noRemote -or $noFetch -or $yes -or $iam) {
      ParaforkDie '--reuse cannot be combined with worktree creation options'
    }

    $worktreeId = $symbolWorktreeId
    if ([string]::IsNullOrEmpty($worktreeId)) {
      $worktreeId = 'UNKNOWN'
    }

    $worktreeRoot = $symbolWorktreeRoot
    if ([string]::IsNullOrEmpty($worktreeRoot)) {
      ParaforkDie "missing WORKTREE_ROOT in .worktree-symbol: $symbolPath"
    }

    EnsureWorktreeUsed $worktreeRoot $symbolPath
    $next = "cd " + (ParaforkQuotePs $worktreeRoot) + "; " + (ParaforkEntryCmd @('check', 'exec'))
    ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' $next
    return 0
  }

  if ($inWorktree -and -not [string]::IsNullOrEmpty($symbolBaseRoot)) {
    $null = Set-Location -LiteralPath $symbolBaseRoot
  }

  $created = InitNewWorktree -BaseBranchOverride $baseBranchOverride -RemoteOverride $remoteOverride -NoRemote:$noRemote -NoFetch:$noFetch -Yes:$yes -Iam:$iam

  $next = "cd " + (ParaforkQuotePs $created.WorktreeRoot) + "; " + (ParaforkEntryCmd @('check', 'exec'))
  ParaforkPrintOutputBlock $created.WorktreeId $invocationPwd 'PASS' $next
  return 0
}

function CmdCheckStatus {
  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $body = { DoStatus $true }
  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check status' @() $body
  return 0
}

function CmdCheckExec {
  param([bool]$Strict)

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $worktreeId = $guard.WorktreeId

  $argv = @()
  if ($Strict) {
    $argv += '--strict'
  }

  $body = {
    $pwdNow = (Get-Location).Path
    DoStatus $false
    if (-not (DoCheck -Phase 'exec' -Strict:$Strict -Mode 'cli')) {
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues and rerun: " + (ParaforkEntryCmd @('check', 'exec')))
      throw 'check failed'
    }

    $changes = (& git status --porcelain 2>$null | Measure-Object).Count
    if ($changes -ne 0) {
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('do', 'commit', '--message', '<msg>'))
    } else {
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' 'edit files (watch will re-check on change)'
    }
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check exec' $argv $body
  return 0
}

function CmdCheckMerge {
  param([bool]$Strict)

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $worktreeId = $guard.WorktreeId

  $argv = @()
  if ($Strict) {
    $argv += '--strict'
  }

  $body = {
    $pwdNow = (Get-Location).Path
    DoStatus $false
    DoReview $false
    if (-not (DoCheck -Phase 'merge' -Strict:$Strict -Mode 'cli')) {
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues then rerun: " + (ParaforkEntryCmd @('check', 'merge')))
      throw 'check failed'
    }

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' ("PARAFORK_APPROVE_MERGE=1 " + (ParaforkEntryCmd @('merge', '--yes', '--i-am-maintainer')))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check merge' $argv $body
  return 0
}

function CmdCheckPlan {
  param([bool]$Strict)

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $worktreeId = $guard.WorktreeId

  $argv = @()
  if ($Strict) {
    $argv += '--strict'
  }

  $body = {
    $pwdNow = (Get-Location).Path
    if (-not (DoCheck -Phase 'plan' -Strict:$Strict -Mode 'cli')) {
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues and rerun: " + (ParaforkEntryCmd @('check', 'plan')))
      throw 'check failed'
    }

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('check', 'exec'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check plan' $argv $body
  return 0
}

function CmdCheck {
  param([string[]]$CmdArgs)

  $strict = $false
  $topic = $null
  $topicProvided = $false
  $phase = $null
  $rest = @()

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
    switch ($a) {
      '--strict' {
        $strict = $true
        $i++
        continue
      }
      '--phase' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --phase'
        }
        $phase = $CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--help' {
        Write-Output ("
Usage: $ENTRY_CMD check [topic] [args...]

Topics:
  exec [--strict]    (default)
  merge [--strict]
  plan [--strict]
  status
  diff
  log [--limit <n>]
  review

Legacy (deprecated):
  check --phase plan|exec|merge [--strict]
")
        return 0
      }
      '-h' {
        Write-Output ("
Usage: $ENTRY_CMD check [topic] [args...]
")
        return 0
      }
      default {
        if (-not $topicProvided) {
          $topic = $a
          $topicProvided = $true
        } else {
          $rest += $a
        }
        $i++
        continue
      }
    }
  }

  if (-not $topicProvided -or [string]::IsNullOrEmpty($topic)) {
    $topic = 'exec'
  }

  if ($phase) {
    if ($topicProvided) {
      ParaforkDie 'cannot combine positional topic and --phase'
    }
    if ($phase -ne 'plan' -and $phase -ne 'exec' -and $phase -ne 'merge') {
      ParaforkDie ("invalid --phase: {0}" -f $phase)
    }
    ParaforkDeprecated ("check --phase {0}" -f $phase) ("check {0}" -f $phase)
    $topic = $phase
  }

  switch ($topic) {
    'exec' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      return (CmdCheckExec -Strict:$strict)
    }
    'merge' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      return (CmdCheckMerge -Strict:$strict)
    }
    'plan' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      return (CmdCheckPlan -Strict:$strict)
    }
    'status' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      return (CmdCheckStatus)
    }
    'diff' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      return (CmdCheckDiff)
    }
    'log' {
      return (CmdCheckLog -CmdArgs $rest)
    }
    'review' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      return (CmdCheckReview)
    }
    default {
      ParaforkDie ("unknown topic: {0}" -f $topic)
    }
  }
}

function CmdDoCommit {
  param([string[]]$CmdArgs)

  $message = $null
  $noCheck = $false

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
    switch ($a) {
      '--message' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --message'
        }
        $message = $CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--no-check' {
        $noCheck = $true
        $i++
        continue
      }
      '--help' {
        Write-Output ('Usage: {0} do commit --message "<msg>" [--no-check]' -f $ENTRY_CMD)
        return 0
      }
      '-h' {
        Write-Output ('Usage: {0} do commit --message "<msg>" [--no-check]' -f $ENTRY_CMD)
        return 0
      }
      default {
        ParaforkDie ("unknown arg: {0}" -f $a)
      }
    }
  }

  if ([string]::IsNullOrEmpty($message)) {
    ParaforkDie 'missing --message'
  }

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $worktreeId = $guard.WorktreeId
  $pwdNow = (Get-Location).Path

  $commitCmd = ParaforkEntryCmd @('do', 'commit', '--message', $message)

  $body = {
    if (-not $noCheck) {
      if (-not (DoCheck -Phase 'exec' -Strict:$false -Mode 'watch')) {
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
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('check', 'exec'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork do commit' @('--message', $message) $body
  return 0
}

function CmdDoPull {
  param([string[]]$CmdArgs)

  $strategy = 'ff-only'
  $noFetch = $false
  $allowDrift = $false
  $yes = $false
  $iam = $false

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
    switch ($a) {
      '--strategy' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --strategy'
        }
        $strategy = $CmdArgs[$i + 1]
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
        Write-Output ("
Usage: $ENTRY_CMD do pull [options]

Default: ff-only (refuse if not fast-forward)

High-risk strategies require approval + CLI gates:
- rebase: PARAFORK_APPROVE_PULL_REBASE=1 (or git config parafork.approval.pull.rebase=true) + --yes --i-am-maintainer
- merge:  PARAFORK_APPROVE_PULL_MERGE=1  (or git config parafork.approval.pull.merge=true)  + --yes --i-am-maintainer

Options:
  --strategy ff-only|rebase|merge
  --no-fetch                 Skip remote fetch (requires --yes --i-am-maintainer only when remote.autosync=true and remote is available)
  --allow-config-drift       Override session config drift checks (requires --yes --i-am-maintainer)
  --yes --i-am-maintainer    Confirmation gates for risky flags
")
        return 0
      }
      '-h' {
        Write-Output ("
Usage: $ENTRY_CMD do pull [options]

Default: ff-only (refuse if not fast-forward)

Options:
  --strategy ff-only|rebase|merge
  --no-fetch                 Skip remote fetch (requires --yes --i-am-maintainer only when remote.autosync=true and remote is available)
  --allow-config-drift       Override session config drift checks (requires --yes --i-am-maintainer)
  --yes --i-am-maintainer    Confirmation gates for risky flags
")
        return 0
      }
      default {
        ParaforkDie ("unknown arg: {0}" -f $a)
      }
    }
  }

  if ($strategy -ne 'ff-only' -and $strategy -ne 'rebase' -and $strategy -ne 'merge') {
    ParaforkDie ("invalid --strategy: {0}" -f $strategy)
  }

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $baseRoot = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $remoteName = ParaforkSymbolGet $symbolPath 'REMOTE_NAME'

  $allowDriftStr = if ($allowDrift) { 'true' } else { 'false' }

  $body = {
    if (-not [string]::IsNullOrEmpty($baseRoot)) {
      ParaforkCheckConfigDrift $allowDriftStr $yes $iam $symbolPath
    }

    $remoteAutosync = ParaforkRemoteAutosyncFromSymbolOrConfig $baseRoot $symbolPath
    $remoteAvailable = $false
    if (-not [string]::IsNullOrEmpty($baseRoot) -and (ParaforkIsRemoteAvailable $baseRoot $remoteName)) {
      $remoteAvailable = $true
    }
    $remoteSyncEnabled = ($remoteAvailable -and $remoteAutosync -eq 'true')

    if ($remoteSyncEnabled -and $noFetch) {
      ParaforkRequireYesIam '--no-fetch' $yes $iam
    }

    $upstream = $baseBranch
    if ($remoteSyncEnabled -and -not $noFetch) {
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

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('check', 'exec'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork do pull' @('--strategy', $strategy) $body
  return 0
}

function CmdDo {
  param([string[]]$CmdArgs)

  if (-not $CmdArgs -or $CmdArgs.Count -eq 0 -or $CmdArgs[0] -eq '--help' -or $CmdArgs[0] -eq '-h') {
    Write-Output ("
Usage: $ENTRY_CMD do <action> [args...]

Actions:
  commit --message ""<msg>"" [--no-check]
  pull [--strategy ff-only|rebase|merge] [--no-fetch] [--allow-config-drift] [--yes] [--i-am-maintainer]
")
    return 0
  }

  $action = $CmdArgs[0]
  $rest = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

  switch ($action) {
    'commit' { return (CmdDoCommit $rest) }
    'pull' { return (CmdDoPull $rest) }
    default { ParaforkDie ("unknown action: {0}" -f $action) }
  }
}

function CmdStatus {
  param([string[]]$CmdArgs = @())
  ParaforkDeprecated 'status' 'check status'
  return (CmdCheck (@('status') + $CmdArgs))
}

function CmdDiff {
  param([string[]]$CmdArgs = @())
  ParaforkDeprecated 'diff' 'check diff'
  return (CmdCheck (@('diff') + $CmdArgs))
}

function CmdLog {
  param([string[]]$CmdArgs = @())
  ParaforkDeprecated 'log' 'check log'
  return (CmdCheck (@('log') + $CmdArgs))
}

function CmdReview {
  param([string[]]$CmdArgs = @())
  ParaforkDeprecated 'review' 'check review'
  return (CmdCheck (@('review') + $CmdArgs))
}

function CmdCommit {
  param([string[]]$CmdArgs = @())
  ParaforkDeprecated 'commit' 'do commit'
  return (CmdDo (@('commit') + $CmdArgs))
}

function CmdPull {
  param([string[]]$CmdArgs = @())
  ParaforkDeprecated 'pull' 'do pull'
  return (CmdDo (@('pull') + $CmdArgs))
}

function CmdCheckDiff {
  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'

  $body = {
    Write-Output ("DIFF_RANGE={0}...HEAD" -f $baseBranch)
    & git diff --stat "$baseBranch...HEAD" 2>$null | ForEach-Object { $_ }
    Write-Output ""
    & git diff "$baseBranch...HEAD" 2>$null | ForEach-Object { $_ }
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('check', 'exec'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check diff' @() $body
  return 0
}

function CmdCheckLog {
  param([string[]]$CmdArgs)

  $limit = 20
  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
    switch ($a) {
      '--limit' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --limit'
        }
        $parsed = 0
        $ok = [int]::TryParse($CmdArgs[$i + 1], [ref]$parsed)
        if (-not $ok -or $parsed -lt 1) {
          ParaforkDie ("invalid --limit: {0}" -f $CmdArgs[$i + 1])
        }
        $limit = $parsed
        $i += 2
        continue
      }
      '--help' {
        Write-Output "Usage: $ENTRY_CMD check log [--limit <n>]"
        return 0
      }
      '-h' {
        Write-Output "Usage: $ENTRY_CMD check log [--limit <n>]"
        return 0
      }
      default {
        ParaforkDie ("unknown arg: {0}" -f $a)
      }
    }
  }

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $pwdNow = (Get-Location).Path
  $worktreeId = $guard.WorktreeId

  $body = {
    & git log --oneline --decorate -n $limit 2>$null | ForEach-Object { $_ }
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('check', 'exec'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check log' @('--limit', "$limit") $body
  return 0
}

function CmdCheckReview {
  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $body = { DoReview $true }
  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check review' @() $body
  return 0
}

function CmdMerge {
  param([string[]]$CmdArgs)

  $yes = $false
  $iam = $false
  $noFetch = $false
  $allowDrift = $false
  $message = $null

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
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
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --message'
        }
        $message = $CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--help' {
        Write-Output ("
Usage: $ENTRY_CMD merge [options]

Preview-only unless all gates are satisfied:
- local approval: PARAFORK_APPROVE_MERGE=1 or git config parafork.approval.merge=true
- CLI gate: --yes --i-am-maintainer

Options:
  --message \"<msg>\"         Override merge commit message (squash mode)
  --no-fetch                 Skip fetch + remote-base alignment (requires --yes --i-am-maintainer only when remote.autosync=true and remote is available)
  --allow-config-drift       Override session config drift checks (requires --yes --i-am-maintainer)
")
        return 0
      }
      '-h' {
        Write-Output ("
Usage: $ENTRY_CMD merge [options]

Preview-only unless all gates are satisfied:
- local approval: PARAFORK_APPROVE_MERGE=1 or git config parafork.approval.merge=true
- CLI gate: --yes --i-am-maintainer

Options:
  --message \"<msg>\"         Override merge commit message (squash mode)
  --no-fetch                 Skip fetch + remote-base alignment (requires --yes --i-am-maintainer only when remote.autosync=true and remote is available)
  --allow-config-drift       Override session config drift checks (requires --yes --i-am-maintainer)
")
        return 0
      }
      default {
        ParaforkDie ("unknown arg: {0}" -f $a)
      }
    }
  }

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot
  $pwdNow = (Get-Location).Path
  $symbolPath = Join-Path $pwdNow '.worktree-symbol'

  $worktreeId = $guard.WorktreeId
  $baseRoot = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
  $baseBranch = ParaforkSymbolGet $symbolPath 'BASE_BRANCH'
  $remoteName = ParaforkSymbolGet $symbolPath 'REMOTE_NAME'
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

  $allowDriftStr = if ($allowDrift) { 'true' } else { 'false' }

  if ([string]::IsNullOrEmpty($message)) {
    $message = "parafork: merge $worktreeId"
  }

  $body = {
    if (-not [string]::IsNullOrEmpty($baseRoot)) {
      ParaforkCheckConfigDrift $allowDriftStr $yes $iam $symbolPath
    }

    $remoteAutosync = ParaforkRemoteAutosyncFromSymbolOrConfig $baseRoot $symbolPath
    $remoteAvailable = $false
    if ($baseRoot -and (ParaforkIsRemoteAvailable $baseRoot $remoteName)) {
      $remoteAvailable = $true
    }
    $remoteSyncEnabled = ($remoteAvailable -and $remoteAutosync -eq 'true')

    if ($remoteSyncEnabled -and $noFetch) {
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

    if (-not (DoCheck -Phase 'merge' -Strict:$false -Mode 'watch')) {
      Write-Output 'REFUSED: check merge failed'
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues then rerun: " + (ParaforkEntryCmd @('merge', '--yes', '--i-am-maintainer')))
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

    if ($remoteSyncEnabled -and -not $noFetch) {
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
    } elseif ($remoteAvailable -and -not $remoteSyncEnabled) {
      Write-Output 'WARN: remote.autosync=false; skip remote-base alignment and use local base'
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

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork merge' $CmdArgs $body
  return 0
}

function CmdWatch {
  param([string[]]$CmdArgs)

  $once = $false
  $interval = 2
  $phase = 'exec'
  $forceNew = $false

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]
    switch ($a) {
      '--once' { $once = $true; $i++; continue }
      '--interval' {
        if ($i + 1 -ge $CmdArgs.Count) { ParaforkDie 'missing value for --interval' }
        $interval = [int]$CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--phase' {
        if ($i + 1 -ge $CmdArgs.Count) { ParaforkDie 'missing value for --phase' }
        $phase = $CmdArgs[$i + 1]
        $i += 2
        continue
      }
      '--new' { $forceNew = $true; $i++; continue }
      '--help' {
        Write-Output "Usage: $ENTRY_CMD watch [--once] [--interval <sec>] [--phase exec|merge] [--new]"
        return 0
      }
      '-h' {
        Write-Output "Usage: $ENTRY_CMD watch [--once] [--interval <sec>] [--phase exec|merge] [--new]"
        return 0
      }
      default { ParaforkDie ("unknown arg: {0}" -f $a) }
    }
  }

  if ($phase -ne 'exec' -and $phase -ne 'merge') {
    ParaforkDie ("invalid --phase: {0}" -f $phase)
  }
  if ($interval -lt 1) {
    ParaforkDie ("invalid --interval: {0}" -f $interval)
  }

  $pwdNow = (Get-Location).Path
  $symbolPath = ParaforkSymbolFindUpwards $pwdNow
  $inWorktree = $false

  if ($symbolPath) {
    if ((ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE') -eq '1') {
      $inWorktree = $true
    }
  }

  if ($inWorktree) {
    $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
    if ([string]::IsNullOrEmpty($worktreeRoot)) {
      ParaforkDie "missing WORKTREE_ROOT in $symbolPath"
    }
    $null = Set-Location -LiteralPath $worktreeRoot
    EnsureWorktreeUsed $worktreeRoot (Join-Path $worktreeRoot '.worktree-symbol')
  } else {
    $baseRoot = ParaforkGitToplevel
    if (-not $baseRoot) {
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help'))
      ParaforkDie 'not in a git repo and no .worktree-symbol found'
    }

    $chosen = $null
    if (-not $forceNew) {
      $roots = ParaforkListWorktreesNewestFirst $baseRoot
      if ($roots -and $roots.Count -gt 0) {
        $chosen = $roots[0]
      }
    }

    if ($chosen) {
      $null = Set-Location -LiteralPath $chosen
      EnsureWorktreeUsed $chosen (Join-Path $chosen '.worktree-symbol')
    } else {
      $null = Set-Location -LiteralPath $baseRoot
      $created = InitNewWorktree
      $null = Set-Location -LiteralPath $created.WorktreeRoot
    }
  }

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }

  $null = Set-Location -LiteralPath $guard.WorktreeRoot

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot

  if ($phase -eq 'merge') {
    DoStatus $false
    DoReview $false
    if (-not (DoCheck -Phase 'merge' -Strict:$false -Mode 'watch')) {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'FAIL' ("fix issues then rerun: " + (ParaforkEntryCmd @('watch', '--phase', 'merge', '--once')))
      return 1
    }
    ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' ("PARAFORK_APPROVE_MERGE=1 " + (ParaforkEntryCmd @('merge', '--yes', '--i-am-maintainer')))
    return 0
  }

  DoStatus $false
  if (-not (DoCheck -Phase 'exec' -Strict:$false -Mode 'watch')) {
    ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'FAIL' ("fix issues and rerun: " + (ParaforkEntryCmd @('check', 'exec')))
    return 1
  }

  if ($once) {
    $changes = (& git status --porcelain 2>$null | Measure-Object).Count
    if ($changes -ne 0) {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' (ParaforkEntryCmd @('do', 'commit', '--message', '<msg>'))
    } else {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' 'edit files (watch will re-check on change)'
    }
    return 0
  }

  $lastHead = (& git rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
  $lastPorcelain = ((& git status --porcelain 2>$null) -join "`n")

  while ($true) {
    Start-Sleep -Seconds $interval

    $head = (& git rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
    $porcelain = ((& git status --porcelain 2>$null) -join "`n")

    if ($head -eq $lastHead -and $porcelain -eq $lastPorcelain) {
      continue
    }

    $lastHead = $head
    $lastPorcelain = $porcelain

    if (-not (DoCheck -Phase 'exec' -Strict:$false -Mode 'watch')) {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'FAIL' ("fix issues and rerun: " + (ParaforkEntryCmd @('check', 'exec')))
      return 1
    }

    DoStatus $false
    $changes = (& git status --porcelain 2>$null | Measure-Object).Count
    if ($changes -ne 0) {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' (ParaforkEntryCmd @('do', 'commit', '--message', '<msg>'))
    } else {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' 'edit files (watch will re-check on change)'
    }
  }
}

try {
  $argv = @($args)

  $cmd = if ($argv.Count -gt 0) { $argv[0] } else { 'watch' }
  if ($cmd -eq '-h' -or $cmd -eq '--help') {
    $cmd = 'help'
    $argv = @()
  } else {
    if ($argv.Count -gt 1) {
      $argv = $argv[1..($argv.Count - 1)]
    } else {
      $argv = @()
    }
  }

  $exitCode = switch ($cmd) {
    'help' { CmdHelp }
    'debug' { CmdDebug }
    'init' { CmdInit $argv }
    'watch' { CmdWatch $argv }
    'status' { CmdStatus $argv }
    'check' { CmdCheck $argv }
    'do' { CmdDo $argv }
    'commit' { CmdCommit $argv }
    'pull' { CmdPull $argv }
    'diff' { CmdDiff $argv }
    'log' { CmdLog $argv }
    'review' { CmdReview $argv }
    'merge' { CmdMerge $argv }
    default {
      Write-Output ("ERROR: unknown command: {0}" -f $cmd)
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help'))
      Write-Output (ParaforkUsage)
      1
    }
  }

  exit $exitCode
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('debug'))
  }
  exit 1
}
