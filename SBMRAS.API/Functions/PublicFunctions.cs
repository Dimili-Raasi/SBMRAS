using System.Globalization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.API.Functions;

public sealed class PublicFunctions(IPublicService service) : FunctionBase
{
    [Function("GetPublicLookups")]
    [AllowAnonymousEndpoint]
    public async Task<IActionResult> GetPublicLookups([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "public/lookups")] HttpRequest req)
        => Ok(await service.GetLookupsAsync(req.HttpContext.RequestAborted));

    [Function("GetPublicStats")]
    [AllowAnonymousEndpoint]
    public async Task<IActionResult> GetPublicStats([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "public/stats")] HttpRequest req)
        => Ok(await service.GetStatsAsync(req.HttpContext.RequestAborted));

    [Function("SearchBloodAvailability")]
    [AllowAnonymousEndpoint]
    public async Task<IActionResult> SearchBloodAvailability(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "public/blood-availability")] HttpRequest req)
    {
        var query = new BloodAvailabilityQuery
        {
            AboGroup = RequestsHttp.Query(req, "aboGroup"),
            RhFactor = RequestsHttp.Query(req, "rhFactor"),
            ComponentId = RequestsHttp.QueryInt(req, "componentId"),
            AreaId = RequestsHttp.QueryInt(req, "areaId"),
            Search = RequestsHttp.Query(req, "search"),
            FreshOnly = RequestsHttp.QueryBool(req, "freshOnly") ?? true,
            MinQuantity = DecimalQuery(req, "minQuantity"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchBloodAsync(query, req.HttpContext.RequestAborted));
    }

    [Function("SearchMedicalResources")]
    [AllowAnonymousEndpoint]
    public async Task<IActionResult> SearchMedicalResources(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "public/medical-resources")] HttpRequest req)
    {
        var query = new ResourceAvailabilityQuery
        {
            CategoryId = RequestsHttp.QueryInt(req, "categoryId"),
            ResourceTypeId = RequestsHttp.QueryInt(req, "resourceTypeId"),
            AreaId = RequestsHttp.QueryInt(req, "areaId"),
            Search = RequestsHttp.Query(req, "search"),
            AvailableOnly = RequestsHttp.QueryBool(req, "availableOnly") ?? false,
            FreshOnly = RequestsHttp.QueryBool(req, "freshOnly") ?? true,
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchResourcesAsync(query, req.HttpContext.RequestAborted));
    }

    [Function("SearchPublicFacilities")]
    [AllowAnonymousEndpoint]
    public async Task<IActionResult> SearchPublicFacilities(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "public/facilities")] HttpRequest req)
    {
        var query = new PublicFacilityQuery
        {
            FacilityType = RequestsHttp.Query(req, "facilityType"),
            AreaId = RequestsHttp.QueryInt(req, "areaId"),
            Search = RequestsHttp.Query(req, "search"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchFacilitiesAsync(query, req.HttpContext.RequestAborted));
    }

    private static decimal? DecimalQuery(HttpRequest request, string name)
    {
        var value = RequestsHttp.Query(request, name);
        if (value is null) return null;
        return decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out var result)
            ? result
            : throw AppException.BadRequest($"Query parameter '{name}' must be a number.");
    }
}
