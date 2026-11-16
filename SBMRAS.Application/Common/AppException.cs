namespace SBMRAS.Application.Common;

public sealed class AppException : Exception
{
    public AppException(int statusCode, string message, IEnumerable<string>? errors = null, Exception? inner = null)
        : base(message, inner)
    {
        StatusCode = statusCode;
        Errors = errors?.ToArray() ?? [];
    }

    public int StatusCode { get; }
    public IReadOnlyList<string> Errors { get; }

    public static AppException BadRequest(string message, IEnumerable<string>? errors = null) => new(400, message, errors);
    public static AppException Validation(string message, IEnumerable<string>? errors = null) => new(400, message, errors);
    public static AppException Unauthorized(string message = "Authentication is required.") => new(401, message);
    public static AppException Forbidden(string message = "You do not have permission to perform this action.") => new(403, message);
    public static AppException NotFound(string message = "The requested resource was not found.") => new(404, message);
    public static AppException Conflict(string message) => new(409, message);
}
