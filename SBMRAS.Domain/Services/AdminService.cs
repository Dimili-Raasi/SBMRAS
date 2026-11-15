using System.Globalization;
using System.Text.Json;
using FluentValidation;
using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;
using SBMRAS.Application.Validators;

namespace SBMRAS.Domain.Services;

/// <summary>Administration orchestration: validates requests, shapes SP arguments (CSV/JSON) and maps result sets (contract §6 Admin).</summary>
public sealed class AdminService(IAdminRepository repository) : IAdminService
{
    private static readonly JsonSerializerOptions CamelCase = new(JsonSerializerDefaults.Web);

    private static readonly AdminUserSearchQueryValidator UserSearchValidator = new();
    private static readonly UserSaveValidator UserSaveValidator = new();
    private static readonly UserStatusValidator UserStatusValidator = new();
    private static readonly UserFacilitiesValidator UserFacilitiesValidator = new();
    private static readonly RolePermissionsValidator RolePermissionsValidator = new();
    private static readonly AdminFacilitySearchQueryValidator FacilitySearchValidator = new();
    private static readonly FacilityCreateValidator FacilityCreateValidator = new();
    private static readonly FacilitySaveValidator FacilityUpdateValidator = new();
    private static readonly FacilityVerifyValidator FacilityVerifyValidator = new();
    private static readonly SettingsUpdateValidator SettingsValidator = new();

    // ------------------------------------------------------------ Users

