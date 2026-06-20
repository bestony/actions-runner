$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-BuildLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string] $Level,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    [Console]::Error.WriteLine("[{0}] {1}", $Level, $Message)
}

function Get-RequiredEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment variable $Name is required."
    }

    return $value
}

$RunnerVersion = Get-RequiredEnvironmentValue -Name 'RUNNER_VERSION'
$TargetArch = Get-RequiredEnvironmentValue -Name 'TARGETARCH'

if ($TargetArch -eq 'amd64') {
    $RunnerArch = 'x64'
    $RunnerSha256 = Get-RequiredEnvironmentValue -Name 'RUNNER_WIN_X64_SHA256'
} elseif ($TargetArch -eq 'arm64') {
    $RunnerArch = 'arm64'
    $RunnerSha256 = Get-RequiredEnvironmentValue -Name 'RUNNER_WIN_ARM64_SHA256'
} else {
    throw "Unsupported target architecture: $TargetArch"
}

$runnerZip = 'C:\actions-runner.zip'
$runnerUrl = 'https://github.com/actions/runner/releases/download/v{0}/actions-runner-win-{1}-{0}.zip' -f $RunnerVersion, $RunnerArch

Write-BuildLog -Level 'INFO' -Message "Downloading GitHub Actions runner $RunnerVersion for Windows $RunnerArch."
Invoke-WebRequest -UseBasicParsing -Uri $runnerUrl -OutFile $runnerZip

$actualSha256 = (Get-FileHash -Algorithm SHA256 -Path $runnerZip).Hash.ToLowerInvariant()
$expectedSha256 = $RunnerSha256.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw ('Checksum mismatch for {0}. Expected {1} but got {2}.' -f $runnerZip, $expectedSha256, $actualSha256)
}

Write-BuildLog -Level 'INFO' -Message 'Expanding GitHub Actions runner archive.'
Expand-Archive -LiteralPath $runnerZip -DestinationPath 'C:\actions-runner' -Force
Remove-Item -LiteralPath $runnerZip -Force
