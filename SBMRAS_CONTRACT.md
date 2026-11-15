# SBMRAS — Shared Implementation Contract (source of truth for all agents)

SBMRAS = **Smart Blood and Medical Resource Availability System**. A centralized platform where verified hospitals and
blood banks publish blood stock and medical-resource availability with **freshness, provenance and audit**; the public
searches availability anonymously and (after self-registration through Microsoft Entra External ID) raises **blood
requests** that institutional users coordinate. Admins govern users, facility verification, master data, settings, audit.
SBMRAS is a coordination/visibility platform — it never reserves stock or makes clinical/compatibility decisions.

Repo root: `C:\Users\rohit\Downloads\SBMRAS` (git repo `Dimili-Raasi/SBMRAS`). Requirements source:
`C:\Users\rohit\.copilot\session-state\05f1b59d-adda-43ea-929f-2f3a279006cd\files\sdd.txt` (plain-text SDD).
`FRRMS\` is a **READ-ONLY reference** implementation of the same architecture (patterns, config, CI/CD, scripts). **Never
modify, copy-reference, or build anything inside `FRRMS\`; never add FRRMS projects to the SBMRAS solution.** Copy patterns
and rename (FRRMS→SBMRAS, Frrms→Sbmras, frrms→sbmras) and adapt to this contract. Do not `git commit`.

## 1. Technology & layout (mandatory)
| Layer | Tech | Folder |
|---|---|---|
| Web | Angular **20** standalone + signals, Angular Material 20, Bootstrap 5 (grid/utilities only), SCSS, Chart.js 4, @azure/msal-browser | `SBMRAS.Web` |
| API | Azure Functions .NET 10 isolated worker (ASP.NET Core integration), host `routePrefix` = `api/v1` | `SBMRAS.API` |
| Application | Common (AppException, ApiResponse, PagedResult, CurrentUser, ResultShape, abstractions), request DTOs, FluentValidation validators, constants (Permissions, Roles, StoredProcedures), repository + service interfaces | `SBMRAS.Application` |
| Domain | Per-module service implementations (validation + orchestration), enums/rules (freshness, request state machine) | `SBMRAS.Domain` |
| Infrastructure | `SqlDbConnectionFactory`, generic `StoredProcedureExecutor` (Dapper; parses `SQL\*.sql` headers like FRRMS), per-module repositories, `EntraTokenValidator`, SQL scripts | `SBMRAS.Infrastructure` |
| Tests | xUnit + NSubstitute + Xunit.SkippableFact | `tests\SBMRAS.Tests` |
| Solution | `SBMRAS.API.slnx` (API, Application, Domain, Infrastructure, tests) | repo root |
| DB | SQL Server, **stored procedures only** from the API (views/functions inside SQL). DB `SBMRAS` (tests: `SBMRAS_Test`) on `localhost` default instance, Windows auth. | `SBMRAS.Infrastructure\SQL` |
| CI/CD & ops | `.github\workflows`, `.github\actions`, `infra\` (bicep), `deploy\` (iis, cloudflare, functions), `scripts\` (database, local), `.vscode`, `docs\` | repo root |

REMOVED (never implement): email/SMTP/mail templates, reminder/escalation engines, Blob/Storage account usage in app code,
queues, server-side file upload framework, microservices, event/service bus, Redis, background jobs/timers, Hangfire, SignalR.
Freshness/expiry is computed at read time (functions/views). Bulk import: browser parses CSV locally and POSTs JSON rows.

## 2. Local ports & configuration
- API `http://localhost:7073/api/v1` (`LocalHttpPort: 7073`, CORS `http://localhost:4400`). Web `http://localhost:4400`
  (`ng serve --port 4400 --proxy-config proxy.conf.json`, proxy `/api` → `http://127.0.0.1:7073`). Angular `apiBaseUrl` local = `/api/v1`.
- `SBMRAS.API/local.settings.json` (gitignored) + `local.settings.sample.json` (committed). Values:
  `FUNCTIONS_WORKER_RUNTIME=dotnet-isolated`, `AzureWebJobsStorage=` (empty),
  `SqlConnectionString=Server=localhost;Database=SBMRAS;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=False`,
  `Auth:Mode=DevHeader`, `Auth:Entra:Instance=https://<tenant-subdomain>.ciamlogin.com/`, `Auth:Entra:TenantId`,
  `Auth:Entra:ClientId` (SBMRAS-API), `Auth:Entra:SpaClientId` (SBMRAS-Web), `Auth:Entra:Audience` (`api://<API-CLIENT-ID>`),
  `Auth:Entra:RequiredScope=access_as_user`, `Auth:Entra:UserFlow=B2X_1_SBMRAS-SignUpSignIn`,
  `Auth:Entra:Groups:HospitalManagement`, `Auth:Entra:Groups:BloodBank`, `Auth:Entra:Groups:Admin` (object-id GUIDs, blank = not mapped),
  `Cors:AllowedOrigins=http://localhost:4400`, `Freshness:BloodStockTtlMinutes=360`, `Freshness:ResourceTtlMinutes=240` (defaults; DB SystemSettings is authoritative), `Import:MaxRows=500`.
- Angular environments: `environment.ts` (local, `/api/v1`), `environment.dev.ts`, `environment.test.ts`, `environment.prod.ts`
  (`https://sbmras-func-<env>.azurewebsites.net/api/v1`), angular.json configs `dev|test|prod`, `public/web.config` (IIS SPA rewrite).

