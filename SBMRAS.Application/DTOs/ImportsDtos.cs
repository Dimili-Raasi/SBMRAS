namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET imports → usp_Import_Search.</summary>
public sealed record ImportSearchQuery
{
    public int? FacilityId { get; init; }
    public string? Status { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Body of POST imports → usp_Import_Stage(@FacilityId, @InventoryKind, @FileName, @FileHash, @RowsJson).</summary>
public sealed record ImportCreateDto
{
    public int FacilityId { get; init; }
    public string InventoryKind { get; init; } = "";
    public string FileName { get; init; } = "";
    public string FileHash { get; init; } = "";
    public IReadOnlyList<ImportRowInputDto> Rows { get; init; } = [];
}

/// <summary>One CSV row parsed in the browser. Values are kept loosely typed so the SP can report per-row errors.</summary>
public sealed record ImportRowInputDto
{
    public int RowNumber { get; init; }
    public string? RawData { get; init; }
    public string? ComponentCode { get; init; }
    public string? AboGroup { get; init; }
    public string? RhFactor { get; init; }
    public string? ResourceTypeCode { get; init; }
    public decimal? Quantity { get; init; }
    public decimal? TotalQuantity { get; init; }
    public decimal? AvailableQuantity { get; init; }
    public string? OperationalStatus { get; init; }
    public string? EarliestExpiryDate { get; init; }
    public string? ValidUntil { get; init; }
}

/// <summary>Response shape ImportBatch.</summary>
public sealed record ImportBatchDto(
    int BatchId, string BatchNo, int FacilityId, string? FacilityName, string InventoryKind, string FileName,
    string FileHash, int TotalRows, int ValidRows, int InvalidRows, int DuplicateRows, int ReviewRows, int AppliedRows,
    string Status, string? SubmittedByName, DateTime SubmittedAt, string? CommittedByName, DateTime? CommittedAt);

/// <summary>Response shape ImportRow.</summary>
public sealed record ImportRowDto(
    int ImportRowId, int RowNumber, string? RawData, string? ComponentCode, string? AboGroup, string? RhFactor,
    string? ResourceTypeCode, decimal? Quantity, decimal? TotalQuantity, decimal? AvailableQuantity,
    string? OperationalStatus, DateTime? EarliestExpiryDate, DateTime? ValidUntil, string ValidationStatus,
    string? ErrorCodes, string? ErrorMessages);

public static class ImportValues
{
    public static readonly string[] InventoryKinds = ["Blood", "Resource"];
    public static readonly string[] Statuses = ["Validated", "Committed", "Cancelled"];
    public const int DefaultMaxRows = 500;
    public const int MaxRawDataLength = 1000;
    public const int MaxFileNameLength = 260;
    public const int MaxFileHashLength = 64;
    public const int MaxIdempotencyKeyLength = 100;
}
