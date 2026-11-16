using System.Globalization;
using System.Text;
using System.Text.Json;
using FluentValidation;
using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;
using SBMRAS.Application.Validators;

namespace SBMRAS.Domain.Services;

public sealed class DashboardService(IDashboardRepository repository) : IDashboardService
{
    public async Task<DashboardSummaryDto> GetSummaryAsync(CurrentUser actor, CancellationToken ct = default)
    {
        var r = await repository.GetSummaryAsync(actor.UserId, ct) ?? new Dictionary<string, object?>();
        return new DashboardSummaryDto(SqlRows.Str(r, "Role"), SqlRows.Int(r, "TotalFacilities"), SqlRows.Int(r, "VerifiedFacilities"),
            SqlRows.Dec(SqlRows.Value(r, "BloodUnitsAvailable")) ?? 0, SqlRows.Dec(SqlRows.Value(r, "FreshPercent")) ?? 0,
            SqlRows.Int(r, "StaleRecords"), SqlRows.Int(r, "PendingReviews"), SqlRows.Int(r, "OpenRequests"),
            SqlRows.Int(r, "EmergencyRequests"), SqlRows.Int(r, "FulfilledRequests"), SqlRows.Int(r, "MyOpenRequests"),
            SqlRows.Int(r, "OpenIssues"), SqlRows.Dec(SqlRows.Value(r, "AvgQualityScore")), SqlRows.Int(r, "PendingFacilityVerifications"));
    }

    public async Task<DashboardChartsDto> GetChartsAsync(CurrentUser actor, CancellationToken ct = default)
    {
        var sets = await repository.GetChartsAsync(actor.UserId, ct);
        IReadOnlyList<object> Rows(int index) => SqlRows.Set(sets, index).Select(CamelRow).Cast<object>().ToArray();
        return new DashboardChartsDto(Rows(0), Rows(1), Rows(2), Rows(3), Rows(4), Rows(5));
    }

    public async Task<IReadOnlyList<DashboardWorklistItemDto>> GetWorklistAsync(CurrentUser actor, CancellationToken ct = default)
        => (await repository.GetWorklistAsync(actor.UserId, ct)).Select(r => new DashboardWorklistItemDto(
            SqlRows.Str(r, "Type"), SqlRows.Str(r, "ReferenceNo"), SqlRows.Str(r, "Title"), SqlRows.Str(r, "Status"),
            NullableText(r, "Priority"), Date(r, "DueAt"), NullableText(r, "Route"))).ToArray();

    public async Task<IReadOnlyList<DashboardActivityDto>> GetActivityAsync(CurrentUser actor, int top, CancellationToken ct = default)
    {
        if (top < 1 || top > DashboardValues.MaxActivityTop) throw AppException.BadRequest($"top must be between 1 and {DashboardValues.MaxActivityTop}.");
        return (await repository.GetActivityAsync(actor.UserId, top, ct)).Select(r => new DashboardActivityDto(
            SqlRows.ToInt(SqlRows.Value(r, "AuditId")) ?? 0, SqlRows.Str(r, "EntityType"), SqlRows.Str(r, "EntityId"),
            NullableText(r, "ReferenceNo"), SqlRows.Str(r, "Action"), SqlRows.Str(r, "Description"),
            NullableText(r, "UserName"), Date(r, "CreatedAt") ?? default)).ToArray();
    }

    private static Dictionary<string, object?> CamelRow(IDictionary<string, object?> row)
        => row.ToDictionary(p => JsonNamingPolicy.CamelCase.ConvertName(p.Key), p => p.Value);
    private static string? NullableText(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is null or DBNull ? null : SqlRows.Str(row, key);
    private static DateTime? Date(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        DateTime value => DateTime.SpecifyKind(value, DateTimeKind.Utc),
        DateTimeOffset value => value.UtcDateTime,
        _ => null,
    };
}

public sealed class ReportService(IReportRepository repository) : IReportService
{
    private static readonly ReportQueryValidator QueryValidator = new();
    private static readonly IReadOnlyList<ReportDefinitionDto> Definitions =
    [
        new(ReportCodes.InventorySummary, "Inventory Summary", "Current blood and medical resource inventory."),
        new(ReportCodes.FreshnessCompliance, "Freshness Compliance", "Inventory freshness and validity compliance."),
        new(ReportCodes.DataCompleteness, "Data Completeness", "Facility inventory data completeness."),
        new(ReportCodes.ImportQuality, "Import Quality", "Bulk inventory import validation and quality."),
        new(ReportCodes.RequestLifecycle, "Request Lifecycle", "Blood request status and fulfillment lifecycle."),
        new(ReportCodes.FacilityReliability, "Facility Reliability", "Facility quality and reporting reliability."),
        new(ReportCodes.ResourceAvailability, "Resource Availability", "Medical resource availability by facility."),
    ];

    public Task<IReadOnlyList<ReportDefinitionDto>> GetDefinitionsAsync(CurrentUser actor, CancellationToken ct = default)
        => Task.FromResult(Definitions);

    public async Task<ReportResultDto> RunAsync(CurrentUser actor, ReportQuery query, CancellationToken ct = default)
    {
        Validate(query);
        var sets = await repository.RunAsync(actor.UserId, query with { Code = query.Code.Trim().ToUpperInvariant() }, ct);
        var meta = SqlRows.Set(sets, 0).FirstOrDefault() ?? new Dictionary<string, object?>();
        var columns = SqlRows.Set(sets, 1).Select(c => new ReportColumnDto(SqlRows.Str(c, "Key"), SqlRows.Str(c, "Label"), SqlRows.Str(c, "Type"))).ToArray();
        var rows = SqlRows.Set(sets, 2).Select(CamelRow).ToArray();
        var code = SqlRows.Str(meta, "Code");
        var name = SqlRows.Str(meta, "Name");
        return new ReportResultDto(code.Length == 0 ? query.Code : code, name, columns, rows, BuildChart(code.Length == 0 ? query.Code : code, columns, rows));
    }

