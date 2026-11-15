using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using SBMRAS.API.Authorization;
using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.API.Functions;

public sealed class AdminFunctions(IAdminService service, ICurrentUserAccessor currentUser) : FunctionBase
{
    [Function("GetUsers")]
    [RequirePermission(Permissions.UsersManage)]
    public async Task<IActionResult> GetUsers([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/users")] HttpRequest req)
    {
        var query = new AdminUserSearchQuery
        {
            Search = RequestsHttp.Query(req, "search"),
            RoleCode = RequestsHttp.Query(req, "roleCode"),
            IsActive = RequestsHttp.QueryBool(req, "isActive"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchUsersAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("GetUser")]
    [RequirePermission(Permissions.UsersManage)]
    public async Task<IActionResult> GetUser([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/users/{id:int}")] HttpRequest req, int id)
        => Ok(await service.GetUserAsync(RequestsHttp.User(currentUser), id, req.HttpContext.RequestAborted));

    [Function("CreateUser")]
    [RequirePermission(Permissions.UsersManage)]
    public async Task<IActionResult> CreateUser([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "{area:regex(^admin$)}/users")] HttpRequest req)
        => Created(await service.CreateUserAsync(RequestsHttp.User(currentUser),
            (await RequestsHttp.ReadBodyAsync<UserSaveDto>(req))!, req.HttpContext.RequestAborted), "User created.");

    [Function("UpdateUser")]
    [RequirePermission(Permissions.UsersManage)]
    public async Task<IActionResult> UpdateUser([HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "{area:regex(^admin$)}/users/{id:int}")] HttpRequest req, int id)
        => Ok(await service.UpdateUserAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<UserSaveDto>(req))!, req.HttpContext.RequestAborted), "User updated.");

    [Function("SetUserStatus")]
    [RequirePermission(Permissions.UsersManage)]
    public async Task<IActionResult> SetUserStatus(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "{area:regex(^admin$)}/users/{id:int}/status")] HttpRequest req, int id)
        => Ok(await service.SetUserStatusAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<UserStatusDto>(req))!, req.HttpContext.RequestAborted), "User status updated.");

    [Function("SetUserFacilities")]
    [RequirePermission(Permissions.UsersManage)]
    public async Task<IActionResult> SetUserFacilities(
        [HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "{area:regex(^admin$)}/users/{id:int}/facilities")] HttpRequest req, int id)
        => Ok(await service.SetUserFacilitiesAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<UserFacilitiesDto>(req))!, req.HttpContext.RequestAborted), "User facility assignments updated.");

    [Function("GetRoles")]
    [RequirePermission(Permissions.RolesManage)]
    public async Task<IActionResult> GetRoles([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/roles")] HttpRequest req)
        => Ok(await service.GetRolesAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("GetPermissions")]
    [RequirePermission(Permissions.RolesManage)]
    public async Task<IActionResult> GetPermissions([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/permissions")] HttpRequest req)
        => Ok(await service.GetPermissionsAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("UpdateRolePermissions")]
    [RequirePermission(Permissions.RolesManage)]
    public async Task<IActionResult> UpdateRolePermissions(
        [HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "{area:regex(^admin$)}/roles/{id:int}/permissions")] HttpRequest req, int id)
        => Ok(await service.UpdateRolePermissionsAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<RolePermissionsDto>(req))!, req.HttpContext.RequestAborted), "Role permissions updated.");

    [Function("GetFacilitiesAdmin")]
    [RequirePermission(Permissions.FacilitiesVerify)]
    public async Task<IActionResult> GetFacilitiesAdmin(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/facilities")] HttpRequest req)
    {
        var query = new AdminFacilitySearchQuery
        {
            Status = RequestsHttp.Query(req, "status"),
            FacilityType = RequestsHttp.Query(req, "facilityType"),
            Search = RequestsHttp.Query(req, "search"),
            Page = RequestsHttp.QueryInt(req, "page") ?? 1,
            PageSize = RequestsHttp.QueryInt(req, "pageSize") ?? 20,
        };
        return Ok(await service.SearchFacilitiesAsync(RequestsHttp.User(currentUser), query, req.HttpContext.RequestAborted));
    }

    [Function("CreateAdminFacility")]
    [RequirePermission(Permissions.FacilitiesVerify)]
    public async Task<IActionResult> CreateAdminFacility(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "{area:regex(^admin$)}/facilities")] HttpRequest req)
        => Created(await service.CreateFacilityAsync(RequestsHttp.User(currentUser),
            (await RequestsHttp.ReadBodyAsync<FacilitySaveDto>(req))!, req.HttpContext.RequestAborted), "Facility created.");

    [Function("UpdateAdminFacility")]
    [RequirePermission(Permissions.FacilitiesVerify)]
    public async Task<IActionResult> UpdateAdminFacility(
        [HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "{area:regex(^admin$)}/facilities/{id:int}")] HttpRequest req, int id)
        => Ok(await service.UpdateFacilityAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<FacilitySaveDto>(req))!, req.HttpContext.RequestAborted), "Facility updated.");

    [Function("VerifyFacility")]
    [RequirePermission(Permissions.FacilitiesVerify)]
    public async Task<IActionResult> VerifyFacility(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "{area:regex(^admin$)}/facilities/{id:int}/verify")] HttpRequest req, int id)
        => Ok(await service.VerifyFacilityAsync(RequestsHttp.User(currentUser), id,
            (await RequestsHttp.ReadBodyAsync<FacilityVerifyDto>(req))!, req.HttpContext.RequestAborted), "Facility status updated.");

    [Function("GetMasterData")]
    [RequirePermission(Permissions.MasterDataManage)]
    public async Task<IActionResult> GetMasterData(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/master-data/{type}")] HttpRequest req, string type)
        => Ok(await service.GetMasterDataAsync(RequestsHttp.User(currentUser), type, req.HttpContext.RequestAborted));

    [Function("SaveMasterData")]
    [RequirePermission(Permissions.MasterDataManage)]
    public async Task<IActionResult> SaveMasterData(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "{area:regex(^admin$)}/master-data/{type}")] HttpRequest req, string type)
    {
        using var body = await RequestsHttp.ReadBodyAsync<System.Text.Json.JsonDocument>(req);
        return Ok(await service.SaveMasterDataAsync(RequestsHttp.User(currentUser), type, body!.RootElement.Clone(), req.HttpContext.RequestAborted),
            "Master data saved.");
    }

    [Function("GetSettings")]
    [RequirePermission(Permissions.SettingsManage)]
    public async Task<IActionResult> GetSettings([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "{area:regex(^admin$)}/settings")] HttpRequest req)
        => Ok(await service.GetSettingsAsync(RequestsHttp.User(currentUser), req.HttpContext.RequestAborted));

    [Function("UpdateSettings")]
    [RequirePermission(Permissions.SettingsManage)]
    public async Task<IActionResult> UpdateSettings([HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "{area:regex(^admin$)}/settings")] HttpRequest req)
        => Ok(await service.UpdateSettingsAsync(RequestsHttp.User(currentUser),
            (await RequestsHttp.ReadBodyAsync<SettingsUpdateDto>(req))!, req.HttpContext.RequestAborted), "Settings updated.");
}
