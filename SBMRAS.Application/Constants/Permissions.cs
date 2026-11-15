namespace SBMRAS.Application.Constants;

public static class Permissions
{
    public const string DashboardView = "dashboard.view";
    public const string SearchView = "search.view";
    public const string RequestsView = "requests.view";
    public const string RequestsCreate = "requests.create";
    public const string RequestsManage = "requests.manage";
    public const string FacilitiesView = "facilities.view";
    public const string FacilitiesManage = "facilities.manage";
    public const string ResourcesManage = "resources.manage";
    public const string BloodStockManage = "bloodstock.manage";
    public const string InventoryImport = "inventory.import";
    public const string InventoryVerify = "inventory.verify";
    public const string DataQualityView = "dataquality.view";
    public const string ReportsView = "reports.view";
    public const string ReportsExport = "reports.export";
    public const string AuditView = "audit.view";
    public const string NotificationsView = "notifications.view";
    public const string UsersManage = "users.manage";
    public const string RolesManage = "roles.manage";
    public const string FacilitiesVerify = "facilities.verify";
    public const string MasterDataManage = "masterdata.manage";
    public const string SettingsManage = "settings.manage";
    public const string DataViewAll = "data.viewall";

    public static readonly IReadOnlyList<string> All =
    [
        DashboardView, SearchView, RequestsView, RequestsCreate, RequestsManage, FacilitiesView, FacilitiesManage,
        ResourcesManage, BloodStockManage, InventoryImport, InventoryVerify, DataQualityView, ReportsView, ReportsExport,
        AuditView, NotificationsView, UsersManage, RolesManage, FacilitiesVerify, MasterDataManage, SettingsManage, DataViewAll,
    ];
}
