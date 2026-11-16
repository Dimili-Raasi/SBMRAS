using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.Infrastructure.Repositories;

public sealed class RequestsRepository(IStoredProcedureExecutor executor, IRequestContext requestContext) : IRequestsRepository
{
    public Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, BloodRequestSearchQuery query,
        CancellationToken cancellationToken = default)
        => executor.QueryPagedAsync(StoredProcedures.RequestSearch, actorUserId, new Dictionary<string, object?>
        {
            ["Scope"] = string.IsNullOrWhiteSpace(query.Scope) ? "mine" : query.Scope.Trim().ToLowerInvariant(),
            ["Status"] = query.Status,
            ["Urgency"] = query.Urgency,
            ["AboGroup"] = query.AboGroup,
            ["AreaId"] = query.AreaId,
            ["Search"] = query.Search,
        }, query.Page, query.PageSize, cancellationToken);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetByIdAsync(int actorUserId, int requestId,
        CancellationToken cancellationToken = default)
        => executor.QueryMultipleAsync(StoredProcedures.RequestGetById, actorUserId,
            new Dictionary<string, object?> { ["RequestId"] = requestId }, cancellationToken);

    public Task<IDictionary<string, object?>?> CreateAsync(int actorUserId, BloodRequestSaveDto request, string? idempotencyKey,
        CancellationToken cancellationToken = default)
        => executor.QuerySingleAsync(StoredProcedures.RequestCreate, actorUserId, new Dictionary<string, object?>
        {
            ["PatientReference"] = request.PatientReference,
            ["AboGroup"] = request.AboGroup,
            ["RhFactor"] = request.RhFactor,
            ["ComponentId"] = request.ComponentId,
            ["QuantityRequested"] = request.QuantityRequested,
            ["UnitId"] = request.UnitId,
            ["Urgency"] = request.Urgency,
            ["NeededBy"] = ToUtc(request.NeededBy),
            ["AreaId"] = request.AreaId,
            ["HospitalName"] = request.HospitalName,
            ["PreferredFacilityId"] = request.PreferredFacilityId,
            ["ContactName"] = request.ContactName,
            ["ContactPhone"] = request.ContactPhone,
            ["ContactConsent"] = request.ContactConsent,
            ["Notes"] = request.Notes,
            ["IdempotencyKey"] = idempotencyKey,
            ["CorrelationId"] = requestContext.CorrelationId,
        }, cancellationToken);

    public Task<IDictionary<string, object?>?> CancelAsync(int actorUserId, int requestId, string? reason,
        CancellationToken cancellationToken = default)
        => executor.QuerySingleAsync(StoredProcedures.RequestCancel, actorUserId, new Dictionary<string, object?>
        {
            ["RequestId"] = requestId,
            ["Reason"] = reason,
            ["CorrelationId"] = requestContext.CorrelationId,
        }, cancellationToken);

    public Task<IDictionary<string, object?>?> ChangeStatusAsync(int actorUserId, int requestId, BloodRequestStatusChangeDto change,
        byte[]? rowVersion, CancellationToken cancellationToken = default)
        => executor.QuerySingleAsync(StoredProcedures.RequestChangeStatus, actorUserId, new Dictionary<string, object?>
        {
            ["RequestId"] = requestId,
            ["ToStatus"] = change.ToStatus,
            ["Note"] = change.Note,
            ["MatchedFacilityId"] = change.MatchedFacilityId,
            ["RowVersion"] = rowVersion,
            ["CorrelationId"] = requestContext.CorrelationId,
        }, cancellationToken);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetMatchesAsync(int actorUserId, int requestId,
        CancellationToken cancellationToken = default)
        => executor.QueryListAsync(StoredProcedures.RequestGetMatches, actorUserId,
            new Dictionary<string, object?> { ["RequestId"] = requestId }, cancellationToken);

    private static DateTime ToUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Local => value.ToUniversalTime(),
        DateTimeKind.Unspecified => DateTime.SpecifyKind(value, DateTimeKind.Utc),
        _ => value,
    };
}

public sealed class NotificationsRepository(IStoredProcedureExecutor executor) : INotificationsRepository
{
    public Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, NotificationQuery query,
        CancellationToken cancellationToken = default)
        => executor.QueryPagedAsync(StoredProcedures.NotificationSearch, actorUserId,
            new Dictionary<string, object?> { ["UnreadOnly"] = query.UnreadOnly }, query.Page, query.PageSize, cancellationToken);

    public async Task<int> GetUnreadCountAsync(int actorUserId, CancellationToken cancellationToken = default)
        => SqlRows.Int(await executor.QuerySingleAsync(StoredProcedures.NotificationGetUnreadCount, actorUserId, null, cancellationToken), "Count");

    public async Task<int> MarkReadAsync(int actorUserId, long notificationId, CancellationToken cancellationToken = default)
        => SqlRows.Int(await executor.QuerySingleAsync(StoredProcedures.NotificationMarkRead, actorUserId,
            new Dictionary<string, object?> { ["NotificationId"] = notificationId }, cancellationToken), "Count");

    public async Task<int> MarkAllReadAsync(int actorUserId, CancellationToken cancellationToken = default)
        => SqlRows.Int(await executor.QuerySingleAsync(StoredProcedures.NotificationMarkAllRead, actorUserId, null, cancellationToken), "Count");
}
