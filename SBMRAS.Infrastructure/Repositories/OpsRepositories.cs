using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.Infrastructure.Repositories;

public sealed class FacilityRepository(IStoredProcedureExecutor executor) : IFacilityRepository
{
    public Task<PagedResult<IDictionary<string, object?>>> SearchMineAsync(int actorUserId, FacilitySearchQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.FacilitySearchMine, actorUserId,
            new Dictionary<string, object?> { ["FacilityType"] = query.FacilityType, ["Search"] = query.Search }, query.Page, query.PageSize, ct);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetByIdAsync(int actorUserId, int facilityId, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.FacilityGetById, actorUserId,
            new Dictionary<string, object?> { ["FacilityId"] = facilityId }, ct);

    public Task<IDictionary<string, object?>?> UpdateAsync(int actorUserId, int facilityId, FacilityUpdateDto dto, string correlationId,
        CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.FacilityUpdate, actorUserId, new Dictionary<string, object?>
        {
            ["FacilityId"] = facilityId, ["Name"] = dto.Name, ["LicenseNo"] = dto.LicenseNo, ["AddressLine"] = dto.AddressLine,
            ["AreaId"] = dto.AreaId, ["City"] = dto.City, ["Pincode"] = dto.Pincode, ["Latitude"] = dto.Latitude,
            ["Longitude"] = dto.Longitude, ["ContactPhone"] = dto.ContactPhone, ["ContactEmail"] = dto.ContactEmail,
            ["Is24x7"] = dto.Is24x7, ["RowVersion"] = RowVersion.FromBase64(dto.RowVersion), ["CorrelationId"] = correlationId,
        }, ct);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetSnapshotsAsync(int actorUserId, int facilityId, string? kind, int? top,
        CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.InventoryGetSnapshots, actorUserId,
            new Dictionary<string, object?> { ["FacilityId"] = facilityId, ["Kind"] = kind, ["Top"] = top }, ct);
}

public sealed class InventoryRepository(IStoredProcedureExecutor executor) : IInventoryRepository
{
    public Task<IReadOnlyList<IDictionary<string, object?>>> GetResourcesAsync(int actorUserId, int facilityId, CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.ResourceGetByFacility, actorUserId, new Dictionary<string, object?> { ["FacilityId"] = facilityId }, ct);

    public Task<IDictionary<string, object?>?> SubmitResourceUpdateAsync(int actorUserId, int facilityId, ResourceUpdateDto dto,
        string correlationId, CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.ResourceSubmitUpdate, actorUserId, new Dictionary<string, object?>
        {
            ["FacilityId"] = facilityId, ["ResourceTypeId"] = dto.ResourceTypeId, ["TotalQuantity"] = dto.TotalQuantity,
            ["AvailableQuantity"] = dto.AvailableQuantity, ["OperationalStatus"] = dto.OperationalStatus, ["ValidUntil"] = dto.ValidUntil,
            ["Notes"] = dto.Notes, ["Reason"] = dto.Reason, ["RowVersion"] = RowVersion.FromBase64(dto.RowVersion), ["CorrelationId"] = correlationId,
        }, ct);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetBloodStockAsync(int actorUserId, int facilityId, CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.BloodStockGetByFacility, actorUserId, new Dictionary<string, object?> { ["FacilityId"] = facilityId }, ct);

    public Task<IDictionary<string, object?>?> SubmitBloodStockUpdateAsync(int actorUserId, int facilityId, BloodStockUpdateDto dto,
        string correlationId, CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.BloodStockSubmitUpdate, actorUserId, new Dictionary<string, object?>
        {
            ["FacilityId"] = facilityId, ["ComponentId"] = dto.ComponentId, ["AboGroup"] = dto.AboGroup, ["RhFactor"] = dto.RhFactor,
            ["Quantity"] = dto.Quantity, ["EarliestExpiryDate"] = dto.EarliestExpiryDate, ["ValidUntil"] = dto.ValidUntil,
            ["Reason"] = dto.Reason, ["RowVersion"] = RowVersion.FromBase64(dto.RowVersion), ["CorrelationId"] = correlationId,
        }, ct);

