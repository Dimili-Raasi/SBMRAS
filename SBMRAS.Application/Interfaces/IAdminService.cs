using System.Text.Json;
using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

/// <summary>Administration use cases (contract §6 Admin). Implemented in SBMRAS.Domain.</summary>
public interface IAdminService
{
    Task<PagedResult<AdminUserDto>> SearchUsersAsync(CurrentUser actor, AdminUserSearchQuery query, CancellationToken cancellationToken = default);
    Task<AdminUserDto> GetUserAsync(CurrentUser actor, int userId, CancellationToken cancellationToken = default);
    Task<AdminUserDto> CreateUserAsync(CurrentUser actor, UserSaveDto body, CancellationToken cancellationToken = default);
    Task<AdminUserDto> UpdateUserAsync(CurrentUser actor, int userId, UserSaveDto body, CancellationToken cancellationToken = default);
    Task<AdminUserDto> SetUserStatusAsync(CurrentUser actor, int userId, UserStatusDto body, CancellationToken cancellationToken = default);
    Task<AdminUserDto> SetUserFacilitiesAsync(CurrentUser actor, int userId, UserFacilitiesDto body, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<AdminRoleDto>> GetRolesAsync(CurrentUser actor, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<AdminPermissionDto>> GetPermissionsAsync(CurrentUser actor, CancellationToken cancellationToken = default);
    Task<AdminRoleDto> UpdateRolePermissionsAsync(CurrentUser actor, int roleId, RolePermissionsDto body, CancellationToken cancellationToken = default);

    Task<PagedResult<IDictionary<string, object?>>> SearchFacilitiesAsync(CurrentUser actor, AdminFacilitySearchQuery query, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>> CreateFacilityAsync(CurrentUser actor, FacilitySaveDto body, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>> UpdateFacilityAsync(CurrentUser actor, int facilityId, FacilitySaveDto body, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>> VerifyFacilityAsync(CurrentUser actor, int facilityId, FacilityVerifyDto body, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IDictionary<string, object?>>> GetMasterDataAsync(CurrentUser actor, string type, CancellationToken cancellationToken = default);
    /// <summary>Upserts one row; body "id" (or the typed key, e.g. "areaId") 0/null = insert.</summary>
    Task<IDictionary<string, object?>> SaveMasterDataAsync(CurrentUser actor, string type, JsonElement body, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IDictionary<string, object?>>> GetSettingsAsync(CurrentUser actor, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> UpdateSettingsAsync(CurrentUser actor, SettingsUpdateDto body, CancellationToken cancellationToken = default);
}
