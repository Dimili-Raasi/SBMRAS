namespace SBMRAS.Application.Common;

public sealed record ApiResponse<T>(bool Success, string Message, T? Data, IReadOnlyList<string> Errors)
{
    public static ApiResponse<T> Ok(T? data, string message = "Success")
        => new(true, message, data, []);

    public static ApiResponse<T> Fail(string message, IReadOnlyList<string>? errors = null)
        => new(false, message, default, errors ?? []);
}

public sealed record PagedResult<T>(IReadOnlyList<T> Items, int TotalCount, int Page, int PageSize);

public enum ResultShape
{
    /// <summary>First row of the first result set (or null).</summary>
    Single,
    /// <summary>All rows of the first result set.</summary>
    List,
    /// <summary>Rows (set 1) + TotalCount (set 2) → <see cref="PagedResult{T}"/>.</summary>
    Paged,
    /// <summary>All result sets → IReadOnlyList&lt;IReadOnlyList&lt;IDictionary&lt;string, object?&gt;&gt;&gt;.</summary>
    Multiple,
    /// <summary>Executes; returns the first row if the procedure selects one, else null.</summary>
    Execute,
}
