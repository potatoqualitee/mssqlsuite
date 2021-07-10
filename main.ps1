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
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Docker finished running"
      Start-Sleep 5
      vboxmanage controlvm "default" natpf1 "mssql,tcp,127.0.0.1,1433,,1433"
      docker ps -a
      docker-machine ip
      docker-machine ls
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
   }

   if ($iswindows) {
      Write-Output "Pulling docker image"
      docker pull microsoft/mssql-server-windows-developer
      
      Write-Output "Running docker image"
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d microsoft/mssql-server-windows-developer
   }

   Write-Output "Waiting for docker to start"
   Start-Sleep -Seconds 10
}

if ("sqlcmd" -in $Install) {
   Write-Output "Installing sqlcmd"

   if ($ismacos) {
      brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
      brew update
      $env:HOMEBREW_NO_ENV_FILTERING = 1
      $env:ACCEPT_EULA = 'Y'
      brew install msodbcsql17 mssql-tools
   }
   
   Write-Output "sqlcmd is installed"
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"
   Write-Output "jk"
}