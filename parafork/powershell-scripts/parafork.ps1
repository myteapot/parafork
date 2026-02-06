Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

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
  help [debug|--debug]
  init [--new|--reuse] [--yes] [--i-am-maintainer]
  do <action> [args...]
  check [topic] [args...]
  merge [--message "<msg>"] [--yes] [--i-am-maintainer]

check topics:
  merge [--strict]
  status    (default)

do actions:
  exec [--loop] [--interval <sec>] [--strict]
  commit --message "<msg>" [--no-check]

Notes:
  - Default (no cmd): init --new + do exec
  - init handles worktree lifecycle (new/reuse)
  - do exec performs status+check and prints NEXT
"@
}

function ParaforkUsageInit {
  @"
Usage: $ENTRY_CMD init [--new|--reuse] [options]

Entry behavior:
  - In base repo: no args defaults to --new
  - Inside a worktree: no args FAIL (must choose --reuse or --new)

Options:
  --new                    Create a new worktree session
  --reuse                  Mark current worktree as entered (WORKTREE_USED=1; requires --yes --i-am-maintainer)
  --yes                    Confirmation gate for risky flags
  --i-am-maintainer        Confirmation gate for risky flags
"@
}

function ParaforkUsageCheck {
  @"
Usage: $ENTRY_CMD check [topic] [args...]

Topics:
  merge [--strict]
  status    (default)
"@
}

function ParaforkUsageDo {
  @"
Usage: $ENTRY_CMD do <action> [args...]

Actions:
  exec [--loop] [--interval <sec>] [--strict]
  commit --message "<msg>" [--no-check]
"@
}

function ParaforkUsageDoExec {
  "Usage: $ENTRY_CMD do exec [--loop] [--interval <sec>] [--strict]"
}

function ParaforkUsageDoCommit {
  'Usage: {0} do commit --message "<msg>" [--no-check]' -f $ENTRY_CMD
}

function ParaforkUsageMerge {
  @"
Usage: $ENTRY_CMD merge [options]

Preview-only unless CLI gate is satisfied:
- CLI gate: --yes --i-am-maintainer

Options:
  --message "<msg>"         Override merge commit message (squash mode)
"@
}

function ParaforkIsHelpFlag {
  param([string]$Value)
  return ($Value -eq '--help' -or $Value -eq '-h')
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
      ParaforkPrintOutputBlock 'UNKNOWN' $pwdNow 'FAIL' (ParaforkEntryCmd @('help', '--debug'))
      return $null
    }
    ParaforkPrintOutputBlock 'UNKNOWN' $pwdNow 'FAIL' ("cd <BASE_ROOT>; " + (ParaforkEntryCmd @('init', '--new')))
    return $null
  }

  $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
  if ($paraforkWorktree -ne '1') {
    ParaforkPrintOutputBlock 'UNKNOWN' $pwdNow 'FAIL' (ParaforkEntryCmd @('help', '--debug'))
    return $null
  }

  $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($worktreeId)) {
    $worktreeId = 'UNKNOWN'
  }

  $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
  if ([string]::IsNullOrEmpty($worktreeRoot)) {
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' (ParaforkEntryCmd @('help', '--debug'))
    return $null
  }

  $worktreeUsed = ParaforkSymbolGet $symbolPath 'WORKTREE_USED'
  if ($worktreeUsed -ne '1') {
    Write-Output 'REFUSED: worktree not entered (WORKTREE_USED!=1)'
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' (ParaforkEntryCmd @('init', '--reuse', '--yes', '--i-am-maintainer'))
    return $null
  }

  $lockEnabled = ParaforkSymbolGet $symbolPath 'WORKTREE_LOCK'
  $lockOwner = ParaforkSymbolGet $symbolPath 'WORKTREE_LOCK_OWNER'
  $agentId = ParaforkAgentId

  if ($lockEnabled -ne '1' -or [string]::IsNullOrEmpty($lockOwner)) {
    ParaforkWriteWorktreeLock $symbolPath
    $lockEnabled = '1'
    $lockOwner = $agentId
  }

  if ($lockEnabled -eq '1' -and $lockOwner -ne $agentId) {
    Write-Output 'REFUSED: worktree locked by another agent'
    ParaforkPrintKv 'LOCK_OWNER' $lockOwner
    ParaforkPrintKv 'AGENT_ID' $agentId

    $safeNext = ParaforkEntryCmd @('init', '--new')
    $takeoverNext = "cd " + (ParaforkQuotePs $worktreeRoot) + "; " + (ParaforkEntryCmd @('init', '--reuse', '--yes', '--i-am-maintainer'))

    ParaforkPrintKv 'SAFE_NEXT' $safeNext
    ParaforkPrintKv 'TAKEOVER_NEXT' $takeoverNext
    Write-Output 'RISK: takeover may interrupt another in-flight session; require explicit human approval.'

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' $safeNext
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

  $body = {
    $ok = ParaforkSymbolSet $SymbolPath 'WORKTREE_USED' '1'
    if (-not $ok) {
      ParaforkDie "failed to update .worktree-symbol: $SymbolPath"
    }
    ParaforkWriteWorktreeLock $SymbolPath
    Write-Output 'MODE=reuse'
    ParaforkPrintKv 'WORKTREE_USED' '1'
  }

  ParaforkInvokeLogged $WorktreeRoot 'parafork init' @('--reuse') $body
}

