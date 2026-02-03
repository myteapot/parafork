$global:PARAFORK_OUTPUT_BLOCK_PRINTED = $false

function ParaforkNowUtc {
  [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss'Z'")
}

function ParaforkDie {
  param([string]$Message)
  Write-Output "ERROR: $Message"
  throw $Message
}

function ParaforkWarn {
  param([string]$Message)
  Write-Output "WARN: $Message"
}

function ParaforkScriptDir {
  if ($PSScriptRoot) {
    return $PSScriptRoot
  }
  return Split-Path -Parent $MyInvocation.MyCommand.Path
}

function ParaforkRootDir {
  Split-Path -Parent (ParaforkScriptDir)
}

function ParaforkScriptPath {
  param([string]$Name)
  Join-Path (ParaforkScriptDir) $Name
}

function ParaforkConfigPath {
  Join-Path (ParaforkRootDir) 'settings/config.toml'
}

function ParaforkNormalizePath {
  param([string]$Path)
  try {
    return (Resolve-Path -LiteralPath $Path).Path
  } catch {
    return [System.IO.Path]::GetFullPath($Path)
  }
}

function ParaforkQuotePs {
  param([string]$Value)

  if ($null -eq $Value) {
    return '""'
  }

  $needsQuotes = $Value -match '[\s"`;]'
  if (-not $needsQuotes) {
    return $Value
  }

  $escaped = $Value.Replace('`', '``').Replace('"', '`"')
  return '"' + $escaped + '"'
}

function ParaforkPsFileCmd {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$Args = @()
  )

  $parts = @(
    'powershell',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (ParaforkQuotePs $FilePath)
  )

  foreach ($a in $Args) {
    $parts += (ParaforkQuotePs $a)
  }

  return ($parts -join ' ')
}

function ParaforkPrintKv {
  param([string]$Key, [string]$Value)
  if ($null -eq $Value) {
    $Value = ""
  }
  Write-Output ("{0}={1}" -f $Key, $Value)
}

function ParaforkPrintOutputBlock {
  param(
    [string]$WorktreeId,
    [string]$Pwd,
    [string]$Status,
    [string]$Next
  )

  $global:PARAFORK_OUTPUT_BLOCK_PRINTED = $true
  ParaforkPrintKv 'WORKTREE_ID' $WorktreeId
  ParaforkPrintKv 'PWD' $Pwd
  ParaforkPrintKv 'STATUS' $Status
  ParaforkPrintKv 'NEXT' $Next
}

function ParaforkTomlGetRaw {
  param(
    [string]$File,
    [string]$Section,
    [string]$Key
  )

  if (-not (Test-Path -LiteralPath $File)) {
    return $null
  }

  $inSection = $false
  foreach ($line in [System.IO.File]::ReadAllLines($File)) {
    $trim = $line.Trim()
    if ($trim -eq '' -or $trim.StartsWith('#')) {
      continue
    }

    if ($trim.StartsWith('[') -and $trim.EndsWith(']')) {
      $sec = $trim.Trim('[', ']').Trim()
      $inSection = ($sec -eq $Section)
      continue
    }

    if (-not $inSection) {
      continue
    }

    $noComment = $line
    $hashIndex = $noComment.IndexOf('#')
    if ($hashIndex -ge 0) {
      $noComment = $noComment.Substring(0, $hashIndex)
    }
    $noComment = $noComment.Trim()
    if ($noComment -eq '') {
      continue
    }

    $eqIndex = $noComment.IndexOf('=')
    if ($eqIndex -lt 0) {
      continue
    }

    $k = $noComment.Substring(0, $eqIndex).Trim()
    $v = $noComment.Substring($eqIndex + 1).Trim()
    if ($k -eq $Key) {
      return $v
    }
  }

  return $null
}

function ParaforkTomlGetStr {
  param(
    [string]$File,
    [string]$Section,
    [string]$Key,
    [string]$Default
  )

  $raw = ParaforkTomlGetRaw $File $Section $Key
  if ($null -eq $raw) {
    return $Default
  }

  if ($raw.Length -ge 2) {
    if (($raw.StartsWith('"') -and $raw.EndsWith('"')) -or ($raw.StartsWith("'") -and $raw.EndsWith("'"))) {
      $raw = $raw.Substring(1, $raw.Length - 2)
    }
  }

  if ([string]::IsNullOrEmpty($raw)) {
    return $Default
  }

  return $raw
}

function ParaforkTomlGetBool {
  param(
    [string]$File,
    [string]$Section,
    [string]$Key,
    [string]$Default
  )

  $raw = ParaforkTomlGetRaw $File $Section $Key
  if ($null -eq $raw) {
    return $Default
  }

  $raw = $raw.ToLowerInvariant()
  switch ($raw) {
    'true' { return 'true' }
    'false' { return 'false' }
    default { return $Default }
  }
}

