param (
    [ValidateSet("sqlclient", "sqlpackage", "sqlengine", "localdb")]
    [string[]]$Install,
    [string]$SaPassword,
    [switch]$ShowLog,
    [string]$Collation = "SQL_Latin1_General_CP1_CI_AS",
    [ValidateSet("2022","2019", "2017")]
    [string]$Version = "2019"
)

if ("sqlengine" -in $Install) {
    Write-Output "Installing SQL Engine"
    if ($ismacos) {
        Write-Output "mac detected, installing docker then downloading a docker container"
        $Env:HOMEBREW_NO_AUTO_UPDATE = 1
        brew install docker
        colima start --runtime docker
        Start-Sleep 5
        docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -e "MSSQL_COLLATION=$Collation" --name sql -p 1433:1433 --memory="2g" -d "mcr.microsoft.com/mssql/server:$Version-latest"
        Write-Output "Docker finished running"
        Start-Sleep 5
        if ($ShowLog) {
            docker ps -a
            docker logs -t sql
        }

        Write-Output "sql engine installed at localhost"
    }

    if ($islinux) {
        Write-Output "linux detected, downloading the docker container"
        docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -e "MSSQL_COLLATION=$Collation" --name sql -p 1433:1433 -d "mcr.microsoft.com/mssql/server:$Version-latest"
        Write-Output "Waiting for docker to start"
        Start-Sleep -Seconds 10

        if ($ShowLog) {
            docker ps -a
            docker logs -t sql
        }
        Write-Output "docker container running - sql server accessible at localhost"
    }

    if ($iswindows) {
        Write-Output "windows detected, downloading sql server"
        # docker takes 16 minutes, this takes 5 minutes
        if (-not (Test-Path C:\temp)) {
            mkdir C:\temp
        }
        Push-Location C:\temp
        $ProgressPreference = "SilentlyContinue"
        switch ($Version) {
            "2017" {
                $exeUri = "https://download.microsoft.com/download/E/F/2/EF23C21D-7860-4F05-88CE-39AA114B014B/SQLServer2017-DEV-x64-ENU.exe"
                $boxUri = "https://download.microsoft.com/download/E/F/2/EF23C21D-7860-4F05-88CE-39AA114B014B/SQLServer2017-DEV-x64-ENU.box"
                $installOptions = ""
                $versionMajor = 14
            }
            "2019" {
                $exeUri = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.exe"
                $boxUri = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.box"
                $installOptions = "/USESQLRECOMMENDEDMEMORYLIMITS"
                $versionMajor = 15
            }
            "2022" {
                $exeUri = "https://download.microsoft.com/download/4/0/2/4027643f-d845-4250-ae93-e66854ee1de6/SQLServer2022-x64-ENU.exe"
                $boxUri = "https://download.microsoft.com/download/4/0/2/4027643f-d845-4250-ae93-e66854ee1de6/SQLServer2022-x64-ENU.box"
                $installOptions = "/USESQLRECOMMENDEDMEMORYLIMITS"
                $versionMajor = 16
            }
        }
        Invoke-WebRequest -Uri $exeUri -OutFile sqlsetup.exe
        Invoke-WebRequest -Uri $boxUri -OutFile sqlsetup.box
        Start-Process -Wait -FilePath ./sqlsetup.exe -ArgumentList /qs, /x:setup

        .\setup\setup.exe /q /ACTION=Install /INSTANCENAME=MSSQLSERVER /FEATURES=SQLEngine /UPDATEENABLED=0 /SQLSVCACCOUNT='NT SERVICE\MSSQLSERVER' /SQLSYSADMINACCOUNTS='BUILTIN\ADMINISTRATORS' /TCPENABLED=1 /NPENABLED=0 /IACCEPTSQLSERVERLICENSETERMS /SQLCOLLATION=$Collation $installOptions

        Set-ItemProperty -path "HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL$versionMajor.MSSQLSERVER\MSSQLSERVER\" -Name LoginMode -Value 2
        Restart-Service MSSQLSERVER
        sqlcmd -S localhost -q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'"
        sqlcmd -S localhost -q "ALTER LOGIN [sa] ENABLE"
        Pop-Location

        Write-Output "sql server $Version installed at localhost and accessible with both windows and sql auth"
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
        curl "https://https://aka.ms/sqlpackage-macos" -4 -sL -o '/tmp/sqlpackage.zip'
        $log = unzip /tmp/sqlpackage.zip -d $HOME/sqlpackage
        chmod +x $HOME/sqlpackage/sqlpackage
        sudo ln -sf $HOME/sqlpackage/sqlpackage /usr/local/bin
        if ($ShowLog) {
            $log
            sqlpackage /version
        }
    }

    if ($islinux) {
        curl "https://aka.ms/sqlpackage-linux" -4 -sL -o '/tmp/sqlpackage.zip'
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
        if ($Version -eq "2022") {
            Write-Output "LocalDB for SQL Server 2022 not available yet."
        } else {
            Write-Host "Downloading SqlLocalDB"
            $ProgressPreference = "SilentlyContinue"
            switch ($Version) {
                "2017" { $uriMSI = "https://download.microsoft.com/download/E/F/2/EF23C21D-7860-4F05-88CE-39AA114B014B/SqlLocalDB.msi" }
                "2019" { $uriMSI = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SqlLocalDB.msi" }
            }
            Invoke-WebRequest -Uri $uriMSI -OutFile SqlLocalDB.msi
            Write-Host "Installing"
            Start-Process -FilePath "SqlLocalDB.msi" -Wait -ArgumentList "/qn", "/norestart", "/l*v SqlLocalDBInstall.log", "IACCEPTSQLLOCALDBLICENSETERMS=YES";
            Write-Host "Checking"
            sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "SELECT @@VERSION;"
            sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'"
            sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "ALTER LOGIN [sa] ENABLE"

            Write-Host "SqlLocalDB $Version installed and accessible at (localdb)\MSSQLLocalDB"
        }
    } else {
        Write-Output "localdb cannot be isntalled on mac or linux"
    }
}