function InitNewWorktree {
  param(
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

  $baseBranch = ParaforkTomlGetStr $configPath 'base' 'branch' 'main'
  $workdirRoot = ParaforkTomlGetStr $configPath 'workdir' 'root' '.parafork'
  $workdirRule = ParaforkTomlGetStr $configPath 'workdir' 'rule' '{YYMMDD}-{HEX4}'
  $autoplan = ParaforkTomlGetBool $configPath 'custom' 'autoplan' 'false'

  $baseChanges = (& git -C $baseRoot status --porcelain 2>$null | Measure-Object).Count
  if ($baseChanges -ne 0) {
    Write-Output ("WARN: base repo has uncommitted changes; init uses committed local '{0}' only" -f $baseBranch)
  }

  $worktreeStartPoint = $baseBranch
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

  $null = & git -C $baseRoot worktree add $worktreeRoot -b $worktreeBranch $worktreeStartPoint
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
      'WORKTREE_USED=1'
      'WORKTREE_LOCK=1'
      ("WORKTREE_LOCK_OWNER={0}" -f (ParaforkAgentId))
      ("WORKTREE_LOCK_AT={0}" -f $createdAt)
      ("BASE_BRANCH={0}" -f $baseBranch)
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
    ParaforkWriteTextUtf8NoBom (Join-Path $paradocDir 'Log.txt') ''

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

    $startCommit = (& git -C $worktreeRoot rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
    $baseCommit = (& git -C $baseRoot rev-parse --short $worktreeStartPoint 2>$null | Select-Object -First 1).Trim()

    Write-Output 'MODE=new'
    ParaforkPrintKv 'AUTOPLAN' $autoplan
    ParaforkPrintKv 'WORKTREE_ROOT' $worktreeRoot
    ParaforkPrintKv 'WORKTREE_START_POINT' $worktreeStartPoint
    ParaforkPrintKv 'START_COMMIT' $startCommit
    ParaforkPrintKv 'BASE_COMMIT' $baseCommit
  }

  $null = ParaforkInvokeLogged $worktreeRoot 'parafork init' @('--new') $body

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
  ParaforkPrintKv 'WORKTREE_BRANCH' $worktreeBranch

  if ($PrintBlock) {
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('do', 'exec'))
  }
}