function ParaforkGitToplevel {
  $out = & git rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0) {
    return $null
  }
  if ($null -eq $out) {
    return $null
  }
  return ($out | Select-Object -First 1).Trim()
}

function ParaforkGitPathAbs {
  param([string]$RepoRoot, [string]$GitPath)

  $p = & git -C $RepoRoot rev-parse --git-path $GitPath 2>$null
  if ($LASTEXITCODE -ne 0) {
    return $null
  }
  $p = ($p | Select-Object -First 1).Trim()
  if ([System.IO.Path]::IsPathRooted($p)) {
    return $p
  }
  return (Join-Path $RepoRoot $p)
}

function ParaforkIsRemoteAvailable {
  param([string]$BaseRoot, [string]$RemoteName)
  if ([string]::IsNullOrEmpty($RemoteName)) {
    return $false
  }
  $null = & git -C $BaseRoot remote get-url $RemoteName 2>$null
  return ($LASTEXITCODE -eq 0)
}

function ParaforkSymbolFindUpwards {
  param([string]$StartDir)

  $cur = ParaforkNormalizePath $StartDir
  while ($true) {
    $candidate = Join-Path $cur '.worktree-symbol'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
    $parent = Split-Path -Parent $cur
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $cur) {
      return $null
    }
    $cur = $parent
  }
}

function ParaforkSymbolGet {
  param([string]$SymbolPath, [string]$Key)

  if (-not (Test-Path -LiteralPath $SymbolPath -PathType Leaf)) {
    return $null
  }

  foreach ($line in [System.IO.File]::ReadAllLines($SymbolPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    if ($line.StartsWith('#')) {
      continue
    }
    $idx = $line.IndexOf('=')
    if ($idx -lt 0) {
      continue
    }
    $k = $line.Substring(0, $idx)
    if ($k -eq $Key) {
      return $line.Substring($idx + 1)
    }
  }

  return $null
}

function ParaforkUtf8NoBom {
  New-Object System.Text.UTF8Encoding($false)
}

function ParaforkWriteTextUtf8NoBom {
  param([string]$Path, [string]$Text)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    $null = New-Item -ItemType Directory -Force -Path $dir
  }
  [System.IO.File]::WriteAllText($Path, $Text, (ParaforkUtf8NoBom))
}

function ParaforkAppendTextUtf8NoBom {
  param([string]$Path, [string]$Text)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    $null = New-Item -ItemType Directory -Force -Path $dir
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    ParaforkWriteTextUtf8NoBom $Path ""
  }
  [System.IO.File]::AppendAllText($Path, $Text, (ParaforkUtf8NoBom))
}

