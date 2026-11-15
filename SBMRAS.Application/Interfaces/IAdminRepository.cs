using SBMRAS.Application.Common;

namespace SBMRAS.Application.Interfaces;

/// <summary>
/// Administration data access (11_StoredProcedures_Admin.sql). Rows are returned as dictionaries keyed by SQL column name.
/// Multi-set procedures return every result set in order.
/// </summary>
public interface IAdminRepository
{
    // Users
    Task<PagedResult<IDictionary<string, object?>>> SearchUsersAsync(int actorUserId, string? search, string? roleCode, bool? isActive,
        int page, int pageSize, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetUserAsync(int actorUserId, int userId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> CreateUserAsync(int actorUserId, AdminUserSaveArgs args, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> UpdateUserAsync(int actorUserId, int userId, AdminUserSaveArgs args, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> SetUserStatusAsync(int actorUserId, int userId, bool isActive, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> SetUserFacilitiesAsync(int actorUserId, int userId, string assignmentsJson, CancellationToken cancellationToken = default);

    // Roles & permissions
    Task<IReadOnlyList<IDictionary<string, object?>>> GetRolesAsync(int actorUserId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetPermissionsAsync(int actorUserId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> UpdateRolePermissionsAsync(int actorUserId, int roleId, string permissionCodesCsv, CancellationToken cancellationToken = default);

    // Facility registry & verification
    Task<PagedResult<IDictionary<string, object?>>> SearchFacilitiesAsync(int actorUserId, string? status, string? facilityType, string? search,
        int page, int pageSize, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>?> CreateFacilityAsync(int actorUserId, AdminFacilitySaveArgs args, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>?> UpdateFacilityAsync(int actorUserId, int facilityId, AdminFacilitySaveArgs args, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>?> VerifyFacilityAsync(int actorUserId, int facilityId, string decision, string? notes, CancellationToken cancellationToken = default);

    // Master data
    Task<IReadOnlyList<IDictionary<string, object?>>> GetMasterDataAsync(int actorUserId, string type, CancellationToken cancellationToken = default);
    Task<IDictionary<string, object?>?> SaveMasterDataAsync(int actorUserId, string type, int? id, string payloadJson, CancellationToken cancellationToken = default);

    // Settings
    Task<IReadOnlyList<IDictionary<string, object?>>> GetSettingsAsync(int actorUserId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> UpdateSettingsAsync(int actorUserId, string settingsJson, CancellationToken cancellationToken = default);
}

/// <summary>Arguments for usp_Admin_CreateUser / usp_Admin_UpdateUser (RoleCodes already joined as CSV).</summary>
public sealed record AdminUserSaveArgs(
    string DisplayName, string? GivenName, string? FamilyName, string Email, string? Phone, string? OrganizationName,
    int? AreaId, string RoleCodes, bool IsActive);

/// <summary>Arguments for usp_Facility_Create / usp_Facility_AdminUpdate (RowVersion already decoded from base64).</summary>
public sealed record AdminFacilitySaveArgs(
    string? FacilityType, string Name, string? LicenseNo, string AddressLine, int AreaId, string? City, string? Pincode,
    decimal? Latitude, decimal? Longitude, string ContactPhone, string? ContactEmail, bool Is24x7, bool? IsActive, byte[]? RowVersion);
