Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$invocationPwd = (Get-Location).Path
$originalArgs = @($args)

$mode = 'auto' # auto|new|reuse
$baseBranchOverride = $null
$remoteOverride = $null
$noRemote = $false
$noFetch = $false
$yes = $false
$iam = $false

$usageText = @"
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File <PARAFORK_SCRIPTS>\init.ps1 [--new|--reuse] [options]

Entry behavior:
  - In base repo: no args defaults to --new
  - Inside a worktree: no args FAIL (must choose --reuse or --new)

Options:
  --new                    Create a new worktree session
  --reuse                  Mark current worktree as entered (WORKTREE_USED=1)
  --base-branch <branch>   Override base branch for this session (untracked; recorded in .worktree-symbol)
  --remote <name>          Override remote name for this session (untracked; recorded in .worktree-symbol)
  --no-remote              Force REMOTE_NAME empty for this session
  --no-fetch               Skip fetch (requires --yes --i-am-maintainer when remote is available)
  --yes                    Confirmation gate for risky flags
  --i-am-maintainer        Confirmation gate for risky flags
"@

for ($i = 0; $i -lt $args.Count; ) {
  $a = $args[$i]
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
      if ($i + 1 -ge $args.Count) {
        ParaforkDie 'missing value for --base-branch'
      }
      $baseBranchOverride = $args[$i + 1]
      $i += 2
      continue
    }
    '--remote' {
      if ($i + 1 -ge $args.Count) {
        ParaforkDie 'missing value for --remote'
      }
      $remoteOverride = $args[$i + 1]
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

function ParaforkHex4 {
  ([System.Guid]::NewGuid().ToString('N').Substring(0, 4)).ToUpperInvariant()
}

function ParaforkExpandRule {
  param([string]$Rule)
  $yymmdd = (Get-Date).ToUniversalTime().ToString('yyMMdd')
  $h = ParaforkHex4
  return $Rule.Replace('{YYMMDD}', $yymmdd).Replace('{HEX4}', $h)
}

function ParaforkAppendUniqueLine {
  param([string]$Path, [string]$Line)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    ParaforkWriteTextUtf8NoBom $Path ""
  }

  $existing = [System.IO.File]::ReadAllLines($Path)
  foreach ($l in $existing) {
    if ($l -eq $Line) {
      return
    }
  }
  ParaforkAppendTextUtf8NoBom $Path ($Line + "`n")
}

