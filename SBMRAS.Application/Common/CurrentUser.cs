using SBMRAS.Application.Constants;

namespace SBMRAS.Application.Common;

public sealed record FacilityAssignment(int FacilityId, string FacilityCode, string Name, string FacilityType, string AssignmentRole);

public sealed record CurrentUser(
    int UserId,
    string DisplayName,
    string? GivenName,
    string? FamilyName,
    string? Email,
    string? Phone,
    string? OrganizationName,
    int? AreaId,
    string? AreaName,
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> RoleNames,
    string? PrimaryRole,
    IReadOnlyList<string> Permissions,
    IReadOnlyList<FacilityAssignment> Facilities)
{
    public bool HasPermission(string code) => Permissions.Contains(code, StringComparer.OrdinalIgnoreCase);
    public bool IsInRole(string roleCode) => Roles.Contains(roleCode, StringComparer.OrdinalIgnoreCase);
    public bool IsAdmin => IsInRole(Constants.Roles.Admin) || HasPermission(Constants.Permissions.DataViewAll);
    public bool CanAccessFacility(int facilityId) => IsAdmin || Facilities.Any(f => f.FacilityId == facilityId);
}

public interface ICurrentUserAccessor
{
    CurrentUser? User { get; set; }
}

public sealed class CurrentUserAccessor : ICurrentUserAccessor
{
    public CurrentUser? User { get; set; }
}

public interface IRequestContext
{
    string CorrelationId { get; set; }
}

public sealed class RequestContext : IRequestContext
{
    public string CorrelationId { get; set; } = Guid.NewGuid().ToString("N");
}
