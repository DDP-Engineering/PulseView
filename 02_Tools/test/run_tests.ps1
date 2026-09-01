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
    Run the project test suite from a PowerShell prompt.

.DESCRIPTION
    The tests themselves are bash, and stay that way: they need mktemp, comm
    and awk, and they must run where the built sigrok-cli.exe can execute -
    which on Windows means Git Bash, natively, not WSL.

    This is the entry point for someone who has a PowerShell prompt and no
    interest in learning that. It finds bash.exe, translates the repository
    path into the /f/... form Git Bash expects, and forwards the exit code
    verbatim.

    It does not summarise, filter or soften the result. In particular exit
    code 77 - "could not run here" - is passed through and called out by
    name, because a skipped suite that reads as a pass is worse than no suite
    at all.

.PARAMETER StagingDir
    Staged tree to test against. Defaults to the Windows staging tree, which
    is also what the bash suite defaults to.

.PARAMETER Test
    Run a single test instead of the whole suite. Accepts a bare name
    (networking_stack_decode_smoke) or a file name.

.EXAMPLE
    .\02_Tools\test\run_tests.ps1

.EXAMPLE
    .\02_Tools\test\run_tests.ps1 -StagingDir 07_Delivery\staging\pulseview-linux-x86_64

.NOTES
    Exit codes: 0 passed, 1 failed, 77 could not run here.
#>

[CmdletBinding()]
param(
    [string] $StagingDir,
    [string] $Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

# The autotools convention the suite is built on: 77 means the test could not
# run here, which is neither a pass nor a failure.
$ExitSkip = 77

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path

# ---------------------------------------------------------------------------
# LOCAL HELPERS
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Locate Git Bash.
.DESCRIPTION
    The System32 shim is rejected deliberately. On any machine with WSL
    enabled, PATH resolves bash to C:\Windows\System32\bash.exe, which runs
    the tests inside the distro - where the Windows .exe under test cannot
    execute. That is the inversion of the two host roles, and it fails
    confusingly rather than obviously.
.OUTPUTS
    Full path to bash.exe, or $null.
#>
function Find-Bash {
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
    Convert a Windows path to the MSYS form Git Bash understands.
.DESCRIPTION
    F:\2026_PulseView\x -> /f/2026_PulseView/x. A path that is already
    POSIX-shaped is returned unchanged, so callers may pass either.
#>
function ConvertTo-MsysPath {
    param([Parameter(Mandatory = $true)] [string] $Path)

    if ($Path -match '^/') { return $Path }
    $full = $Path -replace '\\', '/'
    if ($full -match '^([A-Za-z]):(/.*)?$') {
        $tail = $Matches[2]
        if (-not $tail) { $tail = '/' }
        return ('/{0}{1}' -f $Matches[1].ToLower(), $tail)
    }
    return $full
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

$bash = Find-Bash
if (-not $bash) {
    Write-Host 'skip: no bash.exe found on PATH or in the usual Git for Windows locations.' -ForegroundColor Yellow
    Write-Host '      The tests need a real POSIX toolset (mktemp, comm, awk); cmd.exe cannot run them.'
    Write-Host '      winget install --id Git.Git'
    exit $ExitSkip
}

# Pick the script to run: the whole suite, or one test.
if ($Test) {
    $name = $Test
    if (-not $name.EndsWith('.sh')) { $name = "$name.sh" }
    $target = Join-Path $ScriptDir $name
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host ('error: no such test: {0}' -f $target) -ForegroundColor Red
        Write-Host '       available:'
        Get-ChildItem -LiteralPath $ScriptDir -Filter '*_smoke.sh' |
            ForEach-Object { Write-Host ('         {0}' -f $_.BaseName) }
        Get-ChildItem -LiteralPath $ScriptDir -Filter '*_test.sh' |
            ForEach-Object { Write-Host ('         {0}' -f $_.BaseName) }
        exit 1
    }
} else {
    $target = Join-Path $ScriptDir 'run_tests.sh'
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host ('error: suite driver missing at {0}' -f $target) -ForegroundColor Red
        exit 1
    }
}

$bashArgs = @((ConvertTo-MsysPath $target))

if ($StagingDir) {
    # Resolve against the repository root so a relative path works from any
    # working directory, matching the "scripts take explicit paths" rule. The
    # directory need not exist yet - the bash side reports that itself.
    # Not [System.IO.Path]::IsPathRooted - a static call on a non-core type,
    # which PowerShell ConstrainedLanguage mode refuses. Drive-qualified,
    # UNC and POSIX-shaped paths are all already absolute.
    if ($StagingDir -match '^([A-Za-z]:|\\\\|/)') {
        $stage = $StagingDir
    } else {
        $stage = Join-Path $RepoRoot $StagingDir
    }
    $bashArgs += (ConvertTo-MsysPath $stage)
}

Write-Host ('bash        {0}' -f $bash) -ForegroundColor DarkGray
Write-Host ('suite       {0}' -f (Split-Path -Leaf $target)) -ForegroundColor DarkGray
if ($StagingDir) { Write-Host ('staging     {0}' -f $stage) -ForegroundColor DarkGray }

& $bash @bashArgs
$rc = $LASTEXITCODE

Write-Host ''
switch ($rc) {
    0 { Write-Host 'PASSED' -ForegroundColor Green }
    $ExitSkip {
        Write-Host 'SKIPPED (77) - nothing ran. This is not a passing suite.' -ForegroundColor Yellow
        Write-Host 'The tests drive built artifacts; they need a staged tree and a way to run it.'
    }
    default { Write-Host ('FAILED (exit {0})' -f $rc) -ForegroundColor Red }
}

exit $rc

# END OF FILE
