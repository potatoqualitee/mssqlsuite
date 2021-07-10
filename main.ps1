param (
   [ValidateSet("sqlcmd","sqlpackage", "docker")]
   [string[]]$Install,
   [string]$SaPassword
)
Write-Output "$install"

if ("docker" -in $Install) {
   Write-Output "docker install"
   docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   Write-Output "Waiting for docker to start"
   Start-Sleep -Seconds 5
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"
   Write-Output "jk"
}