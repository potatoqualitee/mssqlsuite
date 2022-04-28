param(
    [Parameter(Mandatory=$true)]
    [string]$ExpectedCollation,
    [Parameter(Mandatory=$true)]
    [string]$UserName,
    [Parameter(Mandatory=$true)]
    [string]$Password
)

$Collation = sqlcmd -S localhost -d tempdb -U $UserName -P $Password -Q "SET NOCOUNT ON;SELECT SERVERPROPERTY('Collation') AS Collation;" -W -h -1

if ($Collation -ne $ExpectedCollation){
    throw "Collation is $Collation.  Expected $ExpectedCollation"
}
else{
    "Collation is $Collation"
}