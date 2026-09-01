#!/usr/bin/env pwsh
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Inspect the Windows host and report whether it can build and test this
    project.

.DESCRIPTION
    The Windows counterpart to check_host.sh, and deliberately its mirror
    image: same PASS/WARN/FAIL vocabulary, same "name the remedy, do not run
    it" default, same exit status rule.

    Windows fills two roles here and this script checks both. It is the test
    host - it runs the built sigrok-cli.exe and the host-side smoke tests,
    which need Git Bash for a real POSIX toolset. And it is the gateway to
    the build host, because the container engine lives in WSL; Docker is
    therefore probed from inside the distro rather than from Windows, since
    that is where the build scripts will look for it.

    Read-only by default. -Install relaxes that, and only that: it offers
    per-item winget remediation with an explicit prompt for each. It never
    elevates silently, and never attempts Docker Desktop or WSL distro
    installation - for those it prints the command and stops.

.PARAMETER ResultPath
    Also write a JSON record of the run here.

.PARAMETER Tag
    Builder image to look for. Default pulseview-builder-mingw:latest.

.PARAMETER Distro
    WSL distribution the build host lives in. Default Ubuntu-24.04.

.PARAMETER Install
    Offer to install missing prerequisites via winget, prompting for each.

.EXAMPLE
    .\02_Tools\bootstrap\check_host.ps1

.EXAMPLE
    .\02_Tools\bootstrap\check_host.ps1 -Install -WhatIf

.NOTES
    Exit status is 1 if any check FAILED, 0 otherwise. WARN does not fail.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ResultPath,
    [string] $Tag = 'pulseview-builder-mingw:latest',
    [string] $Distro = 'Ubuntu-24.04',
    [switch] $Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# -WhatIf has exactly one meaning here: do not install anything. Left as an
# ambient preference it also leaks into every other cmdlet in scope, including
# module autoloading and the result record - so capture the intent, then clear
# the preference and consult the captured value where it actually applies.
$DryRun = [bool] $WhatIfPreference
$WhatIfPreference = $false

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

# Disk needed for the image plus one build tree. The image alone is ~7.3 GB
# unpacked; the build volume reaches a few GB more. Matches check_host.sh.
$NeedGb = 30

# A Git LFS pointer file is a few hundred bytes of text. The real archive is
# ~2.2 GB. Anything under this threshold is a pointer, not a toolchain.
$PointerMaxBytes = 1024

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$LockFile = Join-Path $RepoRoot '02_Tools\upstream\upstreams.lock.toml'
$Toolchain = Join-Path $RepoRoot '07_Delivery\toolchain\pulseview-builder-mingw.tar'

# WSL writes UTF-16LE to a pipe unless told otherwise; without this every
# string comparison against its output silently fails.
$env:WSL_UTF8 = '1'

# ---------------------------------------------------------------------------
# LOCAL HELPERS
# ---------------------------------------------------------------------------

# Plain arrays and hashtables throughout, and no static method calls on
# non-core types. This script has to run on a locked-down host - PowerShell
# ConstrainedLanguage mode blocks New-Object for generic types, [pscustomobject]
# and [math]::Floor - and a readiness check that cannot run on a managed
# machine is not much of a readiness check.
$script:Failed = 0
$script:Warned = 0
$script:Rows = @()
$script:Remedies = @()

<#
.SYNOPSIS
    Record and print one check result.
#>
function Report {
    param(
        [ValidateSet('PASS', 'WARN', 'FAIL')] [string] $Status,
        [string] $Name,
        [string] $Detail,
        [string] $Remedy,
        [string] $WingetId
    )

    switch ($Status) {
        'WARN' { $script:Warned++ }
        'FAIL' { $script:Failed++ }
    }

    $colour = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red' }[$Status]
    Write-Host ('  {0,-4}  {1,-22} {2}' -f $Status, $Name, $Detail) -ForegroundColor $colour
    if ($Remedy) {
        foreach ($line in $Remedy -split "`n") {
            Write-Host ('        {0}' -f $line) -ForegroundColor DarkGray
        }
    }

    $script:Rows += @{ check = $Name; status = $Status; detail = $Detail }

    if ($WingetId -and $Status -ne 'PASS') {
        $script:Remedies += @{ name = $Name; id = $WingetId }
    }
}

<#
.SYNOPSIS
    Locate an executable on PATH.
