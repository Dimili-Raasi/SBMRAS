using SBMRAS.Application.Interfaces;

namespace SBMRAS.Application.Common;

/// <summary>Strongly-shaped wrappers over <see cref="IStoredProcedureExecutor.InvokeAsync"/>. Rows are case-insensitive dictionaries.</summary>
public static class StoredProcedureExecutorExtensions
{
    private static readonly IReadOnlyDictionary<string, object?> NoArguments = new Dictionary<string, object?>();

    /// <summary>First row of the first result set, or null.</summary>
    public static async Task<IDictionary<string, object?>?> QuerySingleAsync(this IStoredProcedureExecutor executor,
        string procedure, int actorUserId, IReadOnlyDictionary<string, object?>? arguments = null, CancellationToken cancellationToken = default)
        => SqlRows.AsRow(await executor.InvokeAsync(procedure, actorUserId, arguments ?? NoArguments, ResultShape.Single,
            cancellationToken: cancellationToken));

    /// <summary>All rows of the first result set.</summary>
    public static async Task<IReadOnlyList<IDictionary<string, object?>>> QueryListAsync(this IStoredProcedureExecutor executor,
        string procedure, int actorUserId, IReadOnlyDictionary<string, object?>? arguments = null, CancellationToken cancellationToken = default)
        => SqlRows.AsRows(await executor.InvokeAsync(procedure, actorUserId, arguments ?? NoArguments, ResultShape.List,
            cancellationToken: cancellationToken));

    /// <summary>Rows (set 1) + TotalCount (set 2). @Page/@PageSize are bound when the procedure declares them.</summary>
    public static async Task<PagedResult<IDictionary<string, object?>>> QueryPagedAsync(this IStoredProcedureExecutor executor,
        string procedure, int actorUserId, IReadOnlyDictionary<string, object?>? arguments, int page, int pageSize,
        CancellationToken cancellationToken = default)
        => SqlRows.AsPaged(await executor.InvokeAsync(procedure, actorUserId, arguments ?? NoArguments, ResultShape.Paged,
            page, pageSize, cancellationToken), page, pageSize);

    /// <summary>All result sets (use <see cref="SqlRows.Set"/> to pick one safely).</summary>
    public static async Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> QueryMultipleAsync(this IStoredProcedureExecutor executor,
        string procedure, int actorUserId, IReadOnlyDictionary<string, object?>? arguments = null, CancellationToken cancellationToken = default)
        => SqlRows.AsSets(await executor.InvokeAsync(procedure, actorUserId, arguments ?? NoArguments, ResultShape.Multiple,
            cancellationToken: cancellationToken));

    /// <summary>Executes; returns the first row if the procedure selects one, else null.</summary>
    public static async Task<IDictionary<string, object?>?> ExecuteAsync(this IStoredProcedureExecutor executor,
        string procedure, int actorUserId, IReadOnlyDictionary<string, object?>? arguments = null, CancellationToken cancellationToken = default)
        => SqlRows.AsRow(await executor.InvokeAsync(procedure, actorUserId, arguments ?? NoArguments, ResultShape.Execute,
            cancellationToken: cancellationToken));
}

/// <summary>ROWVERSION (VARBINARY(8)) ⇄ base64 helpers. Invalid input → 400.</summary>
public static class RowVersion
{
    public static byte[]? FromBase64(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        try
        {
            var bytes = Convert.FromBase64String(value.Trim());
            if (bytes.Length != 8) throw AppException.BadRequest("rowVersion is invalid.");
            return bytes;
        }
        catch (FormatException)
        {
            throw AppException.BadRequest("rowVersion is invalid.");
        }
    }

    public static string? ToBase64(byte[]? value) => value is null ? null : Convert.ToBase64String(value);
}
