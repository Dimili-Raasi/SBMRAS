using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using SBMRAS.Application.Common;

namespace SBMRAS.API.Functions;

public abstract class FunctionBase
{
    protected static IActionResult Ok<T>(T? data, string message = "Success")
        => new OkObjectResult(ApiResponse<T>.Ok(data, message));

    protected static IActionResult Created<T>(T? data, string message = "Created")
        => new ObjectResult(ApiResponse<T>.Ok(data, message)) { StatusCode = StatusCodes.Status201Created };
}
