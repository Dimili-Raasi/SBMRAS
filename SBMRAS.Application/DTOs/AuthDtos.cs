namespace SBMRAS.Application.DTOs;

/// <summary>GET auth/config response (no SP).</summary>
public sealed record AuthConfigDto(string Mode, string Instance, string TenantId, string SpaClientId, string ApiScope,
    string Authority, string UserFlow, string KnownAuthority);

/// <summary>GET auth/dev-users row (usp_Auth_GetDevUsers).</summary>
public sealed record DevUserDto(int UserId, string DisplayName, string? Email, string? RoleCode, string? RoleName,
    string? OrganizationName, string? AreaName, string? FacilityNames);

/// <summary>GET me/menu response: sections with items (usp_Me_GetMenu rows grouped by Section).</summary>
public sealed record MenuSectionDto(string Section, int SectionOrder, IReadOnlyList<MenuItemDto> Items);

public sealed record MenuItemDto(string Code, string Label, string Icon, string Route, int SortOrder);
