using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.Infrastructure.Repositories;

/// <summary>Administration repository: thin wrappers over the stored procedures in 11_StoredProcedures_Admin.sql.</summary>
public sealed class AdminRepository(IStoredProcedureExecutor executor, IRequestContext requestContext) : IAdminRepository
{
    // ------------------------------------------------------------ Users

    public async Task<PagedResult<IDictionary<string, object?>>> SearchUsersAsync(int actorUserId, string? search, string? roleCode, bool? isActive,
        int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var result = await executor.InvokeAsync(StoredProcedures.AdminSearchUsers, actorUserId, new Dictionary<string, object?>
        {
            ["Search"] = search,
            ["RoleCode"] = roleCode,
            ["IsActive"] = isActive,
        }, ResultShape.Paged, page, pageSize, cancellationToken);
        return SqlRows.AsPaged(result, page, pageSize);
    }

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetUserAsync(int actorUserId, int userId, CancellationToken cancellationToken = default)
        => MultipleAsync(StoredProcedures.AdminGetUser, actorUserId, new() { ["UserId"] = userId }, cancellationToken);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> CreateUserAsync(int actorUserId, AdminUserSaveArgs args, CancellationToken cancellationToken = default)
        => MultipleAsync(StoredProcedures.AdminCreateUser, actorUserId, UserArgs(args), cancellationToken);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> UpdateUserAsync(int actorUserId, int userId, AdminUserSaveArgs args, CancellationToken cancellationToken = default)
    {
        var arguments = UserArgs(args);
        arguments["UserId"] = userId;
        return MultipleAsync(StoredProcedures.AdminUpdateUser, actorUserId, arguments, cancellationToken);
    }

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> SetUserStatusAsync(int actorUserId, int userId, bool isActive, CancellationToken cancellationToken = default)
        => MultipleAsync(StoredProcedures.AdminSetUserStatus, actorUserId, new() { ["UserId"] = userId, ["IsActive"] = isActive }, cancellationToken);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> SetUserFacilitiesAsync(int actorUserId, int userId, string assignmentsJson, CancellationToken cancellationToken = default)
        => MultipleAsync(StoredProcedures.AdminSetUserFacilities, actorUserId, new() { ["UserId"] = userId, ["AssignmentsJson"] = assignmentsJson }, cancellationToken);

    // ------------------------------------------------------------ Roles & permissions

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetRolesAsync(int actorUserId, CancellationToken cancellationToken = default)
        => ListAsync(StoredProcedures.AdminGetRoles, actorUserId, new() { ["RoleId"] = null }, cancellationToken);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetPermissionsAsync(int actorUserId, CancellationToken cancellationToken = default)
        => ListAsync(StoredProcedures.AdminGetPermissions, actorUserId, new(), cancellationToken);

    public Task<IReadOnlyList<IDictionary<string, object?>>> UpdateRolePermissionsAsync(int actorUserId, int roleId, string permissionCodesCsv, CancellationToken cancellationToken = default)
        => ListAsync(StoredProcedures.AdminUpdateRolePermissions, actorUserId,
            new() { ["RoleId"] = roleId, ["PermissionCodes"] = permissionCodesCsv }, cancellationToken);

    // ------------------------------------------------------------ Facility registry & verification

    public async Task<PagedResult<IDictionary<string, object?>>> SearchFacilitiesAsync(int actorUserId, string? status, string? facilityType, string? search,
        int page, int pageSize, CancellationToken cancellationToken = default)
    {
        var result = await executor.InvokeAsync(StoredProcedures.FacilityAdminSearch, actorUserId, new Dictionary<string, object?>
        {
            ["Status"] = status,
            ["FacilityType"] = facilityType,
            ["Search"] = search,
        }, ResultShape.Paged, page, pageSize, cancellationToken);
        return SqlRows.AsPaged(result, page, pageSize);
    }

    public Task<IDictionary<string, object?>?> CreateFacilityAsync(int actorUserId, AdminFacilitySaveArgs args, CancellationToken cancellationToken = default)
        => SingleAsync(StoredProcedures.FacilityCreate, actorUserId, FacilityArgs(args, includeUpdateFields: false), cancellationToken);

    public Task<IDictionary<string, object?>?> UpdateFacilityAsync(int actorUserId, int facilityId, AdminFacilitySaveArgs args, CancellationToken cancellationToken = default)
    {
        var arguments = FacilityArgs(args, includeUpdateFields: true);
        arguments["FacilityId"] = facilityId;
        return SingleAsync(StoredProcedures.FacilityAdminUpdate, actorUserId, arguments, cancellationToken);
    }