## 3. Authentication & authorization
### 3.1 Modes
`Auth:Mode` = `DevHeader` | `EntraId` (fail fast otherwise). **DevHeader** (local): SPA sends `X-User-Id: <userId>` chosen on
the login page from `GET auth/dev-users`. **EntraId**: SPA uses MSAL (config from `GET auth/config`), Microsoft Entra External ID
user flow `B2X_1_SBMRAS-SignUpSignIn` (email+password self sign-up with email verification), auth-code + PKCE, scope
`api://<API-CLIENT-ID>/access_as_user`, `Authorization: Bearer <token>`, `cacheLocation: sessionStorage`.
API validates signature (OIDC metadata/JWKS of `{Instance}{TenantId}/v2.0`), issuer (authority + metadata issuer for ciamlogin),
audience (`Audience` or `ClientId`), lifetime, RS256, `scp` contains `access_as_user`, `tid` = TenantId, `oid` present.
### 3.2 Entra groups + app roles → DB roles
App registrations: **SBMRAS-Web** (SPA, no secret) and **SBMRAS-API** (exposes `access_as_user`; app roles
`HospitalManagement`, `BloodBank`, `Admin`). Security groups `SBMRAS-HospitalManagement`, `SBMRAS-BloodBank`, `SBMRAS-Admin`
are assigned to the matching API app role. Token claims: `email, given_name, family_name, preferred_username, groups, roles`.
`EntraTokenValidator` returns `EntraIdentity(TenantId, ObjectId, Email, AlternateEmail, DisplayName, GivenName, FamilyName, string[] AppRoles)`
where AppRoles = (`roles` claim values ∩ {HospitalManagement, BloodBank, Admin}) ∪ (roles mapped from `groups` claim GUIDs via
`Auth:Entra:Groups:*`). Missing/overage groups never grant anything. `RequestContextMiddleware` calls
`usp_User_ResolveEntra(@EntraTenantId, @EntraObjectId, @Email, @AlternateEmail, @DisplayName, @GivenName, @FamilyName, @EntraRoles NVARCHAR(400) CSV)`:
upsert user by (tenant, oid) → else link pre-provisioned user by email → else **self-register** as PublicUser; always ensure
`PublicUser` role; sync `UserRoles` rows with `Source='Entra'` to exactly @EntraRoles (Local rows untouched — admin-assigned
fallback per SDD 6.3); returns same 3 result sets as `usp_User_GetContext` (profile, roles, permissions). Inactive user → 401.
### 3.3 Roles (table Roles; `RoleCode` == Entra app-role value)
| RoleCode | RoleName | EntraGroup | Meaning |
|---|---|---|---|
| PublicUser | Public User | (none) | Search, create/track own blood requests, notifications |
| HospitalManagement | Hospital Management | SBMRAS-HospitalManagement | Assigned hospitals: profile, medical resources, coordinate/approve requests, imports, verification, quality, reports |
| BloodBank | Blood Bank | SBMRAS-BloodBank | Assigned blood banks: blood stock & availability, coordinate requests, imports, verification, quality, reports |
| Admin | Administrator | SBMRAS-Admin | Full access, users, roles, facility verification, master data, settings, audit |
### 3.4 Permissions (table Permissions; RolePermissions)
| Code | PublicUser | HospitalManagement | BloodBank | Admin |
|---|:-:|:-:|:-:|:-:|
| dashboard.view | Y | Y | Y | Y |
| search.view | Y | Y | Y | Y |
| requests.view | Y | Y | Y | Y |
| requests.create | Y | Y | Y | Y |
| requests.manage (coordinate/approve/status) | | Y | Y | Y |
| facilities.view | | Y | Y | Y |
| facilities.manage (edit assigned profile) | | Y | Y | Y |
| resources.manage (medical resource inventory) | | Y | | Y |
| bloodstock.manage | | | Y | Y |
| inventory.import | | Y | Y | Y |
| inventory.verify | | Y | Y | Y |
| dataquality.view | | Y | Y | Y |
| reports.view | | Y | Y | Y |
| reports.export | | Y | Y | Y |
| audit.view | | | | Y |
| notifications.view | Y | Y | Y | Y |
| users.manage | | | | Y |
| roles.manage | | | | Y |
| facilities.verify | | | | Y |
| masterdata.manage | | | | Y |
| settings.manage | | | | Y |
| data.viewall (all facilities/records) | | | | Y |
**Facility scope (BR-08/BR-09)**: every facility-level SP checks `dbo.fn_UserCanAccessFacility(@ActorUserId, @FacilityId)` =
data.viewall OR active `FacilityUserAssignments` row; plus type check (resources only on `Hospital`; blood stock only on
`BloodBank`). Violations `THROW 50403,'You are not assigned to this facility.',1` → HTTP 403.
### 3.5 API authorization mechanics
Middleware order: `GlobalExceptionMiddleware` → `RequestContextMiddleware` → `PermissionAuthorizationMiddleware`.
Each Function method is annotated: `[RequirePermission("code")]` (SBMRAS.API.Authorization), `[AllowAnonymousEndpoint]`
(no identity needed; context still resolved if a token/header is present), or `[AuthenticatedEndpoint]` (any signed-in user).
At startup the middleware reflects over all `[Function]` methods and **throws if any HTTP function lacks one of the three
attributes** (test enforces this). 401 = no/invalid identity; 403 = missing permission.
### 3.6 Response envelope & errors (identical to FRRMS)
`{ "success": bool, "message": string, "data": T|null, "errors": string[] }`, camelCase JSON, ISO-8601 UTC dates.
Paged: `{ items, totalCount, page, pageSize }`. Header `X-Correlation-Id` echoed/generated per request and passed to SPs as
`@CorrelationId` when the SP declares it. SQL `THROW 50001..50099` → 409 (message passed through), `50400` → 400, `50403` → 403,
`50404` → 404, `50409` → 409 (concurrency/duplicate). Validation (FluentValidation) → 400 with `errors`. Unhandled → 500 generic.
Idempotency: `POST requests` and `POST imports/{id}/commit` read header `Idempotency-Key` (string ≤ 100) → SP `@IdempotencyKey`.
Concurrency: inventory updates send `rowVersion` (base64 of ROWVERSION) → SP `@RowVersion VARBINARY(8)`; mismatch → 50409.

## 4. Database (`SBMRAS.Infrastructure\SQL`, run in order; idempotent; `GO`-separated; SQL Server 2019+)
Conventions: INT IDENTITY PKs (AuditLogs/Snapshots BIGINT), `DATETIME2(0)` UTC (`SYSUTCDATETIME()`), audit columns
`CreatedAt, CreatedBy, UpdatedAt, UpdatedBy` (INT FK Users, nullable) on business tables, `RowVer ROWVERSION` on mutable
inventory/facility/request tables, CHECK constraints, FK, indexes per SDD 7.4. Every SP: `CREATE OR ALTER PROCEDURE dbo.usp_<Module>_<Action>`,
first param `@ActorUserId INT`, `SET NOCOUNT ON; SET XACT_ABORT ON;`, writes `AuditLogs` (via `usp_Audit_Write`) and `Notifications`
(via `usp_Notification_Create`) in the **same transaction** as the business change. Paged SPs take `@Page INT=1, @PageSize INT=20`
and return 2 result sets: rows, then `SELECT @Total AS TotalCount`. **SP parameter names = PascalCase of the JSON body/query/route
field names** in §6 (e.g. body `componentId` → `@ComponentId`; route `{id}` → named param given in §6), plus `@ActorUserId`,
`@Page`, `@PageSize`, `@CorrelationId`, `@IdempotencyKey`. Result column names = PascalCase of the JSON fields in §6 (serializer camelCases them).
Booleans as BIT. Return `RowVer AS RowVersion` (VARBINARY(8)); the API JSON-serializes byte[] → base64 string and converts incoming
base64 `rowVersion` → byte[] for `@RowVersion VARBINARY(8)`.

