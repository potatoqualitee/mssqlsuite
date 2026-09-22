[CmdletBinding()]
param (
    [ValidateSet("2019", "2022", "2025")]
    [string]$Version = "2022",
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SaPassword,
    [string]$Collation = "SQL_Latin1_General_CP1_CI_AS",
    [switch]$FullText,
    [switch]$ShowLog,
    [ValidateRange(1, 120)]
    [int]$TryLimit = 18,
    [ValidateRange(0, 60)]
    [int]$RetryDelaySeconds = 10
)

$ErrorActionPreference = "Stop"
# Inspect native exit codes explicitly, including when called from a strict host.
# This preference is scoped to this script and does not change the caller's settings.
$PSNativeCommandUseErrorActionPreference = $false

function Write-SqlContainerDiagnostics {
    $savedExitCode = $global:LASTEXITCODE
    try {
        # Inspect only State: a full inspect would expose the password in Config.Env.
        foreach ($diagnostic in @(
            @("ps", "-a"),
            @("inspect", "sql", "--format", "{{json .State}}"),
            @("logs", "--timestamps", "sql")
        )) {
            try {
                & docker @diagnostic 2>&1 | Out-Host
            } catch {
                Write-Warning "Unable to collect Docker diagnostics ($($diagnostic[0])): $_" -WarningAction Continue
            }
        }
    } finally {
        # Diagnostic failures must not replace a successful or failed startup result.
        $global:LASTEXITCODE = $savedExitCode
    }
}

try {
    if ($FullText) {
        $dockerfile = Join-Path $PSScriptRoot "Dockerfile-$Version"
        docker build --pull -f $dockerfile -t mssql-fulltext $PSScriptRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Docker image build failed with exit code $LASTEXITCODE."
        }
        $image = "mssql-fulltext"
    } else {
        $image = "mcr.microsoft.com/mssql/server:$Version-latest"
    }

    docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=$SaPassword" -e "MSSQL_COLLATION=$Collation" --name sql -p 1433:1433 -d $image
    if ($LASTEXITCODE -ne 0) {
        throw "Docker container start failed with exit code $LASTEXITCODE."
    }

    Write-Output "Waiting for SQL Server to start..."
    $connected = $false
    $lastConnectionError = "No connection attempt completed."
    for ($i = 1; $i -le $TryLimit; $i++) {
        $stateOutput = docker inspect sql --format "{{json .State}}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect SQL Server container: $($stateOutput -join ' ')"
        }
        $state = ($stateOutput -join "`n") | ConvertFrom-Json
        if ($state.Status -in "exited", "dead") {
            throw "SQL Server container stopped before becoming ready (status: $($state.Status), exit code: $($state.ExitCode))."
        }

        Write-Output "Testing connection to SQL Server (Try $i of $TryLimit)"
        try {
            $lastConnectionError = sqlcmd -S localhost -U sa -P $SaPassword -Q "SELECT @@VERSION" -C -b -l 15 2>&1
            $connected = $LASTEXITCODE -eq 0
        } catch {
            $lastConnectionError = $_.Exception.Message
            $connected = $false
        }
        if ($connected) {
            Write-Output "Connection to SQL Server succeeded"
            break
        }
        if ($i -lt $TryLimit) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    if (-not $connected) {
        throw "Timeout waiting for SQL Server to become available after $TryLimit attempts - $($lastConnectionError -join ' ')"
    }
} catch {
    # Always emit diagnostics before the terminating error, even without ShowLog.
    Write-SqlContainerDiagnostics
    throw
}

if ($ShowLog) {
    Write-SqlContainerDiagnostics
}
