using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.DependencyInjection;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;

namespace SBMRAS.API.Middleware;

public sealed class PermissionAuthorizationMiddleware : IFunctionsWorkerMiddleware
{
    public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
    {
        var metadata = FunctionAuthorizationMap.ForFunction(context.FunctionDefinition.Name);
        var user = context.InstanceServices.GetRequiredService<ICurrentUserAccessor>().User;
        if (!metadata.IsAnonymous && user is null)
            throw AppException.Unauthorized();
        if (metadata.Permission is not null && !user!.HasPermission(metadata.Permission.Permission))
            throw AppException.Forbidden();

        await next(context);
    }
}
