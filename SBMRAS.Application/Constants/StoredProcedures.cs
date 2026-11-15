namespace SBMRAS.Application.Constants;

/// <summary>Stored procedure names (dbo schema) used by the API. See SBMRAS_CONTRACT.md §3, §4.3, §6.</summary>
public static class StoredProcedures
{
    // Security / me (03)
    public const string UserGetContext = "usp_User_GetContext";
    public const string UserResolveEntra = "usp_User_ResolveEntra";
    public const string AuthGetDevUsers = "usp_Auth_GetDevUsers";
    public const string MeGetMenu = "usp_Me_GetMenu";

    // Common (04)
    public const string LookupsGet = "usp_Lookups_Get";
    public const string NotificationSearch = "usp_Notification_Search";
    public const string NotificationGetUnreadCount = "usp_Notification_GetUnreadCount";
    public const string NotificationMarkRead = "usp_Notification_MarkRead";
    public const string NotificationMarkAllRead = "usp_Notification_MarkAllRead";

    // Public (09)
    public const string PublicGetStats = "usp_Public_GetStats";
    public const string PublicSearchBlood = "usp_Public_SearchBlood";
    public const string PublicSearchResources = "usp_Public_SearchResources";
    public const string PublicSearchFacilities = "usp_Public_SearchFacilities";

    // Blood requests (09)
    public const string RequestSearch = "usp_Request_Search";
    public const string RequestGetById = "usp_Request_GetById";
    public const string RequestCreate = "usp_Request_Create";
    public const string RequestCancel = "usp_Request_Cancel";
    public const string RequestChangeStatus = "usp_Request_ChangeStatus";
    public const string RequestGetMatches = "usp_Request_GetMatches";

    // Dashboard & reports (10)
    public const string DashboardGetSummary = "usp_Dashboard_GetSummary";
    public const string DashboardGetCharts = "usp_Dashboard_GetCharts";
    public const string DashboardGetWorklist = "usp_Dashboard_GetWorklist";
    public const string DashboardGetActivity = "usp_Dashboard_GetActivity";
    public const string ReportRun = "usp_Report_Run";

    // Facilities & resources (05)
    public const string FacilitySearchMine = "usp_Facility_SearchMine";
    public const string FacilityGetById = "usp_Facility_GetById";
    public const string FacilityUpdate = "usp_Facility_Update";
    public const string ResourceGetByFacility = "usp_Resource_GetByFacility";
    public const string ResourceSubmitUpdate = "usp_Resource_SubmitUpdate";
    public const string InventoryGetSnapshots = "usp_Inventory_GetSnapshots";

    // Blood stock (06)
    public const string BloodStockGetByFacility = "usp_BloodStock_GetByFacility";
    public const string BloodStockSubmitUpdate = "usp_BloodStock_SubmitUpdate";
    public const string BloodStockConfirmCurrent = "usp_BloodStock_ConfirmCurrent";

    // Verification & data quality (07)
    public const string ChangeSearch = "usp_Change_Search";
    public const string ChangeDecide = "usp_Change_Decide";
    public const string DataQualityGetSummary = "usp_DataQuality_GetSummary";
    public const string DataQualitySearchIssues = "usp_DataQuality_SearchIssues";
    public const string DataQualityResolveIssue = "usp_DataQuality_ResolveIssue";
    public const string DataQualityScan = "usp_DataQuality_Scan";

    // Imports (08)
    public const string ImportSearch = "usp_Import_Search";
    public const string ImportStage = "usp_Import_Stage";
    public const string ImportGetById = "usp_Import_GetById";
    public const string ImportCommit = "usp_Import_Commit";
    public const string ImportCancel = "usp_Import_Cancel";

    // Audit (04/11)
    public const string AuditSearch = "usp_Audit_Search";
    public const string AuditGetEntityTimeline = "usp_Audit_GetEntityTimeline";

    // Admin (11)
    public const string AdminSearchUsers = "usp_Admin_SearchUsers";
    public const string AdminGetUser = "usp_Admin_GetUser";
    public const string AdminCreateUser = "usp_Admin_CreateUser";
    public const string AdminUpdateUser = "usp_Admin_UpdateUser";
    public const string AdminSetUserStatus = "usp_Admin_SetUserStatus";
    public const string AdminSetUserFacilities = "usp_Admin_SetUserFacilities";
    public const string AdminGetRoles = "usp_Admin_GetRoles";
    public const string AdminGetPermissions = "usp_Admin_GetPermissions";
    public const string AdminUpdateRolePermissions = "usp_Admin_UpdateRolePermissions";
    public const string FacilityAdminSearch = "usp_Facility_AdminSearch";
    public const string FacilityCreate = "usp_Facility_Create";
    public const string FacilityAdminUpdate = "usp_Facility_AdminUpdate";
    public const string FacilityVerify = "usp_Facility_Verify";
    public const string MasterDataGet = "usp_MasterData_Get";
    public const string MasterDataSave = "usp_MasterData_Save";
    public const string SettingsGet = "usp_Settings_Get";
    public const string SettingsUpdate = "usp_Settings_Update";
}

public static class ReportCodes
{
    public const string InventorySummary = "INVENTORY_SUMMARY";
    public const string FreshnessCompliance = "FRESHNESS_COMPLIANCE";
    public const string DataCompleteness = "DATA_COMPLETENESS";
    public const string ImportQuality = "IMPORT_QUALITY";
    public const string RequestLifecycle = "REQUEST_LIFECYCLE";
    public const string FacilityReliability = "FACILITY_RELIABILITY";
    public const string ResourceAvailability = "RESOURCE_AVAILABILITY";

    public static readonly IReadOnlyList<string> All =
    [
        InventorySummary, FreshnessCompliance, DataCompleteness, ImportQuality, RequestLifecycle, FacilityReliability, ResourceAvailability,
    ];
}
