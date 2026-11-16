namespace SBMRAS.Application.DTOs;

/// <summary>GET dashboard/summary response (usp_Dashboard_GetSummary).</summary>
public sealed record DashboardSummaryDto(string Role, int TotalFacilities, int VerifiedFacilities, decimal BloodUnitsAvailable,
    decimal FreshPercent, int StaleRecords, int PendingReviews, int OpenRequests, int EmergencyRequests, int FulfilledRequests,
    int MyOpenRequests, int OpenIssues, decimal? AvgQualityScore, int PendingFacilityVerifications);

/// <summary>GET dashboard/charts response (usp_Dashboard_GetCharts, 6 result sets in this order).</summary>
public sealed record DashboardChartsDto(
    IReadOnlyList<object> BloodByGroup, IReadOnlyList<object> Freshness, IReadOnlyList<object> RequestTrend,
    IReadOnlyList<object> RequestStatus, IReadOnlyList<object> ResourceUtilization, IReadOnlyList<object> QualityByFacility);

public sealed record DashboardWorklistItemDto(string Type, string ReferenceNo, string Title, string Status, string? Priority,
    DateTime? DueAt, string? Route);

public sealed record DashboardActivityDto(long AuditId, string EntityType, string EntityId, string? ReferenceNo, string Action,
    string Description, string? UserName, DateTime CreatedAt);

public static class DashboardValues
{
    public const int DefaultActivityTop = 10;
    public const int MaxActivityTop = 100;
}