function DoCheck {
  param(
    [Parameter(Mandatory = $true)][string]$Phase,
    [bool]$Strict
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
      $errors.Add("missing file: $f")
    }
  }

  if ($autoplan -eq 'true' -and $autoformat -eq 'true' -and (Test-Path -LiteralPath $planFile -PathType Leaf)) {
    $planText = [System.IO.File]::ReadAllText($planFile)
    if ($planText -notmatch '(?m)^##\s+Milestones\b') {
      $errors.Add('Plan.md missing heading: ## Milestones')
    }
    if ($planText -notmatch '(?m)^##\s+Tasks\b') {
      $errors.Add('Plan.md missing heading: ## Tasks')
    }
    if ($planText -notmatch '(?m)^- \[.\] ') {
      $errors.Add('Plan.md has no checkboxes')
    }

    if ($Phase -eq 'merge' -and $planText -match '(?m)^- \[ \] T[0-9]+') {
      $errors.Add('Plan.md has incomplete tasks (merge phase requires tasks done)')
    }
  }

  if ($autoformat -eq 'true' -and (Test-Path -LiteralPath $mergeFile -PathType Leaf)) {
    $mergeText = [System.IO.File]::ReadAllText($mergeFile)
    if ($mergeText -notmatch '(?i)Acceptance|Repro') {
      $errors.Add('Merge.md missing Acceptance/Repro section keywords')
    }
  }

  if ($Phase -eq 'merge' -or $Strict) {
    foreach ($f in @($execFile, $mergeFile)) {
      if (Test-Path -LiteralPath $f -PathType Leaf) {
        $t = [System.IO.File]::ReadAllText($f)
        if ($t -match 'PARAFORK_TBD|TODO_TBD') {
          $errors.Add("placeholder remains: $f")
        }
      }
    }
    if ($autoplan -eq 'true' -and (Test-Path -LiteralPath $planFile -PathType Leaf)) {
      $pt = [System.IO.File]::ReadAllText($planFile)
      if ($pt -match 'PARAFORK_TBD|TODO_TBD') {
        $errors.Add("placeholder remains: $planFile")
      }
    }
  }

  if ($Phase -eq 'merge') {
    $trackedParadoc = (& git ls-files -- 'paradoc/' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $trackedParadoc) {
      if (($trackedParadoc | Measure-Object).Count -gt 0) {
        $errors.Add("git pollution: tracked files under paradoc/ (must be empty: git ls-files -- 'paradoc/')")
      }
    }

    $trackedSymbol = (& git ls-files -- '.worktree-symbol' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $trackedSymbol) {
      if (($trackedSymbol | Measure-Object).Count -gt 0) {
        $errors.Add("git pollution: .worktree-symbol is tracked (must be empty: git ls-files -- '.worktree-symbol')")
      }
    }

    $staged = (& git diff --cached --name-only -- 2>$null)
    if ($LASTEXITCODE -eq 0 -and $staged) {
      $polluted = $staged | Where-Object { $_ -match '^(paradoc/|\.worktree-symbol$)' }
      if ($polluted -and ($polluted | Measure-Object).Count -gt 0) {
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
  Write-Output ''
  Write-Output ("#### Commits ({0}..{1})" -f $baseBranch, $worktreeBranch)
  & git log --oneline "$baseBranch..$worktreeBranch" 2>$null | ForEach-Object { $_ }
  Write-Output ''
  Write-Output ("#### Files ({0}...{1})" -f $baseBranch, $worktreeBranch)
  & git diff --name-status "$baseBranch...$worktreeBranch" 2>$null | ForEach-Object { $_ }
  Write-Output ''
  Write-Output '#### Notes'
  Write-Output '- Ensure Merge.md contains Acceptance / Repro steps.'
  Write-Output '- Mention risks and rollback plan if relevant.'

  if ($PrintBlock) {
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' ("edit paradoc/Merge.md then " + (ParaforkEntryCmd @('check', 'merge')))
  }
}

function CmdHelp {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) {
    $CmdArgs = @()
  }

  $topic = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { '' }
  switch ($topic) {
    '' {
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'PASS' (ParaforkEntryCmd @())
      Write-Output (ParaforkUsage)
      return 0
    }
    'debug' {
      if ($CmdArgs.Count -gt 1) {
        ParaforkDie ("unknown arg for help debug: {0}" -f $CmdArgs[1])
      }
      return (CmdDebug)
    }
    '--debug' {
      if ($CmdArgs.Count -gt 1) {
        ParaforkDie ("unknown arg for help --debug: {0}" -f $CmdArgs[1])
      }
      return (CmdDebug)
    }
    default {
      ParaforkDie ("unknown help topic: {0}" -f $topic)
    }
  }
}

function CmdDebug {
  $pwdNow = (Get-Location).Path
  $symbolPath = ParaforkSymbolFindUpwards $pwdNow

  $debugCmd = ParaforkEntryCmd @('help', '--debug')

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
      ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' (ParaforkEntryCmd @('do', 'exec'))
    }

    if (-not [string]::IsNullOrEmpty($worktreeRoot)) {
      ParaforkInvokeLogged $worktreeRoot 'parafork help debug' @() $body
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

  $next = "cd " + (ParaforkQuotePs $chosen) + "; " + (ParaforkEntryCmd @('init', '--reuse', '--yes', '--i-am-maintainer'))

  $body = {
    Write-Output ""
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock $chosenId $invocationPwd 'PASS' $next
  }

  ParaforkInvokeLogged $chosen 'parafork help debug' @() $body
  return 0
}

function CmdInit {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) { $CmdArgs = @() }

  $mode = 'auto' # auto|new|reuse
  $yes = $false
  $iam = $false

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]

    if (ParaforkIsHelpFlag $a) {
      Write-Output (ParaforkUsageInit)
      return 0
    }

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
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help', '--debug'))
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
    Write-Output 'Choose one:'
    Write-Output ("- Reuse current worktree: {0}" -f (ParaforkEntryCmd @('init', '--reuse', '--yes', '--i-am-maintainer')))
    Write-Output ("- Create new worktree:    {0}" -f (ParaforkEntryCmd @('init', '--new')))
    ParaforkPrintOutputBlock $wtId $invocationPwd 'FAIL' (ParaforkEntryCmd @('init', '--new'))
    return 1
  }

  if (-not $inWorktree -and $mode -eq 'reuse') {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help', '--debug'))
    ParaforkDie '--reuse requires being inside an existing parafork worktree'
  }

  if ($mode -eq 'auto') {
    $mode = 'new'
  }

  if ($mode -eq 'reuse') {
    if ([string]::IsNullOrEmpty($symbolBaseRoot)) {
      ParaforkDie "missing BASE_ROOT in .worktree-symbol: $symbolPath"
    }

    ParaforkRequireYesIam '--reuse' $yes $iam

    $worktreeId = $symbolWorktreeId
    if ([string]::IsNullOrEmpty($worktreeId)) {
      $worktreeId = 'UNKNOWN'
    }

    $worktreeRoot = $symbolWorktreeRoot
    if ([string]::IsNullOrEmpty($worktreeRoot)) {
      ParaforkDie "missing WORKTREE_ROOT in .worktree-symbol: $symbolPath"
    }

    EnsureWorktreeUsed $worktreeRoot $symbolPath
    $next = "cd " + (ParaforkQuotePs $worktreeRoot) + "; " + (ParaforkEntryCmd @('do', 'exec'))
    ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' $next
    return 0
  }

  if ($inWorktree -and -not [string]::IsNullOrEmpty($symbolBaseRoot)) {
    $null = Set-Location -LiteralPath $symbolBaseRoot
  }

  $createdRaw = @(InitNewWorktree -Yes:$yes -Iam:$iam)
  $created = $null
  foreach ($item in $createdRaw) {
    if ($item -is [hashtable]) {
      $created = $item
    } else {
      Write-Output $item
    }
  }

  if (-not $created) {
    ParaforkDie 'init failed: missing worktree metadata'
  }

  $next = "cd " + (ParaforkQuotePs $created.WorktreeRoot) + "; " + (ParaforkEntryCmd @('do', 'exec'))
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
    if (-not (DoCheck -Phase 'merge' -Strict:$Strict)) {
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues then rerun: " + (ParaforkEntryCmd @('check', 'merge')))
      throw 'check failed'
    }

    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('merge', '--yes', '--i-am-maintainer'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork check merge' $argv $body
  return 0
}

