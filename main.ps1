param (
   [ValidateSet("sqlcmd","sqlpackage", "docker")]
   [string[]]$Install,
   [string]$SaPassword
)

if ("docker" -in $Install) {
   Write-Output "Installing docker"
   if ($ismacos) {
      mkdir -p ~/.docker/machine/cache
      curl -Lo ~/.docker/machine/cache/boot2docker.iso https://github.com/boot2docker/boot2docker/releases/download/v19.03.12/boot2docker.iso
      brew install docker docker-machine
      docker-machine create --driver virtualbox default
      docker-machine env default
      
      $profiledir = Split-Path $profile
      if (-not (Test-Path $profiledir)) {
         mkdir $profiledir
      }

      docker-machine env default | Add-Content "$home/.bashrc"
      docker-machine env default | Add-Content $profile
      ((Get-Content $profile) -replace 'export ','$env:') | Set-Content $profile
      . $profile
      docker-machine ip default
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2017-latest
      Write-Output "Docker finished running"
      docker-machine ssh default -L 1433:localhost:1433
      Start-Sleep 5
      docker ps -a
      docker-machine ip
      docker-machine ls
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($iswindows) {
      
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