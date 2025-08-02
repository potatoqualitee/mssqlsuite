param(
    [string]$UserName,
    [string]$Password
)

Write-Output "Checking for SSISDB catalog on localhost..."

try {
    $result = sqlcmd -S localhost -d master -U $UserName -P $Password -Q "SELECT name FROM sys.databases WHERE name = 'SSISDB';" -W -h -1 2>&1

    if ($result -match "SSISDB") {
        Write-Output "SSISDB catalog exists."
        exit 0
    } else {
        Write-Error "SSISDB catalog does not exist."
        exit 1
    }
} catch {
    Write-Error "Failed to execute sqlcmd: $_"
    exit 2
}