### 4.1 Tables (`01_Tables.sql`)
- **Roles**(RoleId, RoleCode UQ NVARCHAR(50), RoleName, Description, EntraAppRole NULL, EntraGroupName NULL, IsSystem BIT, IsActive BIT, CreatedAt)
- **Permissions**(PermissionId, PermissionCode UQ, PermissionName, Module, Description)
- **RolePermissions**(RoleId FK, PermissionId FK, PK both)
- **Areas**(AreaId, Name UQ, City, State, Pincode NULL, IsActive)
- **Users**(UserId, DisplayName NVARCHAR(150), GivenName NULL, FamilyName NULL, Email NVARCHAR(320) (not unique identity; filtered UQ when not null), Phone NULL, OrganizationName NULL, AreaId FK NULL, EntraTenantId UNIQUEIDENTIFIER NULL, EntraObjectId UNIQUEIDENTIFIER NULL (filtered UQ tenant+oid), IsSelfRegistered BIT, IsActive BIT, LastLoginAt NULL, audit cols)
- **UserRoles**(UserId FK, RoleId FK, Source NVARCHAR(10) CHECK IN('Local','Entra'), AssignedAt, AssignedBy NULL; PK(UserId,RoleId))
- **MenuItems**(MenuItemId, Code UQ, Section, SectionOrder, Label, Icon, Route, SortOrder, IsActive) ; **MenuPermissions**(MenuItemId, PermissionId PK)
- **Units**(UnitId, Code UQ ('UNITS','ML','BEDS','CYL','NOS','LTR'), Name, IsActive)
- **BloodComponents**(ComponentId, Code UQ ('WB','PRBC','FFP','PLT','CRYO','SDP'), Name, ShelfLifeDays, StorageNote NULL, IsActive)
- **ResourceCategories**(CategoryId, Name UQ, Description NULL, IsActive)
- **MedicalResourceTypes**(ResourceTypeId, CategoryId FK, Code UQ, Name, DefaultUnitId FK, TrackingMode CHECK IN('Count','Status','Capacity'), IsActive)
- **Facilities**(FacilityId, FacilityCode UQ ('HSP-0001'/'BBK-0001'), Name, FacilityType CHECK IN('Hospital','BloodBank'), LicenseNo NULL, AddressLine, AreaId FK, City, Pincode NULL, Latitude DECIMAL(9,6) NULL, Longitude DECIMAL(9,6) NULL, ContactPhone, ContactEmail NULL, Is24x7 BIT, VerificationStatus CHECK IN('Pending','Verified','Rejected','Suspended'), VerifiedAt NULL, VerifiedBy NULL, VerificationNotes NULL, IsActive BIT, RowVer, audit cols)
- **FacilityUserAssignments**(AssignmentId, FacilityId FK, UserId FK, AssignmentRole CHECK IN('Manager','Operator','Verifier'), IsActive, AssignedAt, AssignedBy NULL, EndedAt NULL; UQ(FacilityId,UserId))
- **BloodInventory**(InventoryId, FacilityId FK, ComponentId FK, AboGroup CHECK IN('A','B','AB','O'), RhFactor CHECK IN('Positive','Negative'), Quantity DECIMAL(12,2) CHECK>=0, UnitId FK, EarliestExpiryDate DATE NULL, SourceType CHECK IN('ManualPortal','CSVImport','PartnerAPI','AdminCorrection'), VerificationStatus CHECK IN('Confirmed','PendingReview','Unverified'), LastUpdatedAt NULL, LastUpdatedBy NULL, ValidUntil NULL, RowVer, audit cols; UQ(FacilityId,ComponentId,AboGroup,RhFactor); IX(FacilityId,AboGroup,RhFactor,ComponentId) INCLUDE(Quantity,LastUpdatedAt,ValidUntil))
- **MedicalResourceInventory**(ResourceInventoryId, FacilityId FK, ResourceTypeId FK, TotalQuantity DECIMAL(12,2) >=0, AvailableQuantity DECIMAL(12,2) >=0 AND <= TotalQuantity, UnitId FK, OperationalStatus CHECK IN('Available','Limited','Unavailable','Unknown'), Notes NULL, SourceType, VerificationStatus, LastUpdatedAt, LastUpdatedBy, ValidUntil, RowVer, audit cols; UQ(FacilityId,ResourceTypeId))
- **InventoryChanges**(ChangeId, ChangeNo UQ 'CHG-YYYY-NNNN', FacilityId FK, InventoryKind CHECK IN('Blood','Resource'), InventoryId INT NULL, ComponentId NULL, AboGroup NULL, RhFactor NULL, ResourceTypeId NULL, PreviousQuantity NULL, ProposedQuantity NULL, PreviousAvailable NULL, ProposedAvailable NULL, ProposedTotal NULL, ProposedStatus NULL, EarliestExpiryDate NULL, ValidUntil NULL, BeforeJson NVARCHAR(MAX) NULL, AfterJson NVARCHAR(MAX) NULL, SourceType, Reason NVARCHAR(500), AnomalyFlags NVARCHAR(400) NULL, Status CHECK IN('Applied','PendingReview','Rejected'), ImportBatchId NULL, IdempotencyKey NULL, SubmittedBy, SubmittedAt, DecidedBy NULL, DecidedAt NULL, DecisionReason NULL)
- **AvailabilitySnapshots**(SnapshotId BIGINT, FacilityId, InventoryKind, InventoryId, ComponentId NULL, AboGroup NULL, RhFactor NULL, ResourceTypeId NULL, Quantity NULL, AvailableQuantity NULL, TotalQuantity NULL, OperationalStatus NULL, SourceType, VerificationStatus, RecordedAt, ValidUntil, ChangeId NULL, RecordedBy; IX(FacilityId,RecordedAt))
- **ImportBatches**(BatchId, BatchNo UQ 'IMP-YYYY-NNNN', FacilityId FK, InventoryKind, FileName, FileHash NVARCHAR(64), TotalRows, ValidRows, InvalidRows, DuplicateRows, AppliedRows, ReviewRows, Status CHECK IN('Validated','Committed','Cancelled'), IdempotencyKey NULL, SubmittedBy, SubmittedAt, CommittedBy NULL, CommittedAt NULL; UQ filtered (FacilityId, FileHash) WHERE Status<>'Cancelled')
- **ImportRows**(ImportRowId, BatchId FK, RowNumber, RawData NVARCHAR(1000), ComponentCode NULL, AboGroup NULL, RhFactor NULL, ResourceTypeCode NULL, Quantity NULL, TotalQuantity NULL, AvailableQuantity NULL, OperationalStatus NULL, EarliestExpiryDate NULL, ValidUntil NULL, ValidationStatus CHECK IN('Valid','Invalid','Duplicate','Applied','Review'), ErrorCodes NULL, ErrorMessages NULL; UQ(BatchId,RowNumber))
- **ValidationIssues**(IssueId, FacilityId FK, EntityType, EntityId, IssueCode CHECK IN('STALE','NEGATIVE','LARGE_JUMP','MISSING_FIELD','DUPLICATE','CONFLICT','EXPIRING'), Severity CHECK IN('Low','Medium','High'), ObservedValue NULL, Message, Status CHECK IN('Open','Resolved','Dismissed'), DetectedAt, ResolvedBy NULL, ResolvedAt NULL, Resolution NULL; filtered UQ (EntityType,EntityId,IssueCode) WHERE Status='Open')
- **BloodRequests**(RequestId, RequestNo UQ 'BRQ-YYYY-NNNN', RequesterUserId FK, PatientReference NVARCHAR(50) NULL (alias, no PII), AboGroup, RhFactor, ComponentId FK, QuantityRequested DECIMAL(12,2) >0, UnitId FK, Urgency CHECK IN('Routine','Urgent','Emergency'), NeededBy DATETIME2, AreaId FK, HospitalName NVARCHAR(200), PreferredFacilityId NULL FK, MatchedFacilityId NULL FK, ContactName, ContactPhone, ContactConsent BIT (must be 1), Notes NULL, Status CHECK IN('Submitted','UnderReview','Matched','Contacted','Fulfilled','UnableToFulfil','Closed','Cancelled'), StatusReason NULL, IdempotencyKey NULL (filtered UQ RequesterUserId+IdempotencyKey), RowVer, audit cols; IX(Status,CreatedAt), IX(RequesterUserId,CreatedAt))
- **BloodRequestHistory**(HistoryId, RequestId FK, FromStatus NULL, ToStatus, Note NULL, FacilityId NULL, ChangedBy, ChangedAt)
- **Notifications**(NotificationId, UserId FK, Title, Message, Type CHECK IN('Info','Success','Warning','Action'), EntityType NULL, EntityId NULL, Route NULL, IsRead BIT, ReadAt NULL, CreatedAt; IX(UserId,IsRead,CreatedAt))
- **AuditLogs**(AuditId BIGINT, EntityType, EntityId NVARCHAR(50), ReferenceNo NULL, FacilityId NULL, Action, Description, OldValues NVARCHAR(MAX) NULL, NewValues NVARCHAR(MAX) NULL, SourceType NULL, Reason NULL, CorrelationId NVARCHAR(64) NULL, UserId NULL, ActorRole NULL, CreatedAt; IX(EntityType,EntityId,CreatedAt), IX(UserId,CreatedAt)) — app SPs only INSERT (append-only).
- **SystemSettings**(SettingKey PK, SettingValue, DataType CHECK IN('int','decimal','bool','string'), Category, Description, UpdatedAt, UpdatedBy NULL).
  Seed keys: BLOOD_STOCK_TTL_MINUTES=360, RESOURCE_TTL_MINUTES=240, AGING_THRESHOLD_PERCENT=75, LOW_STOCK_THRESHOLD_UNITS=5,
  LARGE_JUMP_PERCENT=50, LARGE_JUMP_MIN_UNITS=20, REQUIRE_REVIEW_FOR_ANOMALY=true, MAX_IMPORT_ROWS=500, EXPIRING_WITHIN_DAYS=3,
  QUALITY_WEIGHT_COMPLETENESS=30, QUALITY_WEIGHT_RECENCY=30, QUALITY_WEIGHT_VERIFICATION=25, QUALITY_WEIGHT_ANOMALY=15, PUBLIC_SHOW_STALE_DEFAULT=false.
