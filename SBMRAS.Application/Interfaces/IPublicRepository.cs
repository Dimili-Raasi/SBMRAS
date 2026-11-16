using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

public interface IPublicRepository
{
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetLookupsAsync(CancellationToken ct = default);
    Task<IDictionary<string, object?>?> GetStatsAsync(CancellationToken ct = default);
    Task<PagedResult<IDictionary<string, object?>>> SearchBloodAsync(BloodAvailabilityQuery query, CancellationToken ct = default);
    Task<PagedResult<IDictionary<string, object?>>> SearchResourcesAsync(ResourceAvailabilityQuery query, CancellationToken ct = default);
    Task<PagedResult<IDictionary<string, object?>>> SearchFacilitiesAsync(PublicFacilityQuery query, CancellationToken ct = default);
}

public interface IPublicService
{
    Task<PublicLookupsDto> GetLookupsAsync(CancellationToken ct = default);
    Task<PublicStatsDto> GetStatsAsync(CancellationToken ct = default);
    Task<PagedResult<BloodAvailabilityDto>> SearchBloodAsync(BloodAvailabilityQuery query, CancellationToken ct = default);
    Task<PagedResult<ResourceAvailabilityDto>> SearchResourcesAsync(ResourceAvailabilityQuery query, CancellationToken ct = default);
    Task<PagedResult<PublicFacilityDto>> SearchFacilitiesAsync(PublicFacilityQuery query, CancellationToken ct = default);
}
