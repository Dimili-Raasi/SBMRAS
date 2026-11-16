# Shared helpers for Invoke-SqlMigrations.ps1, Invoke-SqlScript.ps1 and scripts/local/*.ps1 (dot-sourced).

Set-StrictMode -Version Latest

function New-SqlCmdTarget {
    <#
        Builds the sqlcmd connection arguments from either a connection string or an explicit
        server/database/auth argument set.
          - SQL authentication (User ID + Password): the password is passed through the SQLCMDPASSWORD
            environment variable, never on the command line.
          - Integrated Security / Trusted_Connection=True: uses -E (Windows authentication).
        TrustServerCertificate=True adds -C.
    #>
    param(
        [string] $ConnectionString,
        [string] $Server,
        [string] $Database,
        [string[]] $AuthArgs = @()
    )

    $password = $null
    if ($ConnectionString) {
        $builder = New-Object System.Data.Common.DbConnectionStringBuilder
        $builder.set_ConnectionString($ConnectionString)

        function Get-Value([string[]] $keys) {
            foreach ($key in $keys) {
                if ($builder.ContainsKey($key) -and "$($builder[$key])".Trim()) { return "$($builder[$key])".Trim() }
            }
            return $null
        }

        $Server = Get-Value @('Server', 'Data Source', 'Address', 'Addr', 'Network Address')
        if (-not $Database) { $Database = Get-Value @('Initial Catalog', 'Database') }
        $user = Get-Value @('User ID', 'UID', 'User', 'UserID')
        $password = Get-Value @('Password', 'PWD')
        $integrated = Get-Value @('Integrated Security', 'Trusted_Connection')
        $trustCert = Get-Value @('TrustServerCertificate', 'Trust Server Certificate')

        if (-not $Server -or -not $Database) {
            throw 'The connection string must contain Server and Initial Catalog (or Database).'
        }
        if ($user -and $password) {
            $AuthArgs = @('-U', $user)
        }
        elseif ($integrated -and @('true', 'yes', 'sspi') -contains $integrated.ToLowerInvariant()) {
            $AuthArgs = @('-E')
        }
        else {
            throw 'The connection string must contain User ID and Password, or Integrated Security/Trusted_Connection=True.'
        }
        if ($trustCert -and @('true', 'yes') -contains $trustCert.ToLowerInvariant()) { $AuthArgs += '-C' }
    }

    if (-not $Server -or -not $Database) {
        throw 'Provide -ConnectionString, or -Server and -Database.'
    }

    return [pscustomobject]@{
        Server   = $Server
        Database = $Database
        AuthArgs = $AuthArgs
        Password = $password
    }
}

function Invoke-SqlTool {
    param(
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] [string] $SqlCmd,
        [string[]] $CodePageArgs = @(),
        [string[]] $Arguments = @(),
        [switch] $PassThru
    )

    $all = @('-S', $Target.Server, '-d', $Target.Database) + $Target.AuthArgs + @('-b', '-I') + $CodePageArgs + $Arguments
    $previousPassword = $env:SQLCMDPASSWORD
    try {
        if ($Target.Password) { $env:SQLCMDPASSWORD = $Target.Password }
        $output = & $SqlCmd @all 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:SQLCMDPASSWORD = $previousPassword
    }

    if ($exitCode -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "sqlcmd failed with exit code $exitCode."
    }

    if ($PassThru) { return $output }
    $output | ForEach-Object { Write-Host "  $_" }
}

function New-SqlWorkFile {
    <#
        Writes generated SQL (UTF-8, no BOM, LF line endings) to scripts/database/.work (git-ignored) and returns the
        path. Callers delete the file when done.
    #>
    param([Parameter(Mandatory = $true)] [string] $Sql)

    $dir = Join-Path $PSScriptRoot '.work'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ("sbmras-sql-{0}.sql" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($file, $Sql.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
    return $file
}

function Initialize-SbmrasDatabase {
    <#
        Creates the database on the target server when it does not exist (connects to master).
        Returns $true when the database was created.
    #>
    param(
        [Parameter(Mandatory = $true)] $Target,
        [string] $SqlCmd = 'sqlcmd',
        [string[]] $CodePageArgs = @()
    )

    if ($Target.Database -notmatch '^[A-Za-z0-9_]+$') { throw "Unsafe database name '$($Target.Database)'." }
    $master = [pscustomobject]@{ Server = $Target.Server; Database = 'master'; AuthArgs = $Target.AuthArgs; Password = $Target.Password }
    $sql = "SET NOCOUNT ON; IF DB_ID(N'$($Target.Database)') IS NULL BEGIN CREATE DATABASE [$($Target.Database)]; SELECT N'created'; END ELSE SELECT N'exists';"
    $rows = Invoke-SqlTool -Target $master -SqlCmd $SqlCmd -CodePageArgs $CodePageArgs -Arguments @('-h', '-1', '-W', '-Q', $sql) -PassThru
    return [bool](@($rows | ForEach-Object { "$_".Trim() }) -contains 'created')
}
