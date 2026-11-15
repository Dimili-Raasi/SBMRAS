namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET audit-logs → usp_Audit_Search. CorrelationId here is a filter, not the request correlation id.</summary>
public sealed record AuditSearchQuery
{
    public string? Search { get; init; }
    public string? EntityType { get; init; }
    public string? Action { get; init; }
    public int? FacilityId { get; init; }
    public int? UserId { get; init; }
    public string? CorrelationId { get; init; }
    public DateTime? FromDate { get; init; }
    public DateTime? ToDate { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Audit log row (search + entity timeline).</summary>
public sealed record AuditLogDto(long AuditId, string EntityType, string EntityId, string? ReferenceNo, int? FacilityId,
    string? FacilityName, string Action, string Description, string? OldValues, string? NewValues, string? SourceType,
    string? Reason, string? CorrelationId, string? UserName, string? ActorRole, DateTime CreatedAt);
