namespace SBMRAS.Application.DTOs;

/// <summary>Query of GET reports/{code} and reports/{code}/export → usp_Report_Run.</summary>
public sealed record ReportQuery
{
    public string Code { get; init; } = "";
    public DateTime? FromDate { get; init; }
    public DateTime? ToDate { get; init; }
    public int? FacilityId { get; init; }
    public int? AreaId { get; init; }
}

/// <summary>GET reports row (usp_Report_List).</summary>
public sealed record ReportDefinitionDto(string Code, string Name, string Description);

/// <summary>GET reports/{code} response.</summary>
public sealed record ReportResultDto(string Code, string Name, IReadOnlyList<ReportColumnDto> Columns,
    IReadOnlyList<IDictionary<string, object?>> Rows, ReportChartDto? Chart);

/// <summary>Type ∈ text | number | date | percent.</summary>
public sealed record ReportColumnDto(string Key, string Label, string Type);

/// <summary>Type ∈ bar | line | doughnut.</summary>
public sealed record ReportChartDto(string Type, IReadOnlyList<string> Labels, IReadOnlyList<ReportChartDatasetDto> Datasets);

public sealed record ReportChartDatasetDto(string Label, IReadOnlyList<decimal?> Data);

/// <summary>CSV export payload.</summary>
public sealed record ReportExportDto(string FileName, string ContentType, byte[] Content);
