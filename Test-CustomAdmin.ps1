param(
    [Parameter(Mandatory=$true)]
    [string]$AdminUsername,
    [Parameter(Mandatory=$true)]
    [string]$Password
)

# Attempt to connect and check if the user is a sysadmin
$IsSysadmin = sqlcmd -S localhost -d master -U $AdminUsername -P $Password -Q "SET NOCOUNT ON;SELECT IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin;" -W -h -1 -C

if ($IsSysadmin -ne "1") {
    throw "User $AdminUsername is NOT a sysadmin or cannot connect."
} else {
    "User $AdminUsername is a sysadmin."
}