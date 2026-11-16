using System.Text.Json;
using FluentValidation;
using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;
using SBMRAS.Application.Validators;

namespace SBMRAS.Domain.Services;

public sealed class FacilityService(IFacilityRepository repository) : IFacilityService
{
    private static readonly FacilitySearchQueryValidator SearchValidator = new();
    private static readonly FacilityUpdateValidator UpdateValidator = new();
    private static readonly InventoryHistoryQueryValidator HistoryValidator = new();

    public async Task<PagedResult<IDictionary<string, object?>>> SearchMineAsync(CurrentUser actor, FacilitySearchQuery query, CancellationToken ct = default)
    {
        Validate(SearchValidator, query);
        return CamelPage(await repository.SearchMineAsync(actor.UserId, query with { Search = Trim(query.Search), FacilityType = Trim(query.FacilityType) }, ct));
    }

    public async Task<IDictionary<string, object?>> GetByIdAsync(CurrentUser actor, int facilityId, CancellationToken ct = default)
    {
        RequireId(facilityId, "Facility");
        var sets = await repository.GetByIdAsync(actor.UserId, facilityId, ct);
        var facility = SqlRows.Set(sets, 0).FirstOrDefault() ?? throw AppException.NotFound("Facility not found.");
        var users = SqlRows.Set(sets, 1).Select(CamelRow).ToArray();
        var quality = SqlRows.Set(sets, 2).FirstOrDefault();
        return new Dictionary<string, object?>
        {
            ["facility"] = CamelRow(facility),
            ["users"] = users,
            ["quality"] = quality is null ? null : CamelRow(quality),
        };
    }

    public async Task<IDictionary<string, object?>> UpdateAsync(CurrentUser actor, int facilityId, FacilityUpdateDto body, string correlationId,
        CancellationToken ct = default)
    {
        RequireId(facilityId, "Facility");
        Validate(UpdateValidator, body);
        var normalized = body with
        {
            Name = body.Name.Trim(), AddressLine = body.AddressLine.Trim(), City = body.City.Trim(),
            ContactPhone = body.ContactPhone.Trim(), LicenseNo = Trim(body.LicenseNo), Pincode = Trim(body.Pincode),
            ContactEmail = Trim(body.ContactEmail),
        };
        var row = await repository.UpdateAsync(actor.UserId, facilityId, normalized, correlationId, ct);
        return row is null ? throw AppException.NotFound("Facility not found.") : CamelRow(row);
    }

    public async Task<IReadOnlyList<IDictionary<string, object?>>> GetSnapshotsAsync(CurrentUser actor, int facilityId,
        InventoryHistoryQuery query, CancellationToken ct = default)
    {
        RequireId(facilityId, "Facility");
        Validate(HistoryValidator, query);
        return (await repository.GetSnapshotsAsync(actor.UserId, facilityId, query.Kind, query.Top, ct)).Select(CamelRow).ToArray();
    }

    internal static void Validate<T>(IValidator<T> validator, T body)
    {
        if (body is null) throw AppException.BadRequest("Request body is required.");
        var result = validator.Validate(body);
        if (!result.IsValid) throw AppException.Validation("Validation failed.", result.Errors.Select(e => e.ErrorMessage).Distinct());
    }

    internal static int RequireId(int id, string entity)
        => id > 0 ? id : throw AppException.BadRequest($"{entity} id is invalid.");

    internal static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    internal static Dictionary<string, object?> CamelRow(IDictionary<string, object?> row)
        => row.ToDictionary(p => JsonNamingPolicy.CamelCase.ConvertName(p.Key), p => p.Value);

    internal static PagedResult<IDictionary<string, object?>> CamelPage(PagedResult<IDictionary<string, object?>> result)
        => new(result.Items.Select(CamelRow).ToArray(), result.TotalCount, result.Page, result.PageSize);
}

public sealed class InventoryService(IInventoryRepository repository) : IInventoryService
{
    private static readonly ResourceUpdateValidator ResourceValidator = new();
    private static readonly BloodStockUpdateValidator BloodValidator = new();
    private static readonly BloodStockConfirmValidator ConfirmValidator = new();

    public async Task<IReadOnlyList<IDictionary<string, object?>>> GetResourcesAsync(CurrentUser actor, int facilityId, CancellationToken ct = default)
        => (await repository.GetResourcesAsync(actor.UserId, FacilityService.RequireId(facilityId, "Facility"), ct))
            .Select(FacilityService.CamelRow).ToArray();

