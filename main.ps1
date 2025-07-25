param (
    [ValidateSet("sqlclient", "sqlpackage", "sqlengine", "localdb", "fulltext")]
    [string[]]$Install,
    [string]$SaPassword = "dbatools.I0",
    [switch]$ShowLog,
    [string]$Collation = "SQL_Latin1_General_CP1_CI_AS",
    [ValidateSet("2022", "2019", "2017", "2016")]
    [string]$Version = "2022"
)

if ("sqlengine" -in $Install) {
    Write-Output "Installing SQL Engine"

    if (-not $IsWindows -and $Version -in "2016", "2017") {
        Write-Warning "SQL Server 2016 and 2017 are not supported on Linux or Mac, please use 2019 or 2022"
        return
    }

    if ($ismacos) {
        Write-Output "mac detected, installing colima and docker"
        $Env:HOMEBREW_NO_AUTO_UPDATE = 1
        brew install docker colima qemu
        colima --verbose start -a x86_64 --cpu 4 --memory 4 --runtime docker
    }

    if ($ismacos -or $islinux) {
        Write-Output "linux/mac detected, downloading the docker container"

        if ("fulltext" -in $Install) {
            docker build -f $PSScriptRoot/Dockerfile-$Version -t mssql-fulltext .
            $img = "mssql-fulltext"
        } else {
            $img = "mcr.microsoft.com/mssql/server:$Version-latest"
        }

        docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$SaPassword" -e "MSSQL_COLLATION=$Collation" --name sql -p 1433:1433 -d $img
        Write-Output "Waiting for docker to start"

        # MacOS takes longer to start using qemu
        if ($ismacos) {
            Start-Sleep -Seconds 90
        } else {
            Start-Sleep -Seconds 10
        }

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
            "2016" {
                $exeUri = "https://download.microsoft.com/download/C/5/0/C50D5F5E-1ADF-43EB-BF16-205F7EAB1944/SQLServer2016-SSEI-Dev.exe"
                $boxUri = ""
                $versionMajor = 13
            }
            "2017" {
                $exeUri = "https://download.microsoft.com/download/5/A/7/5A7065A2-C81C-4A31-9972-8A31AC9388C1/SQLServer2017-SSEI-Dev.exe"
                $boxUri = ""
                $versionMajor = 14
            }
            "2019" {
                $exeUri = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.exe"
                $boxUri = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.box"
                $versionMajor = 15
            }
            "2022" {
                $exeUri = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-DEV-x64-ENU.exe"
                $boxUri = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-DEV-x64-ENU.box"
                $versionMajor = 16
            }
        }

        $features = if ("fulltext" -in $Install) { "SQLEngine,FullText" } else { "SQLEngine" }

        $installArgs = @(
            "/q",
            "/ACTION=Install",
            "/INSTANCENAME=MSSQLSERVER",
            "/FEATURES=$features",
            "/UPDATEENABLED=0",
            "/SQLSVCACCOUNT=""NT SERVICE\MSSQLSERVER""",
            "/SQLSYSADMINACCOUNTS=""BUILTIN\ADMINISTRATORS""",
            "/TCPENABLED=1",
            "/NPENABLED=0",
            "/IACCEPTSQLSERVERLICENSETERMS",
            "/SQLCOLLATION=$Collation"
        )

        if ($boxUri -eq "") {
            # For 2016 & 2017.
            # Download the small setup utility that allows us to download the full installation media
            Invoke-WebRequest -Uri $exeUri -OutFile c:\temp\downloadsetup.exe
            # Use the small setup utility to download the full installation media (*.box and *.exe) files to c:\temp
            Start-Process -Wait -FilePath ./downloadsetup.exe -ArgumentList /ACTION:Download, /QUIET, /MEDIAPATH:c:\temp
            # Rename the *.box and *.exe files to our standard name.  From here we can process the same as 2019 & 2022
            Get-ChildItem -Name "SQLServer*.box" | Rename-Item -NewName "sqlsetup.box"
            Get-ChildItem -Name "SQLServer*.exe" | Rename-Item -NewName "sqlsetup.exe"
        } else {
            # For 2019 & 2022
            Invoke-WebRequest -Uri $exeUri -OutFile sqlsetup.exe
            Invoke-WebRequest -Uri $boxUri -OutFile sqlsetup.box
            # Add argument here as it's not supported on older versions
            $installArgs += "/USESQLRECOMMENDEDMEMORYLIMITS"
        }
        # Extracts media
        Start-Process -Wait -FilePath ./sqlsetup.exe -ArgumentList /qs, /x:setup

        # Runs SQL Server installation
        Start-Process -FilePath ".\setup\setup.exe" -ArgumentList $installArgs -Wait -NoNewWindow

        Set-ItemProperty -path "HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL$versionMajor.MSSQLSERVER\MSSQLSERVER\" -Name LoginMode -Value 2
        Restart-Service MSSQLSERVER
        sqlcmd -S localhost -q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'" -C
        sqlcmd -S localhost -q "ALTER LOGIN [sa] ENABLE" -C
        Pop-Location

        Write-Output "sql server $Version installed at localhost and accessible with both windows and sql auth"
    }
}

