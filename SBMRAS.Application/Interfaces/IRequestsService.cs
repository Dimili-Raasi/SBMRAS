using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

/// <summary>Blood request + coordination use cases (contract §6 Blood requests, §4.5). Implemented in SBMRAS.Domain.</summary>
public interface IRequestsService
{
    Task<PagedResult<BloodRequestDto>> SearchAsync(CurrentUser actor, BloodRequestSearchQuery query, CancellationToken cancellationToken = default);
    Task<BloodRequestDetailDto> GetAsync(CurrentUser actor, int requestId, CancellationToken cancellationToken = default);
    Task<BloodRequestDto> CreateAsync(CurrentUser actor, BloodRequestSaveDto body, string? idempotencyKey, CancellationToken cancellationToken = default);
    Task<BloodRequestDto> CancelAsync(CurrentUser actor, int requestId, BloodRequestCancelDto body, CancellationToken cancellationToken = default);
    Task<BloodRequestDto> ChangeStatusAsync(CurrentUser actor, int requestId, BloodRequestStatusChangeDto body, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<BloodAvailabilityDto>> GetMatchesAsync(CurrentUser actor, int requestId, CancellationToken cancellationToken = default);
}

/// <summary>In-app notification use cases (contract §6 Notifications). Implemented in SBMRAS.Domain.</summary>
public interface INotificationsService
{
    Task<PagedResult<NotificationDto>> SearchAsync(CurrentUser actor, NotificationQuery query, CancellationToken cancellationToken = default);
    Task<UnreadCountDto> GetUnreadCountAsync(CurrentUser actor, CancellationToken cancellationToken = default);
    /// <summary>Marks one notification read; returns the remaining unread count.</summary>
    Task<UnreadCountDto> MarkReadAsync(CurrentUser actor, long notificationId, CancellationToken cancellationToken = default);
    /// <summary>Marks all notifications read; returns the number updated.</summary>
    Task<int> MarkAllReadAsync(CurrentUser actor, CancellationToken cancellationToken = default);
}
