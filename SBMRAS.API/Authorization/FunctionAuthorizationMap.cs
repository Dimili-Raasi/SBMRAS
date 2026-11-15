using System.Reflection;
using Microsoft.Azure.Functions.Worker;

namespace SBMRAS.API.Authorization;

public sealed record FunctionAuthorizationMetadata(
    MethodInfo Method,
    RequirePermissionAttribute? Permission,
    bool IsAnonymous,
    bool RequiresAuthentication);

public static class FunctionAuthorizationMap
{
    private static IReadOnlyDictionary<string, FunctionAuthorizationMetadata> _functions =
        new Dictionary<string, FunctionAuthorizationMetadata>(StringComparer.OrdinalIgnoreCase);

    public static void Initialize(Assembly assembly)
    {
        var functions = new Dictionary<string, FunctionAuthorizationMetadata>(StringComparer.OrdinalIgnoreCase);
        foreach (var method in assembly.GetTypes().SelectMany(type => type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)))
        {
            var function = method.GetCustomAttributes(inherit: true)
                .FirstOrDefault(attribute => attribute.GetType() == typeof(FunctionAttribute));
            if (function is null || !method.GetParameters().SelectMany(parameter => parameter.GetCustomAttributes(inherit: true))
                    .Any(attribute => attribute.GetType().Name == "HttpTriggerAttribute"))
                continue;

            var permission = method.GetCustomAttribute<RequirePermissionAttribute>(inherit: true);
            var anonymous = method.IsDefined(typeof(AllowAnonymousEndpointAttribute), inherit: true);
            var authenticated = method.IsDefined(typeof(AuthenticatedEndpointAttribute), inherit: true);
            if ((permission is not null ? 1 : 0) + (anonymous ? 1 : 0) + (authenticated ? 1 : 0) != 1)
                throw new InvalidOperationException($"HTTP function '{method.Name}' must declare exactly one authorization attribute.");

            var functionName = function.GetType().GetProperty("Name")?.GetValue(function) as string;
            if (string.IsNullOrWhiteSpace(functionName))
                throw new InvalidOperationException($"HTTP function '{method.Name}' has no function name.");
            functions[functionName] = new FunctionAuthorizationMetadata(method, permission, anonymous, authenticated);
        }

        _functions = functions;
    }

    public static FunctionAuthorizationMetadata ForFunction(string functionName)
        => _functions.TryGetValue(functionName, out var metadata)
            ? metadata
            : throw new InvalidOperationException($"No authorization metadata is registered for HTTP function '{functionName}'.");
}
