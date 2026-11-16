<#
.SYNOPSIS
    Runs one SQL script with sqlcmd variables, outside migration tracking.

.DESCRIPTION
    Used for environment-specific operations such as Deployment/ProvisionAdmin.sql,
    Deployment/GrantRuntimeIdentity.sql and Deployment/CreateDatabase.sql (run that one with -Database master).
    Variables are passed through a generated wrapper (:setvar + script text) so values may contain spaces or be
    empty with both ODBC sqlcmd and go-sqlcmd. Values containing quotes, line breaks or "$(" are rejected.

.EXAMPLE
    # Local default instance, Windows authentication (defaults: -Server localhost -Database SBMRAS -AuthArgs '-E','-C')
    ./Invoke-SqlScript.ps1 -Path ../../SBMRAS.Infrastructure/SQL/Deployment/ProvisionAdmin.sql `
        -Variables @{ AdminEmail = 'jane.doe@contoso.com'; AdminDisplayName = 'Jane Doe' }

.EXAMPLE
    ./Invoke-SqlScript.ps1 -Database master -Path ../../SBMRAS.Infrastructure/SQL/Deployment/CreateDatabase.sql
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [hashtable] $Variables = @{},

    # SQL authentication or Integrated Security connection string (Server, Initial Catalog, ...).
    [string] $ConnectionString,

    [string] $Server = 'localhost',

    [string] $Database = 'SBMRAS',

    [string[]] $AuthArgs = @('-E', '-C'),

    [string] $SqlCmd = 'sqlcmd',

    # ODBC sqlcmd needs -f 65001 for UTF-8 scripts. go-sqlcmd reads UTF-8 natively and has no -f; pass @() for it.
    [string[]] $CodePageArgs = @('-f', '65001')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SqlCmd.Common.ps1')

if ($ConnectionString) {
    $target = New-SqlCmdTarget -ConnectionString $ConnectionString
}
else {
    $target = New-SqlCmdTarget -Server $Server -Database $Database -AuthArgs $AuthArgs
}
$scriptPath = (Resolve-Path $Path).Path

$lines = New-Object System.Collections.Generic.List[string]
foreach ($key in ($Variables.Keys | Sort-Object)) {
    $value = [string]$Variables[$key]
    if ($key -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw "Invalid sqlcmd variable name '$key'."
    }
    if ($value -match "[`"'\r\n]" -or $value.Contains('$(')) {
        throw "Value of '$key' contains a quote, line break or '`$('."
    }
    $lines.Add(":setvar $key `"$value`"")
}
# Inline the script after the :setvar lines; go-sqlcmd does not accept a quoted :r path.
$lines.Add('GO')
$lines.Add([IO.File]::ReadAllText($scriptPath))

$wrapper = New-SqlWorkFile -Sql (($lines -join "`n") + "`n")
try {
    Write-Host "Running $(Split-Path $scriptPath -Leaf) on $($target.Server) / $($target.Database)"
    Invoke-SqlTool -Target $target -SqlCmd $SqlCmd -CodePageArgs $CodePageArgs -Arguments @('-i', $wrapper)
}
finally {
    Remove-Item -LiteralPath $wrapper -Force -ErrorAction SilentlyContinue
}
