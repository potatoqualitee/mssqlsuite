param(
    [Parameter(Mandatory)]
    [string]$ExpectedCollation,
    [Parameter(Mandatory)]
    [string]$UserName,
    [Parameter(Mandatory)]
    [string]$Password
)

$Collation = sqlcmd -S localhost -d tempdb -U $UserName -P $Password -Q "SET NOCOUNT ON;SELECT SERVERPROPERTY('Collation') AS Collation;" -W -h -1 -C

if ($Collation -ne $ExpectedCollation){
    throw "Collation is $Collation.  Expected $ExpectedCollation"
} else{
    "Collation is $Collation"
}
