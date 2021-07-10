param (
   [ValidateSet("sqlcmd","sqlpackage", "docker")]
   [string[]]$Install,
   [string]$SaPassword
)
Write-Output "$install"

if ("sqlcmd" -in $Install) {
   Write-Output "sqlcmd install"  
   curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
   curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
   sudo apt-get update
   sudo apt-get install mssql-tools unixodbc-dev
   Write-Output 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bash_profile
   bash source ~/.bashrc
}

if ("docker" -in $Install) {
   Write-Output "docker install"
   docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"
   Write-Output "jk"
}