    public async Task<IDictionary<string, object?>> SubmitResourceUpdateAsync(CurrentUser actor, int facilityId, ResourceUpdateDto body,
        string correlationId, CancellationToken ct = default)
    {
        FacilityService.RequireId(facilityId, "Facility");
        FacilityService.Validate(ResourceValidator, body);
        var normalized = body with
        {
            OperationalStatus = body.OperationalStatus.Trim(), Notes = FacilityService.Trim(body.Notes), Reason = FacilityService.Trim(body.Reason),
        };
        return Required(await repository.SubmitResourceUpdateAsync(actor.UserId, facilityId, normalized, correlationId, ct), "Resource update");
    }

    public async Task<IReadOnlyList<IDictionary<string, object?>>> GetBloodStockAsync(CurrentUser actor, int facilityId, CancellationToken ct = default)
        => (await repository.GetBloodStockAsync(actor.UserId, FacilityService.RequireId(facilityId, "Facility"), ct))
            .Select(FacilityService.CamelRow).ToArray();

    public async Task<IDictionary<string, object?>> SubmitBloodStockUpdateAsync(CurrentUser actor, int facilityId, BloodStockUpdateDto body,
        string correlationId, CancellationToken ct = default)
    {
        FacilityService.RequireId(facilityId, "Facility");
        FacilityService.Validate(BloodValidator, body);
        var normalized = body with
        {
            AboGroup = body.AboGroup.Trim(), RhFactor = body.RhFactor.Trim(), Reason = FacilityService.Trim(body.Reason),
        };
        return Required(await repository.SubmitBloodStockUpdateAsync(actor.UserId, facilityId, normalized, correlationId, ct), "Blood stock update");
    }

    public async Task<IReadOnlyList<IDictionary<string, object?>>> ConfirmBloodStockAsync(CurrentUser actor, int facilityId,
        BloodStockConfirmDto body, string correlationId, CancellationToken ct = default)
    {
        FacilityService.RequireId(facilityId, "Facility");
        FacilityService.Validate(ConfirmValidator, body);
        var ids = body.InventoryIds.Distinct().ToArray();
        if (ids.Length != body.InventoryIds.Count) throw AppException.BadRequest("Inventory ids must be unique.");
        return (await repository.ConfirmBloodStockAsync(actor.UserId, facilityId, ids, correlationId, ct))
            .Select(FacilityService.CamelRow).ToArray();
    }

    private static IDictionary<string, object?> Required(IDictionary<string, object?>? row, string entity)
        => row is null ? throw AppException.NotFound($"{entity} was not found.") : FacilityService.CamelRow(row);
}

public sealed class InventoryChangeService(IInventoryChangeRepository repository) : IInventoryChangeService
{
    private static readonly InventoryChangeSearchQueryValidator SearchValidator = new();
    private static readonly InventoryChangeDecisionValidator DecisionValidator = new();

    public async Task<PagedResult<IDictionary<string, object?>>> SearchAsync(CurrentUser actor, InventoryChangeSearchQuery query, CancellationToken ct = default)
    {
        FacilityService.Validate(SearchValidator, query);
        return FacilityService.CamelPage(await repository.SearchAsync(actor.UserId, query with
        {
            Status = FacilityService.Trim(query.Status), InventoryKind = FacilityService.Trim(query.InventoryKind),
        }, ct));
    }

    public async Task<IDictionary<string, object?>> DecideAsync(CurrentUser actor, int changeId, InventoryChangeDecisionDto body,
        string correlationId, CancellationToken ct = default)
    {
        FacilityService.RequireId(changeId, "Inventory change");
        FacilityService.Validate(DecisionValidator, body);
        var row = await repository.DecideAsync(actor.UserId, changeId,
            body with { Decision = body.Decision.Trim(), Reason = FacilityService.Trim(body.Reason) }, correlationId, ct);
        return row is null ? throw AppException.NotFound("Inventory change not found.") : FacilityService.CamelRow(row);
    }
}

public sealed class ImportService(IImportRepository repository) : IImportService
{
    private static readonly ImportSearchQueryValidator SearchValidator = new();
    private static readonly ImportCreateValidator CreateValidator = new();

    public async Task<PagedResult<IDictionary<string, object?>>> SearchAsync(CurrentUser actor, ImportSearchQuery query, CancellationToken ct = default)
    {
        FacilityService.Validate(SearchValidator, query);
        return FacilityService.CamelPage(await repository.SearchAsync(actor.UserId, query with { Status = FacilityService.Trim(query.Status) }, ct));
    }