    public async Task<ReportExportDto> ExportAsync(CurrentUser actor, ReportQuery query, CancellationToken ct = default)
    {
        var report = await RunAsync(actor, query, ct);
        var builder = new StringBuilder();
        builder.AppendLine(string.Join(',', report.Columns.Select(c => Csv(c.Label))));
        foreach (var row in report.Rows)
            builder.AppendLine(string.Join(',', report.Columns.Select(c => Csv(ValueText(row, c.Key)))));
        var file = $"{report.Code.ToLowerInvariant()}-{DateTime.UtcNow:yyyyMMdd-HHmmss}.csv";
        return new ReportExportDto(file, "text/csv; charset=utf-8", new UTF8Encoding(false).GetBytes(builder.ToString()));
    }

    private static void Validate(ReportQuery query)
    {
        var result = QueryValidator.Validate(query);
        if (!result.IsValid) throw AppException.Validation("Validation failed.", result.Errors.Select(e => e.ErrorMessage).Distinct());
    }

    private static ReportChartDto? BuildChart(string code, IReadOnlyList<ReportColumnDto> columns, IReadOnlyList<IDictionary<string, object?>> rows)
    {
        var category = columns.FirstOrDefault(c => c.Type.Equals("text", StringComparison.OrdinalIgnoreCase));
        var valueColumns = columns.Where(c => c.Type.Equals("number", StringComparison.OrdinalIgnoreCase) || c.Type.Equals("percent", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (category is null || valueColumns.Length == 0 || rows.Count == 0) return null;
        var labels = rows.Select(r => ValueText(r, category.Key)).ToArray();
        var datasets = valueColumns.Select(c => new ReportChartDatasetDto(c.Label, rows.Select(r => Number(SqlRows.Value(r, c.Key))).ToArray())).ToArray();
        var type = code.Equals(ReportCodes.RequestLifecycle, StringComparison.OrdinalIgnoreCase) ? "line"
            : code.Equals(ReportCodes.FreshnessCompliance, StringComparison.OrdinalIgnoreCase) ? "doughnut" : "bar";
        return new ReportChartDto(type, labels, datasets);
    }

    private static string Csv(string? value)
    {
        value ??= "";
        return value.IndexOfAny([',', '"', '\r', '\n']) >= 0 ? $"\"{value.Replace("\"", "\"\"")}\"" : value;
    }

    private static string ValueText(IDictionary<string, object?> row, string key)
        => Convert.ToString(SqlRows.Value(row, key), CultureInfo.InvariantCulture) ?? "";
    private static decimal? Number(object? value) => SqlRows.Dec(value);
    private static Dictionary<string, object?> CamelRow(IDictionary<string, object?> row)
        => row.ToDictionary(p => JsonNamingPolicy.CamelCase.ConvertName(p.Key), p => p.Value);
}

public sealed class AuditService(IAuditRepository repository) : IAuditService
{
    private static readonly AuditSearchQueryValidator QueryValidator = new();

    public async Task<PagedResult<AuditLogDto>> SearchAsync(CurrentUser actor, AuditSearchQuery query, CancellationToken ct = default)
    {
        var result = QueryValidator.Validate(query);
        if (!result.IsValid) throw AppException.Validation("Validation failed.", result.Errors.Select(e => e.ErrorMessage).Distinct());
        var paged = await repository.SearchAsync(actor.UserId, query, ct);
        return new PagedResult<AuditLogDto>(paged.Items.Select(Map).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    public async Task<IReadOnlyList<AuditLogDto>> GetEntityTimelineAsync(CurrentUser actor, string entityType, string entityId,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(entityType) || entityType.Length > 50 || string.IsNullOrWhiteSpace(entityId) || entityId.Length > 100)
            throw AppException.BadRequest("Entity type or entity id is invalid.");
        var rows = await repository.GetEntityTimelineAsync(actor.UserId, entityType.Trim(), entityId.Trim(), ct);
        return rows.Select(Map).ToArray();
    }

    private static AuditLogDto Map(IDictionary<string, object?> r) => new(
        SqlRows.ToInt(SqlRows.Value(r, "AuditId")) ?? 0, SqlRows.Str(r, "EntityType"), SqlRows.Str(r, "EntityId"),
        NullableText(r, "ReferenceNo"), SqlRows.ToInt(SqlRows.Value(r, "FacilityId")), NullableText(r, "FacilityName"),
        SqlRows.Str(r, "Action"), SqlRows.Str(r, "Description"), NullableText(r, "OldValues"), NullableText(r, "NewValues"),
        NullableText(r, "SourceType"), NullableText(r, "Reason"), NullableText(r, "CorrelationId"), NullableText(r, "UserName"),
        NullableText(r, "ActorRole"), Date(r, "CreatedAt") ?? default);

    private static string? NullableText(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is null or DBNull ? null : SqlRows.Str(row, key);
    private static DateTime? Date(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        DateTime value => DateTime.SpecifyKind(value, DateTimeKind.Utc),
        DateTimeOffset value => value.UtcDateTime,
        _ => null,
    };
}
