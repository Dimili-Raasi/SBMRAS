using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using SBMRAS.Application.Constants;

namespace SBMRAS.Infrastructure.Auth;

public sealed record EntraIdentity(
    Guid TenantId,
    Guid ObjectId,
    string? Email,
    string? AlternateEmail,
    string? DisplayName,
    string? GivenName,
    string? FamilyName,
    IReadOnlyList<string> AppRoles);

public sealed class EntraTokenValidator
{
    private readonly IConfiguration _configuration;
    private readonly Lazy<ConfigurationManager<OpenIdConnectConfiguration>> _metadata;

    public EntraTokenValidator(IConfiguration configuration)
    {
        _configuration = configuration;
        _metadata = new Lazy<ConfigurationManager<OpenIdConnectConfiguration>>(() =>
            new ConfigurationManager<OpenIdConnectConfiguration>(
                GetMetadataAddress(_configuration),
                new OpenIdConnectConfigurationRetriever(),
                new HttpDocumentRetriever { RequireHttps = true }));
    }

    public async Task<EntraIdentity> ValidateAsync(string token, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(token))
            throw new SecurityTokenException("A bearer token is required.");

        var expectedTenant = Required("Auth:Entra:TenantId");
        var clientId = Required("Auth:Entra:ClientId");
        var userFlow = Required("Auth:Entra:UserFlow");
        var audience = _configuration["Auth:Entra:Audience"];
        var requiredScope = _configuration["Auth:Entra:RequiredScope"] ?? "access_as_user";
        var tenantId = Guid.TryParse(expectedTenant, out var tenantGuid)
            ? tenantGuid
            : throw new InvalidOperationException("Auth:Entra:TenantId must be a GUID.");

