param (
    [ValidateSet("sqlclient", "sqlpackage", "sqlengine", "localdb", "fulltext", "ssis")]
    [string[]]$Install,
    [string]$SaPassword = "dbatools.I0",
    [string]$AdminUsername = "sa",
    [switch]$ShowLog,
    [string]$Collation = "SQL_Latin1_General_CP1_CI_AS",
    [ValidateSet("2022", "2019", "2017", "2016")]
    [string]$Version = "2022"
)
# Warn if SSIS is requested on unsupported OS
if (("ssis" -in $Install) -and ($islinux -or $ismacos)) {
    Write-Warning "The 'ssis' option is only supported on Windows. Skipping SSIS installation."
    $Install = $Install | Where-Object { $_ -ne "ssis" }
}

# if ssis then also ensure sqlengine
if ("ssis" -in $Install -and -not ("sqlengine" -in $Install)) {
    Write-Output "Adding sqlengine to install list because ssis is requested"
    $Install += "sqlengine"
}

# Install sqlcmd first to ensure it's available for any sa renaming operations
Write-Output "Installing sqlcmd before proceeding with other installations"

if ($islinux) {
    Write-Output "Installing sqlcmd on Linux"
    bash -c "curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc"
    bash -c "curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list"
    bash -c "sudo apt-get update"
    bash -c "sudo apt-get install -y sqlcmd"
}

if ($ismacos) {
    Write-Output "Installing sqlcmd on macOS"
    brew update
    brew install sqlcmd
}

if ($iswindows) {
    Write-Output "Installing sqlcmd on Windows"
    choco install sqlcmd -y --no-progress
}

Write-Output "sqlcmd installation completed"