function CmdCheck {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) { $CmdArgs = @() }

  $strict = $false
  $topic = $null
  $topicProvided = $false
  $rest = @()

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]

    if (ParaforkIsHelpFlag $a) {
      Write-Output (ParaforkUsageCheck)
      return 0
    }

    switch ($a) {
      '--strict' {
        $strict = $true
        $i++
        continue
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
    $topic = 'status'
  }

  switch ($topic) {
    'merge' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      $code = CmdCheckMerge -Strict:$strict
      return $code
    }
    'status' {
      if ($rest.Count -gt 0) {
        ParaforkDie ("unknown arg: {0}" -f $rest[0])
      }
      $code = CmdCheckStatus
      return $code
    }
    default {
      ParaforkDie ("unknown topic: {0}" -f $topic)
    }
  }
}

function CmdDoExec {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) { $CmdArgs = @() }

  $strict = $false
  $loop = $false
  $interval = 2

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]

    if (ParaforkIsHelpFlag $a) {
      Write-Output (ParaforkUsageDoExec)
      return 0
    }

    switch ($a) {
      '--strict' { $strict = $true; $i++; continue }
      '--loop' { $loop = $true; $i++; continue }
      '--interval' {
        if ($i + 1 -ge $CmdArgs.Count) { ParaforkDie 'missing value for --interval' }
        $interval = [int]$CmdArgs[$i + 1]
        $i += 2
        continue
      }
      default { ParaforkDie ("unknown arg: {0}" -f $a) }
    }
  }

  if ($interval -lt 1) {
    ParaforkDie ("invalid --interval: {0}" -f $interval)
  }

  $guard = ParaforkGuardWorktree
  if (-not $guard) {
    return 1
  }
  $null = Set-Location -LiteralPath $guard.WorktreeRoot

  $worktreeId = $guard.WorktreeId
  $worktreeRoot = $guard.WorktreeRoot

  $execOnce = {
    DoStatus $false
    if (-not (DoCheck -Phase 'exec' -Strict:$strict)) {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'FAIL' ("fix issues and rerun: " + (ParaforkEntryCmd @('do', 'exec')))
      throw 'check failed'
    }

    $changes = (& git status --porcelain 2>$null | Measure-Object).Count
    if ($changes -ne 0) {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' (ParaforkEntryCmd @('do', 'commit', '--message', '<msg>'))
    } else {
      ParaforkPrintOutputBlock $worktreeId $worktreeRoot 'PASS' ("edit files (rerun: " + (ParaforkEntryCmd @('do', 'exec')) + ")")
    }
  }

  if (-not $loop) {
    try {
      & $execOnce
      return 0
    } catch {
      return 1
    }
  }

  try {
    & $execOnce
  } catch {
    return 1
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

    try {
      & $execOnce
    } catch {
      return 1
    }
  }
}

