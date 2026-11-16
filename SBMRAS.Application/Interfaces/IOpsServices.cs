using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

public interface IFacilityService
{
    Task<PagedResult<IDictionary<string, object?>>> SearchMineAsync(CurrentUser actor, FacilitySearchQuery query, CancellationToken ct = default);
    Task<IDictionary<string, object?>> GetByIdAsync(CurrentUser actor, int facilityId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> UpdateAsync(CurrentUser actor, int facilityId, FacilityUpdateDto body, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetSnapshotsAsync(CurrentUser actor, int facilityId, InventoryHistoryQuery query, CancellationToken ct = default);
}

public interface IInventoryService
{
    Task<IReadOnlyList<IDictionary<string, object?>>> GetResourcesAsync(CurrentUser actor, int facilityId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> SubmitResourceUpdateAsync(CurrentUser actor, int facilityId, ResourceUpdateDto body, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetBloodStockAsync(CurrentUser actor, int facilityId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> SubmitBloodStockUpdateAsync(CurrentUser actor, int facilityId, BloodStockUpdateDto body, string correlationId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> ConfirmBloodStockAsync(CurrentUser actor, int facilityId, BloodStockConfirmDto body, string correlationId, CancellationToken ct = default);
}

public interface IInventoryChangeService
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(CurrentUser actor, InventoryChangeSearchQuery query, CancellationToken ct = default);
    Task<IDictionary<string, object?>> DecideAsync(CurrentUser actor, int changeId, InventoryChangeDecisionDto body, string correlationId, CancellationToken ct = default);
}

public interface IImportService
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(CurrentUser actor, ImportSearchQuery query, CancellationToken ct = default);
    Task<IDictionary<string, object?>> StageAsync(CurrentUser actor, ImportCreateDto body, string correlationId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> GetByIdAsync(CurrentUser actor, int batchId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> CommitAsync(CurrentUser actor, int batchId, string? idempotencyKey, string correlationId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> CancelAsync(CurrentUser actor, int batchId, string correlationId, CancellationToken ct = default);
}

public interface IDataQualityService
{
    Task<IDictionary<string, object?>> GetSummaryAsync(CurrentUser actor, DataQualitySummaryQuery query, CancellationToken ct = default);
    Task<PagedResult<IDictionary<string, object?>>> SearchIssuesAsync(CurrentUser actor, DataQualityIssueQuery query, CancellationToken ct = default);
    Task<IDictionary<string, object?>> ResolveIssueAsync(CurrentUser actor, int issueId, DataQualityResolveDto body, string correlationId, CancellationToken ct = default);
    Task<IDictionary<string, object?>> ScanAsync(CurrentUser actor, DataQualityScanDto body, string correlationId, CancellationToken ct = default);
}
