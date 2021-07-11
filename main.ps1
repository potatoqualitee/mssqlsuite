param (
   [ValidateSet("sqlclient","sqlpackage", "engine", "localdb")]
   [string[]]$Install,
   [string]$SaPassword,
   [switch]$ShowLog
)

if ("engine" -in $Install) {
   Write-Output "Installing docker"
   if ($ismacos) {
      mkdir -p ~/.docker/machine/cache
      curl -Lo ~/.docker/machine/cache/boot2docker.iso https://github.com/boot2docker/boot2docker/releases/download/v19.03.12/boot2docker.iso
      brew install docker docker-machine
      docker-machine create --driver virtualbox --virtualbox-memory 3072 default
      docker-machine env default
      
      $profiledir = Split-Path $profile
      if (-not (Test-Path $profiledir)) {
         mkdir $profiledir
         "" | Add-Content $profile
      }

      docker-machine env default | Add-Content "$home/.bashrc"
      docker-machine env default | Add-Content $profile
      ((Get-Content $profile) -replace 'export ','$env:') | Set-Content $profile
      . $profile
      docker-machine stop default
      VBoxManage modifyvm "default" --natpf1 "mssql,tcp,,1433,,1433"
      docker-machine start default
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" --name sql -p 1433:1433 --memory="2g" -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Docker finished running"
      Start-Sleep 5
      if ($ShowLog) {
         docker-machine ip default
         docker ps -a
         docker-machine ip
         docker-machine ls
         docker logs -t sql
      }
   }

   if ($islinux) {
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" --name sql -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Waiting for docker to start"
      Start-Sleep -Seconds 10
      
      if ($ShowLog) {
         docker ps -a
         docker-machine ip
         docker-machine ls
         docker logs -t sql
      }
   }

   if ($iswindows) {
      # docker takes 16 minutes, this takes 5 minutes
      if (-not (Test-Path C:\temp)) {
         mkdir C:\temp
      }
      Push-Location C:\temp
      $ProgressPreference = "SilentlyContinue"
      Invoke-WebRequest -Uri https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.exe -OutFile sqlsetup.exe
      Invoke-WebRequest -Uri https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.box -OutFile sqlsetup.box
      Start-Process -Wait -FilePath ./sqlsetup.exe -ArgumentList /qs, /x:setup
      .\setup\setup.exe /q /ACTION=Install /INSTANCENAME=MSSQLSERVER /FEATURES=SQLEngine /UPDATEENABLED=0 /SQLSVCACCOUNT='NT AUTHORITY\NETWORK SERVICE' /SQLSYSADMINACCOUNTS='BUILTIN\ADMINISTRATORS' /TCPENABLED=1 /NPENABLED=0 /IACCEPTSQLSERVERLICENSETERMS
      Set-ItemProperty -path 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLSERVER\' -Name LoginMode -Value 2 
      Restart-Service MSSQLSERVER
      sqlcmd -S localhost -q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'"
      sqlcmd -S localhost -q "ALTER LOGIN [sa] ENABLE"
      Pop-Location
   }
}

if ("sqlclient" -in $Install) {
   if ($ismacos) {
      Write-Output "Installing sqlclient tools"
      brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
      $null = brew update
      $log = brew install msodbcsql17 mssql-tools
      
      if ($ShowLog) {
         $log
      }
   }
   
   Write-Output "sqlclient tools are installed"
}

if ("sqlpackage" -in $Install) {
   Write-Output "sqlpackage install"

   if ($ismacos) {
      curl "https://go.microsoft.com/fwlink/?linkid=2143659" -4 -sL -o '/tmp/sqlpackage.zip'
      $log = unzip /tmp/sqlpackage.zip -d $HOME/sqlpackage
      chmod +x $HOME/sqlpackage/sqlpackage
      sudo ln -sf $HOME/sqlpackage/sqlpackage /usr/local/bin
      if ($ShowLog) {
         $log
         sqlpackage /version
      }
   }

   if ($islinux) {
      curl "https://go.microsoft.com/fwlink/?linkid=2143497" -4 -sL -o '/tmp/sqlpackage.zip'
      $log = unzip /tmp/sqlpackage.zip -d $HOME/sqlpackage
      chmod +x $HOME/sqlpackage/sqlpackage
      sudo ln -sf $HOME/sqlpackage/sqlpackage /usr/local/bin
      if ($ShowLog) {
         $log
         sqlpackage /version
      }
   }

   if ($iswindows) {
      $log = choco install sqlpackage
      if ($ShowLog) {
         $log
         sqlpackage /version
      }
   }
}

if ("localdb" -in $Install) {
   if ($iswindows) {
      Write-Host "Downloading"
      $ProgressPreference = "SilentlyContinue"
      Invoke-WebRequest -Uri https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SqlLocalDB.msi -OutFile SqlLocalDB.msi
      Write-Host "Installing"
      Start-Process -FilePath "SqlLocalDB.msi" -Wait -ArgumentList "/qn", "/norestart", "/l*v SqlLocalDBInstall.log", "IACCEPTSQLLOCALDBLICENSETERMS=YES";
      Write-Host "Checking"
      sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "SELECT @@VERSION;"
      sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'"
   } else {
      Write-Output "localdb cannot be isntalled on mac or linux"
   }
}