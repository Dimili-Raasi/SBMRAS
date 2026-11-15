/** Permission codes (contract §3.4). Use with SessionService.hasPermission / *sbHasPermission / route data. */
export const Permissions = {
  DashboardView: 'dashboard.view',
  SearchView: 'search.view',
  RequestsView: 'requests.view',
  RequestsCreate: 'requests.create',
  RequestsManage: 'requests.manage',
  FacilitiesView: 'facilities.view',
  FacilitiesManage: 'facilities.manage',
  ResourcesManage: 'resources.manage',
  BloodStockManage: 'bloodstock.manage',
  InventoryImport: 'inventory.import',
  InventoryVerify: 'inventory.verify',
  DataQualityView: 'dataquality.view',
  ReportsView: 'reports.view',
  ReportsExport: 'reports.export',
  AuditView: 'audit.view',
  NotificationsView: 'notifications.view',
  UsersManage: 'users.manage',
  RolesManage: 'roles.manage',
  FacilitiesVerify: 'facilities.verify',
  MasterDataManage: 'masterdata.manage',
  SettingsManage: 'settings.manage',
  DataViewAll: 'data.viewall',
} as const;

export type PermissionCode = (typeof Permissions)[keyof typeof Permissions];

export const Roles = {
  PublicUser: 'PublicUser',
  HospitalManagement: 'HospitalManagement',
  BloodBank: 'BloodBank',
  Admin: 'Admin',
} as const;
