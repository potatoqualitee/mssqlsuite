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
      Get-Content $profile
      . $profile      
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($iswindows) {
      #docker pull microsoft/mssql-server-windows-developer
      #docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d microsoft/mssql-server-windows-developer
   }

   Write-Output "Waiting for docker to start"
   Start-Sleep -Seconds 10
}

if ("sqlcmd" -in $Install) {
   Write-Output "Installing sqlcmd"
   if ($ismacos) {
      brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
      brew update
      'HOMEBREW_NO_ENV_FILTERING=1', 'ACCEPT_EULA=Y' brew install msodbcsql17 mssql-tools
   }
   
   Write-Output "sqlcmd is installed"
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"
   Write-Output "jk"
}