using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.API.Functions;

public sealed class FacilitiesFunctions(IFacilityService service, ICurrentUserAccessor currentUser, IRequestContext requestContext) : FunctionBase
{
    [Function("GetMyFacilities")]
    [RequirePermission(Permissions.FacilitiesView)]
    public async Task<IActionResult> GetMyFacilities([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "facilities")] HttpRequest req)
    {
        var query = new FacilitySearchQuery
        {
            FacilityType = RequestsHttp.Query(req, "facilityType"),
            Search = RequestsHttp.Query(req, "search"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchMineAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("GetFacility")]
    [RequirePermission(Permissions.FacilitiesView)]
    public async Task<IActionResult> GetFacility([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "facilities/{id:int}")] HttpRequest req, int id)
        => Ok(await service.GetByIdAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));

    [Function("UpdateFacility")]
    [RequirePermission(Permissions.FacilitiesManage)]
    public async Task<IActionResult> UpdateFacility([HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "facilities/{id:int}")] HttpRequest req, int id)
        => Ok(await service.UpdateAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<FacilityUpdateDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Facility updated.");

    [Function("GetInventoryHistory")]
    [RequirePermission(Permissions.FacilitiesView)]
    public async Task<IActionResult> GetInventoryHistory(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "facilities/{id:int}/history")] HttpRequest req, int id)
    {
        var query = new InventoryHistoryQuery { Kind = RequestsHttp.Query(req, "kind"), Top = RequestsHttp.QueryInt(req, "top") };
        return Ok(await service.GetSnapshotsAsync(RequestsHttp.User(currentUser), id, query, req.HttpContext.RequestAborted));
    }
}

public sealed class InventoryFunctions(IInventoryService service, ICurrentUserAccessor currentUser, IRequestContext requestContext) : FunctionBase
{
    [Function("GetResourceInventory")]
    [RequirePermission(Permissions.ResourcesManage)]
    public async Task<IActionResult> GetResourceInventory(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "facilities/{id:int}/resources")] HttpRequest req, int id)
        => Ok(await service.GetResourcesAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));

    [Function("SubmitResourceUpdate")]
    [RequirePermission(Permissions.ResourcesManage)]
    public async Task<IActionResult> SubmitResourceUpdate(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "facilities/{id:int}/resources/updates")] HttpRequest req, int id)
        => Ok(await service.SubmitResourceUpdateAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<ResourceUpdateDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Resource inventory update submitted.");

    [Function("GetBloodStock")]
    [RequirePermission(Permissions.BloodStockManage)]
    public async Task<IActionResult> GetBloodStock(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "facilities/{id:int}/blood-stock")] HttpRequest req, int id)
        => Ok(await service.GetBloodStockAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));

    [Function("SubmitBloodStockUpdate")]
    [RequirePermission(Permissions.BloodStockManage)]
    public async Task<IActionResult> SubmitBloodStockUpdate(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "facilities/{id:int}/blood-stock/updates")] HttpRequest req, int id)
        => Ok(await service.SubmitBloodStockUpdateAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<BloodStockUpdateDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Blood stock update submitted.");

    [Function("ConfirmBloodStock")]
    [RequirePermission(Permissions.BloodStockManage)]
    public async Task<IActionResult> ConfirmBloodStock(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "facilities/{id:int}/blood-stock/confirm")] HttpRequest req, int id)
        => Ok(await service.ConfirmBloodStockAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<BloodStockConfirmDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Blood stock confirmed.");
}

public sealed class InventoryChangesFunctions(IInventoryChangeService service, ICurrentUserAccessor currentUser, IRequestContext requestContext)
    : FunctionBase
{
    [Function("GetInventoryChanges")]
    [RequirePermission(Permissions.InventoryVerify)]
    public async Task<IActionResult> GetInventoryChanges(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "inventory-changes")] HttpRequest req)
    {
        var query = new InventoryChangeSearchQuery
        {
            Status = RequestsHttp.Query(req, "status"),
            FacilityId = RequestsHttp.QueryInt(req, "facilityId"),
            InventoryKind = RequestsHttp.Query(req, "inventoryKind"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("DecideInventoryChange")]
    [RequirePermission(Permissions.InventoryVerify)]
    public async Task<IActionResult> DecideInventoryChange(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "inventory-changes/{id:int}/decision")] HttpRequest req, int id)
        => Ok(await service.DecideAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<InventoryChangeDecisionDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Inventory change decision recorded.");
}