- **ReferenceSequences**(Prefix, [Year], LastNumber; PK(Prefix,Year)).

### 4.2 Functions & views (`02_Views_Functions.sql`)
`fn_UserHasPermission(@UserId,@Code) BIT`, `fn_UserIsAdmin(@UserId)`, `fn_UserCanAccessFacility(@UserId,@FacilityId) BIT`,
`fn_GetSettingInt(@Key, @Default)`, `fn_FreshnessStatus(@LastUpdatedAt, @ValidUntil, @VerificationStatus) NVARCHAR(20)`:
`UnderReview` if PendingReview; `Unknown` if LastUpdatedAt NULL; `Stale` if ValidUntil < now; `Aging` if elapsed ≥ AGING_THRESHOLD_PERCENT of (ValidUntil−LastUpdatedAt); else `Fresh`.
`vw_UserPermissions`, `vw_BloodAvailability` (inventory + facility + area + component + unit + FreshnessStatus + MinutesSinceUpdate,
`AvailabilityStatus` = 'OutOfStock' if Quantity=0, 'Low' if < LOW_STOCK_THRESHOLD_UNITS, else 'Available'; Unknown when never updated),
`vw_ResourceAvailability`, `vw_BloodRequests` (with requester, component, area, matched facility names), `vw_FacilityQualityScore`
(per facility: CompletenessScore, RecencyScore (fresh+aging share), VerificationScore (Confirmed share), AnomalyScore (100 − open issues penalty),
QualityScore weighted by settings, Fresh/Aging/Stale/Unknown/UnderReview counts, LastUpdateAt).

### 4.3 Script files
`01_Tables.sql`, `02_Views_Functions.sql`, `03_StoredProcedures_Security.sql` (auth/me/menu/Entra resolve/dev users),
`04_StoredProcedures_Common.sql` (lookups, `usp_Reference_Next(@Prefix, @Next OUTPUT)`, `usp_Audit_Write`, `usp_Notification_Create`, notification read SPs, `usp_Notification_NotifyRole(@RoleCode,…)`, `usp_Notification_NotifyFacilityUsers(@FacilityId,…)`),
`05_StoredProcedures_Facilities_Resources.sql`, `06_StoredProcedures_BloodStock.sql`, `07_StoredProcedures_Verification_DataQuality.sql`,
`08_StoredProcedures_Imports.sql`, `09_StoredProcedures_Public_Requests.sql`, `10_StoredProcedures_Dashboard_Reports.sql`,
`11_StoredProcedures_Admin.sql` (users, assignments, roles, permissions, facility verification, master data, settings, audit search),
`12_SeedData.sql`. `Deployment\CreateDatabase.sql`, `Deployment\GrantRuntimeIdentity.sql`, `Deployment\ProvisionAdmin.sql`.

### 4.4 Inventory update rules (05/06/07/08)
Submit update (blood or resource): validate facility active+verified-or-pending, scope, type, master codes, non-negative,
Available ≤ Total, ValidUntil default = now + TTL (> now, ≤ now+7 days), `@RowVersion` match if row exists (else 50409).
Anomaly detection: |new−old| ≥ max(LARGE_JUMP_MIN_UNITS, old×LARGE_JUMP_PERCENT%) → flag `LARGE_JUMP`; repeated identical
submission within 2 minutes → `DUPLICATE` (idempotent: return existing change). If flagged and REQUIRE_REVIEW_FOR_ANOMALY →
InventoryChanges.Status='PendingReview', inventory row VerificationStatus='PendingReview' (values unchanged), ValidationIssue created,
notify facility Verifiers/Managers + Admins. Else apply atomically: update row (or insert), Status 'Applied',
VerificationStatus 'Confirmed', snapshot, audit. Decision (`inventory.verify`, decider ≠ submitter unless Admin, scoped):
Approve → apply proposed values + snapshot + audit + resolve LARGE_JUMP issue; Reject (reason required) → restore
VerificationStatus 'Confirmed', audit, notify submitter. Returns the change row.

### 4.5 Blood request rules (09)
Create: ContactConsent=1, NeededBy > now, quantity 0<q≤50, same `@IdempotencyKey` for same requester returns existing request.
Status 'Submitted' + history + notify requester (Success) and all HospitalManagement/BloodBank users whose assigned facility
is in the same Area + Admins (Action). Allowed transitions (`requests.manage`, except owner may Cancel from Submitted/UnderReview):
Submitted→UnderReview|Cancelled ; UnderReview→Matched|UnableToFulfil|Cancelled ; Matched→Contacted|Closed|Cancelled (requires `MatchedFacilityId`,
facility must be accessible to actor unless admin) ; Contacted→Fulfilled|UnableToFulfil|Closed ; UnableToFulfil→Submitted|Closed ;
Fulfilled→Closed. Invalid → 50409. Each change: history row, audit, notify requester. Visibility: owner, or requests.manage.
Matches (`usp_Request_GetMatches`): vw_BloodAvailability rows for same ABO/Rh/component, Quantity>0, facility verified+active,
ordered same-area first, Fresh before Aging, then quantity desc; Stale excluded.

