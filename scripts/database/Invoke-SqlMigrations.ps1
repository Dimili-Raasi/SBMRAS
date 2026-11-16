<#
.SYNOPSIS
    Applies the SBMRAS SQL scripts with sqlcmd and records them in dbo.SchemaMigrationHistory.

.DESCRIPTION
    Script order:
      1. Numbered scripts in SBMRAS.Infrastructure/SQL in numeric order (01_Tables.sql, 02_Views_Functions.sql, ...,
         12_SeedData.sql, then any later NN_*.sql). 12_SeedData.sql holds the reference data (roles, permissions,
         menu, lookups) and always runs. Numbered scripts whose name contains "DemoData" or "SampleData" run only
         with -IncludeDemoData.
      2. With -IncludeDeployment: SBMRAS.Infrastructure/SQL/Deployment/*.sql (except CreateDatabase.sql, which runs
         against master - use -CreateDatabase instead). These are run every time (not tracked) and receive the
         -Variables hashtable as sqlcmd variables; a script that references a $(Variable) that was not supplied is
         skipped with a warning.

    Modes:
      Plan      Show what would run. Changes nothing except creating the empty history table.
      Baseline  For a database that was migrated by hand: verify that every table, column, procedure,
                function and view defined by the scripts exists, then record the current scripts as
                applied without running them. Fails and records nothing if the schema is incomplete.
      Apply     Run new or changed scripts. When a script runs, every later script runs too, because
                later scripts may depend on objects created by earlier ones. All scripts are idempotent.
                Refuses to run on a populated database without history (run Baseline first, or locally use
                -AllowExistingSchema to re-run the idempotent scripts).
                Never re-runs a numbered script recorded by Baseline: if an edit (or demo data) would
                replay one, Apply stops before running anything. Put changes in a new numbered script.

    Checksums are SHA-256 over the script text with line endings normalised. sqlcmd runs with -b, so
    any SQL error stops the run and the failing script is not recorded. Works with ODBC sqlcmd and go-sqlcmd.

.EXAMPLE
    # Local default instance, Windows authentication (defaults: -Server localhost -Database SBMRAS -AuthArgs '-E','-C')
    ./Invoke-SqlMigrations.ps1 -Mode Apply -CreateDatabase

.EXAMPLE
    # Same, also running the deployment scripts that need variables
    ./Invoke-SqlMigrations.ps1 -Mode Apply -IncludeDeployment -Variables @{ AdminEmail = 'admin@contoso.com'; AdminDisplayName = 'SBMRAS Admin' }

.EXAMPLE
    # Azure SQL with a dedicated SQL migration user (go-sqlcmd reads UTF-8 natively, so no code page)
    ./Invoke-SqlMigrations.ps1 -ConnectionString $env:SQL_MIGRATION_CONNECTION_STRING -CodePageArgs @() -Mode Plan
#>
[CmdletBinding()]
param(
    # SQL authentication or Integrated Security connection string (Server, Initial Catalog, ...).
    [string] $ConnectionString,

    [string] $Server = 'localhost',

    [string] $Database = 'SBMRAS',

    # Authentication arguments passed to sqlcmd when -ConnectionString is not used. Default: Windows auth, trust cert.
    [string[]] $AuthArgs = @('-E', '-C'),

    [ValidateSet('Plan', 'Baseline', 'Apply')]
    [string] $Mode = 'Plan',

    [switch] $IncludeDemoData,

    # Also run Deployment/*.sql (except CreateDatabase.sql) after the numbered scripts. Not tracked.
    [switch] $IncludeDeployment,

    # sqlcmd variables for the deployment scripts, e.g. @{ AdminEmail = 'a@b.com'; AdminDisplayName = 'Admin' }.
    [hashtable] $Variables = @{},

    # Create the database (connecting to master) when it does not exist. Not supported in Baseline mode.
    [switch] $CreateDatabase,

    # Local development only: in Apply mode, re-run the idempotent scripts on a database that already has SBMRAS
    # tables but no migration history (e.g. scripts run by hand), instead of requiring Baseline.
    [switch] $AllowExistingSchema,

    [string] $SqlCmd = 'sqlcmd',

    # ODBC sqlcmd needs -f 65001 for UTF-8 scripts. go-sqlcmd reads UTF-8 natively and has no -f; pass @() for it.
    [string[]] $CodePageArgs = @('-f', '65001'),

    [string] $ScriptRoot = (Join-Path $PSScriptRoot '..\..\SBMRAS.Infrastructure\SQL')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SqlCmd.Common.ps1')

$DemoPattern = '(?i)(DemoData|SampleData)'

if ($ConnectionString) {
    $target = New-SqlCmdTarget -ConnectionString $ConnectionString
}
else {
    $target = New-SqlCmdTarget -Server $Server -Database $Database -AuthArgs $AuthArgs
}

function Invoke-Sql([string[]] $Arguments, [switch] $PassThru) {
    Invoke-SqlTool -Target $target -SqlCmd $SqlCmd -CodePageArgs $CodePageArgs -Arguments $Arguments -PassThru:$PassThru
}

function Invoke-SqlText([string] $Sql, [switch] $PassThru) {
    $file = New-SqlWorkFile -Sql $Sql
    try {
        $extra = if ($PassThru) { @('-h', '-1', '-W', '-i', $file) } else { @('-i', $file) }
        Invoke-Sql -Arguments $extra -PassThru:$PassThru
    }
    finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

function Get-ScriptChecksum([string] $Path) {
    $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
    return -join ($hash | ForEach-Object { $_.ToString('x2') })
}

function Get-ExpectedObjects([string[]] $Paths) {
    $objects = New-Object System.Collections.Generic.List[string]
    $columns = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Paths) {
        $text = [IO.File]::ReadAllText($path)
        foreach ($m in [regex]::Matches($text, '(?im)^\s*CREATE\s+(?:OR\s+ALTER\s+)?(?:TABLE|PROCEDURE|PROC|VIEW|FUNCTION)\s+(?:\[?dbo\]?\.)\[?(\w+)\]?')) {
            $objects.Add("dbo.$($m.Groups[1].Value)")
        }
        foreach ($m in [regex]::Matches($text, "COL_LENGTH\(\s*N?'(dbo\.\w+)'\s*,\s*N?'(\w+)'\s*\)")) {
            $columns.Add("$($m.Groups[1].Value)|$($m.Groups[2].Value)")
        }
    }
    return [pscustomobject]@{
        Objects = @($objects | Sort-Object -Unique)
        Columns = @($columns | Sort-Object -Unique)
    }
}

function Invoke-DeploymentScript([string] $Path) {
    $text = [IO.File]::ReadAllText($Path)
    $needed = @([regex]::Matches($text, '\$\((\w+)\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $missingVars = @($needed | Where-Object { -not $Variables.ContainsKey($_) })
    if ($missingVars.Count -gt 0) {
        return "skipped (needs -Variables $($missingVars -join ', '))"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $needed) {
        $value = [string]$Variables[$key]
        if ($value -match "[`"'\r\n]" -or $value.Contains('$(')) { throw "Value of '$key' contains a quote, line break or '`$('." }
        $lines.Add(":setvar $key `"$value`"")
    }
    $lines.Add('GO')
    $lines.Add($text)
    $file = New-SqlWorkFile -Sql (($lines -join "`n") + "`n")
    try { Invoke-Sql -Arguments @('-i', $file) } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    return 'ran (untracked)'
}

if (-not (Test-Path $ScriptRoot)) { throw "SQL script folder not found: $ScriptRoot" }
$ScriptRoot = (Resolve-Path $ScriptRoot).Path
$numbered = @(Get-ChildItem -Path $ScriptRoot -File -Filter '*.sql' |
    Where-Object { $_.Name -match '^\d{2}_.+\.sql$' } |
    Sort-Object Name |
    ForEach-Object { $_.Name })
if ($numbered.Count -eq 0) { throw "No numbered SQL scripts found in $ScriptRoot." }

$plan = @($numbered | Where-Object { $IncludeDemoData -or ($_ -notmatch $DemoPattern) })
foreach ($name in $plan) {
    if ($name -notmatch '^[A-Za-z0-9_./-]+$') { throw "Unsafe script name: $name" }
}

$deploymentScripts = @()
if ($IncludeDeployment) {
    $deploymentDir = Join-Path $ScriptRoot 'Deployment'
    if (Test-Path $deploymentDir) {
        $deploymentScripts = @(Get-ChildItem -Path $deploymentDir -File -Filter '*.sql' |
            Where-Object { $_.Name -ne 'CreateDatabase.sql' } | Sort-Object Name)
    }
    else {
        Write-Warning "No Deployment folder in $ScriptRoot."
    }
}

Write-Host "Target: $($target.Server) / $($target.Database)  Mode: $Mode  Demo data: $([bool]$IncludeDemoData)  Deployment scripts: $([bool]$IncludeDeployment)"

if ($CreateDatabase) {
    if ($Mode -eq 'Baseline') { throw '-CreateDatabase cannot be combined with Baseline.' }
    if (Initialize-SbmrasDatabase -Target $target -SqlCmd $SqlCmd -CodePageArgs $CodePageArgs) {
        Write-Host "Created database $($target.Database)."
    }
}

Invoke-SqlText @'
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.SchemaMigrationHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SchemaMigrationHistory
    (
        ScriptName     NVARCHAR(260) NOT NULL CONSTRAINT PK_SchemaMigrationHistory PRIMARY KEY,
        Checksum       CHAR(64)      NOT NULL,
        AppliedAtUtc   DATETIME2(3)  NOT NULL CONSTRAINT DF_SchemaMigrationHistory_AppliedAtUtc DEFAULT (SYSUTCDATETIME()),
        AppliedBy      NVARCHAR(256) NOT NULL CONSTRAINT DF_SchemaMigrationHistory_AppliedBy DEFAULT (SUSER_SNAME()),
        ExecutionCount INT           NOT NULL CONSTRAINT DF_SchemaMigrationHistory_ExecutionCount DEFAULT (1),
        IsBaseline     BIT           NOT NULL CONSTRAINT DF_SchemaMigrationHistory_IsBaseline DEFAULT (0)
    );
END
'@

$applied = @{}
$rows = Invoke-SqlText -PassThru @'
SET NOCOUNT ON;
SELECT ScriptName + N'|' + Checksum + N'|' + CASE WHEN IsBaseline = 1 THEN N'1' ELSE N'0' END FROM dbo.SchemaMigrationHistory;
SELECT N'#users|' + CASE WHEN OBJECT_ID(N'dbo.Users', N'U') IS NULL THEN N'0' ELSE N'1' END;
'@
$schemaExists = $false
$baselined = @{}
foreach ($row in $rows) {
    $line = "$row".Trim()
    if ($line -eq '#users|1') { $schemaExists = $true }
    elseif ($line -match '^(?<name>[^|#][^|]*)\|(?<sum>[0-9a-f]{64})\|(?<base>[01])$') {
        $applied[$Matches.name] = $Matches.sum
        if ($Matches.base -eq '1') { $baselined[$Matches.name] = $true }
    }
}

$results = New-Object System.Collections.Generic.List[object]

if ($Mode -eq 'Baseline') {
    if ($applied.Count -gt 0) {
        throw "dbo.SchemaMigrationHistory already has $($applied.Count) entries. Baseline is only for databases without history."
    }

    $schemaScripts = @($plan | ForEach-Object { Join-Path $ScriptRoot $_ })
    $expected = Get-ExpectedObjects -Paths $schemaScripts
    $values = @($expected.Objects | ForEach-Object { "(N'$_', NULL)" }) + @($expected.Columns | ForEach-Object {
            $parts = $_.Split('|'); "(N'$($parts[0])', N'$($parts[1])')" })
    if ($values.Count -eq 0) { throw 'No CREATE statements were found in the scripts; nothing to verify.' }
    $missing = Invoke-SqlText -PassThru @"
SET NOCOUNT ON;
SELECT N'missing|' + v.ObjectName + ISNULL(N'.' + v.ColumnName, N'')
FROM (VALUES
$($values -join ",`n")
) v (ObjectName, ColumnName)
WHERE (v.ColumnName IS NULL AND OBJECT_ID(v.ObjectName) IS NULL)
   OR (v.ColumnName IS NOT NULL AND COL_LENGTH(v.ObjectName, v.ColumnName) IS NULL);
SELECT N'roles|' + CAST(COUNT(*) AS NVARCHAR(10)) FROM dbo.Roles;
"@
    $missingNames = @($missing | ForEach-Object { "$_".Trim() } | Where-Object { $_ -like 'missing|*' } | ForEach-Object { $_.Substring(8) })
    $roleCount = 0
    $missing | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^roles\|(\d+)$' } | ForEach-Object { $roleCount = [int]$Matches[1] }

    Write-Host "Baseline check: $($expected.Objects.Count) objects and $($expected.Columns.Count) columns expected; $($missingNames.Count) missing."
    Write-Host "Reference data: $roleCount roles."
    if ($missingNames.Count -gt 0) {
        $missingNames | ForEach-Object { Write-Host "  missing: $_" }
        throw 'The database does not match the scripts. Nothing was recorded. Fix the schema or use Apply.'
    }
    if ($roleCount -lt 4) {
        throw "Expected the 4 SBMRAS roles (PublicUser, HospitalManagement, BloodBank, Admin); found $roleCount. Nothing was recorded."
    }

    $merge = foreach ($name in $plan) {
        $checksum = Get-ScriptChecksum (Join-Path $ScriptRoot $name)
        $results.Add([pscustomobject]@{ Script = $name; Action = 'recorded as baseline' })
        "INSERT INTO dbo.SchemaMigrationHistory (ScriptName, Checksum, IsBaseline) VALUES (N'$name', '$checksum', 1);"
    }
    Invoke-SqlText ("SET NOCOUNT ON;`nSET XACT_ABORT ON;`nBEGIN TRANSACTION;`n" + ($merge -join "`n") + "`nCOMMIT TRANSACTION;")
}
else {
    if ($Mode -eq 'Apply' -and $applied.Count -eq 0 -and $schemaExists) {
        if (-not $AllowExistingSchema) {
            throw 'The database already has SBMRAS tables but no migration history. Run with -Mode Baseline first (or, for a local database, -AllowExistingSchema to re-run the idempotent scripts).'
        }
        Write-Warning 'Existing SBMRAS schema without migration history: re-running every (idempotent) script and recording it (-AllowExistingSchema).'
    }
    if ($Mode -eq 'Plan' -and $applied.Count -eq 0 -and $schemaExists) {
        Write-Warning 'The database already has SBMRAS tables but no migration history. Run Baseline before Apply.'
        if ($env:GITHUB_ACTIONS) { Write-Host '::warning::Existing schema without migration history. Run mode "baseline" before "apply".' }
    }

    # Decide everything first so a blocked plan changes nothing.
    $steps = New-Object System.Collections.Generic.List[object]
    $reapplyRest = $false
    foreach ($name in $plan) {
        $checksum = Get-ScriptChecksum (Join-Path $ScriptRoot $name)
        $reason = $null
        if (-not $applied.ContainsKey($name)) { $reason = 'new' }
        elseif ($applied[$name] -ne $checksum) { $reason = 'changed' }
        elseif ($reapplyRest) { $reason = 'after earlier change' }
        if ($reason) { $reapplyRest = $true }
        # Scripts recorded by Baseline describe a schema that was built by hand; never replay them.
        $blocked = [bool]$reason -and $baselined.ContainsKey($name)
        $steps.Add([pscustomobject]@{ Name = $name; Checksum = $checksum; Reason = $reason; Blocked = $blocked })
    }

    $blockedSteps = @($steps | Where-Object Blocked)
    if ($blockedSteps.Count -gt 0) {
        $message = "These baseline scripts would be re-run: $(($blockedSteps | ForEach-Object { "$($_.Name) ($($_.Reason))" }) -join ', '). " +
        'Baseline scripts are never replayed. Revert the edits and put the change in a new numbered script (e.g. 13_...sql). ' +
        'Demo data cannot be added to a baselined database.'
        if ($Mode -eq 'Apply') {
            $steps | ForEach-Object { $results.Add([pscustomobject]@{ Script = $_.Name; Action = if ($_.Blocked) { "BLOCKED ($($_.Reason))" } elseif ($_.Reason) { "not run ($($_.Reason))" } else { 'skipped (unchanged)' } }) }
            $results | Format-Table -AutoSize | Out-String | Write-Host
            throw $message
        }
        Write-Warning $message
        if ($env:GITHUB_ACTIONS) { Write-Host "::warning::$message" }
    }

    foreach ($step in $steps) {
        $name = $step.Name
        $path = Join-Path $ScriptRoot $name
        $checksum = $step.Checksum
        $reason = $step.Reason

        if (-not $reason) {
            $results.Add([pscustomobject]@{ Script = $name; Action = 'skipped (unchanged)' })
            continue
        }

        if ($Mode -eq 'Plan') {
            $results.Add([pscustomobject]@{ Script = $name; Action = if ($step.Blocked) { "BLOCKED ($reason)" } else { "would apply ($reason)" } })
            continue
        }

        Write-Host "Applying $name ($reason)..."
        Invoke-Sql -Arguments @('-i', $path)
        Invoke-SqlText @"
SET NOCOUNT ON;
MERGE dbo.SchemaMigrationHistory AS t
USING (SELECT N'$name' AS ScriptName, '$checksum' AS Checksum) AS s
ON t.ScriptName = s.ScriptName
WHEN MATCHED THEN UPDATE SET Checksum = s.Checksum, AppliedAtUtc = SYSUTCDATETIME(), AppliedBy = SUSER_SNAME(), ExecutionCount = t.ExecutionCount + 1, IsBaseline = 0
WHEN NOT MATCHED THEN INSERT (ScriptName, Checksum) VALUES (s.ScriptName, s.Checksum);
"@
        $results.Add([pscustomobject]@{ Script = $name; Action = "applied ($reason)" })
    }

    foreach ($script in $deploymentScripts) {
        $display = "Deployment/$($script.Name)"
        if ($Mode -eq 'Plan') {
            $results.Add([pscustomobject]@{ Script = $display; Action = 'would run (untracked)' })
            continue
        }
        Write-Host "Running $display..."
        $results.Add([pscustomobject]@{ Script = $display; Action = (Invoke-DeploymentScript -Path $script.FullName) })
    }
}

$results | Format-Table -AutoSize | Out-String | Write-Host

if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @("### Database migrations: $Mode ($($target.Database))", '', "Demo data: $([bool]$IncludeDemoData)", '', '| Script | Action |', '|---|---|')
    $lines += $results | ForEach-Object { "| ``$($_.Script)`` | $($_.Action) |" }
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $lines -Encoding utf8
}
