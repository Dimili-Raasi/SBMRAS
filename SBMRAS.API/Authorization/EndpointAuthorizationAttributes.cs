namespace SBMRAS.API.Authorization;

[AttributeUsage(AttributeTargets.Method, AllowMultiple = false, Inherited = true)]
public sealed class RequirePermissionAttribute(string permission) : Attribute
{
    public string Permission { get; } = string.IsNullOrWhiteSpace(permission)
        ? throw new ArgumentException("A permission code is required.", nameof(permission))
        : permission;
}

[AttributeUsage(AttributeTargets.Method, AllowMultiple = false, Inherited = true)]
public sealed class AllowAnonymousEndpointAttribute : Attribute
{
}

[AttributeUsage(AttributeTargets.Method, AllowMultiple = false, Inherited = true)]
public sealed class AuthenticatedEndpointAttribute : Attribute
{
}
