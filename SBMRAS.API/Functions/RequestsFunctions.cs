using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.API.Functions;

/// <summary>Blood requests (citizen) + coordination endpoints (contract §6 Blood requests).</summary>
public sealed class RequestsFunctions(IRequestsService service, ICurrentUserAccessor currentUser)
{
    [Function("GetBloodRequests")]
    [RequirePermission(Permissions.RequestsView)]
    public async Task<IActionResult> GetBloodRequests(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "requests")] HttpRequest req)
    {
        var query = new BloodRequestSearchQuery
        {
            Scope = RequestsHttp.Query(req, "scope"),
            Status = RequestsHttp.Query(req, "status"),
            Urgency = RequestsHttp.Query(req, "urgency"),
            AboGroup = RequestsHttp.Query(req, "aboGroup"),
            AreaId = RequestsHttp.QueryInt(req, "areaId"),
            Search = RequestsHttp.Query(req, "search"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return RequestsHttp.Ok(await service.SearchAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("GetBloodRequest")]
    [RequirePermission(Permissions.RequestsView)]
    public async Task<IActionResult> GetBloodRequest(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "requests/{id:int}")] HttpRequest req, int id)
        => RequestsHttp.Ok(await service.GetAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));

    [Function("CreateBloodRequest")]
    [RequirePermission(Permissions.RequestsCreate)]
    public async Task<IActionResult> CreateBloodRequest(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "requests")] HttpRequest req)
    {
        var body = await RequestsHttp.ReadBodyAsync<BloodRequestSaveDto>(req);
        var idempotencyKey = req.Headers[Headers.IdempotencyKey].FirstOrDefault();
        var result = await service.CreateAsync(RequestsHttp.User(currentUser), body!, idempotencyKey, req.HttpContext.RequestAborted);
        return RequestsHttp.Ok(result, $"Blood request {result.RequestNo} submitted.");
    }

    [Function("CancelBloodRequest")]
    [RequirePermission(Permissions.RequestsCreate)]
    public async Task<IActionResult> CancelBloodRequest(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "requests/{id:int}/cancel")] HttpRequest req, int id)
    {
        var body = await RequestsHttp.ReadBodyAsync<BloodRequestCancelDto>(req, optional: true) ?? new BloodRequestCancelDto();
        var result = await service.CancelAsync(RequestsHttp.User(currentUser), id, body, req.HttpContext.RequestAborted);
        return RequestsHttp.Ok(result, $"Blood request {result.RequestNo} cancelled.");
    }

    [Function("ChangeBloodRequestStatus")]
    [RequirePermission(Permissions.RequestsManage)]
    public async Task<IActionResult> ChangeBloodRequestStatus(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "requests/{id:int}/status")] HttpRequest req, int id)
    {
        var body = await RequestsHttp.ReadBodyAsync<BloodRequestStatusChangeDto>(req);
        var result = await service.ChangeStatusAsync(RequestsHttp.User(currentUser), id, body!, req.HttpContext.RequestAborted);
        return RequestsHttp.Ok(result, $"Blood request {result.RequestNo} is now {result.Status}.");
    }

    [Function("GetRequestMatches")]
    [RequirePermission(Permissions.RequestsView)]
    public async Task<IActionResult> GetRequestMatches(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "requests/{id:int}/matches")] HttpRequest req, int id)
        => RequestsHttp.Ok(await service.GetMatchesAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));
}

/// <summary>In-app notifications of the signed-in user (contract §6 Notifications).</summary>
public sealed class NotificationsFunctions(INotificationsService service, ICurrentUserAccessor currentUser)
{
    [Function("GetNotifications")]
    [RequirePermission(Permissions.NotificationsView)]
    public async Task<IActionResult> GetNotifications(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "notifications")] HttpRequest req)
    {
        var query = new NotificationQuery
        {
            UnreadOnly = RequestsHttp.QueryBool(req, "unreadOnly") ?? false,
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return RequestsHttp.Ok(await service.SearchAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("GetUnreadNotificationCount")]
    [RequirePermission(Permissions.NotificationsView)]
    public async Task<IActionResult> GetUnreadNotificationCount(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "notifications/unread-count")] HttpRequest req)
        => RequestsHttp.Ok(await service.GetUnreadCountAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("MarkNotificationRead")]
    [RequirePermission(Permissions.NotificationsView)]
    public async Task<IActionResult> MarkNotificationRead(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "notifications/{id:long}/read")] HttpRequest req, long id)
        => RequestsHttp.Ok(await service.MarkReadAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted),
            "Notification marked as read.");

    [Function("MarkAllNotificationsRead")]
    [RequirePermission(Permissions.NotificationsView)]
    public async Task<IActionResult> MarkAllNotificationsRead(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "notifications/read-all")] HttpRequest req)
    {
        var updated = await service.MarkAllReadAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted);
        return RequestsHttp.Ok(new { updated, count = 0 }, $"{updated} notification(s) marked as read.");
    }
}

/// <summary>Request parsing + envelope helpers shared by the Requests/Notifications functions.</summary>
internal static class RequestsHttp
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static CurrentUser User(ICurrentUserAccessor accessor) => accessor.User ?? throw AppException.Unauthorized();

    public static IActionResult Ok<T>(T data, string message = "Success") => new OkObjectResult(ApiResponse<T>.Ok(data, message));

    public static string? Query(HttpRequest req, string name)
    {
        var value = req.Query[name].FirstOrDefault();
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    public static int? QueryInt(HttpRequest req, string name)
    {
        var value = Query(req, name);
        if (value is null) return null;
        return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var number)
            ? number
            : throw AppException.BadRequest($"Query parameter '{name}' must be a whole number.");
    }

    public static bool? QueryBool(HttpRequest req, string name)
    {
        var value = Query(req, name);
        if (value is null) return null;
        if (bool.TryParse(value, out var flag)) return flag;
        return value switch
        {
            "1" => true,
            "0" => false,
            _ => throw AppException.BadRequest($"Query parameter '{name}' must be true or false."),
        };
    }

    public static async Task<T?> ReadBodyAsync<T>(HttpRequest req, bool optional = false) where T : class
    {
        using var reader = new StreamReader(req.Body);
        var text = await reader.ReadToEndAsync(req.HttpContext.RequestAborted);
        try
        {
            var body = string.IsNullOrWhiteSpace(text) ? null : JsonSerializer.Deserialize<T>(text, JsonOptions);
            return body ?? (optional ? null : throw AppException.BadRequest("Request body is required."));
        }
        catch (JsonException)
        {
            throw AppException.BadRequest("Request body is not valid JSON.");
        }
    }
}