## 5. Seed (`12_SeedData.sql`, idempotent MERGE/IF NOT EXISTS; synthetic data only, names suffixed with "(Demo)")
Roles/permissions/role-permissions per §3; menu per §7.3; settings §4.1; 8 Hyderabad areas (Banjara Hills, Secunderabad,
Gachibowli, Kukatpally, LB Nagar, Ameerpet, Madhapur, Dilsukhnagar); 6 components; 6 units; resource categories (Critical Care,
Beds, Oxygen, Equipment, Transport) + 10 resource types (ICU_BED, NICU_BED, GEN_BED, VENTILATOR, O2_CYL, O2_CONC, DIALYSIS,
AMBULANCE, CT_SCAN, DEFIB). Facilities: 6 hospitals + 6 blood banks across areas (1 hospital + 1 blood bank `Pending`, 1 `Suspended`).
Users (UserId order matters for dev login): 1 `Dr. Ananya Rao` Admin; 2 Admin `System Steward`; 3–4 HospitalManagement (assigned
2 hospitals each, one Manager one Verifier on same facility); 5–6 BloodBank (assigned blood banks, Operator + Verifier); 7–10 PublicUser.
All institutional users also have PublicUser. Full blood matrix (component × ABO × Rh) for each verified blood bank with mixed
Fresh/Aging/Stale/never-updated, some zero/low; resource inventory for each hospital; ~20 requests across all statuses with history;
InventoryChanges (Applied + 3 PendingReview with LARGE_JUMP); 2 import batches; ValidationIssues open/resolved; snapshots over the
last 14 days (charts); notifications per user; ~60 audit logs. Use relative dates (DATEADD from SYSUTCDATETIME()).

## 6. REST API (`/api/v1/...`; Function name in [brackets] : permission ; → SP)
Auth/me: `GET auth/config` [GetAuthConfig: anonymous] → `{ mode, instance, tenantId, spaClientId, apiScope (full api://…/access_as_user), authority, userFlow, knownAuthority }`
(no SP) ; `GET auth/dev-users` [GetDevUsers: anonymous; 404 unless DevHeader] → usp_Auth_GetDevUsers → `[{ userId, displayName, email, roleCode, roleName, organizationName, areaName, facilityNames }]` ;
`GET me` [GetMe: authenticated] → `{ userId, displayName, givenName, familyName, email, phone, organizationName, areaId, areaName, roles[], roleNames[], primaryRole, permissions[], facilities:[{facilityId, facilityCode, name, facilityType, assignmentRole}] }`
(usp_User_GetContext / usp_User_ResolveEntra result sets: profile, roles, permissions, facilities) ; `GET me/menu` [GetMyMenu: authenticated] → usp_Me_GetMenu → `[{ section, sectionOrder, items:[{ code, label, icon, route, sortOrder }] }]`.

Public (anonymous): `GET public/lookups` [GetPublicLookups] → usp_Lookups_Get → `{ areas:[{areaId,name,city}], components:[{componentId,code,name,shelfLifeDays}], units:[{unitId,code,name}], resourceCategories:[{categoryId,name}], resourceTypes:[{resourceTypeId,categoryId,categoryName,code,name,defaultUnitId,unitCode,trackingMode}], aboGroups:["A","B","AB","O"], rhFactors:["Positive","Negative"], urgencies:[…], requestStatuses:[…], freshnessStatuses:["Fresh","Aging","Stale","Unknown","UnderReview"] }` ;
`GET public/stats` [GetPublicStats] → usp_Public_GetStats → `{ verifiedFacilities, hospitals, bloodBanks, unitsAvailable, freshPercent, openRequests, fulfilledRequests, lastUpdatedAt }` ;
`GET public/blood-availability?aboGroup&rhFactor&componentId&areaId&search&freshOnly(bool, default true)&minQuantity&page&pageSize` [SearchBloodAvailability] → usp_Public_SearchBlood → Paged<BloodAvailability> ;
`GET public/medical-resources?categoryId&resourceTypeId&areaId&search&availableOnly&freshOnly&page&pageSize` [SearchMedicalResources] → usp_Public_SearchResources → Paged<ResourceAvailability> ;
`GET public/facilities?facilityType&areaId&search&page&pageSize` [SearchPublicFacilities] → usp_Public_SearchFacilities → Paged<{ facilityId, facilityCode, name, facilityType, addressLine, areaName, city, contactPhone, contactEmail, is24x7, qualityScore, lastUpdateAt }>.
BloodAvailability = `{ inventoryId, facilityId, facilityName, facilityType, areaId, areaName, city, addressLine, contactPhone, is24x7, componentId, componentCode, componentName, aboGroup, rhFactor, bloodGroup ('O+'), quantity, unitCode, availabilityStatus, freshnessStatus, verificationStatus, sourceType, lastUpdatedAt, validUntil, minutesSinceUpdate, earliestExpiryDate, qualityScore }`.
ResourceAvailability = `{ resourceInventoryId, facilityId, facilityName, areaId, areaName, city, contactPhone, is24x7, categoryName, resourceTypeId, resourceTypeCode, resourceTypeName, totalQuantity, availableQuantity, unitCode, operationalStatus, freshnessStatus, verificationStatus, lastUpdatedAt, validUntil, minutesSinceUpdate, notes }`.
Search never returns requester data. Only Verified+active facilities.

Dashboard (dashboard.view; role-scoped: PublicUser = own requests; facility roles = assigned facilities; Admin = all):
`GET dashboard/summary` [GetDashboardSummary] → usp_Dashboard_GetSummary → `{ role, totalFacilities, verifiedFacilities, bloodUnitsAvailable, freshPercent, staleRecords, pendingReviews, openRequests, emergencyRequests, fulfilledRequests, myOpenRequests, openIssues, avgQualityScore, pendingFacilityVerifications }` ;
`GET dashboard/charts` [GetDashboardCharts] → usp_Dashboard_GetCharts → `{ bloodByGroup:[{label,value}], freshness:[{label,value}], requestTrend:[{label,submitted,fulfilled}], requestStatus:[{label,value}], resourceUtilization:[{label,total,available}], qualityByFacility:[{label,value}] }` (6 result sets in that order) ;
`GET dashboard/worklist` [GetDashboardWorklist] → usp_Dashboard_GetWorklist → `[{ type, referenceNo, title, status, priority, dueAt, route }]` ;
`GET dashboard/activity?top=10` [GetDashboardActivity] → usp_Dashboard_GetActivity(@Top) → `[{ auditId, entityType, entityId, referenceNo, action, description, userName, createdAt }]`.