function CmdDoCommit {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) { $CmdArgs = @() }

  $message = $null
  $noCheck = $false

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]

    if (ParaforkIsHelpFlag $a) {
      Write-Output (ParaforkUsageDoCommit)
      return 0
    }

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
      if (-not (DoCheck -Phase 'exec' -Strict:$false)) {
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
      $pollution = $staged | Where-Object { $_ -match '^(paradoc/|\.worktree-symbol$)' }
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
    ParaforkPrintOutputBlock $worktreeId $pwdNow 'PASS' (ParaforkEntryCmd @('do', 'exec'))
  }

  ParaforkInvokeLogged $guard.WorktreeRoot 'parafork do commit' @('--message', $message) $body
  return 0
}

function CmdDo {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) { $CmdArgs = @() }

  if (-not $CmdArgs -or $CmdArgs.Count -eq 0 -or (ParaforkIsHelpFlag $CmdArgs[0])) {
    Write-Output (ParaforkUsageDo)
    return 0
  }

  $action = $CmdArgs[0]
  $rest = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

  switch ($action) {
    'exec' { $code = CmdDoExec -CmdArgs $rest; return $code }
    'commit' { $code = CmdDoCommit -CmdArgs $rest; return $code }
    default { ParaforkDie ("unknown action: {0}" -f $action) }
  }
}

