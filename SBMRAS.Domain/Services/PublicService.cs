using System.Globalization;
using System.Text.Json;
using FluentValidation;
using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;
using SBMRAS.Application.Validators;

namespace SBMRAS.Domain.Services;

public sealed class PublicService(IPublicRepository repository) : IPublicService
{
    private static readonly BloodAvailabilityQueryValidator BloodValidator = new();
    private static readonly ResourceAvailabilityQueryValidator ResourceValidator = new();
    private static readonly PublicFacilityQueryValidator FacilityValidator = new();

    public async Task<PublicLookupsDto> GetLookupsAsync(CancellationToken ct = default)
    {
        var sets = await repository.GetLookupsAsync(ct);
        IReadOnlyList<object> Rows(int i) => SqlRows.Set(sets, i).Select(CamelRow).Cast<object>().ToArray();
        IReadOnlyList<string> Values(int i, params string[] keys) => SqlRows.Set(sets, i)
            .Select(r => keys.Select(k => Text(r, k)).FirstOrDefault(v => !string.IsNullOrWhiteSpace(v)) ?? "")
            .Where(s => s.Length > 0).ToArray();
        return new PublicLookupsDto(Rows(0), Rows(1), Rows(2), Rows(3), Rows(4),
            Values(5, "AboGroup", "Value", "Name"), Values(6, "RhFactor", "Value", "Name"),
            Values(7, "Urgency", "Value", "Name"), Values(8, "Status", "RequestStatus", "Value", "Name"),
            Values(9, "FreshnessStatus", "Status", "Value", "Name"));
    }

    public async Task<PublicStatsDto> GetStatsAsync(CancellationToken ct = default)
    {
        var row = await repository.GetStatsAsync(ct) ?? new Dictionary<string, object?>();
        return new PublicStatsDto(Int(row, "VerifiedFacilities"), Int(row, "Hospitals"), Int(row, "BloodBanks"),
            Dec(row, "UnitsAvailable") ?? 0, Dec(row, "FreshPercent") ?? 0, Int(row, "OpenRequests"),
            Int(row, "FulfilledRequests"), Date(row, "LastUpdatedAt"));
    }

    public async Task<PagedResult<BloodAvailabilityDto>> SearchBloodAsync(BloodAvailabilityQuery query, CancellationToken ct = default)
    {
        Validate(BloodValidator, query);
        var paged = await repository.SearchBloodAsync(query with { Search = Trim(query.Search), AboGroup = Trim(query.AboGroup), RhFactor = Trim(query.RhFactor) }, ct);
        return new PagedResult<BloodAvailabilityDto>(paged.Items.Select(MapBlood).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    public async Task<PagedResult<ResourceAvailabilityDto>> SearchResourcesAsync(ResourceAvailabilityQuery query, CancellationToken ct = default)
    {
        Validate(ResourceValidator, query);
        var paged = await repository.SearchResourcesAsync(query with { Search = Trim(query.Search) }, ct);
        return new PagedResult<ResourceAvailabilityDto>(paged.Items.Select(MapResource).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    public async Task<PagedResult<PublicFacilityDto>> SearchFacilitiesAsync(PublicFacilityQuery query, CancellationToken ct = default)
    {
        Validate(FacilityValidator, query);
        var paged = await repository.SearchFacilitiesAsync(query with { Search = Trim(query.Search), FacilityType = Trim(query.FacilityType) }, ct);
        return new PagedResult<PublicFacilityDto>(paged.Items.Select(r => new PublicFacilityDto(
            Int(r, "FacilityId"), Text(r, "FacilityCode"), Text(r, "Name"), Text(r, "FacilityType"), Text(r, "AddressLine"),
            Text(r, "AreaName"), Text(r, "City"), Text(r, "ContactPhone"), NullableText(r, "ContactEmail"), Bool(r, "Is24x7"),
            Dec(r, "QualityScore"), Date(r, "LastUpdateAt"))).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    private static BloodAvailabilityDto MapBlood(IDictionary<string, object?> r) => new(
        Int(r, "InventoryId"), Int(r, "FacilityId"), Text(r, "FacilityName"), Text(r, "FacilityType"), Int(r, "AreaId"),
        Text(r, "AreaName"), Text(r, "City"), Text(r, "AddressLine"), Text(r, "ContactPhone"), Bool(r, "Is24x7"),
        Int(r, "ComponentId"), Text(r, "ComponentCode"), Text(r, "ComponentName"), Text(r, "AboGroup"), Text(r, "RhFactor"),
        Text(r, "BloodGroup"), Dec(r, "Quantity") ?? 0, Text(r, "UnitCode"), Text(r, "AvailabilityStatus"),
        Text(r, "FreshnessStatus"), Text(r, "VerificationStatus"), Text(r, "SourceType"), Date(r, "LastUpdatedAt"),
        Date(r, "ValidUntil"), IntNullable(r, "MinutesSinceUpdate"), Date(r, "EarliestExpiryDate"), Dec(r, "QualityScore"));

    private static ResourceAvailabilityDto MapResource(IDictionary<string, object?> r) => new(
        Int(r, "ResourceInventoryId"), Int(r, "FacilityId"), Text(r, "FacilityName"), Int(r, "AreaId"), Text(r, "AreaName"),
        Text(r, "City"), Text(r, "ContactPhone"), Bool(r, "Is24x7"), Text(r, "CategoryName"), Int(r, "ResourceTypeId"),
        Text(r, "ResourceTypeCode"), Text(r, "ResourceTypeName"), Dec(r, "TotalQuantity") ?? 0, Dec(r, "AvailableQuantity") ?? 0,
        Text(r, "UnitCode"), Text(r, "OperationalStatus"), Text(r, "FreshnessStatus"), Text(r, "VerificationStatus"),
        Date(r, "LastUpdatedAt"), Date(r, "ValidUntil"), IntNullable(r, "MinutesSinceUpdate"), NullableText(r, "Notes"));

    private static Dictionary<string, object?> CamelRow(IDictionary<string, object?> row)
        => row.ToDictionary(p => JsonNamingPolicy.CamelCase.ConvertName(p.Key), p => p.Value);
    private static string Text(IDictionary<string, object?> row, string key) => SqlRows.Str(row, key);
    private static string? NullableText(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is null or DBNull ? null : SqlRows.Str(row, key);
    private static int Int(IDictionary<string, object?> row, string key) => SqlRows.Int(row, key);
    private static int? IntNullable(IDictionary<string, object?> row, string key) => SqlRows.ToInt(SqlRows.Value(row, key));
    private static decimal? Dec(IDictionary<string, object?> row, string key) => SqlRows.Dec(SqlRows.Value(row, key));
    private static bool Bool(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        bool value => value,
        string value => value == "1" || bool.TryParse(value, out var parsed) && parsed,
        var value when SqlRows.IsNumeric(value) => Convert.ToDecimal(value, CultureInfo.InvariantCulture) != 0,
        _ => false,
    };
    private static DateTime? Date(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        DateTime value => DateTime.SpecifyKind(value, DateTimeKind.Utc),
        DateTimeOffset value => value.UtcDateTime,
        _ => null,
    };
    private static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static void Validate<T>(IValidator<T> validator, T query)
    {
        var result = validator.Validate(query);
        if (!result.IsValid) throw AppException.Validation("Validation failed.", result.Errors.Select(e => e.ErrorMessage).Distinct());
    }
}