Blood requests: `GET requests?scope=mine|all&status&urgency&aboGroup&areaId&search&page&pageSize` [GetBloodRequests: requests.view] → usp_Request_Search (scope=all only honoured with requests.manage) → Paged<BloodRequest> ;
`GET requests/{id}` [GetBloodRequest: requests.view] → usp_Request_GetById(@RequestId) → BloodRequest + `{ history:[{historyId,fromStatus,toStatus,note,facilityName,changedByName,changedAt}], allowedTransitions: string[] }` (3 sets: row, history, transitions(ToStatus)) ;
`POST requests` [CreateBloodRequest: requests.create] body RequestSave → usp_Request_Create → BloodRequest ;
`POST requests/{id}/cancel` `{reason}` [CancelBloodRequest: requests.create] → usp_Request_Cancel(@RequestId,@Reason) ;
`POST requests/{id}/status` `{ toStatus, note, matchedFacilityId?, rowVersion? }` [ChangeBloodRequestStatus: requests.manage] → usp_Request_ChangeStatus(@RequestId,…) ;
`GET requests/{id}/matches` [GetRequestMatches: requests.view] → usp_Request_GetMatches(@RequestId) → BloodAvailability[].
BloodRequest = `{ requestId, requestNo, requesterUserId, requesterName, patientReference, aboGroup, rhFactor, bloodGroup, componentId, componentCode, componentName, quantityRequested, unitId, unitCode, urgency, neededBy, areaId, areaName, hospitalName, preferredFacilityId, preferredFacilityName, matchedFacilityId, matchedFacilityName, matchedFacilityPhone, contactName, contactPhone (null unless owner or requests.manage), notes, status, statusReason, isOwner, createdAt, updatedAt, rowVersion }`.
RequestSave = `{ patientReference?, aboGroup, rhFactor, componentId, quantityRequested, unitId, urgency, neededBy, areaId, hospitalName, preferredFacilityId?, contactName, contactPhone, contactConsent, notes? }`.

Facilities: `GET facilities?facilityType&search&page&pageSize` [GetMyFacilities: facilities.view] → usp_Facility_SearchMine → Paged<Facility> ;
`GET facilities/{id}` [GetFacility: facilities.view] → usp_Facility_GetById(@FacilityId) → Facility + `{ users:[{userId,displayName,email,assignmentRole}], quality:{…vw_FacilityQualityScore} }` ;
`PUT facilities/{id}` [UpdateFacility: facilities.manage] `{ name, licenseNo, addressLine, areaId, city, pincode, latitude, longitude, contactPhone, contactEmail, is24x7, rowVersion }` → usp_Facility_Update.
Facility = `{ facilityId, facilityCode, name, facilityType, licenseNo, addressLine, areaId, areaName, city, pincode, latitude, longitude, contactPhone, contactEmail, is24x7, verificationStatus, verifiedAt, verificationNotes, isActive, qualityScore, freshPercent, staleRecords, lastUpdateAt, rowVersion, createdAt }`.
Medical resources: `GET facilities/{id}/resources` [GetResourceInventory: resources.manage] → usp_Resource_GetByFacility(@FacilityId) → `[{ resourceInventoryId, facilityId, resourceTypeId, resourceTypeCode, resourceTypeName, categoryName, trackingMode, totalQuantity, availableQuantity, unitId, unitCode, operationalStatus, notes, sourceType, verificationStatus, freshnessStatus, lastUpdatedAt, lastUpdatedByName, validUntil, rowVersion }]` (includes un-recorded active types with nulls/Unknown) ;
`POST facilities/{id}/resources/updates` [SubmitResourceUpdate: resources.manage] `{ resourceTypeId, totalQuantity, availableQuantity, operationalStatus, validUntil?, notes?, reason, rowVersion? }` → usp_Resource_SubmitUpdate → InventoryChange.
Blood stock: `GET facilities/{id}/blood-stock` [GetBloodStock: bloodstock.manage] → usp_BloodStock_GetByFacility(@FacilityId) → full matrix rows `{ inventoryId, facilityId, componentId, componentCode, componentName, aboGroup, rhFactor, bloodGroup, quantity, unitCode, earliestExpiryDate, availabilityStatus, freshnessStatus, verificationStatus, sourceType, lastUpdatedAt, lastUpdatedByName, validUntil, rowVersion }` ;
`POST facilities/{id}/blood-stock/updates` [SubmitBloodStockUpdate: bloodstock.manage] `{ componentId, aboGroup, rhFactor, quantity, earliestExpiryDate?, validUntil?, reason, rowVersion? }` → usp_BloodStock_SubmitUpdate → InventoryChange ;
`POST facilities/{id}/blood-stock/confirm` [ConfirmBloodStock: bloodstock.manage] `{ inventoryIds: number[] }` → usp_BloodStock_ConfirmCurrent(@FacilityId,@InventoryIds CSV) re-confirms unchanged values (new ValidUntil, snapshot, audit) ;
`GET facilities/{id}/history?kind&top` [GetInventoryHistory: facilities.view] → usp_Inventory_GetSnapshots → snapshot rows for charts.
Changes: `GET inventory-changes?status&facilityId&inventoryKind&page&pageSize` [GetInventoryChanges: inventory.verify] → usp_Change_Search → Paged<InventoryChange> ;
`POST inventory-changes/{id}/decision` `{ decision:'Approve'|'Reject', reason }` [DecideInventoryChange: inventory.verify] → usp_Change_Decide(@ChangeId,…).
InventoryChange = `{ changeId, changeNo, facilityId, facilityName, inventoryKind, itemLabel (e.g. 'PRBC O+' / 'ICU Bed'), previousQuantity, proposedQuantity, previousAvailable, proposedAvailable, proposedTotal, proposedStatus, validUntil, sourceType, reason, anomalyFlags, status, submittedByName, submittedAt, decidedByName, decidedAt, decisionReason, canDecide }`.
Imports: `GET imports?facilityId&status&page&pageSize` [GetImportBatches: inventory.import] → usp_Import_Search ;
`POST imports` [CreateImportBatch: inventory.import] `{ facilityId, inventoryKind, fileName, fileHash, rows:[{ rowNumber, rawData, componentCode, aboGroup, rhFactor, resourceTypeCode, quantity, totalQuantity, availableQuantity, operationalStatus, earliestExpiryDate, validUntil }] }` (≤ MAX_IMPORT_ROWS) → usp_Import_Stage(@FacilityId,@InventoryKind,@FileName,@FileHash,@RowsJson NVARCHAR(MAX)) — API serializes `rows` to JSON → SP stages via OPENJSON, validates each row (codes, ranges, duplicates within batch & vs. current values, anomaly → 'Review') and returns batch detail ;
`GET imports/{id}` [GetImportBatch: inventory.import] → usp_Import_GetById(@BatchId) → `{ batch…, rows:[…] }` (2 sets) ;
`POST imports/{id}/commit` [CommitImportBatch: inventory.import] → usp_Import_Commit(@BatchId,@IdempotencyKey) applies Valid rows (Review rows → PendingReview changes), snapshots, audit, notification ;
`POST imports/{id}/cancel` [CancelImportBatch: inventory.import] → usp_Import_Cancel.
ImportBatch = `{ batchId, batchNo, facilityId, facilityName, inventoryKind, fileName, fileHash, totalRows, validRows, invalidRows, duplicateRows, reviewRows, appliedRows, status, submittedByName, submittedAt, committedByName, committedAt }`; ImportRow = `{ importRowId, rowNumber, rawData, componentCode, aboGroup, rhFactor, resourceTypeCode, quantity, totalQuantity, availableQuantity, operationalStatus, earliestExpiryDate, validUntil, validationStatus, errorCodes, errorMessages }`.
CSV templates (client-side generated): Blood `componentCode,aboGroup,rhFactor,quantity,earliestExpiryDate,validUntil`; Resource `resourceTypeCode,totalQuantity,availableQuantity,operationalStatus,validUntil`.
Data quality: `GET data-quality/summary?facilityId` [GetDataQualitySummary: dataquality.view] → usp_DataQuality_GetSummary → `{ overall:{ qualityScore, completenessScore, recencyScore, verificationScore, anomalyScore, fresh, aging, stale, unknown, underReview, openIssues }, facilities:[{ facilityId, facilityName, facilityType, qualityScore, completenessScore, recencyScore, verificationScore, anomalyScore, fresh, aging, stale, unknown, underReview, openIssues, lastUpdateAt }] }` (2 sets) ;
`GET data-quality/issues?status&severity&issueCode&facilityId&page&pageSize` [GetDataQualityIssues: dataquality.view] → usp_DataQuality_SearchIssues → Paged<{ issueId, facilityId, facilityName, entityType, entityId, issueCode, severity, observedValue, message, status, detectedAt, resolvedByName, resolvedAt, resolution }> ;
`POST data-quality/issues/{id}/resolve` `{ resolution, dismiss }` [ResolveDataQualityIssue: dataquality.view] → usp_DataQuality_ResolveIssue(@IssueId,…) ;
`POST data-quality/scan` `{ facilityId? }` [RunDataQualityScan: dataquality.view] → usp_DataQuality_Scan → `{ staleFound, expiringFound, missingFound, issuesCreated }` (on-demand, scoped; no background job).

