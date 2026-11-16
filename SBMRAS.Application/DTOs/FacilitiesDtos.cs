namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET facilities → usp_Facility_SearchMine.</summary>
public sealed record FacilitySearchQuery
{
    public string? FacilityType { get; init; }
    public string? Search { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Body of PUT facilities/{id} → usp_Facility_Update(@FacilityId, …).</summary>
public sealed record FacilityUpdateDto
{
    public string Name { get; init; } = "";
    public string? LicenseNo { get; init; }
    public string AddressLine { get; init; } = "";
    public int AreaId { get; init; }
    public string City { get; init; } = "";
    public string? Pincode { get; init; }
    public decimal? Latitude { get; init; }
    public decimal? Longitude { get; init; }
    public string ContactPhone { get; init; } = "";
    public string? ContactEmail { get; init; }
    public bool Is24x7 { get; init; }
    /// <summary>Base64 ROWVERSION → @RowVersion VARBINARY(8).</summary>
    public string? RowVersion { get; init; }
}

/// <summary>Query of GET facilities/{id}/history → usp_Inventory_GetSnapshots.</summary>
public sealed record InventoryHistoryQuery
{
    public string? Kind { get; init; }
    public int? Top { get; init; }
}

/// <summary>Response shape Facility (camelCased SQL columns).</summary>
public sealed record FacilityDto(
    int FacilityId, string FacilityCode, string Name, string FacilityType, string? LicenseNo, string AddressLine,
    int AreaId, string? AreaName, string City, string? Pincode, decimal? Latitude, decimal? Longitude, string ContactPhone,
    string? ContactEmail, bool Is24x7, string VerificationStatus, DateTime? VerifiedAt, string? VerificationNotes,
    bool IsActive, decimal? QualityScore, decimal? FreshPercent, int? StaleRecords, DateTime? LastUpdateAt,
    string? RowVersion, DateTime CreatedAt);

public static class FacilityValues
{
    public const string Hospital = "Hospital";
    public const string BloodBank = "BloodBank";
    public static readonly string[] FacilityTypes = [Hospital, BloodBank];
    public static readonly string[] InventoryKinds = ["Blood", "Resource"];
    public const int MaxHistoryTop = 1000;
}
