using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.API.Functions;

public sealed class AuthFunctions(
    IConfiguration configuration,
    IStoredProcedureExecutor executor,
    ICurrentUserAccessor currentUser) : FunctionBase
{
    [Function("GetAuthConfig")]
    [AllowAnonymousEndpoint]
    public IActionResult GetAuthConfig([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "auth/config")] HttpRequest req)
    {
        var mode = configuration["Auth:Mode"] ?? "DevHeader";
        var instance = configuration["Auth:Entra:Instance"]?.TrimEnd('/') ?? "";
        var tenantId = configuration["Auth:Entra:TenantId"] ?? "";
        var clientId = configuration["Auth:Entra:ClientId"] ?? "";
        var userFlow = configuration["Auth:Entra:UserFlow"] ?? "B2X_1_SBMRAS-SignUpSignIn";
        var resource = configuration["Auth:Entra:Audience"];
        if (string.IsNullOrWhiteSpace(resource))
            resource = string.IsNullOrWhiteSpace(clientId) ? "api://<API-CLIENT-ID>" : $"api://{clientId}";
        var apiScope = $"{resource}/{configuration["Auth:Entra:RequiredScope"] ?? "access_as_user"}";
        var authority = instance;
        if (!string.IsNullOrEmpty(tenantId))
        {
            if (Uri.TryCreate(instance, UriKind.Absolute, out var authorityUri) &&
                authorityUri.Host.EndsWith(".b2clogin.com", StringComparison.OrdinalIgnoreCase))
            {
                var tenantDomain = configuration["Auth:Entra:TenantDomain"]
                    ?? $"{authorityUri.Host.Split('.')[0]}.onmicrosoft.com";
                authority = $"{instance}/{tenantDomain}/{userFlow}";
            }
            else
                authority = $"{instance}/{tenantId}";
        }
        var knownAuthority = Uri.TryCreate(instance, UriKind.Absolute, out var uri) ? uri.Host : instance;
        return Ok(new AuthConfigDto(mode, instance, tenantId,
            configuration["Auth:Entra:SpaClientId"] ?? "", apiScope, authority, userFlow, knownAuthority));
    }

    [Function("GetDevUsers")]
    [AllowAnonymousEndpoint]
    public async Task<IActionResult> GetDevUsers(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "auth/dev-users")] HttpRequest req)
    {
        if (!(configuration["Auth:Mode"] ?? "DevHeader").Equals("DevHeader", StringComparison.OrdinalIgnoreCase))
            throw AppException.NotFound();

        var rows = SqlRows.AsRows(await executor.InvokeAsync(StoredProcedures.AuthGetDevUsers, 0,
            new Dictionary<string, object?>(), ResultShape.List, cancellationToken: req.HttpContext.RequestAborted));
        var users = rows.Select(row => new DevUserDto(
            SqlRows.Int(row, "UserId"), SqlRows.Str(row, "DisplayName"), ReadString(row, "Email"),
            ReadString(row, "RoleCode"), ReadString(row, "RoleName"), ReadString(row, "OrganizationName"),
            ReadString(row, "AreaName"), ReadString(row, "FacilityNames"))).ToArray();
        return Ok(users);
    }

    [Function("GetMe")]
    [AuthenticatedEndpoint]
    public IActionResult GetMe([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "me")] HttpRequest req)
        => Ok(currentUser.User ?? throw AppException.Unauthorized());

    [Function("GetMyMenu")]
    [AuthenticatedEndpoint]
    public async Task<IActionResult> GetMyMenu([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "me/menu")] HttpRequest req)
    {
        var user = currentUser.User ?? throw AppException.Unauthorized();
        var rows = SqlRows.AsRows(await executor.InvokeAsync(StoredProcedures.MeGetMenu, user.UserId,
            new Dictionary<string, object?>(), ResultShape.List, cancellationToken: req.HttpContext.RequestAborted));
        var sections = rows
            .GroupBy(row => (Section: SqlRows.Str(row, "Section"), Order: SqlRows.Int(row, "SectionOrder")))
            .OrderBy(group => group.Key.Order)
            .Select(group => new MenuSectionDto(group.Key.Section, group.Key.Order,
                group.OrderBy(row => SqlRows.Int(row, "SortOrder"))
                    .Select(row => new MenuItemDto(SqlRows.Str(row, "Code"), SqlRows.Str(row, "Label"),
                        SqlRows.Str(row, "Icon"), SqlRows.Str(row, "Route"), SqlRows.Int(row, "SortOrder")))
                    .ToArray()))
            .ToArray();
        return Ok(sections);
    }

    private static string? ReadString(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is null or DBNull ? null : SqlRows.Str(row, key);
}
