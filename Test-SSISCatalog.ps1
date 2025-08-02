Write-Output "Checking for SSISDB catalog on localhost..."

$result = sqlcmd -S localhost -C -E -Q "SELECT name FROM sys.databases WHERE name = 'SSISDB';" -h -1

if ($result -eq "SSISDB") {
    Write-Output "SSISDB catalog exists."
    exit 0
} else {
    Write-Error "SSISDB catalog does not exist."
    exit 1
}