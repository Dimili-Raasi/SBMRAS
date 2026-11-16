namespace SBMRAS.Application.DTOs;

/// <summary>Body of POST facilities/{id}/resources/updates → usp_Resource_SubmitUpdate.</summary>
public sealed record ResourceUpdateDto
{
    public int ResourceTypeId { get; init; }
    public decimal TotalQuantity { get; init; }
    public decimal AvailableQuantity { get; init; }
    public string OperationalStatus { get; init; } = "";
    public DateTime? ValidUntil { get; init; }
    public string? Notes { get; init; }
    public string? Reason { get; init; }
    public string? RowVersion { get; init; }
}

/// <summary>Body of POST facilities/{id}/blood-stock/updates → usp_BloodStock_SubmitUpdate.</summary>
public sealed record BloodStockUpdateDto
{
    public int ComponentId { get; init; }
    public string AboGroup { get; init; } = "";
    public string RhFactor { get; init; } = "";
    public decimal Quantity { get; init; }
    public DateTime? EarliestExpiryDate { get; init; }
    public DateTime? ValidUntil { get; init; }
    public string? Reason { get; init; }
    public string? RowVersion { get; init; }
}

/// <summary>Body of POST facilities/{id}/blood-stock/confirm → usp_BloodStock_ConfirmCurrent(@FacilityId, @InventoryIds CSV).</summary>
public sealed record BloodStockConfirmDto
{
    public IReadOnlyList<int> InventoryIds { get; init; } = [];
}

/// <summary>Query of GET inventory-changes → usp_Change_Search.</summary>
public sealed record InventoryChangeSearchQuery
{
    public string? Status { get; init; }
    public int? FacilityId { get; init; }
    public string? InventoryKind { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Body of POST inventory-changes/{id}/decision → usp_Change_Decide(@ChangeId, @Decision, @Reason).</summary>
public sealed record InventoryChangeDecisionDto
{
    public string Decision { get; init; } = "";
    public string? Reason { get; init; }
}

/// <summary>Response shape InventoryChange (camelCased SQL columns).</summary>
public sealed record InventoryChangeDto(
    int ChangeId, string ChangeNo, int FacilityId, string? FacilityName, string InventoryKind, string? ItemLabel,
    decimal? PreviousQuantity, decimal? ProposedQuantity, decimal? PreviousAvailable, decimal? ProposedAvailable,
    decimal? ProposedTotal, string? ProposedStatus, DateTime? ValidUntil, string SourceType, string? Reason,
    string? AnomalyFlags, string Status, string? SubmittedByName, DateTime SubmittedAt, string? DecidedByName,
    DateTime? DecidedAt, string? DecisionReason, bool CanDecide);

public static class InventoryValues
{
    public static readonly string[] AboGroups = ["A", "B", "AB", "O"];
    public static readonly string[] RhFactors = ["Positive", "Negative"];
    public static readonly string[] OperationalStatuses = ["Available", "Limited", "Unavailable", "Unknown"];
    public static readonly string[] ChangeStatuses = ["Applied", "PendingReview", "Rejected"];
    public static readonly string[] Decisions = ["Approve", "Reject"];
    public const int MaxConfirmIds = 500;
    public const int MaxReasonLength = 500;
    public const int MaxNotesLength = 500;
    public const int MaxValidityDays = 7;
}
