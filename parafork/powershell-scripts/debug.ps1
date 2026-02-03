Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_lib.ps1"

$invocationPwd = (Get-Location).Path
$symbolPath = ParaforkSymbolFindUpwards $invocationPwd

$worktreeId = 'UNKNOWN'
$worktreeRoot = $null
$baseRoot = $null

$initCmd = ParaforkPsFileCmd (ParaforkScriptPath 'init.ps1') @()
$debugCmd = ParaforkPsFileCmd (ParaforkScriptPath 'debug.ps1') @()

function ParaforkPrintWorktreeList {
  param([string[]]$WorktreeRoots)

  Write-Output "Found worktrees (newest first):"
  foreach ($d in $WorktreeRoots) {
    $id = ParaforkSymbolGet (Join-Path $d '.worktree-symbol') 'WORKTREE_ID'
    if ([string]::IsNullOrEmpty($id)) {
      $id = 'UNKNOWN'
    }
    Write-Output ("- {0}  {1}" -f $id, $d)
  }
}

try {
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
    if ([string]::IsNullOrEmpty($worktreeRoot)) {
      $worktreeRoot = $null
    }

    $body = {
      ParaforkPrintKv 'SYMBOL_PATH' $symbolPath
      ParaforkPrintOutputBlock $worktreeId $invocationPwd 'PASS' $initCmd
    }

    if ($worktreeRoot) {
      ParaforkInvokeLogged $worktreeRoot 'debug.ps1' $args $body
    } else {
      & $body
    }
    exit 0
  }

  $baseRoot = ParaforkGitToplevel
  if (-not $baseRoot) {
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'FAIL' ("cd <BASE_ROOT>; " + $initCmd)
    ParaforkDie "not in a git repo and no .worktree-symbol found"
  }

  $workdirRoot = '.parafork'
  $configPath = ParaforkConfigPath
  if (Test-Path -LiteralPath $configPath) {
    $workdirRoot = ParaforkTomlGetStr $configPath 'workdir' 'root' '.parafork'
  }

  $container = Join-Path $baseRoot $workdirRoot
  if (-not (Test-Path -LiteralPath $container -PathType Container)) {
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'PASS' $initCmd
    Write-Output ""
    Write-Output ("No worktree container found at: {0}" -f $container)
    exit 0
  }

  $roots = @()
  $children = Get-ChildItem -LiteralPath $container -Directory -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending
  foreach ($c in $children) {
    $candidate = $c.FullName
    if (Test-Path -LiteralPath (Join-Path $candidate '.worktree-symbol') -PathType Leaf) {
      $roots += $candidate
    }
  }

  if (-not $roots -or $roots.Count -eq 0) {
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock 'UNKNOWN' $invocationPwd 'PASS' $initCmd
    Write-Output ""
    Write-Output ("No worktrees found under: {0}" -f $container)
    exit 0
  }

  $chosen = $roots[0]
  $chosenId = ParaforkSymbolGet (Join-Path $chosen '.worktree-symbol') 'WORKTREE_ID'
  if ([string]::IsNullOrEmpty($chosenId)) {
    $chosenId = 'UNKNOWN'
  }

  $next = "cd " + (ParaforkQuotePs $chosen) + "; " + $initCmd

  $body = {
    ParaforkPrintWorktreeList $roots
    Write-Output ""
    ParaforkPrintKv 'BASE_ROOT' $baseRoot
    ParaforkPrintOutputBlock $chosenId $invocationPwd 'PASS' $next
  }

  ParaforkInvokeLogged $chosen 'debug.ps1' $args $body
  exit 0
} catch {
  if (-not $global:PARAFORK_OUTPUT_BLOCK_PRINTED) {
    ParaforkPrintOutputBlock $worktreeId $invocationPwd 'FAIL' $debugCmd
  }
  exit 1
}
