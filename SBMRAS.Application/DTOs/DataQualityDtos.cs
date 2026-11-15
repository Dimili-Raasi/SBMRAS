namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET data-quality/summary → usp_DataQuality_GetSummary.</summary>
public sealed record DataQualitySummaryQuery
{
    public int? FacilityId { get; init; }
}

/// <summary>Query of GET data-quality/issues → usp_DataQuality_SearchIssues.</summary>
public sealed record DataQualityIssueQuery
{
    public string? Status { get; init; }
    public string? Severity { get; init; }
    public string? IssueCode { get; init; }
    public int? FacilityId { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Body of POST data-quality/issues/{id}/resolve → usp_DataQuality_ResolveIssue(@IssueId, @Resolution, @Dismiss).</summary>
public sealed record DataQualityResolveDto
{
    public string? Resolution { get; init; }
    public bool Dismiss { get; init; }
}

/// <summary>Body of POST data-quality/scan → usp_DataQuality_Scan(@FacilityId).</summary>
public sealed record DataQualityScanDto
{
    public int? FacilityId { get; init; }
}

public static class DataQualityValues
{
    public static readonly string[] IssueStatuses = ["Open", "Resolved", "Dismissed"];
    public static readonly string[] Severities = ["Low", "Medium", "High"];
    public static readonly string[] IssueCodes = ["STALE", "NEGATIVE", "LARGE_JUMP", "MISSING_FIELD", "DUPLICATE", "CONFLICT", "EXPIRING"];
    public const int MaxResolutionLength = 500;
}
