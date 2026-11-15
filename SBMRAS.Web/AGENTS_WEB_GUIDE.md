# SBMRAS Web agent guide

This Angular 20 app is the SBMRAS web client. Work only in `SBMRAS.Web`; do not modify `FRRMS`.
Use the Clinical Science palette in `src/styles.scss` and keep all navigation in the two-tier top
navigation shell (`src/app/shell/app-shell.ts`). Do not add a side navigation or a dropdown-only menu.

## Shared APIs

### Core services

Import services from `src/app/core/services` using the matching relative path:

- `ApiService` (`api.service.ts`): `get<T>(url, params?)`, `getPaged<T>(url, params?)`,
  `post<T>(url, body?, headers?)`, `put<T>(url, body?, headers?)`, and
  `download(url, params, fileName)`. API paths are relative to `/api/v1` (for example
  `requests/42`); the service unwraps `{ success, message, data, errors }` and HTTP failures
  are normalized to `ApiError`.
- `SessionService` (`session.service.ts`): signals `user()`, `isAuthenticated()`,
  `permissions()`, `facilities()`; `hasPermission(code)`, `hasAnyPermission(codes)`,
  `load(force?)`, `setUser(user)`, and `signOut()`.
- `AuthService` (`auth.service.ts`): resolves DevHeader/MSAL Entra mode from `auth/config`,
  supplies `authorizationHeaders()`, loads development users with `devUsers()`, and supports
  `signIn(userId?)` / `signOut()`.
- `MenuService` (`menu.service.ts`): signals `sections()`, `activeSection()`, `activeItems()`;
  use `load()` and `selectSection(section)`.
- `NotificationBadgeService` (`notification-badge.service.ts`): `count()` signal and `refresh()`.
- `LookupService` (`lookup.service.ts`): cached `load(force?)` observable and `data()` signal;
  `set(lookups)` updates the local lookup value.
- `UiService` (`ui.service.ts`): `success(message)`, `error(message)`,
  `confirm({ title, message, confirmText?, danger? }) : Promise<boolean>`, and
  `reason({ title, label?, required? }) : Promise<string | null>`.
- `LoadingService` exposes the global `isLoading()` signal.

Feature API services and their models are owned by the feature that uses them. Existing feature
services are `RequestsService`, `ImportsService`, `VerificationService`, `DataQualityService`,
`NotificationsService`, and `AdminService`, under `src/app/core/services`.

### Shared components, directive and pipes

Use the standalone shared exports (no NgModule):

| Export | Import path |
|---|---|
| `PageHeader` | `src/app/shared/components/page-header.ts` |
| `StatePanel` | `src/app/shared/components/state-panel.ts` |
| `StatusChip` | `src/app/shared/components/status-chip.ts` |
| `FreshnessBadge` | `src/app/shared/components/freshness-badge.ts` |
| `BloodGroupTile` | `src/app/shared/components/blood-group-tile.ts` |
| `UrgencyBadge` | `src/app/shared/components/urgency-badge.ts` |
| `QualityGauge` | `src/app/shared/components/quality-gauge.ts` |
| `KpiCard` | `src/app/shared/components/kpi-card.ts` |
| `ChartView` | `src/app/shared/components/chart-view.ts` |
| `AuditTimeline` | `src/app/shared/components/audit-timeline.ts` |
| `HasPermissionDirective` | `src/app/core/directives/has-permission.directive.ts` |
| `SbDatePipe` | `src/app/shared/pipes/sb-date.pipe.ts` |
| `SbRelativePipe` | `src/app/shared/pipes/sb-relative.pipe.ts` |
| `SbQtyPipe` | `src/app/shared/pipes/sb-qty.pipe.ts` |

`PageHeader` accepts `title`, optional `subtitle` and `icon`, and projects actions. `StatePanel`
accepts `state` (`loading`, `empty`, `error`) and `message`, and emits `retry`. The permission
directive is used as `*sbHasPermission="'permission.code'"`.

## Routes and feature ownership

Routes live in `src/app/app.routes.ts`; use lazy standalone routes and apply `authGuard` plus
`permissionGuard`/route `data.permission` for protected screens. Import the following existing
screens rather than replacing them:

| Route | Export and source |
|---|---|
| `/requests` | `RequestBrowser`, `features/requests/request-browser/request-browser.ts` |
| `/requests/new` | `RequestForm`, `features/requests/request-form/request-form.ts` |
| `/requests/:id` | `RequestView`, `features/requests/request-view/request-view.ts` |
| `/coordination` | `RequestBrowser` (`mode: coordination`) |
| `/coordination/:id` | `RequestView` (`mode: coordination`) |
| `/imports` | `ImportList`, `features/imports/import-list.ts` |
| `/imports/new` | `ImportNew`, `features/imports/import-new.ts` |
| `/imports/:id` | `ImportDetail`, `features/imports/import-detail.ts` |
| `/verifications` | `VerificationQueue`, `features/verifications/verification-queue.ts` |
| `/data-quality` | `DataQuality`, `features/data-quality/data-quality.ts` |
| `/notifications` | `Notifications`, `features/notifications/notifications.ts` |
| `/admin/users` | `AdminUsers`, `features/admin/users/admin-users.ts` |
| `/admin/roles` | `AdminRoles`, `features/admin/roles/admin-roles.ts` |
| `/admin/facilities` | `AdminFacilities`, `features/admin/facilities/admin-facilities.ts` |
| `/admin/master-data` | `AdminMasterData`, `features/admin/master-data/admin-master-data.ts` |
| `/admin/settings` | `AdminSettings`, `features/admin/settings/admin-settings.ts` |

New feature components should use these exact paths and PascalCase exports:

| Route(s) | Export | Source |
|---|---|---|
| `/` | `Landing` | `features/public/landing/landing.ts` |
| `/find-blood` | `FindBlood` | `features/public/find-blood/find-blood.ts` |
| `/find-resources` | `FindResources` | `features/public/find-resources/find-resources.ts` |
| `/directory` | `Directory` | `features/public/directory/directory.ts` |
| `/dashboard` | `Dashboard` | `features/insights/dashboard/dashboard.ts` |
| `/reports` | `Reports` | `features/insights/reports/reports.ts` |
| `/audit-logs` | `AuditLogs` | `features/insights/audit-logs/audit-logs.ts` |
| `/facilities` | `FacilityList` | `features/facilities/facility-list.ts` |
| `/facilities/:id` | `FacilityDetail` | `features/facilities/facility-detail.ts` |
| `/blood-stock` | `BloodStock` | `features/inventory/blood-stock.ts` |
| `/resource-inventory` | `ResourceInventory` | `features/inventory/resource-inventory.ts` |

Where a screen has no feature implementation yet, keep the safe shared `PlaceholderPage` route
until its standalone feature is ready. Authentication and shell files are under `features/auth`
and `shell`; `/login` is outside the shell while public and authenticated screens use the shell.

## Implementation rules

- Use `ViewState` (`loading`, `empty`, `error`, `ready`) and `sb-state-panel` for async screen
  states; provide retry and show server errors in human-readable form.
- Do not display missing quantities as zero; use “Not reported”.
- Parse CSV in the browser and post JSON rows; do not introduce uploads or file storage.
- Use the request/import idempotency headers where the corresponding feature service supports them.
- Keep forms keyboard accessible and use Angular Material controls already in the dependency set.
- `npm start` serves port 4400 and proxies `/api` to local Functions at `127.0.0.1:7073`;
  `npm run build` is the integration check.