Reports (reports.view; scoped): `GET reports` [GetReports] → `[{ code, name, description }]` ; `GET reports/{code}?fromDate&toDate&facilityId&areaId` [RunReport] → usp_Report_Run(@ReportCode,…) → `{ code, name, columns:[{key,label,type:'text'|'number'|'date'|'percent'}], rows:[], chart:{ type:'bar'|'line'|'doughnut', labels:[], datasets:[{label,data:[]}] }|null }` ;
`GET reports/{code}/export?...` [ExportReport: reports.export] → text/csv. Codes: INVENTORY_SUMMARY, FRESHNESS_COMPLIANCE, DATA_COMPLETENESS, IMPORT_QUALITY, REQUEST_LIFECYCLE, FACILITY_RELIABILITY, RESOURCE_AVAILABILITY.
(SP returns 3 sets: meta(Code,Name), columns(Key,Label,Type), rows; API builds chart from first text column + first number column(s) like FRRMS.)

Notifications (notifications.view): `GET notifications?unreadOnly&page&pageSize` [GetNotifications] → Paged<{ notificationId, title, message, type, entityType, entityId, route, isRead, createdAt }> ; `GET notifications/unread-count` [GetUnreadNotificationCount] → `{ count }` ; `POST notifications/{id}/read` [MarkNotificationRead] ; `POST notifications/read-all` [MarkAllNotificationsRead].

Audit: `GET audit-logs?search&entityType&action&facilityId&userId&correlationId&fromDate&toDate&page&pageSize` [SearchAuditLogs: audit.view] → usp_Audit_Search → Paged<{ auditId, entityType, entityId, referenceNo, facilityId, facilityName, action, description, oldValues, newValues, sourceType, reason, correlationId, userName, actorRole, createdAt }> ;
`GET audit-logs/{entityType}/{entityId}` [GetEntityAuditLogs: dashboard.view; SP enforces visibility] → timeline list.

Admin: `GET admin/users?search&roleCode&isActive&page&pageSize` [GetUsers: users.manage] ; `GET admin/users/{id}` [GetUser] → User + facilities ; `POST admin/users` [CreateUser] ; `PUT admin/users/{id}` [UpdateUser] ; `POST admin/users/{id}/status` `{isActive}` [SetUserStatus] ; `PUT admin/users/{id}/facilities` `{ assignments:[{facilityId, assignmentRole}] }` [SetUserFacilities] (SP param @AssignmentsJson).
User = `{ userId, displayName, givenName, familyName, email, phone, organizationName, areaId, areaName, roleCodes[], roleNames[], roleSources:[{roleCode,source}], isActive, isSelfRegistered, entraLinked, lastLoginAt, createdAt, facilities:[{facilityId,name,facilityType,assignmentRole}] }` (roleCodes as CSV column `RoleCodes` → API splits; same for RoleNames). UserSave = `{ displayName, givenName, familyName, email, phone, organizationName, areaId, roleCodes:[] (Local roles), isActive }` (API joins arrays to CSV `@RoleCodes`).
`GET admin/roles` [GetRoles: roles.manage] → `[{ roleId, roleCode, roleName, description, entraAppRole, entraGroupName, userCount, permissionCodes[] }]` ; `GET admin/permissions` [GetPermissions: roles.manage] ; `PUT admin/roles/{id}/permissions` `{ permissionCodes[] }` [UpdateRolePermissions] (Admin must keep users.manage+roles.manage).
`GET admin/facilities?status&facilityType&search&page&pageSize` [GetFacilitiesAdmin: facilities.verify] → Paged<Facility> ; `POST admin/facilities` [CreateFacility: facilities.verify] FacilitySave (status Pending) ; `PUT admin/facilities/{id}` [UpdateFacilityAdmin: facilities.verify] ; `POST admin/facilities/{id}/verify` `{ decision:'Verify'|'Reject'|'Suspend'|'Reactivate', notes }` [VerifyFacility: facilities.verify].
`GET admin/master-data/{type}` [GetMasterData: masterdata.manage] type ∈ areas|components|units|resource-categories|resource-types → rows ; `POST admin/master-data/{type}` [SaveMasterData: masterdata.manage] upsert body (id 0/null = insert) → usp_MasterData_Save(@Type, @Id, @PayloadJson).
`GET admin/settings` [GetSettings: settings.manage] → `[{ settingKey, settingValue, dataType, category, description, updatedAt, updatedByName }]` ; `PUT admin/settings` `{ settings:[{settingKey, settingValue}] }` [UpdateSettings: settings.manage] (@SettingsJson; type-validated).

