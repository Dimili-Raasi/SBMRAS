using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Infrastructure.Auth;

namespace SBMRAS.API.Middleware;

public sealed class RequestContextMiddleware : IFunctionsWorkerMiddleware
{
    public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
    {
        var httpContext = context.GetHttpContext();
        if (httpContext is null)
        {
            await next(context);
            return;
        }

        var requestContext = context.InstanceServices.GetRequiredService<IRequestContext>();
        var configuration = context.InstanceServices.GetRequiredService<IConfiguration>();
        var tokenValidator = context.InstanceServices.GetRequiredService<EntraTokenValidator>();
        var userContextLoader = context.InstanceServices.GetRequiredService<UserContextLoader>();
        var suppliedId = httpContext.Request.Headers["X-Correlation-Id"].FirstOrDefault();
        requestContext.CorrelationId = !string.IsNullOrWhiteSpace(suppliedId) && suppliedId.Length <= 64
            ? suppliedId.Trim()
            : Guid.NewGuid().ToString("N");
        httpContext.Response.Headers["X-Correlation-Id"] = requestContext.CorrelationId;

        var accessor = context.InstanceServices.GetRequiredService<ICurrentUserAccessor>();
        var mode = configuration["Auth:Mode"] ?? "DevHeader";
        if (mode.Equals("DevHeader", StringComparison.OrdinalIgnoreCase))
        {
            if (httpContext.Request.Headers.TryGetValue("X-User-Id", out var value) && !string.IsNullOrWhiteSpace(value))
            {
                if (!int.TryParse(value.ToString(), out var userId) || userId <= 0)
                    throw AppException.Unauthorized("The development user identity is invalid.");
                accessor.User = await userContextLoader.LoadDevUserAsync(userId, httpContext.RequestAborted);
            }
        }
        else
        {
            var authorization = httpContext.Request.Headers.Authorization.FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(authorization))
            {
                if (!authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                    throw AppException.Unauthorized("A bearer access token is required.");
                try
                {
                    var identity = await tokenValidator.ValidateAsync(
                        authorization["Bearer ".Length..].Trim(), httpContext.RequestAborted);
                    accessor.User = await userContextLoader.ResolveEntraUserAsync(identity, httpContext.RequestAborted);
                }
                catch (AppException)
                {
                    throw;
                }
                catch (Exception exception) when (exception is Microsoft.IdentityModel.Tokens.SecurityTokenException
                                                   or ArgumentException)
                {
                    throw AppException.Unauthorized("The access token is invalid.");
                }
            }
        }

        await next(context);
    }
}