.OUTPUTS
    The resolved path, or $null.
#>
function Find-Exe {
    param([string] $Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

<#
.SYNOPSIS
    Locate Git Bash specifically.
.DESCRIPTION
    Not Find-Exe 'bash'. On any machine with WSL enabled, PATH resolves bash
    to C:\Windows\System32\bash.exe - the WSL launcher, which runs the tests
    inside the distro where the Windows .exe cannot execute. That is the exact
    inversion of the two host roles this project depends on, and it fails in a
    confusing way, so the System32 shim is rejected by name.
.OUTPUTS
    Full path to Git Bash, or $null.
#>
function Find-GitBash {
    $system32 = Join-Path $env:SystemRoot 'System32'
    $cmd = Get-Command 'bash' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' -and
                       -not $_.Source.StartsWith($system32, 'OrdinalIgnoreCase') } |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        foreach ($rel in @('Git\bin\bash.exe', 'Programs\Git\bin\bash.exe')) {
            $candidate = Join-Path $root $rel
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return $null
}

<#
.SYNOPSIS
    Run a native command and return its combined output, never throwing.
#>
function Invoke-Capture {
    param([string] $Exe, [string[]] $Arguments)
    try {
        # Deliberately not 2>&1: Windows PowerShell 5.1 wraps a native
        # command's stderr in ErrorRecords and reports failure even on exit 0.
        # $LASTEXITCODE is the only trustworthy signal here.
        $out = & $Exe @Arguments 2>$null | Out-String
        return @{ ok = ($LASTEXITCODE -eq 0); text = $out.Trim() }
    } catch {
        return @{ ok = $false; text = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    First line of a command's --version output, for the detail column.
#>
function Get-VersionLine {
    param([string] $Exe, [string[]] $Arguments = @('--version'))
    $r = Invoke-Capture -Exe $Exe -Arguments $Arguments
    $line = ($r.text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($line) { return $line.Trim() }
    return 'present'
}

# ---------------------------------------------------------------------------
# CHECKS
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host ('Host check: {0}' -f [System.Environment]::OSVersion.VersionString)
Write-Host ('Repository: {0}' -f $RepoRoot)
Write-Host ''

# --- Environment -----------------------------------------------------------
Write-Host 'Environment'

$psv = $PSVersionTable.PSVersion
if ($psv.Major -ge 5) {
    Report PASS 'powershell' ('{0}' -f $psv)
} else {
    Report FAIL 'powershell' ('{0} - need 5.1 or newer' -f $psv) `
        'Windows PowerShell 5.1 ships with Windows 10/11, or install PowerShell 7.'
}

if ([System.Environment]::Is64BitOperatingSystem) {
    Report PASS 'architecture' 'x86_64'
} else {
    Report FAIL 'architecture' 'not 64-bit' 'The delivered binaries are x86_64 only.'
}

# --- Tools -----------------------------------------------------------------
Write-Host ''
Write-Host 'Tools'

$git = Find-Exe 'git'
if ($git) {
    Report PASS 'git' (Get-VersionLine $git)
} else {
    Report FAIL 'git' 'not found' 'winget install --id Git.Git' 'Git.Git'
}

# Git LFS carries the saved toolchain image and the delivery packages. On
# Windows this is not the soft requirement it is on the WSL side: Windows git
# owns this checkout, so its LFS is the one that decides whether the archive
# is real or a pointer.
if ($git) {
    $lfs = Invoke-Capture -Exe $git -Arguments @('lfs', 'version')
    if ($lfs.ok) {
        Report PASS 'git-lfs' (($lfs.text -split "`r?`n")[0])
    } else {
        Report FAIL 'git-lfs' 'not found' `
            "winget install --id GitHub.GitLFS`ngit lfs install" 'GitHub.GitLFS'
    }
}

# Git Bash. The smoke tests need mktemp, comm, awk and friends; cmd.exe and
# PowerShell alone cannot run them, and run_tests.ps1 shells out to this.
$bash = Find-GitBash
if ($bash) {
    Report PASS 'git bash' $bash
} else {
    Report FAIL 'git bash' 'no bash.exe on PATH or in %ProgramFiles%\Git\bin' `
        'Installed with Git for Windows. The host-side smoke tests cannot run without it.' `
        'Git.Git'
}

# python3 generates the synthetic captures for the decode smoke test. Standard
# library only - there is nothing to pip install.
$py = Find-Exe 'python3'
if (-not $py) { $py = Find-Exe 'python' }
if ($py) {
    Report PASS 'python' (Get-VersionLine $py)
} else {
    Report WARN 'python' 'not found' `
        'Only needed by networking_stack_decode_smoke.sh, which exits 77 without it.
winget install --id Python.Python.3.13' 'Python.Python.3.13'
}

# --- WSL and Docker --------------------------------------------------------
Write-Host ''
Write-Host 'Build host (WSL)'

$wsl = Find-Exe 'wsl'
$distroOk = $false

if (-not $wsl) {
    Report FAIL 'wsl' 'not found' `
        'The build scripts need a Linux container host. Install it yourself:
wsl --install -d Ubuntu-24.04'
} else {
    $list = Invoke-Capture -Exe $wsl -Arguments @('-l', '-q')
    $names = @($list.text -split "`r?`n" |
        ForEach-Object { ($_ -replace "`0", '').Trim() } |
        Where-Object { $_ })

    if ($names -contains $Distro) {
        Report PASS 'wsl distro' ('{0} registered' -f $Distro)
        $distroOk = $true
    } elseif ($names.Count -gt 0) {
        Report WARN 'wsl distro' ('{0} not registered; found: {1}' -f $Distro, ($names -join ', ')) `
            ('Pass -Distro to check a different one, or: wsl --install -d {0}' -f $Distro)
    } else {
        Report FAIL 'wsl distro' 'no distributions registered' `
            ('wsl --install -d {0}' -f $Distro)
    }
}

# Docker is probed from inside the distro, not from Windows. Docker Desktop
# can be running happily on the host while WSL integration is off for this
# distro - and it is the distro's view that the build scripts get.
if ($distroOk) {
    $info = Invoke-Capture -Exe $wsl -Arguments @('-d', $Distro, '--', 'docker', 'info')
    if ($info.ok) {
        Report PASS 'docker daemon' ('reachable from {0}' -f $Distro)

        $img = Invoke-Capture -Exe $wsl -Arguments @('-d', $Distro, '--', 'docker', 'image', 'inspect', $Tag)
        if ($img.ok) {
            Report PASS 'builder image' ('{0} present' -f $Tag)
        } else {
            Report WARN 'builder image' ('{0} not present' -f $Tag) `
                ("Load the saved archive:`nwsl -d {0} -- ./02_Tools/build/load_image.sh --image mingw" -f $Distro)
        }
    } else {
        Report FAIL 'docker daemon' ('not reachable from {0}' -f $Distro) `
            'Start Docker. If using Docker Desktop, enable WSL integration for this distro
under Settings -> Resources -> WSL integration.'
    }
}

# --- Repository state ------------------------------------------------------
Write-Host ''
Write-Host 'Repository state'

if (Test-Path -LiteralPath $LockFile) {
    Report PASS 'lock file' (Split-Path -Leaf $LockFile)
} else {
    Report FAIL 'lock file' ('missing at {0}' -f $LockFile)
}

if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    $missing = @()
    foreach ($name in @('libsigrok', 'libsigrokdecode', 'sigrok-cli', 'sigrok-util',
                        'pulseview', 'libserialport', 'libusb')) {
        $dir = Join-Path $RepoRoot "05_Software\$name"
        if (-not (Test-Path -LiteralPath $dir) -or
            -not (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        Report FAIL 'vendored sources' ('missing or empty: {0}' -f ($missing -join ' ')) `
            'git checkout -- 05_Software'
    } else {
        Report PASS 'vendored sources' 'all present'
    }
} else {
    Report FAIL 'git repository' 'not a git checkout'
}

# The failure this catches surfaces much later otherwise, as a corrupt archive
# rather than a missing tool - so check the bytes, not just the filename.
if (Test-Path -LiteralPath $Toolchain) {
    $size = (Get-Item -LiteralPath $Toolchain).Length
    if ($size -le $PointerMaxBytes) {
        Report FAIL 'toolchain archive' ('{0} bytes - this is a Git LFS pointer' -f $size) `
            'git lfs pull'
    } else {
        Report PASS 'toolchain archive' ('{0:N1} GB' -f ($size / 1GB))
    }
} else {
    Report WARN 'toolchain archive' 'not present' `
        'Needed only to load the builder image without rebuilding it: git lfs pull'
}

# --- Capacity --------------------------------------------------------------
Write-Host ''
Write-Host 'Capacity'

# -WhatIf:$false on every cmdlet from here on. -Install makes this script
# SupportsShouldProcess, and PowerShell then propagates -WhatIf to every
# cmdlet in scope - including the ones that only read, and the one that writes
# the result record. Suppressing an inspection or a diagnostic file is not
# what the caller asked to preview.
$drive = Get-PSDrive -Name (Split-Path -Qualifier $RepoRoot).TrimEnd(':') -ErrorAction SilentlyContinue
if ($drive -and $null -ne $drive.Free) {
    $freeGb = [int64] ($drive.Free / 1GB)
    if ($freeGb -ge $NeedGb) {
        Report PASS 'disk (repo)' ('{0} GB free, need ~{1} GB' -f $freeGb, $NeedGb)
    } else {
        Report WARN 'disk (repo)' ('{0} GB free, need ~{1} GB' -f $freeGb, $NeedGb) `
            'Builds put their trees in a container volume inside WSL, so the pressure
is usually there rather than here - but LFS objects live on this drive.'
    }
} else {
    Report WARN 'disk (repo)' ('could not determine free space on {0}' -f $RepoRoot)
}

$cores = [System.Environment]::ProcessorCount
if ($cores -ge 4) {
    Report PASS 'cpu' ('{0} cores' -f $cores)
} else {
    Report WARN 'cpu' ('{0} cores - the toolchain build will be slow' -f $cores)
}

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------

Write-Host ''
if ($script:Failed -gt 0) {
    Write-Host ('RESULT: {0} failed, {1} warnings. Fix the failures above.' -f $script:Failed, $script:Warned) -ForegroundColor Red
} else {
    Write-Host ('RESULT: ready. {0} warnings.' -f $script:Warned) -ForegroundColor Green
}
Write-Host ''

# ---------------------------------------------------------------------------
# OPTIONAL REMEDIATION
# ---------------------------------------------------------------------------

if ($Install) {
    $winget = Find-Exe 'winget'
    # One offer per package, even when several checks want the same one -
    # git and Git Bash both resolve to Git.Git.
    $todo = @()
    $seen = @()
    foreach ($r in $script:Remedies) {
        if ($seen -contains $r.id) { continue }
        $seen += $r.id
        $todo += $r
    }

    if (-not $todo) {
        Write-Host 'Nothing to install.'
    } elseif (-not $winget) {
        Write-Host 'winget not found; install these yourself:' -ForegroundColor Yellow
        foreach ($r in $todo) { Write-Host ('  winget install --id {0}' -f $r.id) }
    } else {
        if ($DryRun) {
            Write-Host 'Would offer (nothing installed, -WhatIf):'
        } else {
            Write-Host 'Remediation (each is asked separately; nothing is installed silently):'
        }
        foreach ($r in $todo) {
            $cmd = 'winget install --id {0} --source winget' -f $r.id
            if ($DryRun) {
                Write-Host ('  {0,-22} {1}' -f $r.name, $cmd)
                continue
            }
            $answer = Read-Host ("  {0}  ->  {1}  [y/N]" -f $r.name, $cmd)
            if ($answer -match '^(y|yes)$') {
                & $winget install --id $r.id --source winget
            } else {
                Write-Host '    skipped'
            }
        }
        Write-Host ''
        Write-Host 'Re-run this script to confirm. Docker Desktop and the WSL distro are'
        Write-Host 'deliberately not installed here - see the commands printed above.'
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# RESULT RECORD
# ---------------------------------------------------------------------------

if ($ResultPath) {
    $dir = Split-Path -Parent $ResultPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null
    }
    $record = @{
        schema    = 1
        tool      = 'check_host.ps1'
        host      = [System.Environment]::OSVersion.VersionString
        repo_root = $RepoRoot
        timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        failed    = $script:Failed
        warnings  = $script:Warned
        checks    = @($script:Rows)
    }
    $record | ConvertTo-Json -Depth 4 | Out-File -FilePath $ResultPath -Encoding utf8 -WhatIf:$false
    Write-Host ('record: {0}' -f $ResultPath)
}

if ($script:Failed -gt 0) { exit 1 }
exit 0

# END OF FILE