## 7. Web UI
### 7.1 Theme — "Clinical Science" (must NOT look like FRRMS/PBGMS)
Palette: nav ink `#0B1F33` (deep laboratory navy), primary **haemoglobin crimson** `#C8102E` (primary-dark `#8E0C21`), secondary
**clinical teal** `#00897B`, accent **plasma amber** `#F2A900`, info **microscope blue** `#1E6FD9`, success `#2E9E5B`, danger `#D93025`,
background `#F3F6F9` (sterile cool grey), surface `#FFFFFF`, border `#DCE3EA`, text `#14212E`, muted `#5B6B7B`. Subtle
molecular/hexagon SVG pattern in hero/header backgrounds. Typography: **"Inter"** body + **"IBM Plex Mono"** for codes, reference
numbers and quantities (lab-readout feel). Cards 10px radius, 1px border + very soft shadow; data-dense tables. Material M3 theme with
red primary / teal tertiary. Blood-group "tile" chips (crimson outline, mono font, e.g. `O+`).
Freshness chips: Fresh `#2E9E5B`, Aging `#F2A900`, Stale `#D93025`, Unknown `#8A96A3`, UnderReview `#7B4FD6` (+ icons
check_circle/schedule/error/help/pending). Request status chips: Submitted blue, UnderReview purple, Matched teal, Contacted amber,
Fulfilled green, UnableToFulfil red, Closed/Cancelled grey. Urgency: Emergency red pulse dot, Urgent amber, Routine grey.
### 7.2 Layout — two-tier TOP navigation (no side nav, no dropdown-only menus)
Tier 1 (64px, `#0B1F33` with faint hex pattern): brand (icon `bloodtype` in crimson circle, "SBMRAS" + tagline "Blood & Medical
Resource Availability"), **section tabs** horizontally (from `GET me/menu` sections; anonymous users get the static "Discover"
section), right side: global quick "Find blood" button (crimson), notification bell with unread badge (signed in), user avatar menu
(name, role chips, assigned facilities, Sign out) or "Sign in / Register" button when anonymous.
Tier 2 (48px, white, bottom border): the **active section's items as horizontal link tabs** with icons and an active crimson underline,
right side breadcrumb-ish page context. Tier 3: page header inside content (title, subtitle, actions).
Mobile (<992px): Tier 1 shows brand + hamburger → full-width **top sheet** panel sliding down listing sections/items (not a side drawer).
Footer: disclaimer "SBMRAS shows reported availability. Always reconfirm with the facility. Not a clinical decision tool."
### 7.3 Menu seed (MenuItems + MenuPermissions)
| Section (order) | Label | Icon | Route | Permission |
|---|---|---|---|---|
| Overview (1) | Dashboard | monitor_heart | /dashboard | dashboard.view |
| Discover (2) | Find Blood | bloodtype | /find-blood | search.view |
| Discover (2) | Medical Resources | medical_services | /find-resources | search.view |
| Discover (2) | Facility Directory | local_hospital | /directory | search.view |
| Requests (3) | My Requests | assignment | /requests | requests.view |
| Requests (3) | New Request | add_circle | /requests/new | requests.create |
| Requests (3) | Request Coordination | hub | /coordination | requests.manage |
| Facility Operations (4) | My Facilities | apartment | /facilities | facilities.view |
| Facility Operations (4) | Resource Inventory | inventory_2 | /resource-inventory | resources.manage |
| Facility Operations (4) | Blood Stock | water_drop | /blood-stock | bloodstock.manage |
| Facility Operations (4) | Bulk Import | upload_file | /imports | inventory.import |
| Facility Operations (4) | Change Verification | rule | /verifications | inventory.verify |
| Insights (5) | Data Quality | verified | /data-quality | dataquality.view |
| Insights (5) | Reports | insights | /reports | reports.view |
| Insights (5) | Audit Explorer | manage_search | /audit-logs | audit.view |
| Administration (6) | Users & Access | manage_accounts | /admin/users | users.manage |
| Administration (6) | Roles & Permissions | admin_panel_settings | /admin/roles | roles.manage |
| Administration (6) | Facility Verification | domain_verification | /admin/facilities | facilities.verify |
| Administration (6) | Master Data | dataset | /admin/master-data | masterdata.manage |
| Administration (6) | System Settings | tune | /admin/settings | settings.manage |
### 7.4 Routes (all lazy standalone components)
Anonymous (inside shell): `/` → landing (hero with search form + public stats + how-it-works + freshness legend), `/find-blood`,
`/find-resources`, `/directory`, `/login` (outside shell, split screen). Authenticated (authGuard + permissionGuard via route data
`permission`): `/dashboard`, `/requests`, `/requests/new`, `/requests/:id`, `/coordination`, `/coordination/:id` (reuse request detail
with management panel), `/facilities`, `/facilities/:id`, `/resource-inventory` (facility picker query `?facilityId=`),
`/blood-stock` (`?facilityId=`), `/imports`, `/imports/new`, `/imports/:id`, `/verifications`, `/data-quality`, `/reports`,
`/audit-logs`, `/notifications`, `/profile`, `/admin/users`, `/admin/roles`, `/admin/facilities`, `/admin/master-data`,
`/admin/settings`, `/forbidden`, `**` not-found. After sign-in redirect to `returnUrl` or `/dashboard`.
"Create blood request" from search when anonymous → login with returnUrl `/requests/new?...prefill`.
### 7.5 Web file ownership & shared APIs (web-core agent creates these first; feature agents consume)
`core/services/api.service.ts`: `get<T>(url, params?)`, `getPaged<T>(url, params)`, `post<T>(url, body?, headers?)`, `put<T>`, `download(url, params, fileName)`; unwraps envelope, throws `ApiError {status, message, errors}`.
`core/services/session.service.ts` (signals: `user()`, `isAuthenticated()`, `permissions()`, `hasPermission(code)`, `hasAnyPermission([...])`, `facilities()`), `auth.service.ts` (DevHeader/MSAL), `menu.service.ts`, `notification-badge.service.ts`, `lookup.service.ts` (cached `public/lookups`), `ui.service.ts` (`success(msg)`, `error(msg)`, `confirm({title,message,confirmText,danger}) : Promise<boolean>`, `reason({title,label,required}) : Promise<string|null>`).
Guards `authGuard`, `permissionGuard`; interceptors (base URL, auth header, correlation id, error→snackbar, loading). Directive `*sbHasPermission="'code'"`.
Shared components (selector prefix `sb-`): `sb-page-header [title] [subtitle] [icon]` (+ content projection for actions), `sb-state-panel [state]="'loading'|'empty'|'error'" [message] (retry)`,
`sb-status-chip [status]`, `sb-freshness-badge [status] [lastUpdatedAt] [validUntil]`, `sb-blood-group-tile [aboGroup] [rhFactor] [size]`, `sb-urgency-badge [urgency]`,
`sb-kpi-card [label] [value] [icon] [tone] [hint] [route]`, `sb-chart-view [type] [labels] [datasets] [height]`, `sb-quality-gauge [score]`, `sb-audit-timeline [entityType] [entityId]`, `sb-confirm-dialog`, `sb-reason-dialog`.
Pipes: `sbDate`, `sbRelative` ("12 min ago"), `sbQty`. Models/services per feature are owned by the feature agent in `core/models/<feature>.models.ts` + `core/services/<feature>.service.ts`.
Every screen: loading, empty, error+retry, validation messages, server error mapping, never show 0 for unknown ("Not reported").