    public Task<IDictionary<string, object?>?> VerifyFacilityAsync(int actorUserId, int facilityId, string decision, string? notes, CancellationToken cancellationToken = default)
        => SingleAsync(StoredProcedures.FacilityVerify, actorUserId,
            new() { ["FacilityId"] = facilityId, ["Decision"] = decision, ["Notes"] = notes }, cancellationToken);

    // ------------------------------------------------------------ Master data

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetMasterDataAsync(int actorUserId, string type, CancellationToken cancellationToken = default)
        => ListAsync(StoredProcedures.MasterDataGet, actorUserId, new() { ["Type"] = type, ["Id"] = null }, cancellationToken);

    public Task<IDictionary<string, object?>?> SaveMasterDataAsync(int actorUserId, string type, int? id, string payloadJson, CancellationToken cancellationToken = default)
        => SingleAsync(StoredProcedures.MasterDataSave, actorUserId,
            new() { ["Type"] = type, ["Id"] = id, ["PayloadJson"] = payloadJson }, cancellationToken);

    // ------------------------------------------------------------ Settings

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetSettingsAsync(int actorUserId, CancellationToken cancellationToken = default)
        => ListAsync(StoredProcedures.SettingsGet, actorUserId, new(), cancellationToken);

    public Task<IReadOnlyList<IDictionary<string, object?>>> UpdateSettingsAsync(int actorUserId, string settingsJson, CancellationToken cancellationToken = default)
        => ListAsync(StoredProcedures.SettingsUpdate, actorUserId, new() { ["SettingsJson"] = settingsJson }, cancellationToken);

    // ------------------------------------------------------------ helpers

    private static Dictionary<string, object?> UserArgs(AdminUserSaveArgs args) => new()
    {
        ["DisplayName"] = args.DisplayName,
        ["GivenName"] = args.GivenName,
        ["FamilyName"] = args.FamilyName,
        ["Email"] = args.Email,
        ["Phone"] = args.Phone,
        ["OrganizationName"] = args.OrganizationName,
        ["AreaId"] = args.AreaId,
        ["RoleCodes"] = args.RoleCodes,
        ["IsActive"] = args.IsActive,
    };

    private static Dictionary<string, object?> FacilityArgs(AdminFacilitySaveArgs args, bool includeUpdateFields)
    {
        var arguments = new Dictionary<string, object?>
        {
            ["FacilityType"] = args.FacilityType,
            ["Name"] = args.Name,
            ["LicenseNo"] = args.LicenseNo,
            ["AddressLine"] = args.AddressLine,
            ["AreaId"] = args.AreaId,
            ["City"] = args.City,
            ["Pincode"] = args.Pincode,
            ["Latitude"] = args.Latitude,
            ["Longitude"] = args.Longitude,
            ["ContactPhone"] = args.ContactPhone,
            ["ContactEmail"] = args.ContactEmail,
            ["Is24x7"] = args.Is24x7,
        };
        if (includeUpdateFields)
        {
            arguments["IsActive"] = args.IsActive;
            arguments["RowVersion"] = args.RowVersion;
        }
        return arguments;
    }

    private Dictionary<string, object?> WithCorrelation(Dictionary<string, object?> arguments)
    {
        arguments["CorrelationId"] = requestContext.CorrelationId;
        return arguments;
    }

    private async Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> MultipleAsync(string procedure, int actorUserId,
        Dictionary<string, object?> arguments, CancellationToken cancellationToken)
        => SqlRows.AsSets(await executor.InvokeAsync(procedure, actorUserId, WithCorrelation(arguments), ResultShape.Multiple,
            cancellationToken: cancellationToken));

    private async Task<IReadOnlyList<IDictionary<string, object?>>> ListAsync(string procedure, int actorUserId,
        Dictionary<string, object?> arguments, CancellationToken cancellationToken)
        => SqlRows.AsRows(await executor.InvokeAsync(procedure, actorUserId, WithCorrelation(arguments), ResultShape.List,
            cancellationToken: cancellationToken));

    private async Task<IDictionary<string, object?>?> SingleAsync(string procedure, int actorUserId,
        Dictionary<string, object?> arguments, CancellationToken cancellationToken)
        => SqlRows.AsRow(await executor.InvokeAsync(procedure, actorUserId, WithCorrelation(arguments), ResultShape.Single,
            cancellationToken: cancellationToken));
}
