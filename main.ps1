param (
   [ValidateSet("sqlcmd","sqlpackage", "docker")]
   [string[]]$Install,
   [string]$SaPassword
)

if ("docker" -in $Install) {
   Write-Output "docker install"
   if ($ismacos) {
      mkdir -p ~/.docker/machine/cache
      curl -Lo ~/.docker/machine/cache/boot2docker.iso https://github.com/boot2docker/boot2docker/releases/download/v19.03.12/boot2docker.iso
      brew install docker docker-machine
      docker-machine create --driver virtualbox default
      docker-machine env default
      eval "$(docker-machine env default)"
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Waiting for docker to start"
      Start-Sleep -Seconds 5
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Waiting for docker to start"
      Start-Sleep -Seconds 5
   }

   if ($iswindows) {
      bash whereis docker
      #bash docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Waiting for docker to start"
      Start-Sleep -Seconds 5
   }
}

if ("sqlcmd" -in $Install) {
   Write-Output "sqlcmd install"
   
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"
   Write-Output "jk"
}