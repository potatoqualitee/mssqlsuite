param (
    [ValidateSet("sqlclient", "sqlpackage", "sqlengine", "localdb", "fulltext", "ssis")]
    [string[]]$Install,
    [string]$SaPassword = "dbatools.I0",
    [string]$AdminUsername = "sa",
    [switch]$ShowLog,
    [string]$Collation = "SQL_Latin1_General_CP1_CI_AS",
    [ValidateSet("2025", "2022", "2019", "2017", "2016")]
    [string]$Version = "2022"
)
if (-not $isLinux -and -not $Ismacos -and -not $IsWindows) {
    # its powershell
    $isWindows = $true
}
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
    # Download go-sqlcmd directly from GitHub releases to avoid Homebrew timeout issues
    # Use arm64 for Apple Silicon (GitHub Actions macOS runners use ARM64)
    $sqlcmdVersion = "v1.8.2"
    $sqlcmdUrl = "https://github.com/microsoft/go-sqlcmd/releases/download/$sqlcmdVersion/sqlcmd-darwin-arm64.tar.bz2"

    Write-Output "Downloading sqlcmd $sqlcmdVersion from GitHub releases..."
    curl -L $sqlcmdUrl -o /tmp/sqlcmd.tar.bz2

    Write-Output "Extracting sqlcmd..."
    tar -xjf /tmp/sqlcmd.tar.bz2 -C /tmp

    Write-Output "Installing sqlcmd to /usr/local/bin..."
    sudo mv /tmp/sqlcmd /usr/local/bin/sqlcmd
    sudo chmod +x /usr/local/bin/sqlcmd

    Write-Output "Verifying sqlcmd installation..."
    sqlcmd --version
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
        Write-Output "Waiting for SQL Server to start..."

        # Try to connect to SQL Server in a loop instead of fixed sleep
        # This allows faster success or additional time if needed (especially on macOS with qemu)
        $TryLimit = 18 # At least 3 minute maximum wait with 10 second delay between retries
        for ($i = 1; $i -le $TryLimit; $i++) {
            try {
                Write-Output "Testing connection to SQL Server (Try $i of $TryLimit)"
                $ErrorOut = sqlcmd -S localhost -U sa -P "$SaPassword" -Q "SELECT @@VERSION" -C -l 15 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "sqlcmd failed with exit code $LASTEXITCODE"
                }
                Write-Output "Connection to SQL Server succeeded"
                break
            } catch {
                if ($i -eq $TryLimit) {
                    # We are done trying, display the suppressed error
                    Write-Error "Timeout waiting for SQL Server to become available - $ErrorOut"
                } else {
                    Start-Sleep -Seconds 10
                }
            }
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
            "2025" {
                $exeUri = "https://go.microsoft.com/fwlink/?linkid=2342429&clcid=0x409&culture=en-us&country=us"
                $boxUri = ""
                $versionMajor = 17
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
            # For 2016, 2017 & 2025.
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
            Write-Output "Installing SSIS and setting up SSISDB catalog..."

            # Detect the default or previously installed SQL Server instance
            $instanceName = "MSSQLSERVER"
            try {
                $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
                if (Test-Path $regPath) {
                    $instances = Get-ItemProperty -Path $regPath | Select-Object -ExpandProperty PSObject.Properties | ForEach-Object { $_.Name }
                    if ($instances.Count -gt 0) {
                        $instanceName = $instances[0]
                        Write-Output "Detected SQL Server instance: $instanceName"
                    }
                }
            } catch {
                Write-Output "Using default instance: MSSQLSERVER"
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

            # Extract media if not already done
            if (-not (Test-Path "setup\setup.exe")) {
                Start-Process -Wait -FilePath ./sqlsetup.exe -ArgumentList /qs, /x:setup
            }

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
            Write-Output "Installing SSIS features..."
            Start-Process -FilePath ".\setup\setup.exe" -ArgumentList $ssisArgs -Wait -NoNewWindow

            Start-Sleep -Seconds 10 # Wait for services

            # Enable CLR integration (required for SSISDB catalog)
            Write-Output "Enabling CLR integration for SSISDB..."
            sqlcmd -S localhost -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;" -C
            sqlcmd -S localhost -Q "EXEC sp_configure 'clr enabled', 1; RECONFIGURE;" -C

            # Start Integration Services
            Write-Output "Starting Integration Services..."
            $ssisServices = Get-Service -Name "*DTS*" -ErrorAction SilentlyContinue
            if ($ssisServices) {
                foreach ($service in $ssisServices) {
                    if ($service.Status -eq "Stopped") {
                        try {
                            Start-Service $service.Name -ErrorAction SilentlyContinue
                            Write-Output "Started service: $($service.Name)"
                        } catch {
                            Write-Warning "Failed to start service: $($service.Name)"
                        }
                    }
                }
            }

            # Create SSISDB catalog using direct T-SQL execution
            Write-Output "Creating SSISDB catalog using T-SQL..."

            try {
                # Set catalog password - use provided SaPassword or default
                $catalogPassword = if ($SaPassword) { $SaPassword } else { "dbatools.I0" }

                # Detect SQL Server version for choosing assembly registration method
                Write-Output "Detecting SQL Server version..."
                $sqlVersion = sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "SELECT SERVERPROPERTY('ProductMajorVersion')" -h -1 -C
                $majorVersion = [int]($sqlVersion | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()
                Write-Output "Detected SQL Server major version: $majorVersion"

                # Find Microsoft.SqlServer.IntegrationServices.Server.dll dynamically
                Write-Output "Finding Integration Services DLL..."
                $sqlServerPaths = @(
                    "C:\Program Files\Microsoft SQL Server",
                    "C:\Program Files (x86)\Microsoft SQL Server"
                )

                $integrationServicesDll = $null
                foreach ($basePath in $sqlServerPaths) {
                    if (Test-Path $basePath) {
                        $foundDlls = Get-ChildItem -Path $basePath -Recurse -Filter "Microsoft.SqlServer.IntegrationServices.Server.dll" -ErrorAction SilentlyContinue
                        if ($foundDlls) {
                            # Prefer the highest version number in the path
                            $integrationServicesDll = ($foundDlls | Sort-Object FullName -Descending | Select-Object -First 1).FullName
                            break
                        }
                    }
                }

                if (-not $integrationServicesDll) {
                    throw "Could not find Microsoft.SqlServer.IntegrationServices.Server.dll"
                }
                Write-Output "Found Integration Services DLL at: $integrationServicesDll"

                # Find SSISDBBackup.bak dynamically
                Write-Output "Finding SSISDB backup file..."
                $ssisdbBackup = $null
                foreach ($basePath in $sqlServerPaths) {
                    if (Test-Path $basePath) {
                        $foundBackups = Get-ChildItem -Path $basePath -Recurse -Filter "SSISDBBackup.bak" -ErrorAction SilentlyContinue
                        if ($foundBackups) {
                            # Prefer the backup file that matches the current version
                            $versionSpecificBackup = $foundBackups | Where-Object { $_.FullName -like "*$versionMajor*" } | Select-Object -First 1
                            if ($versionSpecificBackup) {
                                $ssisdbBackup = $versionSpecificBackup.FullName
                            } else {
                                # Fall back to any backup file found
                                $ssisdbBackup = ($foundBackups | Sort-Object FullName -Descending | Select-Object -First 1).FullName
                            }
                            break
                        }
                    }
                }

                if (-not $ssisdbBackup) {
                    throw "Could not find SSISDBBackup.bak file. Please ensure the backup file is available in the SQL Server installation directories."
                }
                Write-Output "Found SSISDB backup at: $ssisdbBackup"

                # Restore SSISDB from backup
                Write-Output "Restoring SSISDB from backup..."

                # Get the default data directory where master database is located
                Write-Output "Getting SQL Server default data directory..."
                $dataDir = sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "SELECT LEFT(physical_name, LEN(physical_name) - LEN('master.mdf')) FROM sys.master_files WHERE database_id = 1 AND type = 0" -h -1 -C
                $dataDirectory = ($dataDir | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()
                Write-Output "Using data directory: $dataDirectory"

                $dataFilePath = Join-Path $dataDirectory "SSISDB.mdf"
                $logFilePath = Join-Path $dataDirectory "SSISDB.ldf"

                $restoreSql = @"
RESTORE DATABASE [SSISDB] FROM DISK = N'$ssisdbBackup'
WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 5,
MOVE 'data' TO N'$dataFilePath',
MOVE 'log' TO N'$logFilePath';
"@
                sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$restoreSql" -C

                # Update or create database master key password to match catalog password
                Write-Output "Updating database master key password..."
                $updateMasterKeySql = @"
USE [SSISDB];
-- Check if master key exists and create/regenerate as needed
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$catalogPassword';
    PRINT 'Database master key created successfully.';
END
ELSE
BEGIN
    -- Try to regenerate the master key with the new password
    BEGIN TRY
        ALTER MASTER KEY REGENERATE WITH ENCRYPTION BY PASSWORD = '$catalogPassword';
        PRINT 'Database master key regenerated successfully.';
    END TRY
    BEGIN CATCH
        -- If regeneration fails, try to open and regenerate
        BEGIN TRY
            OPEN MASTER KEY DECRYPTION BY PASSWORD = '$catalogPassword';
            ALTER MASTER KEY REGENERATE WITH ENCRYPTION BY PASSWORD = '$catalogPassword';
            CLOSE MASTER KEY;
            PRINT 'Database master key opened and regenerated successfully.';
        END TRY
        BEGIN CATCH
            PRINT 'Warning: Could not regenerate master key. Continuing with existing key.';
        END CATCH
    END CATCH
END
"@
                sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$updateMasterKeySql" -C

                # Register assembly based on SQL Server version (needed for SSISDB functionality)
                if ($majorVersion -ge 14) {
                    # SQL Server 2017+ - Use trusted assemblies
                    Write-Output "Registering assembly using trusted assemblies method (SQL Server 2017+)..."
                    $trustedAssemblySql = @"
USE [SSISDB];
DECLARE @asm_bin VARBINARY(max);
DECLARE @isServerHashCode VARBINARY(64);
SELECT @asm_bin = BulkColumn FROM OPENROWSET (BULK '$integrationServicesDll', SINGLE_BLOB) AS dll;
SELECT @isServerHashCode = HASHBYTES('SHA2_512', @asm_bin);
IF NOT EXISTS(SELECT * FROM sys.trusted_assemblies WHERE hash = @isServerHashCode)
    EXEC sys.sp_add_trusted_assembly @isServerHashCode, N'$integrationServicesDll';
"@
                    sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$trustedAssemblySql" -C
                } else {
                    # SQL Server 2016 - Use asymmetric key
                    Write-Output "Registering assembly using asymmetric key method (SQL Server 2016)..."

                    # First, create the asymmetric key in SSISDB database
                    $createKeySql = @"
USE [SSISDB];
CREATE ASYMMETRIC KEY MS_SQLEnableSystemAssemblyLoadingKey FROM EXECUTABLE FILE = '$integrationServicesDll';
"@
                    sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$createKeySql" -C

                    # Then, create login and grant permissions in master database context
                    $grantPermissionsSql = @"
USE [master];
CREATE LOGIN ##MS_SQLEnableSystemAssemblyLoadingUser## FROM ASYMMETRIC KEY [SSISDB].[dbo].[MS_SQLEnableSystemAssemblyLoadingKey];
GRANT UNSAFE ASSEMBLY TO ##MS_SQLEnableSystemAssemblyLoadingUser##;
"@
                    sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$grantPermissionsSql" -C
                }

                # Create startup procedure
                Write-Output "Creating startup procedure..."

                # First batch: Drop existing procedure if it exists
                $dropProcSql = @"
USE master;
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'sp_ssis_startup')
    DROP PROCEDURE [dbo].[sp_ssis_startup];
"@
                sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$dropProcSql" -C

                # Second batch: Create the procedure (must be in its own batch)
                $createProcSql = @"
CREATE PROCEDURE [dbo].[sp_ssis_startup]
AS
SET NOCOUNT ON
    IF DB_ID('SSISDB') IS NULL
        RETURN
    IF NOT EXISTS(SELECT name FROM [SSISDB].sys.procedures WHERE name = N'startup')
        RETURN
    DECLARE @script nvarchar(500)
    SET @script = N'EXEC [SSISDB].[catalog].[startup]'
    EXECUTE sp_executesql @script;
"@
                sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -d master -Q "$createProcSql" -C

                # Third batch: Enable the startup procedure
                $enableStartupSql = @"
USE master;
EXEC sp_procoption N'sp_ssis_startup', 'startup', 'on';
"@
                sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$enableStartupSql" -C

                # Setup maintenance job for SSIS catalog cleanup
                Write-Output "Setting up SSIS maintenance job..."

                # Start SQL Server Agent if it's not running
                try {
                    $agentService = Get-Service -Name "SQLSERVERAGENT" -ErrorAction SilentlyContinue
                    if ($agentService -and $agentService.Status -eq "Stopped") {
                        Write-Output "Starting SQL Server Agent service..."
                        Start-Service -Name "SQLSERVERAGENT" -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 5
                    }
                } catch {
                    Write-Warning "Could not start SQL Server Agent service: $_"
                }

                $maintenanceJobSql = @"
USE msdb;

-- Create the maintenance job
IF NOT EXISTS (SELECT job_id FROM dbo.sysjobs WHERE name = N'SSIS Server Maintenance Job')
BEGIN
    EXEC dbo.sp_add_job
        @job_name = N'SSIS Server Maintenance Job',
        @enabled = 1,
        @description = N'Maintenance job for SSIS catalog cleanup operations';

    EXEC dbo.sp_add_jobstep
        @job_name = N'SSIS Server Maintenance Job',
        @step_name = N'SSIS Server Operation Records Cleanup',
        @command = N'EXEC [SSISDB].[catalog].[cleanup_server_log] @SERVER_LOG_DAYS=30',
        @database_name = N'SSISDB';

    EXEC dbo.sp_add_schedule
        @schedule_name = N'SSIS Server Maintenance Schedule',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 1,
        @active_start_time = 0;

    EXEC dbo.sp_attach_schedule
        @job_name = N'SSIS Server Maintenance Job',
        @schedule_name = N'SSIS Server Maintenance Schedule';

    EXEC dbo.sp_add_jobserver
        @job_name = N'SSIS Server Maintenance Job';
END
"@
                sqlcmd -S localhost -U $AdminUsername -P "$SaPassword" -Q "$maintenanceJobSql" -C

                Write-Output "SSISDB catalog created successfully using T-SQL"
            } catch {
                $PSItem | Select-Object -Property * | Write-Warning
                Write-Error "Failed to create SSISDB catalog with T-SQL: $_"
                throw
            }

            Write-Output "SSISDB catalog creation completed successfully."
        }
    }
}