    public async Task<PagedResult<AdminUserDto>> SearchUsersAsync(CurrentUser actor, AdminUserSearchQuery query, CancellationToken cancellationToken = default)
    {
        Validate(UserSearchValidator, query);
        var paged = await repository.SearchUsersAsync(actor.UserId, Trim(query.Search), Trim(query.RoleCode), query.IsActive,
            query.Page, query.PageSize, cancellationToken);
        return new PagedResult<AdminUserDto>(paged.Items.Select(r => MapUser(r, [], [])).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    public async Task<AdminUserDto> GetUserAsync(CurrentUser actor, int userId, CancellationToken cancellationToken = default)
        => MapUserSets(await repository.GetUserAsync(actor.UserId, RequireId(userId, "User"), cancellationToken));

    public async Task<AdminUserDto> CreateUserAsync(CurrentUser actor, UserSaveDto body, CancellationToken cancellationToken = default)
    {
        Validate(UserSaveValidator, body);
        return MapUserSets(await repository.CreateUserAsync(actor.UserId, ToUserArgs(body), cancellationToken));
    }

    public async Task<AdminUserDto> UpdateUserAsync(CurrentUser actor, int userId, UserSaveDto body, CancellationToken cancellationToken = default)
    {
        RequireId(userId, "User");
        Validate(UserSaveValidator, body);
        return MapUserSets(await repository.UpdateUserAsync(actor.UserId, userId, ToUserArgs(body), cancellationToken));
    }

    public async Task<AdminUserDto> SetUserStatusAsync(CurrentUser actor, int userId, UserStatusDto body, CancellationToken cancellationToken = default)
    {
        RequireId(userId, "User");
        Validate(UserStatusValidator, body);
        return MapUserSets(await repository.SetUserStatusAsync(actor.UserId, userId, body.IsActive!.Value, cancellationToken));
    }

    public async Task<AdminUserDto> SetUserFacilitiesAsync(CurrentUser actor, int userId, UserFacilitiesDto body, CancellationToken cancellationToken = default)
    {
        RequireId(userId, "User");
        Validate(UserFacilitiesValidator, body);
        var json = JsonSerializer.Serialize(
            (body.Assignments ?? []).Select(a => new { facilityId = a.FacilityId, assignmentRole = a.AssignmentRole.Trim() }), CamelCase);
        return MapUserSets(await repository.SetUserFacilitiesAsync(actor.UserId, userId, json, cancellationToken));
    }

    // ------------------------------------------------------------ Roles & permissions

    public async Task<IReadOnlyList<AdminRoleDto>> GetRolesAsync(CurrentUser actor, CancellationToken cancellationToken = default)
        => (await repository.GetRolesAsync(actor.UserId, cancellationToken)).Select(MapRole).ToArray();

    public async Task<IReadOnlyList<AdminPermissionDto>> GetPermissionsAsync(CurrentUser actor, CancellationToken cancellationToken = default)
        => (await repository.GetPermissionsAsync(actor.UserId, cancellationToken))
            .Select(r => new AdminPermissionDto(SqlRows.Int(r, "PermissionId"), SqlRows.Str(r, "PermissionCode"), SqlRows.Str(r, "PermissionName"),
                NullableStr(r, "Module"), NullableStr(r, "Description")))
            .ToArray();

    public async Task<AdminRoleDto> UpdateRolePermissionsAsync(CurrentUser actor, int roleId, RolePermissionsDto body, CancellationToken cancellationToken = default)
    {
        RequireId(roleId, "Role");
        Validate(RolePermissionsValidator, body);
        var csv = string.Join(',', (body.PermissionCodes ?? []).Select(c => c.Trim()).Where(c => c.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase));
        var rows = await repository.UpdateRolePermissionsAsync(actor.UserId, roleId, csv, cancellationToken);
        return rows.Count > 0 ? MapRole(rows[0]) : throw AppException.NotFound("Role not found.");
    }

    // ------------------------------------------------------------ Facility registry & verification

    public Task<PagedResult<IDictionary<string, object?>>> SearchFacilitiesAsync(CurrentUser actor, AdminFacilitySearchQuery query, CancellationToken cancellationToken = default)
    {
        Validate(FacilitySearchValidator, query);
        return repository.SearchFacilitiesAsync(actor.UserId, Trim(query.Status), Trim(query.FacilityType), Trim(query.Search),
            query.Page, query.PageSize, cancellationToken);
    }

    public async Task<IDictionary<string, object?>> CreateFacilityAsync(CurrentUser actor, FacilitySaveDto body, CancellationToken cancellationToken = default)
    {
        Validate(FacilityCreateValidator, body);
        return Required(await repository.CreateFacilityAsync(actor.UserId, ToFacilityArgs(body), cancellationToken), "Facility");
    }

    public async Task<IDictionary<string, object?>> UpdateFacilityAsync(CurrentUser actor, int facilityId, FacilitySaveDto body, CancellationToken cancellationToken = default)
    {
        RequireId(facilityId, "Facility");
        Validate(FacilityUpdateValidator, body);
        return Required(await repository.UpdateFacilityAsync(actor.UserId, facilityId, ToFacilityArgs(body), cancellationToken), "Facility");
    }

    public async Task<IDictionary<string, object?>> VerifyFacilityAsync(CurrentUser actor, int facilityId, FacilityVerifyDto body, CancellationToken cancellationToken = default)
    {
        RequireId(facilityId, "Facility");
        Validate(FacilityVerifyValidator, body);
        return Required(await repository.VerifyFacilityAsync(actor.UserId, facilityId, body.Decision, Trim(body.Notes), cancellationToken), "Facility");
    }

    // ------------------------------------------------------------ Master data

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetMasterDataAsync(CurrentUser actor, string type, CancellationToken cancellationToken = default)
        => repository.GetMasterDataAsync(actor.UserId, NormalizeType(type), cancellationToken);

    public async Task<IDictionary<string, object?>> SaveMasterDataAsync(CurrentUser actor, string type, JsonElement body, CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeType(type);
        if (body.ValueKind != JsonValueKind.Object)
            throw AppException.Validation("The master data payload must be a JSON object.");

        // Re-key to camelCase so the SP's JSON_VALUE('$.name') etc. match regardless of client casing.
        var payload = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var property in body.EnumerateObject())
            payload[JsonNamingPolicy.CamelCase.ConvertName(property.Name)] = property.Value;

        var id = ReadId(payload, "id") ?? ReadId(payload, AdminValues.MasterDataKeys[normalized]);
        var errors = ValidateMasterData(normalized, payload);
        if (errors.Count > 0)
            throw AppException.Validation("Validation failed.", errors);

        var json = JsonSerializer.Serialize(payload);
        return Required(await repository.SaveMasterDataAsync(actor.UserId, normalized, id is > 0 ? id : null, json, cancellationToken), "Master data row");
    }

    // ------------------------------------------------------------ Settings

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetSettingsAsync(CurrentUser actor, CancellationToken cancellationToken = default)
        => repository.GetSettingsAsync(actor.UserId, cancellationToken);

    public Task<IReadOnlyList<IDictionary<string, object?>>> UpdateSettingsAsync(CurrentUser actor, SettingsUpdateDto body, CancellationToken cancellationToken = default)
    {
        Validate(SettingsValidator, body);
        var json = JsonSerializer.Serialize(
            body.Settings!.Select(s => new { settingKey = s.SettingKey.Trim(), settingValue = s.SettingValue!.Trim() }), CamelCase);
        return repository.UpdateSettingsAsync(actor.UserId, json, cancellationToken);
    }

    // ------------------------------------------------------------ mapping helpers

    private static AdminUserDto MapUserSets(IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>> sets)
    {
        var user = SqlRows.Set(sets, 0).FirstOrDefault() ?? throw AppException.NotFound("User not found.");
        return MapUser(user, SqlRows.Set(sets, 1), SqlRows.Set(sets, 2));
    }

    private static AdminUserDto MapUser(IDictionary<string, object?> row, IReadOnlyList<IDictionary<string, object?>> roleSources,
        IReadOnlyList<IDictionary<string, object?>> facilities) => new()
    {
        UserId = SqlRows.Int(row, "UserId"),
        DisplayName = SqlRows.Str(row, "DisplayName"),
        GivenName = NullableStr(row, "GivenName"),
        FamilyName = NullableStr(row, "FamilyName"),
        Email = NullableStr(row, "Email"),
        Phone = NullableStr(row, "Phone"),
        OrganizationName = NullableStr(row, "OrganizationName"),
        AreaId = SqlRows.ToInt(SqlRows.Value(row, "AreaId")),
        AreaName = NullableStr(row, "AreaName"),
        RoleCodes = SplitCsv(SqlRows.Value(row, "RoleCodes")),
        RoleNames = SplitCsv(SqlRows.Value(row, "RoleNames")),
        RoleSources = roleSources.Select(r => new UserRoleSourceDto(SqlRows.Str(r, "RoleCode"), SqlRows.Str(r, "Source"))).ToArray(),
        IsActive = Bool(row, "IsActive"),
        IsSelfRegistered = Bool(row, "IsSelfRegistered"),
        EntraLinked = Bool(row, "EntraLinked"),
        LastLoginAt = Date(row, "LastLoginAt"),
        CreatedAt = Date(row, "CreatedAt"),
        FacilityCount = SqlRows.ToInt(SqlRows.Value(row, "FacilityCount")) ?? (facilities.Count > 0 ? facilities.Count : null),
        Facilities = facilities.Select(f => new UserFacilityDto(SqlRows.Int(f, "FacilityId"), NullableStr(f, "FacilityCode"),
            SqlRows.Str(f, "Name"), SqlRows.Str(f, "FacilityType"), SqlRows.Str(f, "AssignmentRole"))).ToArray(),
    };

    private static AdminRoleDto MapRole(IDictionary<string, object?> r) => new(
        SqlRows.Int(r, "RoleId"), SqlRows.Str(r, "RoleCode"), SqlRows.Str(r, "RoleName"), NullableStr(r, "Description"),
        NullableStr(r, "EntraAppRole"), NullableStr(r, "EntraGroupName"), Bool(r, "IsSystem"), Bool(r, "IsActive"),
        SqlRows.Int(r, "UserCount"), SplitCsv(SqlRows.Value(r, "PermissionCodes")));

    private static AdminUserSaveArgs ToUserArgs(UserSaveDto body) => new(
        body.DisplayName.Trim(), Trim(body.GivenName), Trim(body.FamilyName), body.Email.Trim(), Trim(body.Phone), Trim(body.OrganizationName),
        body.AreaId is > 0 ? body.AreaId : null,
        string.Join(',', (body.RoleCodes ?? []).Select(c => c.Trim()).Where(c => c.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase)),
        body.IsActive);

    private static AdminFacilitySaveArgs ToFacilityArgs(FacilitySaveDto body) => new(
        Trim(body.FacilityType), body.Name.Trim(), Trim(body.LicenseNo), body.AddressLine.Trim(), body.AreaId, Trim(body.City), Trim(body.Pincode),
        body.Latitude, body.Longitude, body.ContactPhone.Trim(), Trim(body.ContactEmail), body.Is24x7, body.IsActive,
        SqlRows.RowVersionBytes(body.RowVersion));

    private static string NormalizeType(string? type)
    {
        var normalized = (type ?? "").Trim().ToLowerInvariant();
        return AdminValues.MasterDataTypes.Contains(normalized)
            ? normalized
            : throw AppException.BadRequest("Unknown master data type. Use areas, components, units, resource-categories or resource-types.");
    }

    private static int? ReadId(Dictionary<string, JsonElement> payload, string key)
    {
        if (!payload.TryGetValue(key, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetInt32(out var n) => n,
            JsonValueKind.String when int.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) => n,
            JsonValueKind.Null or JsonValueKind.Undefined => null,
            _ => throw AppException.Validation($"'{key}' must be a whole number."),
        };
    }

    private static List<string> ValidateMasterData(string type, Dictionary<string, JsonElement> payload)
    {
        var errors = new List<string>();
        string? Text(string key) => payload.TryGetValue(key, out var v) && v.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined)
            ? (v.ValueKind == JsonValueKind.String ? v.GetString() : v.GetRawText())?.Trim()
            : null;
        void Require(string key, string label) { if (string.IsNullOrWhiteSpace(Text(key))) errors.Add($"{label} is required."); }
        void Max(string key, string label, int length) { if ((Text(key)?.Length ?? 0) > length) errors.Add($"{label} must be at most {length} characters."); }

        Require("name", "Name");
        Max("name", "Name", 100);
        Max("description", "Description", 400);
        Max("storageNote", "Storage note", 400);
        switch (type)
        {
            case "areas":
                Require("city", "City");
                Require("state", "State");
                Max("pincode", "Pincode", 10);
                break;
            case "components":
                Require("code", "Code");
                Max("code", "Code", 20);
                if (!int.TryParse(Text("shelfLifeDays"), NumberStyles.Integer, CultureInfo.InvariantCulture, out var days) || days is < 1 or > 3650)
                    errors.Add("Shelf life must be between 1 and 3650 days.");
                break;
            case "units":
                Require("code", "Code");
                Max("code", "Code", 20);
                break;
            case "resource-types":
                Require("code", "Code");
                Max("code", "Code", 30);
                if (!int.TryParse(Text("categoryId"), out var category) || category < 1) errors.Add("Select a valid resource category.");
                if (!int.TryParse(Text("defaultUnitId"), out var unit) || unit < 1) errors.Add("Select a valid default unit.");
                var mode = Text("trackingMode");
                if (!string.IsNullOrEmpty(mode) && !AdminValues.TrackingModes.Contains(mode))
                    errors.Add("Tracking mode must be Count, Status or Capacity.");
                break;
        }
        return errors;
    }

