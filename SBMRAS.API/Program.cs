using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentValidation;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SBMRAS.API.Authorization;
using SBMRAS.API.Middleware;
using SBMRAS.Application.Common;
using SBMRAS.Application.Interfaces;
using SBMRAS.Infrastructure.Auth;
using SBMRAS.Infrastructure.Database;

namespace SBMRAS.API;

public static class Program
{
    public static void Main()
    {
        FunctionAuthorizationMap.Initialize(Assembly.GetExecutingAssembly());
        var host = new HostBuilder()
            .ConfigureFunctionsWebApplication(worker =>
            {
                worker.UseMiddleware<GlobalExceptionMiddleware>();
                worker.UseMiddleware<RequestContextMiddleware>();
                worker.UseMiddleware<PermissionAuthorizationMiddleware>();
            })
            .ConfigureServices((context, services) =>
            {
                ValidateAuthenticationConfiguration(context.Configuration);
                services.Configure<JsonSerializerOptions>(options =>
                {
                    options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
                    options.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
                    options.Converters.Add(new JsonStringEnumConverter());
                });
                services.AddScoped<ICurrentUserAccessor, CurrentUserAccessor>();
                services.AddScoped<IRequestContext, RequestContext>();
                services.AddScoped<UserContextLoader>();
                services.AddSingleton<EntraTokenValidator>();
                services.AddSingleton<ISqlDbConnectionFactory, SqlDbConnectionFactory>();
                services.AddScoped<IStoredProcedureExecutor, StoredProcedureExecutor>();
                services.AddValidatorsFromAssemblyContaining<SBMRAS.Application.Validators.BloodRequestSaveValidator>();
                RegisterApplicationImplementations(services, typeof(IRequestsService).Assembly);
            })
            .Build();

        host.Run();
    }

    private static void ValidateAuthenticationConfiguration(Microsoft.Extensions.Configuration.IConfiguration configuration)
    {
        var mode = configuration["Auth:Mode"] ?? "DevHeader";
        if (!mode.Equals("DevHeader", StringComparison.OrdinalIgnoreCase) &&
            !mode.Equals("EntraId", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Auth:Mode must be either 'DevHeader' or 'EntraId'.");
        if (!mode.Equals("EntraId", StringComparison.OrdinalIgnoreCase))
            return;

        foreach (var key in new[]
                 {
                     "Auth:Entra:Instance", "Auth:Entra:TenantId", "Auth:Entra:ClientId", "Auth:Entra:SpaClientId",
                     "Auth:Entra:Audience", "Auth:Entra:RequiredScope", "Auth:Entra:UserFlow",
                 })
            if (string.IsNullOrWhiteSpace(configuration[key]))
                throw new InvalidOperationException($"Configuration value '{key}' is required when Auth:Mode is EntraId.");
        if (!Guid.TryParse(configuration["Auth:Entra:TenantId"], out _))
            throw new InvalidOperationException("Auth:Entra:TenantId must be a GUID.");
    }

    private static void RegisterApplicationImplementations(IServiceCollection services, Assembly applicationAssembly)
    {
        var applicationInterfaces = applicationAssembly.GetTypes()
            .Where(type => type.IsInterface && type.Namespace?.StartsWith("SBMRAS.Application.Interfaces", StringComparison.Ordinal) == true)
            .ToArray();
        var implementationAssemblies = new[]
        {
            typeof(SBMRAS.Domain.Services.RequestsService).Assembly,
            typeof(StoredProcedureExecutor).Assembly,
        };
        foreach (var implementation in implementationAssemblies.SelectMany(assembly => assembly.GetTypes())
                     .Where(type => type.IsClass && !type.IsAbstract))
        {
            foreach (var contract in applicationInterfaces.Where(contract => contract.IsAssignableFrom(implementation)))
                services.AddScoped(contract, implementation);
        }
    }
}
