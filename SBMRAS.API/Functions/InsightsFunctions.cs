using System.Globalization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.API.Functions;

public sealed class DashboardFunctions(IDashboardService service, ICurrentUserAccessor currentUser) : FunctionBase
{
    [Function("GetDashboardSummary")]
    [RequirePermission(Permissions.DashboardView)]
    public async Task<IActionResult> GetDashboardSummary([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "dashboard/summary")] HttpRequest req)
        => Ok(await service.GetSummaryAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("GetDashboardCharts")]
    [RequirePermission(Permissions.DashboardView)]
    public async Task<IActionResult> GetDashboardCharts([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "dashboard/charts")] HttpRequest req)
        => Ok(await service.GetChartsAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("GetDashboardWorklist")]
    [RequirePermission(Permissions.DashboardView)]
    public async Task<IActionResult> GetDashboardWorklist([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "dashboard/worklist")] HttpRequest req)
        => Ok(await service.GetWorklistAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("GetDashboardActivity")]
    [RequirePermission(Permissions.DashboardView)]
    public async Task<IActionResult> GetDashboardActivity([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "dashboard/activity")] HttpRequest req)
    {
        var top = RequestsHttp.QueryInt(req, "top") ?? DashboardValues.DefaultActivityTop;
        return Ok(await service.GetActivityAsync(RequestsHttp.User(currentUser), top, req.HttpContext.RequestAborted));
    }
}

public sealed class ReportsFunctions(IReportService service, ICurrentUserAccessor currentUser) : FunctionBase
{
    [Function("GetReports")]
    [RequirePermission(Permissions.ReportsView)]
    public async Task<IActionResult> GetReports([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "reports")] HttpRequest req)
        => Ok(await service.GetDefinitionsAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("RunReport")]
    [RequirePermission(Permissions.ReportsView)]
    public async Task<IActionResult> RunReport(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "reports/{code}")] HttpRequest req, string code)
    {
        var query = BuildQuery(req, code);
        return Ok(await service.RunAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("ExportReport")]
    [RequirePermission(Permissions.ReportsExport)]
    public async Task<IActionResult> ExportReport(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "reports/{code}/export")] HttpRequest req, string code)
    {
        var report = await service.ExportAsync(RequestsHttp.User(currentUser), BuildQuery(req, code), req.HttpContext.RequestAborted);
        return new FileContentResult(report.Content, report.ContentType) { FileDownloadName = report.FileName };
    }

    private static ReportQuery BuildQuery(HttpRequest req, string code) => new()
    {
        Code = code,
        FromDate = DateQuery(req, "fromDate"),
        ToDate = DateQuery(req, "toDate"),
        FacilityId = RequestsHttp.QueryInt(req, "facilityId"),
        AreaId = RequestsHttp.QueryInt(req, "areaId"),
    };

    private static DateTime? DateQuery(HttpRequest request, string name)
    {
        var value = RequestsHttp.Query(request, name);
        if (value is null) return null;
        return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var result)
            ? result
            : throw AppException.BadRequest($"Query parameter '{name}' must be an ISO date.");
    }
}

public sealed class AuditFunctions(IAuditService service, ICurrentUserAccessor currentUser) : FunctionBase
{
    [Function("SearchAuditLogs")]
    [RequirePermission(Permissions.AuditView)]
    public async Task<IActionResult> SearchAuditLogs([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "audit-logs")] HttpRequest req)
    {
        var query = new AuditSearchQuery
        {
            Search = RequestsHttp.Query(req, "search"),
            EntityType = RequestsHttp.Query(req, "entityType"),
            Action = RequestsHttp.Query(req, "action"),
            FacilityId = RequestsHttp.QueryInt(req, "facilityId"),
            UserId = RequestsHttp.QueryInt(req, "userId"),
            CorrelationId = RequestsHttp.Query(req, "correlationId"),
            FromDate = DateQuery(req, "fromDate"),
            ToDate = DateQuery(req, "toDate"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("GetEntityAuditLogs")]
    [RequirePermission(Permissions.DashboardView)]
    public async Task<IActionResult> GetEntityAuditLogs(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "audit-logs/{entityType}/{entityId}")] HttpRequest req,
        string entityType, string entityId)
        => Ok(await service.GetEntityTimelineAsync(RequestsHttp.User(currentUser), entityType, entityId, req.HttpContext.RequestAborted));

    private static DateTime? DateQuery(HttpRequest request, string name)
    {
        var value = RequestsHttp.Query(request, name);
        if (value is null) return null;
        return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var result)
            ? result
            : throw AppException.BadRequest($"Query parameter '{name}' must be an ISO date.");
    }
}