        var metadata = await _metadata.Value.GetConfigurationAsync(cancellationToken);
        var validAudiences = new[] { audience, clientId }
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var parameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = metadata.SigningKeys,
            ValidateIssuer = true,
            // The API app registration may issue v1.0 access tokens, whose issuer omits the "/v2.0" suffix.
            ValidIssuers = ValidIssuersFor(metadata.Issuer),
            ValidateAudience = true,
            ValidAudiences = validAudiences,
            ValidateLifetime = true,
            RequireExpirationTime = true,
            RequireSignedTokens = true,
            ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
            ClockSkew = TimeSpan.FromMinutes(2),
        };

        // Keep raw JWT claim names (tid, oid, scp, roles); the default mapping renames them to long URIs.
        var principal = new JwtSecurityTokenHandler { MapInboundClaims = false }.ValidateToken(token, parameters, out _);
        var tokenTenant = GetClaim(principal, "tid");
        if (!Guid.TryParse(tokenTenant, out var actualTenant) || actualTenant != tenantId)
            throw new SecurityTokenValidationException("The token tenant is not authorized.");
        // B2C reports the user flow in tfp (or acr on older tokens); External ID uses acr for the auth context level ("1").
        var acr = GetClaim(principal, "acr");
        var tokenFlow = GetClaim(principal, "tfp") ?? (acr is not null && acr.Contains('_') ? acr : null);
        if (tokenFlow is not null && !string.Equals(tokenFlow, userFlow, StringComparison.OrdinalIgnoreCase))
            throw new SecurityTokenValidationException("The token was issued by a different sign-up/sign-in user flow.");

        var objectIdText = GetClaim(principal, "oid");
        if (!Guid.TryParse(objectIdText, out var objectId))
            throw new SecurityTokenValidationException("The token does not identify a user.");
        var scopes = (GetClaim(principal, "scp") ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (!scopes.Contains(requiredScope, StringComparer.Ordinal))
            throw new SecurityTokenValidationException("The token does not contain the required API scope.");

        var roles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var role in principal.FindAll("roles").Concat(principal.FindAll(ClaimTypes.Role)).Select(claim => claim.Value))
            AddRole(roles, role);

        var groups = principal.FindAll("groups").Select(claim => claim.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        AddGroupRole(roles, groups, "Auth:Entra:Groups:HospitalManagement", Roles.HospitalManagement);
        AddGroupRole(roles, groups, "Auth:Entra:Groups:BloodBank", Roles.BloodBank);
        AddGroupRole(roles, groups, "Auth:Entra:Groups:Admin", Roles.Admin);

        var emails = principal.FindAll("emails").Select(claim => claim.Value)
            .Concat(principal.FindAll("email").Select(claim => claim.Value))
            .Concat(principal.FindAll(ClaimTypes.Email).Select(claim => claim.Value))
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var preferredUsername = GetClaim(principal, "preferred_username");
        var email = emails.FirstOrDefault() ?? preferredUsername;
        var alternateEmail = emails.Skip(1).FirstOrDefault();
        if (alternateEmail is null && preferredUsername is not null &&
            !string.Equals(preferredUsername, email, StringComparison.OrdinalIgnoreCase))
            alternateEmail = preferredUsername;

        return new EntraIdentity(
            actualTenant,
            objectId,
            email,
            alternateEmail,
            GetClaim(principal, "name"),
            GetClaim(principal, "given_name") ?? GetClaim(principal, ClaimTypes.GivenName),
            GetClaim(principal, "family_name") ?? GetClaim(principal, ClaimTypes.Surname),
            roles.OrderBy(role => role, StringComparer.Ordinal).ToArray());
    }

    private string Required(string key) => _configuration[key]
        ?? throw new InvalidOperationException($"Configuration value '{key}' is required for EntraId authentication.");

    private static string GetMetadataAddress(IConfiguration configuration)
    {
        var instance = configuration["Auth:Entra:Instance"]?.TrimEnd('/')
            ?? throw new InvalidOperationException("Configuration value 'Auth:Entra:Instance' is required.");
        var tenant = configuration["Auth:Entra:TenantId"]
            ?? throw new InvalidOperationException("Configuration value 'Auth:Entra:TenantId' is required.");
        var userFlow = configuration["Auth:Entra:UserFlow"]
            ?? throw new InvalidOperationException("Configuration value 'Auth:Entra:UserFlow' is required.");
        var spaClientId = configuration["Auth:Entra:SpaClientId"]
            ?? throw new InvalidOperationException("Configuration value 'Auth:Entra:SpaClientId' is required.");
        if (!Guid.TryParse(tenant, out _))
            throw new InvalidOperationException("Auth:Entra:TenantId must be a GUID.");
        if (!Uri.TryCreate(instance, UriKind.Absolute, out var instanceUri) || instanceUri.Scheme != Uri.UriSchemeHttps)
            throw new InvalidOperationException("Auth:Entra:Instance must be an HTTPS authority URL.");

        var tenantDomain = configuration["Auth:Entra:TenantDomain"];
        if (string.IsNullOrWhiteSpace(tenantDomain))
            tenantDomain = $"{instanceUri.Host.Split('.')[0]}.onmicrosoft.com";
        var escapedFlow = Uri.EscapeDataString(userFlow);

        if (instanceUri.Host.EndsWith(".ciamlogin.com", StringComparison.OrdinalIgnoreCase))
            return $"{instance}/{tenantDomain}/v2.0/.well-known/openid-configuration?appid={Uri.EscapeDataString(spaClientId)}";

        if (instanceUri.Host.EndsWith(".b2clogin.com", StringComparison.OrdinalIgnoreCase))
            return $"{instance}/{tenantDomain}/{escapedFlow}/v2.0/.well-known/openid-configuration?p={escapedFlow}";

        return $"{instance}/{tenant}/v2.0/.well-known/openid-configuration";
    }

    private static string[] ValidIssuersFor(string metadataIssuer)
    {
        var issuer = metadataIssuer.TrimEnd('/');
        var v1Issuer = issuer.EndsWith("/v2.0", StringComparison.OrdinalIgnoreCase) ? issuer[..^"/v2.0".Length] : issuer;
        return [issuer, issuer + "/", v1Issuer, v1Issuer + "/"];
    }

    private static string? GetClaim(ClaimsPrincipal principal, string type)
        => principal.FindFirst(type)?.Value;

    private static void AddRole(ISet<string> roles, string value)
    {
        var allowed = Roles.EntraAssignable.FirstOrDefault(role => string.Equals(role, value, StringComparison.OrdinalIgnoreCase));
        if (allowed is not null) roles.Add(allowed);
    }

    private void AddGroupRole(ISet<string> roles, IReadOnlySet<string> groups, string configKey, string role)
    {
        var configuredGroups = (_configuration[configKey] ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (configuredGroups.Any(groups.Contains)) roles.Add(role);
    }
}
