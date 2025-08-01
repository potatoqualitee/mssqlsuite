param(
    [string]$ServerInstance = "localhost",
    [string]$UserName = "sa",
    [string]$Password = "dbatools.I0"
)

Write-Output "Checking for SSISDB catalog on $ServerInstance..."

$query = "SELECT name FROM sys.databases WHERE name = 'SSISDB';"
$result = sqlcmd -S $ServerInstance -U $UserName -P $Password -Q $query -h -1

if ($result -eq "SSISDB") {
    Write-Output "SSISDB catalog exists."
    exit 0
} else {
    Write-Error "SSISDB catalog does not exist."
    exit 1
}