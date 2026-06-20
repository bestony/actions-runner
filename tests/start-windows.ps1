$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$StartScript = Join-Path $RootDir 'start.ps1'

function Fail {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    throw $Message
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Haystack,

        [Parameter(Mandatory = $true)]
        [string] $Needle,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Haystack.Contains($Needle)) {
        Fail -Message $Message
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Haystack,

        [Parameter(Mandatory = $true)]
        [string] $Needle,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($Haystack.Contains($Needle)) {
        Fail -Message $Message
    }
}

function Set-TestEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Values
    )

    $names = @(
        'RUNNER_HOME',
        'RUNNER_TEST_LOG',
        'RUNNER_URL',
        'RUNNER_REGISTRATION_TOKEN',
        'REPO',
        'TOKEN',
        'RUNNER_NAME',
        'RUNNER_LABELS',
        'RUNNER_WORKDIR',
        'RUNNER_EPHEMERAL',
        'COMPUTERNAME'
    )

    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    foreach ($entry in $Values.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, [string] $entry.Value, 'Process')
    }
}

function New-FakeRunner {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RunnerHome
    )

    New-Item -ItemType Directory -Force -Path $RunnerHome | Out-Null

    @'
@echo off
setlocal EnableExtensions EnableDelayedExpansion
>> "%RUNNER_TEST_LOG%" echo(config
:args
if "%~1"=="" goto done
set "runner_arg=%~1"
>> "%RUNNER_TEST_LOG%" echo(!runner_arg!
shift
goto args
:done
>> "%RUNNER_TEST_LOG%" echo(end
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $RunnerHome 'config.cmd') -Encoding ASCII

    @'
@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Add-Content -LiteralPath $env:RUNNER_TEST_LOG -Value 'run'"
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $RunnerHome 'run.cmd') -Encoding ASCII
}

function Invoke-StartScript {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $OutputFile
    )

    Set-TestEnvironment -Values $Environment

    $output = & powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $StartScript 2>&1
    $status = $LASTEXITCODE
    $output | Out-File -LiteralPath $OutputFile -Encoding utf8

    return $status
}

function Test-PrimaryVariables {
    $tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
    try {
        New-FakeRunner -RunnerHome $tmpdir
        $logFile = Join-Path $tmpdir 'events.log'
        $outputFile = Join-Path $tmpdir 'output.log'

        $status = Invoke-StartScript -OutputFile $outputFile -Environment @{
            RUNNER_HOME = $tmpdir
            RUNNER_TEST_LOG = $logFile
            RUNNER_URL = 'https://github.com/example/repo/'
            RUNNER_REGISTRATION_TOKEN = 'runner-secret-token'
            RUNNER_NAME = 'runner-1'
            RUNNER_LABELS = 'docker,windows'
            RUNNER_WORKDIR = '_custom'
            RUNNER_EPHEMERAL = 'yes'
            COMPUTERNAME = 'container-host'
        }

        if ($status -ne 0) {
            Fail -Message "Primary variable flow failed with exit code $status."
        }

        $actual = (Get-Content -LiteralPath $logFile -Raw).TrimEnd()
        $expected = @'
config
--unattended
--replace
--url
https://github.com/example/repo
--token
runner-secret-token
--name
runner-1
--work
_custom
--ephemeral
--labels
docker,windows
end
run
config
remove
--unattended
--token
runner-secret-token
end
'@.TrimEnd()

        if ($actual -ne $expected) {
            Fail -Message "Primary variable flow should pass expected runner arguments.`nExpected:`n$expected`nActual:`n$actual"
        }

        Assert-NotContains -Haystack (Get-Content -LiteralPath $outputFile -Raw) -Needle 'runner-secret-token' -Message 'Startup logs must not print the registration token.'
    } finally {
        Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-LegacyVariables {
    $tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
    try {
        New-FakeRunner -RunnerHome $tmpdir
        $logFile = Join-Path $tmpdir 'events.log'
        $outputFile = Join-Path $tmpdir 'output.log'

        $status = Invoke-StartScript -OutputFile $outputFile -Environment @{
            RUNNER_HOME = $tmpdir
            RUNNER_TEST_LOG = $logFile
            REPO = 'example/legacy'
            TOKEN = 'legacy-runner-token'
            COMPUTERNAME = 'container-host'
        }

        if ($status -ne 0) {
            Fail -Message "Legacy variable flow failed with exit code $status."
        }

        $actual = Get-Content -LiteralPath $logFile -Raw
        Assert-Contains -Haystack $actual -Needle "https://github.com/example/legacy" -Message 'Legacy REPO should resolve the GitHub URL.'
        Assert-Contains -Haystack $actual -Needle "legacy-runner-token" -Message 'Legacy TOKEN should be passed to config.cmd.'
        Assert-Contains -Haystack $actual -Needle "_work" -Message 'Legacy flow should use the default work directory.'
        Assert-NotContains -Haystack $actual -Needle "--ephemeral" -Message 'Legacy flow should not enable ephemeral mode by default.'
        Assert-NotContains -Haystack (Get-Content -LiteralPath $outputFile -Raw) -Needle 'legacy-runner-token' -Message 'Startup logs must not print legacy token.'
    } finally {
        Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-PatRejected {
    $tmpdir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
    try {
        New-FakeRunner -RunnerHome $tmpdir
        $outputFile = Join-Path $tmpdir 'output.log'

        $status = Invoke-StartScript -OutputFile $outputFile -Environment @{
            RUNNER_HOME = $tmpdir
            RUNNER_TEST_LOG = (Join-Path $tmpdir 'events.log')
            RUNNER_URL = 'https://github.com/example/repo'
            RUNNER_REGISTRATION_TOKEN = 'ghp_secret'
        }

        if ($status -eq 0) {
            Fail -Message 'PAT-like token should be rejected.'
        }

        $output = Get-Content -LiteralPath $outputFile -Raw
        Assert-Contains -Haystack $output -Needle 'not a PAT or GitHub API token' -Message 'PAT rejection should explain the token type problem.'
        Assert-NotContains -Haystack $output -Needle 'ghp_secret' -Message 'PAT rejection logs must not print the rejected token.'
    } finally {
        Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-PrimaryVariables
Test-LegacyVariables
Test-PatRejected

Write-Host 'Windows startup script tests passed.'
