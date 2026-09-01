# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
Build all five supported PulseView delivery packages from a Windows host.

.DESCRIPTION
Compilation runs in WSL/container builders. The Windows staged tree is then
verified and zipped in native Git Bash, where the Windows executables can run.
The last step refuses to write SHA256SUMS unless all five same-revision package
targets exist exactly once.
#>

[CmdletBinding()]
param(
    [switch]$Plan,
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$GitBash = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$Delivery = Join-Path $RepoRoot '07_Delivery'

$PhaseNames = @(
    'Windows x86_64 ZIP',
    'Linux x86_64 AppImage',
    'Linux x86_64 tarball',
    'Raspberry Pi aarch64 AppImage',
    'Raspberry Pi arm64 Debian package',
    'Complete-set SHA-256 manifest'
)

if ($Plan) {
    Write-Output 'PulseView supported delivery plan:'
    $Index = 1
    foreach ($Name in $PhaseNames) {
        Write-Output ("  {0}. {1}" -f $Index, $Name)
        $Index += 1
    }
    Write-Output 'Build environments: WSL/container builders, then native Git Bash for Windows verification.'
    exit 0
}

if ($RepoRoot.Contains("'")) {
    throw "Repository path cannot contain a single quote: $RepoRoot"
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe was not found. Run 02_Tools/bootstrap/check_host.ps1 first.'
}

if (-not $GitBash) {
    $Candidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            $GitBash = $Candidate
            break
        }
    }
}
if (-not $GitBash -or -not (Test-Path -LiteralPath $GitBash)) {
    throw 'Git Bash was not found. Pass -GitBash with its bash.exe path.'
}

$WslRootLines = & wsl.exe -d $Distribution -- bash -lc "wslpath -a -u '$RepoRoot'"
if ($LASTEXITCODE -ne 0) {
    throw "Could not map the repository into WSL distribution $Distribution."
}
$WslRoot = ($WslRootLines | Select-Object -Last 1).Trim()

$GitRootLines = & $GitBash -lc "cygpath -u '$RepoRoot'"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not map the repository path into Git Bash.'
}
$GitRoot = ($GitRootLines | Select-Object -Last 1).Trim()

function Invoke-WslBuild {
    param([string]$Label, [string]$Command)
    Write-Output "`n==> $Label"
    & wsl.exe -d $Distribution -- bash -lc "cd '$WslRoot' && $Command"
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Invoke-GitBashBuild {
    param([string]$Label, [string]$Command)
    Write-Output "`n==> $Label"
    & $GitBash -lc "cd '$GitRoot' && $Command"
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

$RevisionLines = & wsl.exe -d $Distribution -- bash -lc "cd '$WslRoot' && bash 02_Tools/build/source_revision.sh '$WslRoot'"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not determine the source revision.'
}
$Revision = ($RevisionLines | Select-Object -Last 1).Trim()
Write-Output "Building delivery set for source revision $Revision"

Invoke-WslBuild 'stage Windows x86_64 build' 'bash 02_Tools/build/build_windows_mxe.sh --stage'
Invoke-WslBuild 'build Linux x86_64 thin tarball' 'bash 02_Tools/build/build_linux.sh'
Invoke-WslBuild 'build Linux x86_64 AppImage' 'bash 02_Tools/build/build_appimage.sh'
Invoke-WslBuild 'build Raspberry Pi aarch64 AppImage' 'bash 02_Tools/build/build_appimage.sh --arch aarch64'
Invoke-WslBuild 'build Raspberry Pi arm64 Debian package' 'bash 02_Tools/build/build_deb.sh'

Invoke-GitBashBuild 'verify and package Windows x86_64 ZIP' "bash 02_Tools/build/package_windows.sh --rev '$Revision'"
Invoke-GitBashBuild 'verify the complete same-revision delivery set' "bash 02_Tools/build/verify_delivery_set.sh --revision '$Revision' '$GitRoot/07_Delivery'"

Write-Output "`nDELIVERY_SET_COMPLETE revision=$Revision"
