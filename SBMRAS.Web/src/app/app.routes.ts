import { Routes } from '@angular/router';

import { authGuard } from './core/guards/auth.guard';
import { permissionGuard } from './core/guards/permission.guard';
import { AppShell } from './shell/app-shell';

export const routes: Routes = [
  { path: 'login', loadComponent: () => import('./features/auth/login').then((m) => m.Login) },
  {
    path: '',
    component: AppShell,
    children: [
      { path: '', loadComponent: () => import('./features/public/landing/landing').then((m) => m.Landing) },
      { path: 'find-blood', loadComponent: () => import('./features/public/find-blood/find-blood').then((m) => m.FindBlood) },
      { path: 'find-resources', loadComponent: () => import('./features/public/find-resources/find-resources').then((m) => m.FindResources) },
      { path: 'directory', loadComponent: () => import('./features/public/directory/directory').then((m) => m.Directory) },
      { path: 'forbidden', loadComponent: () => import('./features/auth/forbidden').then((m) => m.Forbidden) },
      { path: 'dashboard', loadComponent: () => import('./features/insights/dashboard/dashboard').then((m) => m.Dashboard), canActivate: [authGuard, permissionGuard], data: { permission: 'dashboard.view' } },
      { path: 'requests', loadComponent: () => import('./features/requests/request-browser/request-browser').then((m) => m.RequestBrowser), canActivate: [authGuard, permissionGuard], data: { permission: 'requests.view', mode: 'mine' } },
      { path: 'requests/new', loadComponent: () => import('./features/requests/request-form/request-form').then((m) => m.RequestForm), canActivate: [authGuard, permissionGuard], data: { permission: 'requests.create' } },
      { path: 'requests/:id', loadComponent: () => import('./features/requests/request-view/request-view').then((m) => m.RequestView), canActivate: [authGuard, permissionGuard], data: { permission: 'requests.view', mode: 'requester' } },
      { path: 'coordination', loadComponent: () => import('./features/requests/request-browser/request-browser').then((m) => m.RequestBrowser), canActivate: [authGuard, permissionGuard], data: { permission: 'requests.manage', mode: 'coordination' } },
      { path: 'coordination/:id', loadComponent: () => import('./features/requests/request-view/request-view').then((m) => m.RequestView), canActivate: [authGuard, permissionGuard], data: { permission: 'requests.manage', mode: 'coordination' } },
      { path: 'facilities', loadComponent: () => import('./features/facilities/facility-list').then((m) => m.FacilityList), canActivate: [authGuard, permissionGuard], data: { permission: 'facilities.view' } },
      { path: 'facilities/:id', loadComponent: () => import('./features/facilities/facility-detail').then((m) => m.FacilityDetail), canActivate: [authGuard, permissionGuard], data: { permission: 'facilities.view' } },
      { path: 'resource-inventory', loadComponent: () => import('./features/inventory/resource-inventory').then((m) => m.ResourceInventory), canActivate: [authGuard, permissionGuard], data: { permission: 'resources.manage' } },
      { path: 'blood-stock', loadComponent: () => import('./features/inventory/blood-stock').then((m) => m.BloodStock), canActivate: [authGuard, permissionGuard], data: { permission: 'bloodstock.manage' } },
      { path: 'imports', loadComponent: () => import('./features/imports/import-list').then((m) => m.ImportList), canActivate: [authGuard, permissionGuard], data: { permission: 'inventory.import' } },
      { path: 'imports/new', loadComponent: () => import('./features/imports/import-new').then((m) => m.ImportNew), canActivate: [authGuard, permissionGuard], data: { permission: 'inventory.import' } },
      { path: 'imports/:id', loadComponent: () => import('./features/imports/import-detail').then((m) => m.ImportDetail), canActivate: [authGuard, permissionGuard], data: { permission: 'inventory.import' } },
      { path: 'verifications', loadComponent: () => import('./features/verifications/verification-queue').then((m) => m.VerificationQueue), canActivate: [authGuard, permissionGuard], data: { permission: 'inventory.verify' } },
      { path: 'data-quality', loadComponent: () => import('./features/data-quality/data-quality').then((m) => m.DataQuality), canActivate: [authGuard, permissionGuard], data: { permission: 'dataquality.view' } },
      { path: 'reports', loadComponent: () => import('./features/insights/reports/reports').then((m) => m.Reports), canActivate: [authGuard, permissionGuard], data: { permission: 'reports.view' } },
      { path: 'audit-logs', loadComponent: () => import('./features/insights/audit-logs/audit-logs').then((m) => m.AuditLogs), canActivate: [authGuard, permissionGuard], data: { permission: 'audit.view' } },
      { path: 'notifications', loadComponent: () => import('./features/notifications/notifications').then((m) => m.Notifications), canActivate: [authGuard, permissionGuard], data: { permission: 'notifications.view' } },
      { path: 'profile', loadComponent: () => import('./features/auth/profile').then((m) => m.Profile), canActivate: [authGuard] },
      { path: 'admin/users', loadComponent: () => import('./features/admin/users/admin-users').then((m) => m.AdminUsers), canActivate: [authGuard, permissionGuard], data: { permission: 'users.manage' } },
      { path: 'admin/roles', loadComponent: () => import('./features/admin/roles/admin-roles').then((m) => m.AdminRoles), canActivate: [authGuard, permissionGuard], data: { permission: 'roles.manage' } },
      { path: 'admin/facilities', loadComponent: () => import('./features/admin/facilities/admin-facilities').then((m) => m.AdminFacilities), canActivate: [authGuard, permissionGuard], data: { permission: 'facilities.verify' } },
      { path: 'admin/master-data', loadComponent: () => import('./features/admin/master-data/admin-master-data').then((m) => m.AdminMasterData), canActivate: [authGuard, permissionGuard], data: { permission: 'masterdata.manage' } },
      { path: 'admin/settings', loadComponent: () => import('./features/admin/settings/admin-settings').then((m) => m.AdminSettings), canActivate: [authGuard, permissionGuard], data: { permission: 'settings.manage' } },
      { path: '**', loadComponent: () => import('./features/auth/not-found').then((m) => m.NotFound) },
    ],
  },
  { path: '**', loadComponent: () => import('./features/auth/not-found').then((m) => m.NotFound) },
];
