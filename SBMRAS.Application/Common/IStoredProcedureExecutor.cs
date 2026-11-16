namespace SBMRAS.Application.Common;

/// <summary>
/// Executes a dbo stored procedure declared in SBMRAS.Infrastructure\SQL\*.sql.
/// Only arguments whose names match a declared parameter are bound (case-insensitive, leading '@' optional).
/// @ActorUserId is always bound from <paramref name="actorUserId"/>; @Page/@PageSize are bound when declared.
/// Rows are returned as IDictionary&lt;string, object?&gt; keyed by SQL column name.
/// </summary>
public interface IStoredProcedureExecutor
{
    Task<object?> InvokeAsync(string procedure, int actorUserId, IReadOnlyDictionary<string, object?> arguments,
        ResultShape shape, int page = 1, int pageSize = 20, CancellationToken cancellationToken = default);
}
