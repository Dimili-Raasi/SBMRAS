using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

/// <summary>Row = SQL result row keyed by column name (case-insensitive).</summary>
public interface IFacilityRepository
{
    Task<PagedResult<IDictionary<string, object?>>> SearchMineAsync(int actorUserId, FacilitySearchQuery query, CancellationToken ct = default);
    /// <summary>usp_Facility_GetById → sets: facility, users, quality.</summary>
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetByIdAsync(int actorUserId, int facilityId, CancellationToken ct = default);
    Task<IDictionary<string, object?>?> UpdateAsync(int actorUserId, int facilityId, FacilityUpdateDto dto, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetSnapshotsAsync(int actorUserId, int facilityId, string? kind, int? top, CancellationToken ct = default);
}

public interface IInventoryRepository
{
    Task<IReadOnlyList<IDictionary<string, object?>>> GetResourcesAsync(int actorUserId, int facilityId, CancellationToken ct = default);
    Task<IDictionary<string, object?>?> SubmitResourceUpdateAsync(int actorUserId, int facilityId, ResourceUpdateDto dto, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetBloodStockAsync(int actorUserId, int facilityId, CancellationToken ct = default);
    Task<IDictionary<string, object?>?> SubmitBloodStockUpdateAsync(int actorUserId, int facilityId, BloodStockUpdateDto dto, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> ConfirmBloodStockAsync(int actorUserId, int facilityId, IReadOnlyList<int> inventoryIds, string correlationId, CancellationToken ct = default);
}

public interface IInventoryChangeRepository
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, InventoryChangeSearchQuery query, CancellationToken ct = default);
    Task<IDictionary<string, object?>?> DecideAsync(int actorUserId, int changeId, InventoryChangeDecisionDto dto, string correlationId, CancellationToken ct = default);
}

public interface IImportRepository
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, ImportSearchQuery query, CancellationToken ct = default);
    /// <summary>usp_Import_Stage → sets: batch, rows.</summary>
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> StageAsync(int actorUserId, ImportCreateDto dto, string rowsJson, string correlationId, CancellationToken ct = default);
    /// <summary>usp_Import_GetById → sets: batch, rows.</summary>
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetByIdAsync(int actorUserId, int batchId, CancellationToken ct = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> CommitAsync(int actorUserId, int batchId, string? idempotencyKey, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> CancelAsync(int actorUserId, int batchId, string correlationId, CancellationToken ct = default);
}

public interface IDataQualityRepository
{
    /// <summary>usp_DataQuality_GetSummary → sets: overall, facilities.</summary>
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetSummaryAsync(int actorUserId, int? facilityId, CancellationToken ct = default);
    Task<PagedResult<IDictionary<string, object?>>> SearchIssuesAsync(int actorUserId, DataQualityIssueQuery query, CancellationToken ct = default);
    Task<IDictionary<string, object?>?> ResolveIssueAsync(int actorUserId, int issueId, DataQualityResolveDto dto, string correlationId, CancellationToken ct = default);
    Task<IDictionary<string, object?>?> ScanAsync(int actorUserId, int? facilityId, string correlationId, CancellationToken ct = default);
}
