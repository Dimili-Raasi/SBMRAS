using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SBMRAS.Application.DTOs;

// ---------------------------------------------------------------- Users (users.manage)

/// <summary>Query of GET admin/users → usp_Admin_SearchUsers.</summary>
public sealed record AdminUserSearchQuery
{
    public string? Search { get; init; }
    public string? RoleCode { get; init; }
    public bool? IsActive { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Body of POST admin/users and PUT admin/users/{id} (contract §6 UserSave). RoleCodes are Local roles → CSV @RoleCodes.</summary>
public sealed record UserSaveDto
{
    public string DisplayName { get; init; } = "";
    public string? GivenName { get; init; }
    public string? FamilyName { get; init; }
    public string Email { get; init; } = "";
    public string? Phone { get; init; }
    public string? OrganizationName { get; init; }
    public int? AreaId { get; init; }
    public IReadOnlyList<string>? RoleCodes { get; init; }
    public bool IsActive { get; init; } = true;
}

/// <summary>Body of POST admin/users/{id}/status → usp_Admin_SetUserStatus.</summary>
public sealed record UserStatusDto
{
    public bool? IsActive { get; init; }
}

public sealed record UserFacilityAssignmentDto
{
    public int FacilityId { get; init; }
    public string AssignmentRole { get; init; } = "";
}

/// <summary>Body of PUT admin/users/{id}/facilities → usp_Admin_SetUserFacilities(@AssignmentsJson).</summary>
public sealed record UserFacilitiesDto
{
    public IReadOnlyList<UserFacilityAssignmentDto>? Assignments { get; init; }
}

public sealed record UserRoleSourceDto(string RoleCode, string Source);

public sealed record UserFacilityDto(int FacilityId, string? FacilityCode, string Name, string FacilityType, string AssignmentRole);

/// <summary>Response shape User (contract §6). RoleCodes/RoleNames are split from the SQL CSV columns.</summary>
public sealed record AdminUserDto
{
    public int UserId { get; init; }
    public string DisplayName { get; init; } = "";
    public string? GivenName { get; init; }
    public string? FamilyName { get; init; }
    public string? Email { get; init; }
    public string? Phone { get; init; }
    public string? OrganizationName { get; init; }
    public int? AreaId { get; init; }
    public string? AreaName { get; init; }
    public IReadOnlyList<string> RoleCodes { get; init; } = [];
    public IReadOnlyList<string> RoleNames { get; init; } = [];
    public IReadOnlyList<UserRoleSourceDto> RoleSources { get; init; } = [];
    public bool IsActive { get; init; }
    public bool IsSelfRegistered { get; init; }
    public bool EntraLinked { get; init; }
    public DateTime? LastLoginAt { get; init; }
    public DateTime? CreatedAt { get; init; }
    /// <summary>Active assignment count (list rows only).</summary>
    public int? FacilityCount { get; init; }
    public IReadOnlyList<UserFacilityDto> Facilities { get; init; } = [];
}

// ---------------------------------------------------------------- Roles & permissions (roles.manage)

/// <summary>Body of PUT admin/roles/{id}/permissions → usp_Admin_UpdateRolePermissions(@PermissionCodes CSV).</summary>
public sealed record RolePermissionsDto
{
    public IReadOnlyList<string>? PermissionCodes { get; init; }
}

public sealed record AdminRoleDto(
    int RoleId, string RoleCode, string RoleName, string? Description, string? EntraAppRole, string? EntraGroupName,
    bool IsSystem, bool IsActive, int UserCount, IReadOnlyList<string> PermissionCodes);

public sealed record AdminPermissionDto(int PermissionId, string PermissionCode, string PermissionName, string? Module, string? Description);

// ---------------------------------------------------------------- Facility registry & verification (facilities.verify)

/// <summary>Query of GET admin/facilities → usp_Facility_AdminSearch. Status = Pending|Verified|Rejected|Suspended|Active|Inactive.</summary>
public sealed record AdminFacilitySearchQuery
{
    public string? Status { get; init; }
    public string? FacilityType { get; init; }
    public string? Search { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

/// <summary>Body of POST admin/facilities (usp_Facility_Create) and PUT admin/facilities/{id} (usp_Facility_AdminUpdate).</summary>
public sealed record FacilitySaveDto
{
    public string? FacilityType { get; init; }
    public string Name { get; init; } = "";
    public string? LicenseNo { get; init; }
    public string AddressLine { get; init; } = "";
    public int AreaId { get; init; }
    public string? City { get; init; }
    public string? Pincode { get; init; }
    public decimal? Latitude { get; init; }
    public decimal? Longitude { get; init; }
    public string ContactPhone { get; init; } = "";
    public string? ContactEmail { get; init; }
    public bool Is24x7 { get; init; }
    /// <summary>Update only; null keeps the current value.</summary>
    public bool? IsActive { get; init; }
    /// <summary>Base64 ROWVERSION (update only); converted to VARBINARY(8) for @RowVersion.</summary>
    public string? RowVersion { get; init; }
}

/// <summary>Body of POST admin/facilities/{id}/verify → usp_Facility_Verify.</summary>
public sealed record FacilityVerifyDto
{
    public string Decision { get; init; } = "";
    public string? Notes { get; init; }
}

// ---------------------------------------------------------------- Settings (settings.manage)

public sealed record SettingValueDto
{
    public string SettingKey { get; init; } = "";
    /// <summary>Accepts JSON strings, numbers and booleans (normalised to the invariant string form).</summary>
    [JsonConverter(typeof(LenientStringJsonConverter))]
    public string? SettingValue { get; init; }
}

/// <summary>Body of PUT admin/settings → usp_Settings_Update(@SettingsJson).</summary>
public sealed record SettingsUpdateDto
{
    public IReadOnlyList<SettingValueDto>? Settings { get; init; }
}

public static class AdminValues
{
    public static readonly string[] AssignmentRoles = ["Manager", "Operator", "Verifier"];
    public static readonly string[] FacilityStatuses = ["Pending", "Verified", "Rejected", "Suspended", "Active", "Inactive"];
    public static readonly string[] VerifyDecisions = ["Verify", "Reject", "Suspend", "Reactivate"];
    public static readonly string[] MasterDataTypes = ["areas", "components", "units", "resource-categories", "resource-types"];
    public static readonly string[] TrackingModes = ["Count", "Status", "Capacity"];

    /// <summary>Typed key column per master data type (accepted in the body as an alternative to "id").</summary>
    public static readonly IReadOnlyDictionary<string, string> MasterDataKeys = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["areas"] = "areaId",
        ["components"] = "componentId",
        ["units"] = "unitId",
        ["resource-categories"] = "categoryId",
        ["resource-types"] = "resourceTypeId",
    };

    public const string EmailPattern = @"^[^@\s]+@[^@\s]+\.[^@\s]+$";
    public const string PhonePattern = @"^\+?[0-9][0-9 \-]{6,19}$";
}

/// <summary>Reads a JSON string, number or boolean into a string (booleans → "true"/"false").</summary>
public sealed class LenientStringJsonConverter : JsonConverter<string?>
{
    public override bool HandleNull => true;

    public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) => reader.TokenType switch
    {
        JsonTokenType.Null => null,
        JsonTokenType.String => reader.GetString(),
        JsonTokenType.True => "true",
        JsonTokenType.False => "false",
        JsonTokenType.Number => reader.TryGetDecimal(out var d) ? d.ToString(CultureInfo.InvariantCulture) : reader.GetDouble().ToString(CultureInfo.InvariantCulture),
        _ => throw new JsonException("Setting value must be a string, number or boolean."),
    };

    public override void Write(Utf8JsonWriter writer, string? value, JsonSerializerOptions options)
    {
        if (value is null) writer.WriteNullValue();
        else writer.WriteStringValue(value);
    }
}
