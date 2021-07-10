param (
   [ValidateSet("sqlcmd","sqlpackage", "docker")]
   [string[]]$Install,
   [string]$SaPassword
)

if ("docker" -in $Install) {
   Write-Output "Installing docker"
   if ($ismacos) {
      brew install docker-machine docker
      sudo docker –version
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Docker finished running"
      Start-Sleep 5
      docker ps -a
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($iswindows) {
      docker run -d -p 1433:1433 -e "sa_password=$SaPassword" -e ACCEPT_EULA=Y microsoft/mssql-server-windows-developer
   }

   Write-Output "Waiting for docker to start"
   Start-Sleep -Seconds 10
}

if ("sqlcmd" -in $Install) {
   Write-Output "Installing sqlcmd"

   if ($ismacos) {
      brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
      brew update
      $env:ACCEPT_EULA = 'Y'
      brew install msodbcsql17 mssql-tools
   }
   
   Write-Output "sqlcmd is installed"
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"

   if ($ismacos) {
      curl "https://go.microsoft.com/fwlink/?linkid=2143659" -4 -sL -o '/tmp/sqlpackage.zip'
      unzip /tmp/sqlpackage.zip -d $HOME/sqlpackage
      chmod +x $HOME/sqlpackage/sqlpackage
      sudo ln -sf $HOME/sqlpackage/sqlpackage /usr/local/bin
      sqlpackage /version
   }

   if ($islinux) {
      curl "https://go.microsoft.com/fwlink/?linkid=2143497" -4 -sL -o '/tmp/sqlpackage.zip'
      unzip /tmp/sqlpackage.zip -d $HOME/sqlpackage
      chmod +x $HOME/sqlpackage/sqlpackage
      sudo ln -sf $HOME/sqlpackage/sqlpackage /usr/local/bin
      sqlpackage /version
   }

   if ($iswindows) {
      choco install sqlpackage
   }
}