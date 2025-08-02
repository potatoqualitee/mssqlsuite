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

            # Create SSISDB catalog using SMO
            Write-Output "Creating SSISDB catalog using SMO..."
            try {
                # Load SMO functions
                function Load-SSISAssemblies {
                    Write-Output "Loading SMO assemblies..."

                    # Strategy 1: Try Add-Type with assembly names (most reliable for CI/CD)
                    try {
                        Write-Output "Trying Add-Type with assembly names..."
                        Add-Type -AssemblyName "Microsoft.SqlServer.Management.Sdk.Sfc" -ErrorAction Stop
                        Add-Type -AssemblyName "Microsoft.SqlServer.Management.Common" -ErrorAction Stop
                        Add-Type -AssemblyName "Microsoft.SqlServer.Smo" -ErrorAction Stop
                        Add-Type -AssemblyName "Microsoft.SqlServer.Management.IntegrationServices" -ErrorAction Stop

                        # Test if the type is available
                        $testType = [Microsoft.SqlServer.Management.Common.ServerConnection]
                        Write-Output "Assembly loading verified - ServerConnection type found"
                        return $true
                    }
                    catch {
                        Write-Warning "Add-Type assembly loading failed: $_"
                    }

                    # Strategy 2: Try LoadWithPartialName (GAC)
                    try {
                        Write-Output "Trying GAC loading with LoadWithPartialName..."
                        $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc")
                        $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Common")
                        $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
                        $null = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices")

                        # Test if the type is available
                        $testType = [Microsoft.SqlServer.Management.Common.ServerConnection]
                        Write-Output "GAC loading successful and verified"
                        return $true
                    }
                    catch {
                        Write-Warning "GAC loading failed: $_"
                    }

                    # Strategy 3: Dynamic recursive search for assemblies
                    try {
                        Write-Output "Searching for SMO assemblies recursively..."

                        # Search common SQL Server installation directories
                        $searchPaths = @(
                            "C:\Program Files\Microsoft SQL Server",
                            "C:\Program Files (x86)\Microsoft SQL Server",
                            "C:\Program Files\Common Files\Microsoft Shared",
                            "C:\Program Files (x86)\Common Files\Microsoft Shared"
                        )

                        foreach ($searchPath in $searchPaths) {
                            if (Test-Path $searchPath) {
                                Write-Output "Searching in: $searchPath"

                                # Find the IntegrationServices assembly first
                                $integrationServicesAssembly = Get-ChildItem -Path $searchPath -Recurse -Filter "Microsoft.SqlServer.Management.IntegrationServices.dll" -ErrorAction SilentlyContinue | Select-Object -First 1

                                if ($integrationServicesAssembly) {
                                    $basePath = $integrationServicesAssembly.DirectoryName
                                    Write-Output "Found SMO assemblies in: $basePath"

                                    # Check if all required assemblies exist in the same directory
                                    $requiredAssemblies = @(
                                        "Microsoft.SqlServer.Management.Sdk.Sfc.dll",
                                        "Microsoft.SqlServer.Management.Common.dll",
                                        "Microsoft.SqlServer.Smo.dll",
                                        "Microsoft.SqlServer.Management.IntegrationServices.dll"
                                    )

                                    $allAssembliesFound = $true
                                    foreach ($assembly in $requiredAssemblies) {
                                        if (-not (Test-Path "$basePath\$assembly")) {
                                            Write-Warning "Missing assembly: $basePath\$assembly"
                                            $allAssembliesFound = $false
                                        }
                                    }

                                    if ($allAssembliesFound) {
                                        Write-Output "Loading assemblies from: $basePath"

                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Management.Sdk.Sfc.dll" -ErrorAction Stop
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Management.Common.dll" -ErrorAction Stop
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Smo.dll" -ErrorAction Stop
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Management.IntegrationServices.dll" -ErrorAction Stop

                                        # Test if the type is available
                                        $testType = [Microsoft.SqlServer.Management.Common.ServerConnection]
                                        Write-Output "Dynamic search successful! Assemblies loaded from: $basePath"
                                        return $true
                                    }
                                }
                            }
                        }

                        # If not found in common locations, search entire Program Files
                        Write-Output "Searching entire Program Files directories..."
                        $programFilesPaths = @("C:\Program Files", "C:\Program Files (x86)")

                        foreach ($programPath in $programFilesPaths) {
                            if (Test-Path $programPath) {
                                $integrationServicesAssembly = Get-ChildItem -Path $programPath -Recurse -Filter "Microsoft.SqlServer.Management.IntegrationServices.dll" -ErrorAction SilentlyContinue | Select-Object -First 1

                                if ($integrationServicesAssembly) {
                                    $basePath = $integrationServicesAssembly.DirectoryName
                                    Write-Output "Found assemblies in Program Files at: $basePath"

                                    try {
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Management.Sdk.Sfc.dll" -ErrorAction SilentlyContinue
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Management.Common.dll" -ErrorAction Stop
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Smo.dll" -ErrorAction SilentlyContinue
                                        Add-Type -Path "$basePath\Microsoft.SqlServer.Management.IntegrationServices.dll" -ErrorAction Stop

                                        # Test if the type is available
                                        $testType = [Microsoft.SqlServer.Management.Common.ServerConnection]
                                        Write-Output "Full system search successful! Assemblies loaded from: $basePath"
                                        return $true
                                    }
                                    catch {
                                        Write-Warning "Failed to load from found path: $basePath - $_"
                                        continue
                                    }
                                }
                            }
                        }

                        throw "No SMO assemblies found anywhere on the system"
                    }
                    catch {
                        Write-Warning "Dynamic assembly search failed: $_"
                    }

                    Write-Error "All assembly loading strategies failed. SMO assemblies not available on this system."
                    return $false
                }

                function Get-SqlServerVersion {
                    param(
                        [string]$ServerName = "localhost",
                        [System.Management.Automation.PSCredential]$SqlCredential = $null
                    )

                    try {
                        if ($SqlCredential) {
                            $connectionString = "Server=$ServerName;User Id=$($SqlCredential.UserName);Password=$($SqlCredential.GetNetworkCredential().Password);TrustServerCertificate=True"
                        } else {
                            $connectionString = "Server=$ServerName;Integrated Security=True;TrustServerCertificate=True"
                        }

                        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
                        $connection.Open()

                        $command = $connection.CreateCommand()
                        $command.CommandText = "SELECT SERVERPROPERTY('ProductMajorVersion') AS MajorVersion"
                        $result = $command.ExecuteScalar()

                        $connection.Close()
                        return [int]$result
                    }
                    catch {
                        Write-Warning "Could not detect SQL Server version: $_"
                        return $versionMajor  # Use the version from the main script
                    }
                }

                function New-SSISCatalogUsingSMO {
                    param(
                        [string]$ServerName = "localhost",
                        [string]$CatalogPassword,
                        [System.Management.Automation.PSCredential]$SqlCredential = $null,
                        [int]$SqlVersionMajor = 16
                    )

                    if (-not (Load-SSISAssemblies -SqlVersionMajor $SqlVersionMajor)) {
                        throw "Failed to load SSIS SMO assemblies"
                    }

                    try {
                        $serverConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection($ServerName)

                        if ($SqlCredential) {
                            $serverConnection.LoginSecure = $false
                            $serverConnection.Login = $SqlCredential.UserName
                            $serverConnection.SecurePassword = $SqlCredential.Password
                        } else {
                            $serverConnection.LoginSecure = $true
                        }

                        $smoServer = New-Object Microsoft.SqlServer.Management.Smo.Server($serverConnection)
                        $smoServer.ConnectionContext.Connect()
                        Write-Output "Connected to SQL Server: $($smoServer.Name) (Version: $($smoServer.Version))"

                        $integrationServices = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices($smoServer)

                        if ($integrationServices.Catalogs.Contains("SSISDB")) {
                            Write-Warning "SSISDB catalog already exists"
                            return $true
                        }

                        Write-Output "Creating SSISDB catalog..."

                        if (-not $CatalogPassword) {
                            $CatalogPassword = "dbatools.I0"
                            Write-Warning "No catalog password specified, using default"
                        }

                        $catalog = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog($integrationServices, "SSISDB", $CatalogPassword)
                        $catalog.Create()

                        Write-Output "SSISDB catalog created successfully"
                        return $true
                    }
                    catch {
                        Write-Error "Failed to create SSISDB catalog: $_"
                        return $false
                    }
                    finally {
                        if ($smoServer -and $smoServer.ConnectionContext.IsOpen) {
                            $smoServer.ConnectionContext.Disconnect()
                        }
                    }
                }

                # Detect SQL Server version
                $detectedVersion = Get-SqlServerVersion -ServerName "localhost"
                Write-Output "Detected SQL Server version: $detectedVersion"

                # Create credentials if needed
                $sqlCredential = $null
                if ($SaPassword) {
                    $securePassword = ConvertTo-SecureString $SaPassword -AsPlainText -Force
                    $sqlCredential = New-Object System.Management.Automation.PSCredential($AdminUsername, $securePassword)
                }

                # Create SSISDB catalog using SMO
                $success = New-SSISCatalogUsingSMO -ServerName "localhost" -CatalogPassword $SaPassword -SqlCredential $sqlCredential -SqlVersionMajor $detectedVersion

                if (-not $success) {
                    throw "SSISDB catalog creation failed"
                }

                Write-Output "SSISDB catalog creation completed successfully."
            } catch {
                Write-Error "Failed to create SSISDB catalog: $_"
            }
        }
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