    private static void Validate<T>(IValidator<T> validator, T? instance)
    {
        if (instance is null)
            throw AppException.Validation("Request body is required.");
        var result = validator.Validate(instance);
        if (!result.IsValid)
            throw AppException.Validation("Validation failed.", result.Errors.Select(e => e.ErrorMessage).Distinct());
    }

    private static int RequireId(int id, string entity)
        => id > 0 ? id : throw AppException.NotFound($"{entity} not found.");

    private static IDictionary<string, object?> Required(IDictionary<string, object?>? row, string entity)
        => row ?? throw AppException.NotFound($"{entity} not found.");

    private static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string? NullableStr(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is { } v and not DBNull ? Convert.ToString(v, CultureInfo.InvariantCulture) : null;

    private static bool Bool(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        bool b => b,
        null or DBNull => false,
        string s => s.Equals("true", StringComparison.OrdinalIgnoreCase) || s == "1",
        var v => SqlRows.IsNumeric(v) && Convert.ToDecimal(v, CultureInfo.InvariantCulture) != 0,
    };

    private static DateTime? Date(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        DateTime d => DateTime.SpecifyKind(d, DateTimeKind.Utc),
        DateTimeOffset o => o.UtcDateTime,
        _ => null,
    };

    private static IReadOnlyList<string> SplitCsv(object? value)
        => value is string csv && csv.Length > 0
            ? csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : [];
}