if ("sqlclient" -in $Install) {
    Write-Output "Installing sqlclient tools"
    $log = ""

    if ($ismacos) {
        Write-Output "Installing ODBC-based mssql-tools18 on macOS"
        Write-Output "Note: go-sqlcmd is already available from initial installation"

        # Microsoft only distributes ODBC tools via Homebrew for macOS
        # Use optimized settings to avoid timeouts
        try {
            Write-Output "Tapping microsoft/mssql-release..."
            bash -c "brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release"

            Write-Output "Installing ODBC driver and tools (this may take a few minutes)..."
            # Install without auto-update (already set via HOMEBREW_NO_AUTO_UPDATE env var)
            bash -c "brew install --quiet microsoft/mssql-release/msodbcsql18 microsoft/mssql-release/mssql-tools18"

            Write-Output "Adding mssql-tools18 to PATH..."
            echo "/opt/mssql-tools18/bin" >> $env:GITHUB_PATH

            Write-Output "mssql-tools18 installation completed"
        } catch {
            Write-Warning "Failed to install mssql-tools18 via Homebrew: $_"
            Write-Warning "go-sqlcmd is still available as the sqlcmd implementation"
        }
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
        # If we don't hace a uriMSI for the version, display a warning and use 2022
        if ($null -eq $uriMSI) {
            Write-Warning "SqlLocalDB is not available yet in this action for version $Version.  Using version 2022 instead."
            $uriMSI = "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SqlLocalDB.msi"
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