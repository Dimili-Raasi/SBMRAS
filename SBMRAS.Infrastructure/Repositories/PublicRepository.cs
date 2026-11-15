using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.Infrastructure.Repositories;

public sealed class PublicRepository(IStoredProcedureExecutor executor) : IPublicRepository
{
    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetLookupsAsync(CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.LookupsGet, 0, cancellationToken: ct);

    public Task<IDictionary<string, object?>?> GetStatsAsync(CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.PublicGetStats, 0, cancellationToken: ct);

    public Task<PagedResult<IDictionary<string, object?>>> SearchBloodAsync(BloodAvailabilityQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.PublicSearchBlood, 0, new Dictionary<string, object?>
        {
            ["AboGroup"] = query.AboGroup,
            ["RhFactor"] = query.RhFactor,
            ["ComponentId"] = query.ComponentId,
            ["AreaId"] = query.AreaId,
            ["Search"] = query.Search,
            ["FreshOnly"] = query.FreshOnly,
            ["MinQuantity"] = query.MinQuantity,
        }, query.Page, query.PageSize, ct);

    public Task<PagedResult<IDictionary<string, object?>>> SearchResourcesAsync(ResourceAvailabilityQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.PublicSearchResources, 0, new Dictionary<string, object?>
        {
            ["CategoryId"] = query.CategoryId,
            ["ResourceTypeId"] = query.ResourceTypeId,
            ["AreaId"] = query.AreaId,
            ["Search"] = query.Search,
            ["AvailableOnly"] = query.AvailableOnly,
            ["FreshOnly"] = query.FreshOnly,
        }, query.Page, query.PageSize, ct);

    public Task<PagedResult<IDictionary<string, object?>>> SearchFacilitiesAsync(PublicFacilityQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.PublicSearchFacilities, 0, new Dictionary<string, object?>
        {
            ["FacilityType"] = query.FacilityType,
            ["AreaId"] = query.AreaId,
            ["Search"] = query.Search,
        }, query.Page, query.PageSize, ct);
}
