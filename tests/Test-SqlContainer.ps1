# Dependency-free regression tests. Docker and sqlcmd are mocked; no SQL install is performed.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

foreach ($file in Get-ChildItem $root -Recurse -Filter *.ps1) {
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "PowerShell syntax errors in $($file.FullName): $($parseErrors -join '; ')"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function docker {
    $call = $args -join " "
    $global:MssqlSuiteTestState.Calls.Add($call)
    $global:LASTEXITCODE = 0
    $scenario = $global:MssqlSuiteTestState.Scenario
    switch ($args[0]) {
        "build" {
            $global:MssqlSuiteTestState.BuildContext = $args[-1]
            if ($scenario -eq "BuildFailure") { $global:LASTEXITCODE = 23 }
        }
        "run" {
            if ($scenario -eq "RunFailure") { $global:LASTEXITCODE = 125 }
            else { "test-container-id" }
        }
        "inspect" {
            if ($scenario -eq "InspectFailure") {
                $global:LASTEXITCODE = 1
                "test inspection failure"
            } else {
                $status = switch ($scenario) {
                    "Exited" { "exited" }
                    "Dead" { "dead" }
                    default { "running" }
                }
                @{ Status = $status; ExitCode = 127 } | ConvertTo-Json -Compress
            }
        }
        "ps" {
            if ($scenario -eq "TimeoutDiagnosticsFailure") { throw "test ps failure" }
        }
        "logs" {
            if ($scenario -eq "TimeoutDiagnosticsFailure") { throw "test log failure" }
            if ($scenario -eq "SuccessDiagnosticsFailure") { $global:LASTEXITCODE = 1 }
            "test SQL Server log"
        }
        default { throw "Unexpected Docker call: $call" }
    }
}

function sqlcmd {
    $global:MssqlSuiteTestState.Attempts++
    $scenario = $global:MssqlSuiteTestState.Scenario
    if ($scenario -eq "SqlcmdThrows") { throw "test transport exception" }
    if ($scenario -in "Timeout", "TimeoutDiagnosticsFailure" -or
        ($scenario -eq "Retry" -and $global:MssqlSuiteTestState.Attempts -lt 3)) {
        $global:LASTEXITCODE = 1
        "test connection refused"
    } else {
        $global:LASTEXITCODE = 0
        "test SQL Server version"
    }
}

$cases = @(
    @{ Scenario = "Success"; FullText = $false; ShowLog = $false; Attempts = 1; Error = $null; Diagnostics = $false },
    @{ Scenario = "Success"; FullText = $true; ShowLog = $true; Attempts = 1; Error = $null; Diagnostics = $true },
    @{ Scenario = "BuildFailure"; FullText = $true; ShowLog = $false; Attempts = 0; Error = "image build failed with exit code 23"; Diagnostics = $true },
    @{ Scenario = "RunFailure"; FullText = $false; ShowLog = $false; Attempts = 0; Error = "container start failed with exit code 125"; Diagnostics = $true },
    @{ Scenario = "Exited"; FullText = $false; ShowLog = $false; Attempts = 0; Error = "status: exited, exit code: 127"; Diagnostics = $true },
    @{ Scenario = "Dead"; FullText = $false; ShowLog = $false; Attempts = 0; Error = "status: dead"; Diagnostics = $true },
    @{ Scenario = "InspectFailure"; FullText = $false; ShowLog = $false; Attempts = 0; Error = "Unable to inspect SQL Server container"; Diagnostics = $true },
    @{ Scenario = "Timeout"; FullText = $false; ShowLog = $false; Attempts = 3; Error = "after 3 attempts.*test connection refused"; Diagnostics = $true },
    @{ Scenario = "Retry"; FullText = $false; ShowLog = $false; Attempts = 3; Error = $null; Diagnostics = $false },
    @{ Scenario = "SqlcmdThrows"; FullText = $false; ShowLog = $false; Attempts = 3; Error = "after 3 attempts.*test transport exception"; Diagnostics = $true },
    @{ Scenario = "TimeoutDiagnosticsFailure"; FullText = $false; ShowLog = $false; Attempts = 3; Error = "after 3 attempts.*test connection refused"; Diagnostics = $true },
    @{ Scenario = "SuccessDiagnosticsFailure"; FullText = $false; ShowLog = $true; Attempts = 1; Error = $null; Diagnostics = $true }
)

try {
    # Test both caller error policies: startup failures must always terminate.
    foreach ($callerPolicy in "Stop", "Continue") {
        foreach ($case in $cases) {
            $global:MssqlSuiteTestState = @{
                Scenario = $case.Scenario
                Calls = [System.Collections.Generic.List[string]]::new()
                Attempts = 0
                BuildContext = $null
            }
            $global:LASTEXITCODE = 0
            $failure = $null
            $ErrorActionPreference = $callerPolicy
            try {
                & "$root/Start-SqlContainer.ps1" -Version 2025 -SaPassword "test-password" -FullText:$case.FullText -ShowLog:$case.ShowLog -TryLimit 3 -RetryDelaySeconds 0 | Out-Null
            } catch {
                $failure = $_.Exception.Message
            }
            $ErrorActionPreference = "Stop"
            $label = "$($case.Scenario), FullText=$($case.FullText), caller=$callerPolicy"
            if ($case.Error) {
                Assert-True ($null -ne $failure -and $failure -match $case.Error) "$label did not preserve the expected failure: $failure"
            } else {
                Assert-True ($null -eq $failure) "$label unexpectedly failed: $failure"
                Assert-True ($global:LASTEXITCODE -eq 0) "$label leaked a diagnostic exit code"
            }
            Assert-True ($global:MssqlSuiteTestState.Attempts -eq $case.Attempts) "$label made the wrong number of connection attempts"
            $calls = $global:MssqlSuiteTestState.Calls
            Assert-True (($calls -contains "logs --timestamps sql") -eq $case.Diagnostics) "$label collected the wrong diagnostics"
            if ($case.Diagnostics) {
                Assert-True ($calls -contains "ps -a") "$label did not list containers"
                Assert-True ($calls -contains "inspect sql --format {{json .State}}") "$label did not inspect container state"
            }
            Assert-True (@($calls | Where-Object { $_ -like "inspect*" -and $_ -notlike "*{{json .State}}*" }).Count -eq 0) "$label exposed full container configuration"
            if ($case.FullText) {
                Assert-True ($global:MssqlSuiteTestState.BuildContext -eq $root) "$label used the caller's working directory as the build context"
            }
            if ($case.Scenario -eq "BuildFailure") {
                Assert-True (@($calls | Where-Object { $_ -like "run *" }).Count -eq 0) "A failed build was followed by docker run"
            }
            Write-Output "PASS: $label"
        }
    }
    Write-Output "All 24 container startup regression cases passed."
} finally {
    $ErrorActionPreference = "Stop"
    Remove-Variable MssqlSuiteTestState -Scope Global -ErrorAction SilentlyContinue
}
