using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

/// <summary>Blood request persistence (09_StoredProcedures_Public_Requests.sql). Rows keyed by SQL column name.</summary>
public interface IRequestsRepository
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, BloodRequestSearchQuery query, CancellationToken cancellationToken = default);

    /// <summary>usp_Request_GetById: request row, history, allowed transitions (3 sets).</summary>
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetByIdAsync(int actorUserId, int requestId, CancellationToken cancellationToken = default);

    Task<IDictionary<string, object?>?> CreateAsync(int actorUserId, BloodRequestSaveDto request, string? idempotencyKey,
        CancellationToken cancellationToken = default);

    Task<IDictionary<string, object?>?> CancelAsync(int actorUserId, int requestId, string? reason,
        CancellationToken cancellationToken = default);

    Task<IDictionary<string, object?>?> ChangeStatusAsync(int actorUserId, int requestId, BloodRequestStatusChangeDto change, byte[]? rowVersion,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IDictionary<string, object?>>> GetMatchesAsync(int actorUserId, int requestId, CancellationToken cancellationToken = default);
}

/// <summary>In-app notifications of the caller (04_StoredProcedures_Common.sql).</summary>
public interface INotificationsRepository
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, NotificationQuery query, CancellationToken cancellationToken = default);
    Task<int> GetUnreadCountAsync(int actorUserId, CancellationToken cancellationToken = default);
    /// <summary>Returns the remaining unread count.</summary>
    Task<int> MarkReadAsync(int actorUserId, long notificationId, CancellationToken cancellationToken = default);
    /// <summary>Returns the number of notifications updated.</summary>
    Task<int> MarkAllReadAsync(int actorUserId, CancellationToken cancellationToken = default);
}
