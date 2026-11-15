namespace SBMRAS.Application.DTOs;

/// <summary>Body of POST requests (contract §6 RequestSave) → usp_Request_Create.</summary>
public sealed record BloodRequestSaveDto
{
    public string? PatientReference { get; init; }
    public string AboGroup { get; init; } = "";
    public string RhFactor { get; init; } = "";
    public int ComponentId { get; init; }
    public decimal QuantityRequested { get; init; }
    public int UnitId { get; init; }
    public string Urgency { get; init; } = "Routine";
    public DateTime NeededBy { get; init; }
    public int AreaId { get; init; }
    public string HospitalName { get; init; } = "";
    public int? PreferredFacilityId { get; init; }
    public string ContactName { get; init; } = "";
    public string ContactPhone { get; init; } = "";
    public bool ContactConsent { get; init; }
    public string? Notes { get; init; }
}

/// <summary>Body of POST requests/{id}/cancel → usp_Request_Cancel(@RequestId, @Reason).</summary>
public sealed record BloodRequestCancelDto
{
    public string? Reason { get; init; }
}

/// <summary>Body of POST requests/{id}/status → usp_Request_ChangeStatus.</summary>
public sealed record BloodRequestStatusChangeDto
{
    public string ToStatus { get; init; } = "";
    public string? Note { get; init; }
    public int? MatchedFacilityId { get; init; }
    /// <summary>Base64 ROWVERSION; converted to VARBINARY(8) for @RowVersion.</summary>
    public string? RowVersion { get; init; }
}

/// <summary>Query of GET requests → usp_Request_Search.</summary>
public sealed record BloodRequestSearchQuery
{
    public string? Scope { get; init; }
    public string? Status { get; init; }
    public string? Urgency { get; init; }
    public string? AboGroup { get; init; }
    public int? AreaId { get; init; }
    public string? Search { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Response shape BloodRequest (documents the camelCased SQL columns returned by usp_Request_GetRow).</summary>
public record BloodRequestDto(
    int RequestId, string RequestNo, int RequesterUserId, string? RequesterName, string? PatientReference,
    string AboGroup, string RhFactor, string BloodGroup, int ComponentId, string ComponentCode, string ComponentName,
    decimal QuantityRequested, int UnitId, string UnitCode, string Urgency, DateTime NeededBy, int AreaId, string AreaName,
    string HospitalName, int? PreferredFacilityId, string? PreferredFacilityName, int? MatchedFacilityId,
    string? MatchedFacilityName, string? MatchedFacilityPhone, string ContactName, string? ContactPhone, string? Notes,
    string Status, string? StatusReason, bool IsOwner, DateTime CreatedAt, DateTime? UpdatedAt, string? RowVersion);

/// <summary>Response shape of GET requests/{id}: BloodRequest fields + history + allowedTransitions.</summary>
public sealed record BloodRequestHistoryDto(long HistoryId, string? FromStatus, string ToStatus, string? Note,
    string? FacilityName, string? ChangedByName, DateTime ChangedAt);

/// <summary>GET requests/{id}: BloodRequest fields (flattened) + history + allowedTransitions for the caller.</summary>
public sealed record BloodRequestDetailDto : BloodRequestDto
{
    public BloodRequestDetailDto(BloodRequestDto request, IReadOnlyList<BloodRequestHistoryDto> history, IReadOnlyList<string> allowedTransitions)
        : base(request)
    {
        History = history;
        AllowedTransitions = allowedTransitions;
    }

    public IReadOnlyList<BloodRequestHistoryDto> History { get; init; }
    public IReadOnlyList<string> AllowedTransitions { get; init; }
}

public static class BloodRequestValues
{
    public static readonly string[] AboGroups = ["A", "B", "AB", "O"];
    public static readonly string[] RhFactors = ["Positive", "Negative"];
    public static readonly string[] Urgencies = ["Routine", "Urgent", "Emergency"];
    public static readonly string[] Statuses =
        ["Submitted", "UnderReview", "Matched", "Contacted", "Fulfilled", "UnableToFulfil", "Closed", "Cancelled"];
    public static readonly string[] Scopes = ["mine", "all"];
    public const decimal MaxQuantity = 50m;
    public const int MaxIdempotencyKeyLength = 100;
    /// <summary>Digits with optional leading '+', spaces or dashes; 7–20 characters (fits NVARCHAR(30)).</summary>
    public const string PhonePattern = @"^\+?[0-9][0-9 \-]{6,19}$";
}