function ParaforkSymbolSet {
  param([string]$SymbolPath, [string]$Key, [string]$Value)

  if (-not (Test-Path -LiteralPath $SymbolPath -PathType Leaf)) {
    return $false
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $found = $false
  foreach ($line in [System.IO.File]::ReadAllLines($SymbolPath)) {
    if ($line -match '^[^=]+=') {
      $idx = $line.IndexOf('=')
      $k = $line.Substring(0, $idx)
      if ($k -eq $Key) {
        $lines.Add(("{0}={1}" -f $Key, $Value))
        $found = $true
        continue
      }
    }
    $lines.Add($line)
  }

  if (-not $found) {
    $lines.Add(("{0}={1}" -f $Key, $Value))
  }

  $text = ($lines -join "`n") + "`n"
  ParaforkWriteTextUtf8NoBom $SymbolPath $text
  return $true
}

function ParaforkGuardWorktreeRoot {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptBasename,
    [string[]]$Args = @()
  )

  $pwd = (Get-Location).Path

  $debugPath = ParaforkScriptPath 'debug.ps1'
  $initPath = ParaforkScriptPath 'init.ps1'

  $symbolPath = ParaforkSymbolFindUpwards $pwd
  if (-not $symbolPath) {
    $baseRoot = ParaforkGitToplevel
    if ($baseRoot) {
      ParaforkPrintOutputBlock 'UNKNOWN' $pwd 'FAIL' (ParaforkPsFileCmd $debugPath @())
      return $null
    }
    ParaforkPrintOutputBlock 'UNKNOWN' $pwd 'FAIL' ("cd <BASE_ROOT>; " + (ParaforkPsFileCmd $initPath @()))
    return $null
  }

  $paraforkWorktree = ParaforkSymbolGet $symbolPath 'PARAFORK_WORKTREE'
  if ($paraforkWorktree -ne '1') {
    ParaforkPrintOutputBlock 'UNKNOWN' $pwd 'FAIL' (ParaforkPsFileCmd $debugPath @())
    return $null
  }

  $worktreeId = ParaforkSymbolGet $symbolPath 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($worktreeId)) {
    $worktreeId = 'UNKNOWN'
  }

  $worktreeRoot = ParaforkSymbolGet $symbolPath 'WORKTREE_ROOT'
  if ([string]::IsNullOrEmpty($worktreeRoot)) {
    ParaforkPrintOutputBlock $worktreeId $pwd 'FAIL' (ParaforkPsFileCmd $debugPath @())
    return $null
  }

  $worktreeUsed = ParaforkSymbolGet $symbolPath 'WORKTREE_USED'
  if ($worktreeUsed -ne '1') {
    Write-Output 'REFUSED: worktree not entered (WORKTREE_USED!=1)'
    ParaforkPrintOutputBlock $worktreeId $pwd 'FAIL' (ParaforkPsFileCmd $initPath @('--reuse'))
    return $null
  }

  $pwdNorm = ParaforkNormalizePath $pwd
  $rootNorm = ParaforkNormalizePath $worktreeRoot
  if ($pwdNorm -ne $rootNorm) {
    $scriptPath = ParaforkScriptPath $ScriptBasename
    $next = "cd " + (ParaforkQuotePs $worktreeRoot) + "; " + (ParaforkPsFileCmd $scriptPath $Args)
    ParaforkPrintOutputBlock $worktreeId $pwd 'FAIL' $next
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

function ParaforkInvokeLogged {
  param(
    [Parameter(Mandatory = $true)][string]$WorktreeRoot,
    [Parameter(Mandatory = $true)][string]$ScriptName,
    [string[]]$Argv = @(),
    [Parameter(Mandatory = $true)][scriptblock]$Body
  )

  $logDir = Join-Path $WorktreeRoot 'paradoc'
  if (-not (Test-Path -LiteralPath $logDir)) {
    $null = New-Item -ItemType Directory -Force -Path $logDir
  }
  $logFile = Join-Path $logDir 'Log.txt'
  if (-not (Test-Path -LiteralPath $logFile)) {
    ParaforkWriteTextUtf8NoBom $logFile ""
  }

  $ts = ParaforkNowUtc
  $cmdLine = $ScriptName
  if ($Argv -and $Argv.Count -gt 0) {
    $cmdLine = $cmdLine + " " + ($Argv -join ' ')
  }

  ParaforkAppendTextUtf8NoBom $logFile ("===== $ts $ScriptName`n")
  ParaforkAppendTextUtf8NoBom $logFile ("cmd: $cmdLine`n")
  ParaforkAppendTextUtf8NoBom $logFile ("pwd: " + (Get-Location).Path + "`n")

  $exitCode = 0
  try {
    & $Body *>&1 | ForEach-Object {
      $s = $_.ToString()
      ParaforkAppendTextUtf8NoBom $logFile ($s + "`n")
      $s
    }
  } catch {
    $exitCode = 1
    $msg = $_.ToString()
    ParaforkAppendTextUtf8NoBom $logFile ("ERROR: $msg`n")
    throw
  } finally {
    ParaforkAppendTextUtf8NoBom $logFile ("exit: $exitCode`n`n")
  }
}

function ParaforkRequireYesIam {
  param([string]$FlagName, [bool]$Yes, [bool]$Iam)
  if (-not $Yes -or -not $Iam) {
    ParaforkDie "$FlagName requires --yes --i-am-maintainer"
  }
}

function ParaforkCheckConfigDrift {
  param(
    [string]$AllowDrift,
    [bool]$Yes,
    [bool]$Iam,
    [string]$SymbolPath
  )

  $configPath = ParaforkConfigPath
  if (-not (Test-Path -LiteralPath $configPath)) {
    ParaforkDie "missing config: $configPath"
  }

  $baseBranchSource = ParaforkSymbolGet $SymbolPath 'BASE_BRANCH_SOURCE'
  $remoteNameSource = ParaforkSymbolGet $SymbolPath 'REMOTE_NAME_SOURCE'

  $symbolBaseBranch = ParaforkSymbolGet $SymbolPath 'BASE_BRANCH'
  $symbolRemoteName = ParaforkSymbolGet $SymbolPath 'REMOTE_NAME'

  $configBaseBranch = ParaforkTomlGetStr $configPath 'base' 'branch' 'main'
  $configRemoteName = ParaforkTomlGetStr $configPath 'remote' 'name' ''

  if ($baseBranchSource -eq 'config' -and $configBaseBranch -ne $symbolBaseBranch) {
    if ($AllowDrift -ne 'true') {
      ParaforkDie ("config drift detected (base.branch): symbol='{0}' config='{1}' (rerun with --allow-config-drift --yes --i-am-maintainer to override)" -f $symbolBaseBranch, $configBaseBranch)
    }
    ParaforkRequireYesIam '--allow-config-drift' $Yes $Iam
  }

  if ($remoteNameSource -eq 'config' -and $configRemoteName -ne $symbolRemoteName) {
    if ($AllowDrift -ne 'true') {
      ParaforkDie ("config drift detected (remote.name): symbol='{0}' config='{1}' (rerun with --allow-config-drift --yes --i-am-maintainer to override)" -f $symbolRemoteName, $configRemoteName)
    }
    ParaforkRequireYesIam '--allow-config-drift' $Yes $Iam
  }
}
