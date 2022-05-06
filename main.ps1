param (
   [ValidateSet("sqlclient","sqlpackage", "sqlengine", "localdb")]
   [string[]]$Install,
   [string]$SaPassword,
   [switch]$ShowLog,
   [string]$Collation="SQL_Latin1_General_CP1_CI_AS"
)

if ("sqlengine" -in $Install) {
   Write-Output "Installing SQL Engine"
   if ($ismacos) {
      Write-Output "mac detected, installing docker then downloading a docker container"
      $Env:HOMEBREW_NO_AUTO_UPDATE = 1
      brew install --cask docker
      sudo /Applications/Docker.app/Contents/MacOS/Docker --unattended --install-privileged-components
      open -a /Applications/Docker.app --args --unattended --accept-license
      Start-Sleep 30
      $tries = 0
      Write-Output "We are waiting for Docker to be up and running. It can take over 2 minutes..."
      do { 
         try {
            $tries++
            $sock = Get-ChildItem $home/Library/Containers/com.docker.docker/Data/docker.raw.sock -ErrorAction Stop
         } catch {
            Write-Output "Waiting..."
            Start-Sleep 5
         }
      }
      until ($sock.BaseName -or $tries -gt 55)
      
      if ($tries -gt 55) {
         Write-Output "
         
         
         
         Moving on without waiting for docker to start
         
         
         
         
         "
      }

      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -e "MSSQL_COLLATION=$Collation" --name sql -p 1433:1433 --memory="2g" -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Docker finished running"
      Start-Sleep 5
      if ($ShowLog) {
         docker ps -a
         docker logs -t sql
      }
      
      Write-Output "sql engine installed at localhost"
   }

   if ($islinux) {
      Write-Output "linux detected, downloading the 2019 docker container"
      docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -e "MSSQL_COLLATION=$Collation" --name sql -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
      Write-Output "Waiting for docker to start"
      Start-Sleep -Seconds 10
      
      if ($ShowLog) {
         docker ps -a
         docker logs -t sql
      }
      Write-Output "docker container running - sql server accessible at localhost"
   }

   if ($iswindows) {
      Write-Output "windows detected, downloading sql server 2019"
      # docker takes 16 minutes, this takes 5 minutes
      if (-not (Test-Path C:\temp)) {
         mkdir C:\temp
      }
      Push-Location C:\temp
      $ProgressPreference = "SilentlyContinue"
      Invoke-WebRequest -Uri https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.exe -OutFile sqlsetup.exe
      Invoke-WebRequest -Uri https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.box -OutFile sqlsetup.box
      Start-Process -Wait -FilePath ./sqlsetup.exe -ArgumentList /qs, /x:setup
      .\setup\setup.exe /q /ACTION=Install /INSTANCENAME=MSSQLSERVER /FEATURES=SQLEngine /UPDATEENABLED=0 /SQLSVCACCOUNT='NT SERVICE\MSSQLSERVER' /SQLSYSADMINACCOUNTS='BUILTIN\ADMINISTRATORS' /TCPENABLED=1 /NPENABLED=0 /IACCEPTSQLSERVERLICENSETERMS /SQLCOLLATION=$Collation /USESQLRECOMMENDEDMEMORYLIMITS
      Set-ItemProperty -path 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLSERVER\' -Name LoginMode -Value 2 
      Restart-Service MSSQLSERVER
      sqlcmd -S localhost -q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'"
      sqlcmd -S localhost -q "ALTER LOGIN [sa] ENABLE"
      Pop-Location
      
      Write-Output "sql server 2019 installed at localhost and accessible with both windows and sql auth"
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
   Write-Output "installing sqlpackage"

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
   
   Write-Output "sqlpackage installed"
}

if ("localdb" -in $Install) {
   if ($iswindows) {
      Write-Host "Downloading SqlLocalDB"
      $ProgressPreference = "SilentlyContinue"
      Invoke-WebRequest -Uri https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SqlLocalDB.msi -OutFile SqlLocalDB.msi
      Write-Host "Installing"
      Start-Process -FilePath "SqlLocalDB.msi" -Wait -ArgumentList "/qn", "/norestart", "/l*v SqlLocalDBInstall.log", "IACCEPTSQLLOCALDBLICENSETERMS=YES";
      Write-Host "Checking"
      sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "SELECT @@VERSION;"
      sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'"
      
      Write-Host "SqlLocalDB installed and accessible at (localdb)\MSSQLLocalDB"
   } else {
      Write-Output "localdb cannot be isntalled on mac or linux"
   }
}