public sealed class ImportsFunctions(IImportService service, ICurrentUserAccessor currentUser, IRequestContext requestContext) : FunctionBase
{
    [Function("GetImportBatches")]
    [RequirePermission(Permissions.InventoryImport)]
    public async Task<IActionResult> GetImportBatches([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "imports")] HttpRequest req)
    {
        var query = new ImportSearchQuery
        {
            FacilityId = RequestsHttp.QueryInt(req, "facilityId"),
            Status = RequestsHttp.Query(req, "status"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("CreateImportBatch")]
    [RequirePermission(Permissions.InventoryImport)]
    public async Task<IActionResult> CreateImportBatch([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "imports")] HttpRequest req)
        => Created(await service.StageAsync(RequestsHttp.User(currentUser),
            (await RequestsHttp.ReadBodyAsync<ImportCreateDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Import batch staged.");

    [Function("GetImportBatch")]
    [RequirePermission(Permissions.InventoryImport)]
    public async Task<IActionResult> GetImportBatch(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "imports/{id:int}")] HttpRequest req, int id)
        => Ok(await service.GetByIdAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));

    [Function("CommitImportBatch")]
    [RequirePermission(Permissions.InventoryImport)]
    public async Task<IActionResult> CommitImportBatch(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "imports/{id:int}/commit")] HttpRequest req, int id)
        => Ok(await service.CommitAsync(RequestsHttp.User(currentUser), id, req.Headers[Headers.IdempotencyKey].FirstOrDefault(),
            requestContext.CorrelationId, req.HttpContext.RequestAborted), "Import batch committed.");

    [Function("CancelImportBatch")]
    [RequirePermission(Permissions.InventoryImport)]
    public async Task<IActionResult> CancelImportBatch(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "imports/{id:int}/cancel")] HttpRequest req, int id)
        => Ok(await service.CancelAsync(RequestsHttp.User(currentUser), id, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Import batch cancelled.");
}

public sealed class DataQualityFunctions(IDataQualityService service, ICurrentUserAccessor currentUser, IRequestContext requestContext)
    : FunctionBase
{
    [Function("GetDataQualitySummary")]
    [RequirePermission(Permissions.DataQualityView)]
    public async Task<IActionResult> GetDataQualitySummary(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "data-quality/summary")] HttpRequest req)
    {
        var query = new DataQualitySummaryQuery { FacilityId = RequestsHttp.QueryInt(req, "facilityId") };
        return Ok(await service.GetSummaryAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("GetDataQualityIssues")]
    [RequirePermission(Permissions.DataQualityView)]
    public async Task<IActionResult> GetDataQualityIssues(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "data-quality/issues")] HttpRequest req)
    {
        var query = new DataQualityIssueQuery
        {
            Status = RequestsHttp.Query(req, "status"),
            Severity = RequestsHttp.Query(req, "severity"),
            IssueCode = RequestsHttp.Query(req, "issueCode"),
            FacilityId = RequestsHttp.QueryInt(req, "facilityId"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchIssuesAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("ResolveDataQualityIssue")]
    [RequirePermission(Permissions.DataQualityView)]
    public async Task<IActionResult> ResolveDataQualityIssue(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "data-quality/issues/{id:int}/resolve")] HttpRequest req, int id)
        => Ok(await service.ResolveIssueAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<DataQualityResolveDto>(req))!, requestContext.CorrelationId, req.HttpContext.RequestAborted),
            "Data quality issue resolved.");

    [Function("RunDataQualityScan")]
    [RequirePermission(Permissions.DataQualityView)]
    public async Task<IActionResult> RunDataQualityScan([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "data-quality/scan")] HttpRequest req)
    {
        var body = await RequestsHttp.ReadBodyAsync<DataQualityScanDto>(req);
        return Ok(await service.ScanAsync(RequestsHttp.User(currentUser), body ?? new DataQualityScanDto(),
            requestContext.CorrelationId, req.HttpContext.RequestAborted), "Data quality scan complete.");
    }
}
