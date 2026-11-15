using System.Collections.Concurrent;
using System.Data;
using System.Text.RegularExpressions;
using Dapper;
using Microsoft.Data.SqlClient;
using SBMRAS.Application.Common;

namespace SBMRAS.Infrastructure.Database;

/// <summary>Executes only stored procedures declared in the shipped SQL scripts.</summary>
public sealed class StoredProcedureExecutor(ISqlDbConnectionFactory connectionFactory) : IStoredProcedureExecutor
{
    private static readonly ConcurrentDictionary<string, IReadOnlySet<string>> ProcedureParameters =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly Regex ProcedureHeader = new(
        @"(?ims)^\s*CREATE\s+OR\s+ALTER\s+PROCEDURE\s+(?:\[?dbo\]?\.)?\[?(?<name>[A-Za-z_]\w*)\]?(?<parameters>.*?)(?=^\s*AS\b)",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex ParameterName = new(
        @"(?m)(?:^|,)\s*@(?<name>[A-Za-z_]\w*)\s+(?=[A-Za-z\[])",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public async Task<object?> InvokeAsync(string procedure, int actorUserId, IReadOnlyDictionary<string, object?> arguments,
        ResultShape shape, int page = 1, int pageSize = 20, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(procedure) || !procedure.StartsWith("usp_", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Only a declared SBMRAS stored procedure may be executed.", nameof(procedure));

        var declared = GetDeclaredParameters(procedure);
        var parameters = new DynamicParameters();
        BindIfDeclared(parameters, declared, "ActorUserId", actorUserId);
        BindIfDeclared(parameters, declared, "Page", page);
        BindIfDeclared(parameters, declared, "PageSize", pageSize);
        foreach (var (name, value) in arguments)
            BindIfDeclared(parameters, declared, name, value);

        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        using var grid = await connection.QueryMultipleAsync(new CommandDefinition(
            $"dbo.{procedure}", parameters, commandType: CommandType.StoredProcedure, cancellationToken: cancellationToken));

        return shape switch
        {
            ResultShape.Single or ResultShape.Execute => await ReadFirstAsync(grid),
            ResultShape.List => await ReadRowsAsync(grid),
            ResultShape.Paged => await ReadPagedAsync(grid, page, pageSize),
            ResultShape.Multiple => await ReadSetsAsync(grid),
            _ => throw new ArgumentOutOfRangeException(nameof(shape), shape, "Unknown result shape."),
        };
    }

    private static async Task<IDictionary<string, object?>?> ReadFirstAsync(SqlMapper.GridReader grid)
        => (await ReadRowsAsync(grid)).FirstOrDefault();

    private static async Task<IReadOnlyList<IDictionary<string, object?>>> ReadRowsAsync(SqlMapper.GridReader grid)
    {
        var rows = await grid.ReadAsync();
        return rows.Select(ToRow).ToArray();
    }

    private static async Task<PagedResult<IDictionary<string, object?>>> ReadPagedAsync(
        SqlMapper.GridReader grid, int page, int pageSize)
    {
        var rows = await ReadRowsAsync(grid);
        var countRows = await grid.ReadAsync();
        var totalCount = countRows.Select(ToRow).FirstOrDefault();
        var count = totalCount is null || !totalCount.TryGetValue("TotalCount", out var value) || value is null
            ? 0
            : Convert.ToInt32(value, System.Globalization.CultureInfo.InvariantCulture);
        return new PagedResult<IDictionary<string, object?>>(rows, count, page, pageSize);
    }

    private static async Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> ReadSetsAsync(SqlMapper.GridReader grid)
    {
        var result = new List<IReadOnlyList<IDictionary<string, object?>>>();
        while (!grid.IsConsumed)
            result.Add(await ReadRowsAsync(grid));
        return result;
    }

    private static IDictionary<string, object?> ToRow(object value)
    {
        if (value is IDictionary<string, object> row)
            return row.ToDictionary(pair => pair.Key, pair => (object?)pair.Value, StringComparer.OrdinalIgnoreCase);
        if (value is IDictionary<string, object?> nullableRow)
            return new Dictionary<string, object?>(nullableRow, StringComparer.OrdinalIgnoreCase);
        throw new InvalidOperationException("A stored procedure returned a row in an unsupported shape.");
    }

    private static IReadOnlySet<string> GetDeclaredParameters(string procedure)
    {
        var normalized = procedure.StartsWith("dbo.", StringComparison.OrdinalIgnoreCase) ? procedure[4..] : procedure;
        if (!normalized.StartsWith("usp_", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Only dbo.usp_* stored procedures are supported.", nameof(procedure));
        return ProcedureParameters.GetOrAdd(normalized, name =>
        {
            var sqlRoot = Path.Combine(AppContext.BaseDirectory, "SQL");
            if (!Directory.Exists(sqlRoot))
                throw new InvalidOperationException($"Stored procedure declarations were not found at '{sqlRoot}'.");

            foreach (var file in Directory.EnumerateFiles(sqlRoot, "*.sql", SearchOption.AllDirectories))
            {
                var sql = File.ReadAllText(file);
                foreach (Match match in ProcedureHeader.Matches(sql))
                {
                    if (!string.Equals(match.Groups["name"].Value, name, StringComparison.OrdinalIgnoreCase))
                        continue;
                    var parameters = ParameterName.Matches(match.Groups["parameters"].Value)
                        .Select(m => m.Groups["name"].Value)
                        .ToHashSet(StringComparer.OrdinalIgnoreCase);
                    return parameters;
                }
            }
            throw new InvalidOperationException($"Stored procedure 'dbo.{name}' is not declared in the shipped SQL scripts.");
        });
    }

    private static void BindIfDeclared(DynamicParameters parameters, IReadOnlySet<string> declared, string name, object? value)
    {
        var normalized = name.TrimStart('@');
        if (declared.Contains(normalized))
            parameters.Add(normalized, value);
    }
}
