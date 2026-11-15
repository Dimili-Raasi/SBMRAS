namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET public/blood-availability → usp_Public_SearchBlood.</summary>
public sealed record BloodAvailabilityQuery
{
    public string? AboGroup { get; init; }
    public string? RhFactor { get; init; }
    public int? ComponentId { get; init; }
    public int? AreaId { get; init; }
    public string? Search { get; init; }
    public bool FreshOnly { get; init; } = true;
    public decimal? MinQuantity { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Query of GET public/medical-resources → usp_Public_SearchResources.</summary>
public sealed record ResourceAvailabilityQuery
{
    public int? CategoryId { get; init; }
    public int? ResourceTypeId { get; init; }
    public int? AreaId { get; init; }
    public string? Search { get; init; }
    public bool AvailableOnly { get; init; }
    public bool FreshOnly { get; init; } = true;
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Query of GET public/facilities → usp_Public_SearchFacilities.</summary>
public sealed record PublicFacilityQuery
{
    public string? FacilityType { get; init; }
    public int? AreaId { get; init; }
    public string? Search { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>GET public/lookups response (usp_Lookups_Get, 10 result sets).</summary>
public sealed record PublicLookupsDto(
    IReadOnlyList<object> Areas, IReadOnlyList<object> Components, IReadOnlyList<object> Units,
    IReadOnlyList<object> ResourceCategories, IReadOnlyList<object> ResourceTypes,
    IReadOnlyList<string> AboGroups, IReadOnlyList<string> RhFactors, IReadOnlyList<string> Urgencies,
    IReadOnlyList<string> RequestStatuses, IReadOnlyList<string> FreshnessStatuses);

/// <summary>GET public/stats response.</summary>
public sealed record PublicStatsDto(int VerifiedFacilities, int Hospitals, int BloodBanks, decimal UnitsAvailable,
    decimal FreshPercent, int OpenRequests, int FulfilledRequests, DateTime? LastUpdatedAt);

/// <summary>BloodAvailability row (public search, request matches).</summary>
public sealed record BloodAvailabilityDto(
    int InventoryId, int FacilityId, string FacilityName, string FacilityType, int AreaId, string AreaName, string City,
    string AddressLine, string ContactPhone, bool Is24x7, int ComponentId, string ComponentCode, string ComponentName,
    string AboGroup, string RhFactor, string BloodGroup, decimal Quantity, string UnitCode, string AvailabilityStatus,
    string FreshnessStatus, string VerificationStatus, string SourceType, DateTime? LastUpdatedAt, DateTime? ValidUntil,
    int? MinutesSinceUpdate, DateTime? EarliestExpiryDate, decimal? QualityScore);

/// <summary>ResourceAvailability row (public search).</summary>
public sealed record ResourceAvailabilityDto(
    int ResourceInventoryId, int FacilityId, string FacilityName, int AreaId, string AreaName, string City,
    string ContactPhone, bool Is24x7, string CategoryName, int ResourceTypeId, string ResourceTypeCode,
    string ResourceTypeName, decimal TotalQuantity, decimal AvailableQuantity, string UnitCode, string OperationalStatus,
    string FreshnessStatus, string VerificationStatus, DateTime? LastUpdatedAt, DateTime? ValidUntil,
    int? MinutesSinceUpdate, string? Notes);

/// <summary>Public facility directory row.</summary>
public sealed record PublicFacilityDto(int FacilityId, string FacilityCode, string Name, string FacilityType,
    string AddressLine, string AreaName, string City, string ContactPhone, string? ContactEmail, bool Is24x7,
    decimal? QualityScore, DateTime? LastUpdateAt);

public static class PublicValues
{
    public static readonly string[] FacilityTypes = ["Hospital", "BloodBank"];
    public const int MaxPageSize = 100;
    public const int MaxSearchLength = 200;
}
