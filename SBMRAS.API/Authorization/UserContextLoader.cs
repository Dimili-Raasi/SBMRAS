using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.Interfaces;
using SBMRAS.Infrastructure.Auth;

namespace SBMRAS.API.Authorization;

public sealed class UserContextLoader(IStoredProcedureExecutor executor, IRequestContext requestContext)
{
    public async Task<CurrentUser> LoadDevUserAsync(int userId, CancellationToken cancellationToken)
    {
        var result = await executor.InvokeAsync(StoredProcedures.UserGetContext, userId,
            new Dictionary<string, object?> { ["UserId"] = userId, ["TouchLogin"] = true },
            ResultShape.Multiple, cancellationToken: cancellationToken);
        return MapContext(result);
    }

    public async Task<CurrentUser> ResolveEntraUserAsync(EntraIdentity identity, CancellationToken cancellationToken)
    {
        var result = await executor.InvokeAsync(StoredProcedures.UserResolveEntra, 0,
            new Dictionary<string, object?>
            {
                ["EntraTenantId"] = identity.TenantId,
                ["EntraObjectId"] = identity.ObjectId,
                ["Email"] = identity.Email,
                ["AlternateEmail"] = identity.AlternateEmail,
                ["DisplayName"] = identity.DisplayName,
                ["GivenName"] = identity.GivenName,
                ["FamilyName"] = identity.FamilyName,
                ["EntraRoles"] = string.Join(',', identity.AppRoles),
                ["CorrelationId"] = requestContext.CorrelationId,
            },
            ResultShape.Multiple, cancellationToken: cancellationToken);
        return MapContext(result);
    }

    public static CurrentUser MapContext(object? result)
    {
        var sets = SqlRows.AsSets(result);
        var profile = SqlRows.Set(sets, 0).FirstOrDefault();
        if (profile is null || !ReadBool(profile, "IsActive"))
            throw AppException.Unauthorized();

        var roles = SqlRows.Set(sets, 1);
        var permissions = SqlRows.Set(sets, 2)
            .Select(row => SqlRows.Str(row, "PermissionCode"))
            .Where(code => !string.IsNullOrWhiteSpace(code)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var facilities = SqlRows.Set(sets, 3).Select(row => new FacilityAssignment(
            SqlRows.Int(row, "FacilityId"), SqlRows.Str(row, "FacilityCode"), SqlRows.Str(row, "Name"),
            SqlRows.Str(row, "FacilityType"), SqlRows.Str(row, "AssignmentRole"))).ToArray();
        var roleCodes = roles.Select(row => SqlRows.Str(row, "RoleCode")).Where(role => !string.IsNullOrWhiteSpace(role)).ToArray();
        var roleNames = roles.Select(row => SqlRows.Str(row, "RoleName")).Where(role => !string.IsNullOrWhiteSpace(role)).ToArray();

        return new CurrentUser(
            SqlRows.Int(profile, "UserId"),
            SqlRows.Str(profile, "DisplayName"),
            ReadNullableString(profile, "GivenName"),
            ReadNullableString(profile, "FamilyName"),
            ReadNullableString(profile, "Email"),
            ReadNullableString(profile, "Phone"),
            ReadNullableString(profile, "OrganizationName"),
            SqlRows.ToInt(SqlRows.Value(profile, "AreaId")),
            ReadNullableString(profile, "AreaName"),
            roleCodes,
            roleNames,
            ReadNullableString(profile, "PrimaryRole"),
            permissions,
            facilities);
    }

    private static string? ReadNullableString(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is null or DBNull ? null : SqlRows.Str(row, key);

    private static bool ReadBool(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        bool value => value,
        byte value => value != 0,
        int value => value != 0,
        string value => bool.TryParse(value, out var parsed) ? parsed : value == "1",
        _ => false,
    };
}