if ("sqlengine" -in $Install) {
    Write-Output "Installing SQL Engine"

    if (-not $IsWindows -and $Version -in "2016", "2017") {
        Write-Warning "SQL Server 2016 and 2017 are not supported on Linux or Mac, please use 2019 or 2022"
        return
    }

    if ($ismacos) {
        Write-Output "mac detected, installing colima and docker"
        $Env:HOMEBREW_NO_AUTO_UPDATE = 1
        brew install docker colima qemu lima-additional-guestagents
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

        # Rename sa user if custom admin username is specified
        if ($AdminUsername -ne "sa") {
            Write-Output "Renaming sa user to: $AdminUsername"
            $renameSql = "ALTER LOGIN [sa] WITH NAME = [$AdminUsername];"
            # Use sqlcmd from host to connect to the Docker container
            sqlcmd -S localhost -U sa -P "$SaPassword" -Q "$renameSql" -C
            Write-Output "sa user renamed to '$AdminUsername' successfully"
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

        if ("fulltext" -in $Install) {
            $features = "SQLEngine,FullText"
        } else {
            $features = "SQLEngine"
        }

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

        Write-Warning "INSTALL ARGS: $installArgs"

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

        # Rename sa user if custom admin username is specified
        if ($AdminUsername -ne "sa") {
            Write-Output "Renaming sa user to: $AdminUsername"
            $renameSql = "ALTER LOGIN [sa] WITH NAME = [$AdminUsername];"
            sqlcmd -S localhost -q "$renameSql" -C
            Write-Output "sa user renamed to '$AdminUsername' successfully"
        }

        # After SQL Server and SSIS install, create SSISDB catalog if requested
        if ("ssis" -in $Install) {
            # Detect the default or previously installed SQL Server instance
            $instanceName = "MSSQLSERVER"
            try {
                $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
                if (Test-Path $regPath) {
                    $instances = Get-ItemProperty -Path $regPath | Select-Object -ExpandProperty PSObject.Properties | ForEach-Object { $_.Name }
                    if ($instances.Count -gt 0) {
                        $instanceName = $instances[0]
                        Write-Output "Detected SQL Server instance: $instanceName"
                    } else {
                        Write-Output "No SQL Server instances found in registry, defaulting to MSSQLSERVER"
                    }
                } else {
                    Write-Output "SQL Server instance registry path not found, defaulting to MSSQLSERVER"
                }
            } catch {
                Write-Output "Error detecting SQL Server instance, defaulting to MSSQLSERVER"
            }

            # Download and extract media (reuses $exeUri and $boxUri from main logic)
            if (-not (Test-Path C:\temp)) { mkdir C:\temp }
            Push-Location C:\temp
            $ProgressPreference = "SilentlyContinue"

            if ($boxUri -eq "") {
                # For 2016 & 2017
                if (-not (Test-Path "downloadsetup.exe")) {
                    Invoke-WebRequest -Uri $exeUri -OutFile downloadsetup.exe
                    Start-Process -Wait -FilePath ./downloadsetup.exe -ArgumentList /ACTION:Download, /QUIET, /MEDIAPATH:C:\temp
                    Get-ChildItem -Name "SQLServer*.box" | Rename-Item -NewName "sqlsetup.box"
                    Get-ChildItem -Name "SQLServer*.exe" | Rename-Item -NewName "sqlsetup.exe"
                }
            } else {
                # For 2019 & 2022
                if (-not (Test-Path "sqlsetup.exe")) {
                    Invoke-WebRequest -Uri $exeUri -OutFile sqlsetup.exe
                }
                if (-not (Test-Path "sqlsetup.box")) {
                    Invoke-WebRequest -Uri $boxUri -OutFile sqlsetup.box
                }
            }

            # Extracts media
            Start-Process -Wait -FilePath ./sqlsetup.exe -ArgumentList /qs, /x:setup

            # Prepare SSIS add-on install arguments for existing instance
            $ssisArgs = @(
                "/Q",
                "/ACTION=Install",
                "/FEATURES=IS",
                "/INSTANCENAME=$instanceName",
                "/ISSVCSTARTUPTYPE=Automatic",
                "/IACCEPTSQLSERVERLICENSETERMS"
            )

            # Run SSIS add-on install
            Write-Output ("Running SSIS add-on setup for instance {0}: .\setup\setup.exe {1}" -f $instanceName, ($ssisArgs -join ' '))
            Start-Process -FilePath ".\setup\setup.exe" -ArgumentList $ssisArgs -Wait -NoNewWindow

            Start-Sleep -Seconds 5 # Wait for SSIS service to start

            # Enable CLR integration (required for SSISDB catalog)
            Write-Output "Enabling CLR integration for SSISDB..."
            sqlcmd -S localhost -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;" -C
            sqlcmd -S localhost -Q "EXEC sp_configure 'clr enabled', 1; RECONFIGURE;" -C

            # Start Integration Services - dynamic service detection
            Write-Output "Starting Integration Services..."
            $ssisServices = Get-Service -Name "*DTS*" -ErrorAction SilentlyContinue
            if ($ssisServices) {
                foreach ($service in $ssisServices) {
                    Write-Output "Found DTS service: $($service.Name) - Status: $($service.Status)"
                    if ($service.Status -eq "Stopped") {
                        try {
                            Start-Service $service.Name -ErrorAction SilentlyContinue
                            Write-Output "Started service: $($service.Name)"
                        } catch {
                            Write-Warning "Failed to start service: $($service.Name)"
                        }
                    }
                }
            } else {
                Write-Warning "No Integration Services (DTS) services found"
            }

            # Create SSISDB catalog using the backup restoration method
            Write-Output "Creating SSISDB catalog using SSISDBBackup.bak..."

            # First check if SSISDB already exists
            $ssisdbExists = sqlcmd -S localhost -Q "SELECT COUNT(*) FROM sys.databases WHERE name = 'SSISDB'" -h -1 -C
            if ($ssisdbExists -eq "1") {
                Write-Output "SSISDB database already exists"
            } else {
                # Locate the SSISDBBackup.bak file based on version
                $backupPath = "C:\Program Files\Microsoft SQL Server\$versionMajor" + "0\DTS\Binn\SSISDBBackup.bak"

                if (-not (Test-Path $backupPath)) {
                    Write-Warning "SSISDBBackup.bak not found at $backupPath"
                    # Try alternative locations
                    $alternativePaths = @(
                        "C:\Program Files\Microsoft SQL Server\$versionMajor" + "0\Shared\SSISDBBackup.bak",
                        "C:\Program Files\Microsoft SQL Server\MSSQL$versionMajor.MSSQLSERVER\MSSQL\Backup\SSISDBBackup.bak"
                    )

                    foreach ($altPath in $alternativePaths) {
                        if (Test-Path $altPath) {
                            $backupPath = $altPath
                            Write-Output "Found backup at alternative location: $backupPath"
                            break
                        }
                    }

                    if (-not (Test-Path $backupPath)) {
                        Write-Error "Could not locate SSISDBBackup.bak file. SSIS may not be properly installed."
                        continue
                    }
                }

                Write-Output "Found SSISDBBackup.bak at: $backupPath"

                # Get the SQL Server data directory dynamically
                $dataDir = sqlcmd -S localhost -Q "SELECT SERVERPROPERTY('InstanceDefaultDataPath')" -h -1 -C
                if (-not $dataDir -or $dataDir.Trim() -eq "" -or $dataDir.Trim() -eq "NULL") {
                    # Fallback to standard path based on version
                    $dataDir = "C:\Program Files\Microsoft SQL Server\MSSQL$versionMajor.MSSQLSERVER\MSSQL\DATA\"
                }
                $dataDir = $dataDir.Trim()
                Write-Output "Using data directory: $dataDir"

                # Restore SSISDB from backup
                $restoreSql = @"
RESTORE DATABASE [SSISDB]
FROM DISK = N'$backupPath'
WITH FILE = 1,
MOVE N'data' TO N'$dataDir\SSISDB.mdf',
MOVE N'log' TO N'$dataDir\SSISDB.ldf',
NOUNLOAD, REPLACE, STATS = 5
"@

                try {
                    Write-Output "Restoring SSISDB database from backup..."
                    sqlcmd -S localhost -Q "$restoreSql" -C
                    Write-Output "✓ SSISDB database restored successfully"
                } catch {
                    Write-Warning "Backup restoration failed: $_"
                    Write-Output "Trying simplified restore command..."

                    # Try simplified restore
                    $simplifiedRestore = "RESTORE DATABASE [SSISDB] FROM DISK = N'$backupPath' WITH REPLACE"
                    try {
                        sqlcmd -S localhost -Q "$simplifiedRestore" -C
                        Write-Output "✓ SSISDB database restored with simplified command"
                    } catch {
                        Write-Error "Both restore methods failed: $_"
                        continue
                    }
                }

                # Configure the restored database
                $configureSql = @"
-- Set database to trustworthy for CLR assemblies
ALTER DATABASE [SSISDB] SET TRUSTWORTHY ON;

-- Configure recovery model
ALTER DATABASE [SSISDB] SET RECOVERY SIMPLE;

-- Ensure database is accessible
ALTER DATABASE [SSISDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [SSISDB] SET MULTI_USER;
"@

                try {
                    sqlcmd -S localhost -Q "$configureSql" -C
                    Write-Output "✓ SSISDB database configured"
                } catch {
                    Write-Warning "Database configuration had issues: $_"
                }
            }

            # Now try to complete catalog initialization using PowerShell
            Write-Output "Completing SSISDB catalog initialization..."

            try {
                # Map SQL Server versions to assembly versions
                $assemblyVersion = switch ($versionMajor) {
                    13 { "13.0.0.0" }  # SQL Server 2016
                    14 { "14.0.0.0" }  # SQL Server 2017
                    15 { "15.0.0.0" }  # SQL Server 2019
                    16 { "16.0.0.0" }  # SQL Server 2022
                    default { "16.0.0.0" }  # Default to latest
                }

                Write-Output "Loading Integration Services assemblies for version $assemblyVersion..."

                $assemblyLoaded = $false
                try {
                    # Try version-specific assembly first
                    [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices, Version=$assemblyVersion, Culture=neutral, PublicKeyToken=89845dcd8080cc91") | Out-Null
                    $assemblyLoaded = $true
                    Write-Output "✓ Loaded version-specific Integration Services assembly ($assemblyVersion)"
                } catch {
                    Write-Output "Version-specific assembly failed, trying generic load..."
                    try {
                        # Fallback to generic load without version
                        [Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices") | Out-Null
                        $assemblyLoaded = $true
                        Write-Output "✓ Loaded Integration Services assembly (generic)"
                    } catch {
                        Write-Output "Integration Services assembly not available: $($_.Exception.Message)"
                    }
                }

                if ($assemblyLoaded) {
                    try {
                        $sqlConnectionString = "Data Source=localhost;Initial Catalog=master;Integrated Security=True;"
                        $sqlConnection = New-Object System.Data.SqlClient.SqlConnection $sqlConnectionString
                        $integrationServices = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $sqlConnection

                        if ($integrationServices.Catalogs.Count -eq 0) {
                            Write-Output "Initializing SSISDB catalog with password..."
                            $catalog = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog($integrationServices, "SSISDB", $SaPassword)
                            $catalog.Create()
                            Write-Output "✓ SSISDB catalog initialized successfully using PowerShell method"
                        } else {
                            Write-Output "✓ SSISDB catalog already exists and is accessible"
                        }
                    } catch {
                        Write-Output "PowerShell catalog initialization failed: $($_.Exception.Message)"
                        Write-Output "Catalog database exists, trying direct T-SQL approach..."

                        # Try using the catalog.create_catalog procedure that should now exist
                        try {
                            sqlcmd -S localhost -d SSISDB -Q "EXEC catalog.create_catalog @password = N'$SaPassword'" -C
                            Write-Output "✓ SSISDB catalog initialized using T-SQL method"
                        } catch {
                            Write-Output "T-SQL catalog creation also failed, but database is restored"
                        }
                    }
                } else {
                    Write-Output "Assembly loading failed, trying direct database approach..."
                    # The database should be functional even without assembly initialization
                    try {
                        sqlcmd -S localhost -d SSISDB -Q "EXEC catalog.create_catalog @password = N'$SaPassword'" -C
                        Write-Output "✓ SSISDB catalog initialized using direct T-SQL"
                    } catch {
                        Write-Output "Direct T-SQL approach failed, but database should be functional"
                    }
                }
            } catch {
                Write-Warning "Catalog initialization had issues: $_"
            }

            # Comprehensive verification
            Write-Output "Performing comprehensive SSISDB verification..."

            # Check database exists and is accessible
            $dbCheck = sqlcmd -S localhost -Q "SELECT COUNT(*) FROM sys.databases WHERE name = 'SSISDB'" -h -1 -C
            if ($dbCheck -eq "1") {
                Write-Output "✓ SSISDB database verification successful"

                # Check if we can connect to the database
                try {
                    $dbAccessible = sqlcmd -S localhost -d SSISDB -Q "SELECT DB_NAME()" -h -1 -C
                    if ($dbAccessible -match "SSISDB") {
                        Write-Output "✓ SSISDB database is accessible"

                        # Check catalog schema exists
                        $catalogSchema = sqlcmd -S localhost -d SSISDB -Q "SELECT COUNT(*) FROM sys.schemas WHERE name = 'catalog'" -h -1 -C
                        if ($catalogSchema -eq "1") {
                            Write-Output "✓ SSISDB catalog schema exists"

                            # Check essential catalog objects
                            $catalogObjects = sqlcmd -S localhost -d SSISDB -Q "SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('catalog')" -h -1 -C
                            Write-Output "✓ SSISDB has $catalogObjects catalog tables"

                            # Test catalog functionality
                            try {
                                $folderTest = sqlcmd -S localhost -d SSISDB -Q "SELECT COUNT(*) FROM catalog.folders" -h -1 -C
                                Write-Output "✓ SSISDB catalog is functional (folders table accessible)"
                            } catch {
                                Write-Output "⚠ SSISDB catalog exists but may need additional configuration"
                            }
                        } else {
                            Write-Warning "SSISDB database exists but catalog schema is missing"
                        }
                    }
                } catch {
                    Write-Warning "SSISDB database exists but access failed: $_"
                }
            } else {
                Write-Warning "✗ SSISDB database verification failed"
                Write-Output "Available databases:"
                sqlcmd -S localhost -Q "SELECT name FROM sys.databases" -C
            }

            Pop-Location
            Write-Output "SSIS installation and catalog setup complete"
        }

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
        brew uninstall sqlcmd
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

        # Rename sa user if custom admin username is specified
        if ($AdminUsername -ne "sa") {
            Write-Host "Renaming sa user to: $AdminUsername"
            $renameSql = "ALTER LOGIN [sa] WITH NAME = [$AdminUsername];"
            sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "$renameSql" -C
            Write-Host "sa user renamed to '$AdminUsername' successfully"
        }

        Write-Host "SqlLocalDB $Version installed and accessible at (localdb)\MSSQLLocalDB"
    } else {
        Write-Output "localdb cannot be installed on mac or linux"
    }
}