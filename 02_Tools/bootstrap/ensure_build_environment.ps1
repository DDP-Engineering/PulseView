# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
Ensure that a PulseView builder image is installed and complete through WSL.

.DESCRIPTION
Delegates to ensure_build_environment.sh inside the selected WSL distribution.
The script selects a current installed image first, restores audited local Git
LFS parts when required, or offers a local online rebuild. It does not download
LFS content and does not upload or publish anything.
#>

[CmdletBinding()]
param(
    [ValidateSet('mingw', 'appimage')] [string] $Image = 'mingw',
    [string] $Platform = '',
    [ValidateSet('docker', 'podman')] [string] $Engine = 'docker',
    [string] $Manifest = '',
    [string] $Distribution = 'Ubuntu-24.04',
    [switch] $ForceRestore,
    [switch] $AllowLegacyRestore,
    [switch] $AllowHistoricalBuilder,
    [switch] $Rebuild,
    [switch] $NoRebuild
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($Rebuild -and $NoRebuild) {
    throw '-Rebuild and -NoRebuild cannot be used together.'
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe was not found. Install WSL with an Ubuntu distribution first.'
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
if ($RepoRoot.Contains("'")) {
    throw "Repository path cannot contain a single quote: $RepoRoot"
}

$WslRootLines = & wsl.exe -d $Distribution -- bash -lc "wslpath -a -u '$RepoRoot'"
if ($LASTEXITCODE -ne 0) {
    throw "Could not map the repository into WSL distribution $Distribution."
}
$WslRoot = ($WslRootLines | Select-Object -Last 1).Trim()
$WslScript = "$WslRoot/02_Tools/bootstrap/ensure_build_environment.sh"

$Forward = @('--image', $Image, '--engine', $Engine)
if ($Platform) { $Forward += @('--platform', $Platform) }
if ($Manifest) {
    $ResolvedManifest = (Resolve-Path -LiteralPath $Manifest).Path
    if ($ResolvedManifest.Contains("'")) {
        throw "Manifest path cannot contain a single quote: $ResolvedManifest"
    }
    $WslManifestLines = & wsl.exe -d $Distribution -- bash -lc "wslpath -a -u '$ResolvedManifest'"
    if ($LASTEXITCODE -ne 0) { throw "Could not map manifest path: $ResolvedManifest" }
    $Forward += @('--manifest', (($WslManifestLines | Select-Object -Last 1).Trim()))
}
if ($ForceRestore) { $Forward += '--force-restore' }
if ($AllowLegacyRestore) { $Forward += '--allow-legacy-restore' }
if ($AllowHistoricalBuilder) { $Forward += '--allow-historical-builder' }
if ($Rebuild) { $Forward += '--rebuild' }
if ($NoRebuild) { $Forward += '--no-rebuild' }

& wsl.exe -d $Distribution -- bash $WslScript @Forward
exit $LASTEXITCODE

# END OF FILE
