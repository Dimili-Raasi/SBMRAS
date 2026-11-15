using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.Logging;
using SBMRAS.Application.Common;

namespace SBMRAS.API.Middleware;

public sealed class GlobalExceptionMiddleware(ILogger<GlobalExceptionMiddleware> logger) : IFunctionsWorkerMiddleware
{
    public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
    {
        try
        {
            await next(context);
        }
        catch (Exception exception)
        {
            var httpContext = context.GetHttpContext();
            if (httpContext is null)
                throw;

            var (status, message, errors) = MapException(exception);
            if (status >= 500)
                logger.LogError(exception, "Unhandled exception in function {FunctionName}", context.FunctionDefinition.Name);
            else
                logger.LogInformation("Request failed in function {FunctionName}: {Message}", context.FunctionDefinition.Name, exception.Message);

            context.GetInvocationResult().Value = new ObjectResult(ApiResponse<object>.Fail(message, errors))
            {
                StatusCode = status,
            };
        }
    }

    private static (int Status, string Message, IReadOnlyList<string> Errors) MapException(Exception exception)
    {
        if (exception is AppException appException)
            return (appException.StatusCode, appException.Message, appException.Errors);

        if (FindSqlException(exception) is { } sqlException)
        {
            var status = sqlException.Number switch
            {
                >= 50001 and <= 50099 => 409,
                50400 => 400,
                50403 => 403,
                50404 => 404,
                50409 => 409,
                _ => 0,
            };
            if (status != 0)
                return (status, sqlException.Message, []);
        }

        return (500, "An unexpected error occurred.", []);
    }

    private static SqlException? FindSqlException(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
            if (current is SqlException sqlException) return sqlException;
        return null;
    }
}