if ("sqlclient" -in $Install) {
    Write-Output "Installing sqlclient tools"
    $log = ""

    if ($ismacos) {
        brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
        #$null = brew update
        $log = brew install microsoft/mssql-release/msodbcsql18 microsoft/mssql-release/mssql-tools18

        echo "/opt/homebrew/bin" >> $env:GITHUB_PATH
    }

    if ($islinux) {
        # Add Microsoft repository key
        $log = bash -c "curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -"

        # Add Microsoft repository
        $log += bash -c "curl https://packages.microsoft.com/config/ubuntu/\$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list"

        # Install prerequisites and SQL tools
        $null = bash -c "sudo apt-get update"
        $log += bash -c "sudo apt-get install -y apt-transport-https"
        $log += bash -c "sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18 mssql-tools18 unixodbc-dev"

        # Add to PATH for current session and future sessions
        echo "/opt/mssql-tools18/bin" >> $env:GITHUB_PATH
        $log += bash -c "echo 'export PATH=`$PATH:/opt/mssql-tools18/bin' | sudo tee -a /etc/bash.bashrc"
        $log += bash -c "source /etc/bash.bashrc"
    }

    if ($ShowLog) {
        $log
    }

    Write-Output "sqlclient tools are installed"
}

if ("sqlpackage" -in $Install) {
    Write-Output "installing sqlpackage"

    if ($ismacos) {
        curl "https://aka.ms/sqlpackage-macos" -4 -sL -o '/tmp/sqlpackage.zip'
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
        Write-Host "Downloading SqlLocalDB"
        $ProgressPreference = "SilentlyContinue"
        switch ($Version) {
            "2017" { $uriMSI = "https://download.microsoft.com/download/E/F/2/EF23C21D-7860-4F05-88CE-39AA114B014B/SqlLocalDB.msi" }
            "2016" { $uriMSI = "https://download.microsoft.com/download/4/1/A/41AD6EDE-9794-44E3-B3D5-A1AF62CD7A6F/sql16_sp2_dlc/en-us/SqlLocalDB.msi" }
            "2019" { $uriMSI = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SqlLocalDB.msi" }
            "2022" { $uriMSI = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SqlLocalDB.msi" }
        }
        Invoke-WebRequest -Uri $uriMSI -OutFile SqlLocalDB.msi
        Write-Host "Installing"
        Start-Process -FilePath "SqlLocalDB.msi" -Wait -ArgumentList "/qn", "/norestart", "/l*v SqlLocalDBInstall.log", "IACCEPTSQLLOCALDBLICENSETERMS=YES";
        Write-Host "Checking"
        sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "SELECT @@VERSION;" -C
        sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "ALTER LOGIN [sa] WITH PASSWORD=N'$SaPassword'" -C
        sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "ALTER LOGIN [sa] ENABLE" -C

        Write-Host "SqlLocalDB $Version installed and accessible at (localdb)\MSSQLLocalDB"
    } else {
        Write-Output "localdb cannot be installed on mac or linux"
    }
}