    public async Task<IDictionary<string, object?>> StageAsync(CurrentUser actor, ImportCreateDto body, string correlationId, CancellationToken ct = default)
    {
        FacilityService.Validate(CreateValidator, body);
        var normalized = body with
        {
            InventoryKind = body.InventoryKind.Trim(), FileName = body.FileName.Trim(), FileHash = body.FileHash.Trim(),
        };
        var rowsJson = JsonSerializer.Serialize(normalized.Rows, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        return Detail(await repository.StageAsync(actor.UserId, normalized, rowsJson, correlationId, ct));
    }

    public async Task<IDictionary<string, object?>> GetByIdAsync(CurrentUser actor, int batchId, CancellationToken ct = default)
    {
        FacilityService.RequireId(batchId, "Import batch");
        return Detail(await repository.GetByIdAsync(actor.UserId, batchId, ct));
    }

    public async Task<IDictionary<string, object?>> CommitAsync(CurrentUser actor, int batchId, string? idempotencyKey, string correlationId,
        CancellationToken ct = default)
    {
        FacilityService.RequireId(batchId, "Import batch");
        idempotencyKey = FacilityService.Trim(idempotencyKey);
        if (idempotencyKey is { Length: > ImportValues.MaxIdempotencyKeyLength })
            throw AppException.BadRequest($"Idempotency-Key must not exceed {ImportValues.MaxIdempotencyKeyLength} characters.");
        return Detail(await repository.CommitAsync(actor.UserId, batchId, idempotencyKey, correlationId, ct));
    }

    public async Task<IDictionary<string, object?>> CancelAsync(CurrentUser actor, int batchId, string correlationId, CancellationToken ct = default)
    {
        FacilityService.RequireId(batchId, "Import batch");
        return Detail(await repository.CancelAsync(actor.UserId, batchId, correlationId, ct));
    }

    private static IDictionary<string, object?> Detail(IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>> sets)
    {
        var batch = SqlRows.Set(sets, 0).FirstOrDefault() ?? throw AppException.NotFound("Import batch not found.");
        return new Dictionary<string, object?>
        {
            ["batch"] = FacilityService.CamelRow(batch),
            ["rows"] = SqlRows.Set(sets, 1).Select(FacilityService.CamelRow).ToArray(),
        };
    }
}

public sealed class DataQualityService(IDataQualityRepository repository) : IDataQualityService
{
    private static readonly DataQualityIssueQueryValidator SearchValidator = new();
    private static readonly DataQualityResolveValidator ResolveValidator = new();
    private static readonly DataQualityScanValidator ScanValidator = new();

    public async Task<IDictionary<string, object?>> GetSummaryAsync(CurrentUser actor, DataQualitySummaryQuery query, CancellationToken ct = default)
    {
        if (query.FacilityId is <= 0) throw AppException.BadRequest("Facility id is invalid.");
        var sets = await repository.GetSummaryAsync(actor.UserId, query.FacilityId, ct);
        var overall = SqlRows.Set(sets, 0).FirstOrDefault();
        return new Dictionary<string, object?>
        {
            ["overall"] = overall is null ? null : FacilityService.CamelRow(overall),
            ["facilities"] = SqlRows.Set(sets, 1).Select(FacilityService.CamelRow).ToArray(),
        };
    }

    public async Task<PagedResult<IDictionary<string, object?>>> SearchIssuesAsync(CurrentUser actor, DataQualityIssueQuery query, CancellationToken ct = default)
    {
        FacilityService.Validate(SearchValidator, query);
        return FacilityService.CamelPage(await repository.SearchIssuesAsync(actor.UserId, query with
        {
            Status = FacilityService.Trim(query.Status), Severity = FacilityService.Trim(query.Severity), IssueCode = FacilityService.Trim(query.IssueCode),
        }, ct));
    }

    public async Task<IDictionary<string, object?>> ResolveIssueAsync(CurrentUser actor, int issueId, DataQualityResolveDto body,
        string correlationId, CancellationToken ct = default)
    {
        FacilityService.RequireId(issueId, "Issue");
        FacilityService.Validate(ResolveValidator, body);
        var row = await repository.ResolveIssueAsync(actor.UserId, issueId, body with { Resolution = FacilityService.Trim(body.Resolution) },
            correlationId, ct);
        return row is null ? throw AppException.NotFound("Data quality issue not found.") : FacilityService.CamelRow(row);
    }

    public async Task<IDictionary<string, object?>> ScanAsync(CurrentUser actor, DataQualityScanDto body, string correlationId, CancellationToken ct = default)
    {
        FacilityService.Validate(ScanValidator, body);
        var row = await repository.ScanAsync(actor.UserId, body.FacilityId, correlationId, ct);
        return row is null ? new Dictionary<string, object?>() : FacilityService.CamelRow(row);
    }
}
