param(
    [Parameter(Mandatory)]
    [string]$ExpectedStatus,
    [Parameter(Mandatory)]
    [string]$UserName,
    [Parameter(Mandatory)]
    [string]$Password
)

$Status = sqlcmd -S localhost -U $UserName -P $Password -Q "SELECT servicename, status_desc FROM sys.dm_server_services WHERE servicename LIKE 'SQL Full-text Filter Daemon Launcher%';" -C | Select-String -Pattern "Running" -Quiet

if ($ExpectedStatus -eq "Running"){
    if ($Status){
        "Full-Text Search is installed and running."
    }
    else{
        throw "Full-Text Search is not running or not installed."
    }
}
else{
    if ($Status){
        throw "Full-Text Search is running but it should not be."
    }
    else{
        "Full-Text Search is not running."
    }
}

exit 0