try {
  $pwdNow = (Get-Location).Path
  $symbolPath = $null
  $inWorktree = $false
  $symbolWorktreeId = $null
  $symbolWorktreeRoot = $null
  $symbolBaseRoot = $null

  $symbolPath = ParaforkSymbolFindUpwards $pwdNow
  if ($symbolPath) {
    $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
    if ($paraforkWorktree -ne '1') {
      ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
      ParaforkDie "found .worktree-symbol but not a parafork worktree: $symbolPath"
    }
    $inWorktree = $true
    $symbolWorktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
    $symbolWorktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
    $symbolBaseRoot = ParaforkSymbolGet $symbolPath 'BASE_ROOT'
  }

  $scriptDir = ParaforkScriptDir
  $statusCmd = ParaforkPsFileCmd (ParaforkScriptPath 'status.ps1') @()
  $reuseCmd = ParaforkPsFileCmd (ParaforkScriptPath 'init.ps1') @('--reuse')
  $newCmd = ParaforkPsFileCmd (ParaforkScriptPath 'init.ps1') @('--new')

  if ($inWorktree -and $mode -eq 'auto') {
    $body = {
      $wtId = $symbolWorktreeId
      if ([string]::IsNullOrEmpty($wtId)) {
        $wtId = 'UNKNOWN'
      }

      Write-Output 'REFUSED: init.ps1 called from inside a worktree without --reuse or --new'
      ParaforkPrintKv 'SYMBOL_PATH' $symbolPath
      ParaforkPrintKv 'WORKTREE_ID' $wtId
      ParaforkPrintKv 'WORKTREE_ROOT' $symbolWorktreeRoot
      ParaforkPrintKv 'BASE_ROOT' $symbolBaseRoot
      Write-Output ""
      Write-Output "Choose one:"
      Write-Output ("- Reuse current worktree: {0}" -f $reuseCmd)
      Write-Output ("- Create new worktree:    {0}" -f $newCmd)
      ParaforkPrintOutputBlock $wtId $invocationPwd 'FAIL' $newCmd
      throw 'refused'
    }

    if ($symbolWorktreeRoot) {
      ParaforkInvokeLogged $symbolWorktreeRoot 'init.ps1' $originalArgs $body
    } else {
      & $body
    }
    exit 1
  }

  if (-not $inWorktree -and $mode -eq 'reuse') {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
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

    $body = {
      $ok = ParaforkSymbolSet $symbolPath 'WORKTREE_USED' '1'
      if (-not $ok) {
        ParaforkDie "failed to update .worktree-symbol: $symbolPath"
      }
      Write-Output 'MODE=reuse'
      ParaforkPrintKv 'WORKTREE_USED' '1'
      $next = "cd " + (ParaforkQuotePs $worktreeRoot) + "; " + $statusCmd
      ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' $next
    }

    ParaforkInvokeLogged $worktreeRoot 'init.ps1' $originalArgs $body
    exit 0
  }

  $baseRoot = $null
  if ($inWorktree) {
    $baseRoot = $symbolBaseRoot
  } else {
    $baseRoot = ParaforkGitToplevel
  }

  if (-not $baseRoot) {
    $next = "cd <BASE_ROOT>; " + (ParaforkPsFileCmd (ParaforkScriptPath 'init.ps1') @())
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' $next
    ParaforkDie 'not in a git repo'
  }

  $paraforkRoot = ParaforkRootDir
  $configPath = ParaforkConfigPath
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    ParaforkDie "missing config: $configPath (parafork-win skill package incomplete?)"
  }

  $configBaseBranch = ParaforkTomlGetStr $configPath 'base' 'branch' 'main'
  $configRemoteName = ParaforkTomlGetStr $configPath 'remote' 'name' ''
  $workdirRoot = ParaforkTomlGetStr $configPath 'workdir' 'root' '.parafork'
  $workdirRule = ParaforkTomlGetStr $configPath 'workdir' 'rule' '{YYMMDD}-{HEX4}'
  $autoplan = ParaforkTomlGetBool $configPath 'custom' 'autoplan' 'false'

  $baseBranchSource = 'config'
  $baseBranch = $configBaseBranch
  if ($baseBranchOverride) {
    $baseBranchSource = 'cli'
    $baseBranch = $baseBranchOverride
  }

  $remoteNameSource = 'config'
  $remoteName = $configRemoteName
  if ($noRemote) {
    $remoteNameSource = 'none'
    $remoteName = ''
  } elseif ($remoteOverride) {
    $remoteNameSource = 'cli'
    $remoteName = $remoteOverride
  } elseif ([string]::IsNullOrEmpty($remoteName)) {
    $remoteNameSource = 'none'
  }

  $remoteAvailable = ParaforkIsRemoteAvailable $baseRoot $remoteName
  if ($remoteAvailable -and $noFetch) {
    ParaforkRequireYesIam '--no-fetch' $yes $iam
  }

  if ($remoteAvailable -and -not $noFetch) {
    & git -C $baseRoot fetch $remoteName
    if ($LASTEXITCODE -ne 0) {
      ParaforkDie "git fetch failed: $remoteName"
    }
  }

  $worktreeStartPoint = $baseBranch
  if ($remoteAvailable -and -not $noFetch) {
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
      ("BASE_BRANCH_SOURCE={0}" -f $baseBranchSource)
      ("REMOTE_NAME_SOURCE={0}" -f $remoteNameSource)
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

    $startCommit = (& git -C $worktreeRoot rev-parse --short HEAD 2>$null | Select-Object -First 1).Trim()
    $baseCommit = (& git -C $baseRoot rev-parse --short $worktreeStartPoint 2>$null | Select-Object -First 1).Trim()

    Write-Output 'MODE=new'
    ParaforkPrintKv 'AUTOPLAN' $autoplan
    ParaforkPrintKv 'WORKTREE_ROOT' $worktreeRoot
    ParaforkPrintKv 'WORKTREE_START_POINT' $worktreeStartPoint
    ParaforkPrintKv 'START_COMMIT' $startCommit
    ParaforkPrintKv 'BASE_COMMIT' $baseCommit

    $next = "cd " + (ParaforkQuotePs $worktreeRoot) + "; " + $statusCmd
    ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' $next
  }

  ParaforkInvokeLogged $worktreeRoot 'init.ps1' $originalArgs $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' (ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @())
  }
  exit 1
}
