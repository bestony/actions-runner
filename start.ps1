$ErrorActionPreference = 'Stop'

$RunnerHome = if ([string]::IsNullOrWhiteSpace($env:RUNNER_HOME)) {
    'C:\actions-runner'
} else {
    $env:RUNNER_HOME
}

function Write-RunnerLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string] $Level,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    [Console]::Error.WriteLine("[{0}] {1}", $Level, $Message)
}

function Exit-WithError {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-RunnerLog -Level 'ERROR' -Message $Message
    exit 1
}

function Test-PlaceholderValue {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    if ($Value -match '(?i)^(null|none|undefined|changeme|change-me|todo|owner/repo)$') {
        return $true
    }

    if ($Value -eq 'OWNER/REPO') {
        return $true
    }

    return $Value -match '<[^>]*>'
}

function Resolve-RunnerUrl {
    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_URL)) {
        if (Test-PlaceholderValue -Value $env:RUNNER_URL) {
            Exit-WithError -Message 'RUNNER_URL must be the GitHub URL from the official config.cmd --url command, for example https://github.com/owner/repo.'
        }

        if ($env:RUNNER_URL -notmatch '^https://\S+$') {
            Exit-WithError -Message 'RUNNER_URL must be an https:// URL.'
        }

        return ($env:RUNNER_URL).TrimEnd('/')
    }

    if ([string]::IsNullOrWhiteSpace($env:REPO)) {
        Exit-WithError -Message 'Set RUNNER_URL or REPO. RUNNER_URL is preferred and should match the official config.cmd --url value.'
    }

    if (Test-PlaceholderValue -Value $env:REPO) {
        Exit-WithError -Message 'REPO must be an owner/repo value, or set RUNNER_URL to the full GitHub URL.'
    }

    if ($env:REPO -match '^https?://') {
        Exit-WithError -Message 'REPO must use owner/repo format. Use RUNNER_URL for a full URL.'
    }

    if ($env:REPO -notmatch '^[^/\s]+/[^/\s]+$') {
        Exit-WithError -Message 'REPO must be in owner/repo format, or set RUNNER_URL to the full GitHub URL.'
    }

    return "https://github.com/$($env:REPO)"
}

function Resolve-RegistrationToken {
    $token = $null

    if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_REGISTRATION_TOKEN)) {
        $token = $env:RUNNER_REGISTRATION_TOKEN
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TOKEN)) {
        $token = $env:TOKEN
    } else {
        Exit-WithError -Message 'Set RUNNER_REGISTRATION_TOKEN to the token from the official config.cmd --token command.'
    }

    if (Test-PlaceholderValue -Value $token) {
        Exit-WithError -Message 'RUNNER_REGISTRATION_TOKEN/TOKEN must be a valid self-hosted runner registration token.'
    }

    if ($token -match '^(ghp_|github_pat_|gho_|ghu_|ghs_|ghr_)') {
        Exit-WithError -Message 'RUNNER_REGISTRATION_TOKEN/TOKEN must be a self-hosted runner registration token, not a PAT or GitHub API token.'
    }

    return $token
}

function ConvertTo-NormalizedBool {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = ''
    }

    switch -Regex ($Value) {
        '(?i)^(true|1|yes)$' {
            return $true
        }
        '(?i)^(false|0|no|)$' {
            return $false
        }
        default {
            Exit-WithError -Message 'RUNNER_EPHEMERAL must be one of: true, false, 1, 0, yes, no.'
        }
    }
}

function Quote-CmdArgumentValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    return '"' + $Value + '"'
}

function Get-DefaultRunnerName {
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        return $env:COMPUTERNAME
    }

    return [System.Net.Dns]::GetHostName()
}

$RunnerUrlValue = Resolve-RunnerUrl
$RegistrationToken = Resolve-RegistrationToken
$RunnerName = if ([string]::IsNullOrWhiteSpace($env:RUNNER_NAME)) { Get-DefaultRunnerName } else { $env:RUNNER_NAME }
$RunnerWorkDir = if ([string]::IsNullOrWhiteSpace($env:RUNNER_WORKDIR)) { '_work' } else { $env:RUNNER_WORKDIR }
$RunnerEphemeral = ConvertTo-NormalizedBool -Value $env:RUNNER_EPHEMERAL

Write-RunnerLog -Level 'INFO' -Message 'Configuring GitHub Actions runner.'
Write-RunnerLog -Level 'INFO' -Message "Runner URL: $RunnerUrlValue"
Write-RunnerLog -Level 'INFO' -Message "Runner name: $RunnerName"
Write-RunnerLog -Level 'INFO' -Message "Runner work directory: $RunnerWorkDir"
Write-RunnerLog -Level 'INFO' -Message "Runner ephemeral: $RunnerEphemeral"
if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_LABELS)) {
    Write-RunnerLog -Level 'INFO' -Message "Runner labels: $($env:RUNNER_LABELS)"
}

Set-Location -LiteralPath $RunnerHome

$configArgs = @(
    '--unattended',
    '--replace',
    '--url',
    $RunnerUrlValue,
    '--token',
    $RegistrationToken,
    '--name',
    $RunnerName,
    '--work',
    $RunnerWorkDir
)

if ($RunnerEphemeral) {
    $configArgs += '--ephemeral'
}

if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_LABELS)) {
    $configArgs += @('--labels', (Quote-CmdArgumentValue -Value $env:RUNNER_LABELS))
}

$exitCode = 0
$registered = $false

try {
    Write-RunnerLog -Level 'INFO' -Message 'Registering runner.'
    & .\config.cmd @configArgs
    if ($LASTEXITCODE -ne 0) {
        throw "config.cmd failed with exit code $LASTEXITCODE."
    }

    $registered = $true

    Write-RunnerLog -Level 'INFO' -Message 'Starting runner process.'
    & .\run.cmd
    $exitCode = $LASTEXITCODE
} catch {
    Write-RunnerLog -Level 'ERROR' -Message $($_.Exception.Message)
    $exitCode = 1
} finally {
    if ($registered) {
        Write-RunnerLog -Level 'INFO' -Message 'Removing runner registration.'
        & .\config.cmd remove --unattended --token $RegistrationToken
        if ($LASTEXITCODE -ne 0) {
            Write-RunnerLog -Level 'WARN' -Message 'Runner cleanup failed. The runner may already be removed if ephemeral, or may need to be removed manually in GitHub settings.'
        }
    }
}

exit $exitCode