function CmdMerge {
  param([string[]]$CmdArgs = @())

  if ($null -eq $CmdArgs) { $CmdArgs = @() }

  $yes = $false
  $iam = $false
  $message = $null

  for ($i = 0; $i -lt $CmdArgs.Count; ) {
    $a = $CmdArgs[$i]

    if (ParaforkIsHelpFlag $a) {
      Write-Output (ParaforkUsageMerge)
      return 0
    }

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
      '--message' {
        if ($i + 1 -ge $CmdArgs.Count) {
          ParaforkDie 'missing value for --message'
        }
        $message = $CmdArgs[$i + 1]
        $i += 2
        continue
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
  $worktreeBranch = ParaforkSymbolGet $symbolPath 'WORKTREE_BRANCH'

  if ([string]::IsNullOrEmpty($message)) {
    $message = "parafork: merge $worktreeId"
  }

  $body = {

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

    DoStatus $false
    DoReview $false
    if (-not (DoCheck -Phase 'merge' -Strict:$false)) {
      Write-Output 'REFUSED: check merge failed'
      ParaforkPrintOutputBlock $worktreeId $pwdNow 'FAIL' ("fix issues then rerun: " + (ParaforkEntryCmd @('check', 'merge')))
      throw 'check failed'
    }

    $baseTrackedDirty = (& git -C $baseRoot status --porcelain --untracked-files=no 2>$null | Measure-Object).Count
    $baseUntrackedCount = ((& git -C $baseRoot status --porcelain 2>$null) | Where-Object { $_ -match '^\?\?' } | Measure-Object).Count

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

    Write-Output ("PREVIEW_COMMITS={0}..{1}" -f $baseBranch, $worktreeBranch)
    & git -C $baseRoot log --oneline "$baseBranch..$worktreeBranch" 2>$null | ForEach-Object { $_ }
    Write-Output ""
    Write-Output ("PREVIEW_FILES={0}...{1}" -f $baseBranch, $worktreeBranch)
    & git -C $baseRoot diff --name-status "$baseBranch...$worktreeBranch" 2>$null | ForEach-Object { $_ }

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
function CmdDefault {
  $pwdNow = (Get-Location).Path
  $symbolPath = ParaforkSymbolFindUpwards $pwdNow
  $inWorktree = $false

  if ($symbolPath) {
    if ((ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE') -eq '1') {
      $inWorktree = $true
    }
  }

  $baseRoot = if ($inWorktree) { ParaforkSymbolGet $symbolPath 'BASE_ROOT' } else { ParaforkGitToplevel }
  if (-not $baseRoot) {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help'))
    ParaforkDie 'not in a git repo and no .worktree-symbol found'
  }

  $null = Set-Location -LiteralPath $baseRoot
  $createdRaw = @(InitNewWorktree)
  $created = $null
  foreach ($item in $createdRaw) {
    if ($item -is [hashtable]) {
      $created = $item
    } else {
      Write-Output $item
    }
  }

  if (-not $created) {
    ParaforkDie 'default flow failed: missing worktree metadata'
  }

  $null = Set-Location -LiteralPath $created.WorktreeRoot

  return (CmdDoExec @())
}

function InvokeParaforkCommand {
  param([Parameter(Mandatory = $true)][scriptblock]$Script)

  $items = @(& $Script)
  if ($items.Count -eq 0) {
    return 0
  }

  $exitCode = 0
  $last = $items[-1]
  if ($last -is [int]) {
    $exitCode = [int]$last
    if ($items.Count -gt 1) {
      $items = $items[0..($items.Count - 2)]
    } else {
      $items = @()
    }
  }

  foreach ($item in $items) {
    Write-Host $item
  }

  return $exitCode
}

try {
  $argv = @($args)

  $cmd = if ($argv.Count -gt 0) { $argv[0] } else { '' }
  if (-not $cmd) {
    $exitCode = InvokeParaforkCommand { CmdDefault }
    exit $exitCode
  }

  if (ParaforkIsHelpFlag $cmd) {
    $cmd = 'help'
    $argv = @()
  } else {
    if ($argv.Count -gt 1) {
      $argv = $argv[1..($argv.Count - 1)]
    } else {
      $argv = @()
    }
  }

  $exitCode = 0
  switch ($cmd) {
    'help' {
      $exitCode = InvokeParaforkCommand { CmdHelp $argv }
      break
    }
    'init' {
      $exitCode = InvokeParaforkCommand { CmdInit $argv }
      break
    }
    'check' {
      $exitCode = InvokeParaforkCommand { CmdCheck $argv }
      break
    }
    'do' {
      $exitCode = InvokeParaforkCommand { CmdDo $argv }
      break
    }
    'merge' {
      $exitCode = InvokeParaforkCommand { CmdMerge $argv }
      break
    }
    default {
      $exitCode = InvokeParaforkCommand {
        Write-Output ("ERROR: unknown command: {0}" -f $cmd)
        ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help'))
        Write-Output (ParaforkUsage)
        return 1
      }
      break
    }
  }

  exit $exitCode
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkEntryCmd @('help', '--debug'))
  }
  exit 1
}
