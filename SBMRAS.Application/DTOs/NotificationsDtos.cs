namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET notifications → usp_Notification_Search.</summary>
public sealed record NotificationQuery
{
    public bool UnreadOnly { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Notification row.</summary>
public sealed record NotificationDto(long NotificationId, string Title, string Message, string Type, string? EntityType,
    string? EntityId, string? Route, bool IsRead, DateTime CreatedAt);

/// <summary>GET notifications/unread-count response.</summary>
public sealed record UnreadCountDto(int Count);