    public Task<IReadOnlyList<IDictionary<string, object?>>> ConfirmBloodStockAsync(int actorUserId, int facilityId,
        IReadOnlyList<int> inventoryIds, string correlationId, CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.BloodStockConfirmCurrent, actorUserId, new Dictionary<string, object?>
        {
            ["FacilityId"] = facilityId, ["InventoryIds"] = string.Join(',', inventoryIds), ["CorrelationId"] = correlationId,
        }, ct);
}

public sealed class InventoryChangeRepository(IStoredProcedureExecutor executor) : IInventoryChangeRepository
{
    public Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, InventoryChangeSearchQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.ChangeSearch, actorUserId, new Dictionary<string, object?>
        {
            ["Status"] = query.Status, ["FacilityId"] = query.FacilityId, ["InventoryKind"] = query.InventoryKind,
        }, query.Page, query.PageSize, ct);

    public Task<IDictionary<string, object?>?> DecideAsync(int actorUserId, int changeId, InventoryChangeDecisionDto dto, string correlationId,
        CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.ChangeDecide, actorUserId, new Dictionary<string, object?>
        {
            ["ChangeId"] = changeId, ["Decision"] = dto.Decision, ["Reason"] = dto.Reason, ["CorrelationId"] = correlationId,
        }, ct);
}

public sealed class ImportRepository(IStoredProcedureExecutor executor) : IImportRepository
{
    public Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, ImportSearchQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.ImportSearch, actorUserId,
            new Dictionary<string, object?> { ["FacilityId"] = query.FacilityId, ["Status"] = query.Status }, query.Page, query.PageSize, ct);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> StageAsync(int actorUserId, ImportCreateDto dto, string rowsJson,
        string correlationId, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.ImportStage, actorUserId, new Dictionary<string, object?>
        {
            ["FacilityId"] = dto.FacilityId, ["InventoryKind"] = dto.InventoryKind, ["FileName"] = dto.FileName,
            ["FileHash"] = dto.FileHash, ["RowsJson"] = rowsJson, ["CorrelationId"] = correlationId,
        }, ct);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetByIdAsync(int actorUserId, int batchId, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.ImportGetById, actorUserId, new Dictionary<string, object?> { ["BatchId"] = batchId }, ct);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> CommitAsync(int actorUserId, int batchId, string? idempotencyKey,
        string correlationId, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.ImportCommit, actorUserId, new Dictionary<string, object?>
        {
            ["BatchId"] = batchId, ["IdempotencyKey"] = idempotencyKey, ["CorrelationId"] = correlationId,
        }, ct);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> CancelAsync(int actorUserId, int batchId, string correlationId,
        CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.ImportCancel, actorUserId,
            new Dictionary<string, object?> { ["BatchId"] = batchId, ["CorrelationId"] = correlationId }, ct);
}

public sealed class DataQualityRepository(IStoredProcedureExecutor executor) : IDataQualityRepository
{
    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetSummaryAsync(int actorUserId, int? facilityId, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.DataQualityGetSummary, actorUserId, new Dictionary<string, object?> { ["FacilityId"] = facilityId }, ct);

    public Task<PagedResult<IDictionary<string, object?>>> SearchIssuesAsync(int actorUserId, DataQualityIssueQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.DataQualitySearchIssues, actorUserId, new Dictionary<string, object?>
        {
            ["Status"] = query.Status, ["Severity"] = query.Severity, ["IssueCode"] = query.IssueCode, ["FacilityId"] = query.FacilityId,
        }, query.Page, query.PageSize, ct);

    public Task<IDictionary<string, object?>?> ResolveIssueAsync(int actorUserId, int issueId, DataQualityResolveDto dto, string correlationId,
        CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.DataQualityResolveIssue, actorUserId, new Dictionary<string, object?>
        {
            ["IssueId"] = issueId, ["Resolution"] = dto.Resolution, ["Dismiss"] = dto.Dismiss, ["CorrelationId"] = correlationId,
        }, ct);

    public Task<IDictionary<string, object?>?> ScanAsync(int actorUserId, int? facilityId, string correlationId, CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.DataQualityScan, actorUserId, new Dictionary<string, object?>
        {
            ["FacilityId"] = facilityId, ["CorrelationId"] = correlationId,
        }, ct);
}
