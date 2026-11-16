/*=====================================================================
  SBMRAS - 12_SeedData.sql
  Reference data (roles, permissions, menu, settings, master data),
  demo facilities/users and a realistic, re-runnable transactional data
  set (synthetic only - every facility name is suffixed with "(Demo)").

  - Reference data is upserted (MERGE) on every run.
  - Demo users are inserted with fixed ids (1..10) only when missing.
  - Inventory rows are inserted only when their natural key is missing.
  - Each transactional section runs only when its table is still empty,
    so the script is safe to re-run.
  - All timestamps are relative to SYSUTCDATETIME() so freshness
    (Fresh / Aging / Stale / Unknown / UnderReview) is always mixed.
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/*---------------------------------------------------------------------
  Roles (RoleCode == Entra app-role value)
---------------------------------------------------------------------*/
MERGE dbo.Roles AS t
USING (VALUES
    (N'PublicUser',         N'Public User',         N'Search availability, create and track own blood requests, notifications.', NULL,                    NULL),
    (N'HospitalManagement', N'Hospital Management', N'Assigned hospitals: profile, medical resources, request coordination, imports, verification, quality and reports.', N'HospitalManagement', N'SBMRAS-HospitalManagement'),
    (N'BloodBank',          N'Blood Bank',          N'Assigned blood banks: blood stock and availability, request coordination, imports, verification, quality and reports.', N'BloodBank', N'SBMRAS-BloodBank'),
    (N'Admin',              N'Administrator',       N'Full access: users, roles, facility verification, master data, settings and audit.', N'Admin', N'SBMRAS-Admin')
) AS s (RoleCode, RoleName, Description, EntraAppRole, EntraGroupName)
ON t.RoleCode = s.RoleCode
WHEN MATCHED THEN UPDATE SET RoleName = s.RoleName, Description = s.Description, EntraAppRole = s.EntraAppRole,
                             EntraGroupName = s.EntraGroupName, IsSystem = 1, IsActive = 1
WHEN NOT MATCHED THEN INSERT (RoleCode, RoleName, Description, EntraAppRole, EntraGroupName, IsSystem, IsActive, CreatedAt)
                      VALUES (s.RoleCode, s.RoleName, s.Description, s.EntraAppRole, s.EntraGroupName, 1, 1, SYSUTCDATETIME());
GO

/*---------------------------------------------------------------------
  Permissions
---------------------------------------------------------------------*/
MERGE dbo.Permissions AS t
USING (VALUES
    (N'dashboard.view',     N'View dashboard',                   N'Dashboard',     N'Open the role-scoped dashboard.'),
    (N'search.view',        N'Search availability',              N'Discover',      N'Search blood stock, medical resources and the facility directory.'),
    (N'requests.view',      N'View blood requests',              N'Requests',      N'View own blood requests (all requests with requests.manage).'),
    (N'requests.create',    N'Create blood requests',            N'Requests',      N'Raise and cancel own blood requests.'),
    (N'requests.manage',    N'Coordinate blood requests',        N'Requests',      N'Review, match, contact, fulfil and close blood requests.'),
    (N'facilities.view',    N'View facilities',                  N'Facilities',    N'View assigned facilities and their inventory history.'),
    (N'facilities.manage',  N'Manage facility profile',          N'Facilities',    N'Edit the profile of assigned facilities.'),
    (N'resources.manage',   N'Manage medical resources',         N'Inventory',     N'Update medical resource inventory of assigned hospitals.'),
    (N'bloodstock.manage',  N'Manage blood stock',               N'Inventory',     N'Update and confirm blood stock of assigned blood banks.'),
    (N'inventory.import',   N'Bulk import inventory',            N'Inventory',     N'Stage, commit and cancel CSV inventory imports.'),
    (N'inventory.verify',   N'Verify inventory changes',         N'Inventory',     N'Approve or reject inventory changes held for review.'),
    (N'dataquality.view',   N'Data quality',                     N'Insights',      N'View quality scores, scan and resolve data quality issues.'),
    (N'reports.view',       N'View reports',                     N'Insights',      N'Run operational reports.'),
    (N'reports.export',     N'Export reports',                   N'Insights',      N'Export reports as CSV.'),
    (N'audit.view',         N'View audit logs',                  N'Insights',      N'Search the audit explorer.'),
    (N'notifications.view', N'View notifications',               N'Notifications', N'Read own notifications.'),
    (N'users.manage',       N'Manage users',                     N'Administration',N'Create and edit users, roles and facility assignments.'),
    (N'roles.manage',       N'Manage roles and permissions',     N'Administration',N'Edit role permission matrix.'),
    (N'facilities.verify',  N'Verify facilities',                N'Administration',N'Create, verify, reject, suspend and reactivate facilities.'),
    (N'masterdata.manage',  N'Manage master data',               N'Administration',N'Maintain areas, components, units and resource types.'),
    (N'settings.manage',    N'Manage system settings',           N'Administration',N'Maintain freshness, anomaly and quality settings.'),
    (N'data.viewall',       N'View all facilities and records',  N'Administration',N'Bypass facility assignment scope.')
) AS s (PermissionCode, PermissionName, Module, Description)
ON t.PermissionCode = s.PermissionCode
WHEN MATCHED THEN UPDATE SET PermissionName = s.PermissionName, Module = s.Module, Description = s.Description
WHEN NOT MATCHED THEN INSERT (PermissionCode, PermissionName, Module, Description)
                      VALUES (s.PermissionCode, s.PermissionName, s.Module, s.Description);
GO

/*---------------------------------------------------------------------
  Role permissions (insert-only so administrator changes are preserved,
  except Admin which always receives every permission).
---------------------------------------------------------------------*/
;WITH Matrix AS (
    SELECT r.RoleId, p.PermissionId
    FROM (VALUES
        (N'PublicUser', N'dashboard.view'), (N'PublicUser', N'search.view'), (N'PublicUser', N'requests.view'),
        (N'PublicUser', N'requests.create'), (N'PublicUser', N'notifications.view'),

        (N'HospitalManagement', N'dashboard.view'), (N'HospitalManagement', N'search.view'), (N'HospitalManagement', N'requests.view'),
        (N'HospitalManagement', N'requests.create'), (N'HospitalManagement', N'requests.manage'), (N'HospitalManagement', N'facilities.view'),
        (N'HospitalManagement', N'facilities.manage'), (N'HospitalManagement', N'resources.manage'), (N'HospitalManagement', N'inventory.import'),
        (N'HospitalManagement', N'inventory.verify'), (N'HospitalManagement', N'dataquality.view'), (N'HospitalManagement', N'reports.view'),
        (N'HospitalManagement', N'reports.export'), (N'HospitalManagement', N'notifications.view'),

        (N'BloodBank', N'dashboard.view'), (N'BloodBank', N'search.view'), (N'BloodBank', N'requests.view'),
        (N'BloodBank', N'requests.create'), (N'BloodBank', N'requests.manage'), (N'BloodBank', N'facilities.view'),
        (N'BloodBank', N'facilities.manage'), (N'BloodBank', N'bloodstock.manage'), (N'BloodBank', N'inventory.import'),
        (N'BloodBank', N'inventory.verify'), (N'BloodBank', N'dataquality.view'), (N'BloodBank', N'reports.view'),
        (N'BloodBank', N'reports.export'), (N'BloodBank', N'notifications.view')
    ) AS m (RoleCode, PermissionCode)
    INNER JOIN dbo.Roles r ON r.RoleCode = m.RoleCode
    INNER JOIN dbo.Permissions p ON p.PermissionCode = m.PermissionCode
    UNION
    SELECT r.RoleId, p.PermissionId
    FROM dbo.Roles r CROSS JOIN dbo.Permissions p
    WHERE r.RoleCode = N'Admin'
)
INSERT INTO dbo.RolePermissions (RoleId, PermissionId)
SELECT m.RoleId, m.PermissionId
FROM Matrix m
WHERE NOT EXISTS (SELECT 1 FROM dbo.RolePermissions rp WHERE rp.RoleId = m.RoleId AND rp.PermissionId = m.PermissionId);
GO

/*---------------------------------------------------------------------
  Menu (two-tier top navigation: Section = tier-1 tab, items = tier-2)
---------------------------------------------------------------------*/
DECLARE @Menu TABLE (Code NVARCHAR(50), Section NVARCHAR(50), SectionOrder INT, Label NVARCHAR(100), Icon NVARCHAR(50),
                     Route NVARCHAR(200), SortOrder INT, PermissionCode NVARCHAR(100));
INSERT INTO @Menu VALUES
    (N'dashboard',          N'Overview',            1, N'Dashboard',             N'monitor_heart',        N'/dashboard',          1, N'dashboard.view'),
    (N'find-blood',         N'Discover',            2, N'Find Blood',            N'bloodtype',            N'/find-blood',         1, N'search.view'),
    (N'find-resources',     N'Discover',            2, N'Medical Resources',     N'medical_services',     N'/find-resources',     2, N'search.view'),
    (N'directory',          N'Discover',            2, N'Facility Directory',    N'local_hospital',       N'/directory',          3, N'search.view'),
    (N'my-requests',        N'Requests',            3, N'My Requests',           N'assignment',           N'/requests',           1, N'requests.view'),
    (N'new-request',        N'Requests',            3, N'New Request',           N'add_circle',           N'/requests/new',       2, N'requests.create'),
    (N'coordination',       N'Requests',            3, N'Request Coordination',  N'hub',                  N'/coordination',       3, N'requests.manage'),
    (N'my-facilities',      N'Facility Operations', 4, N'My Facilities',         N'apartment',            N'/facilities',         1, N'facilities.view'),
    (N'resource-inventory', N'Facility Operations', 4, N'Resource Inventory',    N'inventory_2',          N'/resource-inventory', 2, N'resources.manage'),
    (N'blood-stock',        N'Facility Operations', 4, N'Blood Stock',           N'water_drop',           N'/blood-stock',        3, N'bloodstock.manage'),
    (N'imports',            N'Facility Operations', 4, N'Bulk Import',           N'upload_file',          N'/imports',            4, N'inventory.import'),
    (N'verifications',      N'Facility Operations', 4, N'Change Verification',   N'rule',                 N'/verifications',      5, N'inventory.verify'),
    (N'data-quality',       N'Insights',            5, N'Data Quality',          N'verified',             N'/data-quality',       1, N'dataquality.view'),
    (N'reports',            N'Insights',            5, N'Reports',               N'insights',             N'/reports',            2, N'reports.view'),
    (N'audit-logs',         N'Insights',            5, N'Audit Explorer',        N'manage_search',        N'/audit-logs',         3, N'audit.view'),
    (N'admin-users',        N'Administration',      6, N'Users & Access',        N'manage_accounts',      N'/admin/users',        1, N'users.manage'),
    (N'admin-roles',        N'Administration',      6, N'Roles & Permissions',   N'admin_panel_settings', N'/admin/roles',        2, N'roles.manage'),
    (N'admin-facilities',   N'Administration',      6, N'Facility Verification', N'domain_verification',  N'/admin/facilities',   3, N'facilities.verify'),
    (N'admin-master-data',  N'Administration',      6, N'Master Data',           N'dataset',              N'/admin/master-data',  4, N'masterdata.manage'),
    (N'admin-settings',     N'Administration',      6, N'System Settings',       N'tune',                 N'/admin/settings',     5, N'settings.manage');

MERGE dbo.MenuItems AS t
USING @Menu AS s ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Section = s.Section, SectionOrder = s.SectionOrder, Label = s.Label, Icon = s.Icon, Route = s.Route,
                             SortOrder = s.SortOrder, IsActive = 1
WHEN NOT MATCHED THEN INSERT (Code, Section, SectionOrder, Label, Icon, Route, SortOrder, IsActive)
                      VALUES (s.Code, s.Section, s.SectionOrder, s.Label, s.Icon, s.Route, s.SortOrder, 1);

DELETE mp
FROM dbo.MenuPermissions mp
INNER JOIN dbo.MenuItems mi ON mi.MenuItemId = mp.MenuItemId
INNER JOIN @Menu m ON m.Code = mi.Code
INNER JOIN dbo.Permissions p ON p.PermissionId = mp.PermissionId
WHERE p.PermissionCode <> m.PermissionCode;

INSERT INTO dbo.MenuPermissions (MenuItemId, PermissionId)
SELECT mi.MenuItemId, p.PermissionId
FROM @Menu m
INNER JOIN dbo.MenuItems mi ON mi.Code = m.Code
INNER JOIN dbo.Permissions p ON p.PermissionCode = m.PermissionCode
WHERE NOT EXISTS (SELECT 1 FROM dbo.MenuPermissions x WHERE x.MenuItemId = mi.MenuItemId AND x.PermissionId = p.PermissionId);
GO

/*---------------------------------------------------------------------
  System settings (values are only inserted; admin edits are preserved)
---------------------------------------------------------------------*/
MERGE dbo.SystemSettings AS t
USING (VALUES
    (N'BLOOD_STOCK_TTL_MINUTES',     N'360',   N'int',  N'Freshness',  N'Minutes a blood stock update stays valid before it is Stale.'),
    (N'RESOURCE_TTL_MINUTES',        N'240',   N'int',  N'Freshness',  N'Minutes a medical resource update stays valid before it is Stale.'),
    (N'AGING_THRESHOLD_PERCENT',     N'75',    N'int',  N'Freshness',  N'Share of the validity window after which a record is Aging.'),
    (N'LOW_STOCK_THRESHOLD_UNITS',   N'5',     N'int',  N'Availability', N'Quantities below this value are shown as Low.'),
    (N'LARGE_JUMP_PERCENT',          N'50',    N'int',  N'Anomaly',    N'Percentage change versus previous value that is flagged LARGE_JUMP.'),
    (N'LARGE_JUMP_MIN_UNITS',        N'20',    N'int',  N'Anomaly',    N'Minimum absolute change that is flagged LARGE_JUMP.'),
    (N'REQUIRE_REVIEW_FOR_ANOMALY',  N'true',  N'bool', N'Anomaly',    N'Hold anomalous updates for verification instead of applying them.'),
    (N'MAX_IMPORT_ROWS',             N'500',   N'int',  N'Import',     N'Maximum rows accepted in one bulk import batch.'),
    (N'EXPIRING_WITHIN_DAYS',        N'3',     N'int',  N'DataQuality',N'Stock with earliest expiry within this many days is flagged EXPIRING.'),
    (N'QUALITY_WEIGHT_COMPLETENESS', N'30',    N'int',  N'DataQuality',N'Weight of the completeness score in the quality score.'),
    (N'QUALITY_WEIGHT_RECENCY',      N'30',    N'int',  N'DataQuality',N'Weight of the recency score in the quality score.'),
    (N'QUALITY_WEIGHT_VERIFICATION', N'25',    N'int',  N'DataQuality',N'Weight of the verification score in the quality score.'),
    (N'QUALITY_WEIGHT_ANOMALY',      N'15',    N'int',  N'DataQuality',N'Weight of the anomaly score in the quality score.'),
    (N'PUBLIC_SHOW_STALE_DEFAULT',   N'false', N'bool', N'Public',     N'Whether public search includes stale records by default.')
) AS s (SettingKey, SettingValue, DataType, Category, Description)
ON t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET DataType = s.DataType, Category = s.Category, Description = s.Description
WHEN NOT MATCHED THEN INSERT (SettingKey, SettingValue, DataType, Category, Description, UpdatedAt)
                      VALUES (s.SettingKey, s.SettingValue, s.DataType, s.Category, s.Description, SYSUTCDATETIME());
GO

/*---------------------------------------------------------------------
  Master data: areas, blood components, units, resource categories/types
---------------------------------------------------------------------*/
MERGE dbo.Areas AS t
USING (VALUES
    (N'Banjara Hills', N'Hyderabad', N'Telangana', N'500034'),
    (N'Secunderabad',  N'Hyderabad', N'Telangana', N'500003'),
    (N'Gachibowli',    N'Hyderabad', N'Telangana', N'500032'),
    (N'Kukatpally',    N'Hyderabad', N'Telangana', N'500072'),
    (N'LB Nagar',      N'Hyderabad', N'Telangana', N'500074'),
    (N'Ameerpet',      N'Hyderabad', N'Telangana', N'500016'),
    (N'Madhapur',      N'Hyderabad', N'Telangana', N'500081'),
    (N'Dilsukhnagar',  N'Hyderabad', N'Telangana', N'500060')
) AS s (Name, City, State, Pincode)
ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (Name, City, State, Pincode, IsActive) VALUES (s.Name, s.City, s.State, s.Pincode, 1);

MERGE dbo.BloodComponents AS t
USING (VALUES
    (N'WB',   N'Whole Blood',                    35,  N'2-6 °C, CPDA-1 bag'),
    (N'PRBC', N'Packed Red Blood Cells',         42,  N'2-6 °C, SAGM additive'),
    (N'FFP',  N'Fresh Frozen Plasma',            365, N'-18 °C or colder'),
    (N'PLT',  N'Platelet Concentrate (RDP)',     5,   N'20-24 °C with continuous agitation'),
    (N'CRYO', N'Cryoprecipitate',                365, N'-18 °C or colder'),
    (N'SDP',  N'Single Donor Platelets (Apheresis)', 5, N'20-24 °C with continuous agitation')
) AS s (Code, Name, ShelfLifeDays, StorageNote)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name, ShelfLifeDays = s.ShelfLifeDays, StorageNote = s.StorageNote
WHEN NOT MATCHED THEN INSERT (Code, Name, ShelfLifeDays, StorageNote, IsActive) VALUES (s.Code, s.Name, s.ShelfLifeDays, s.StorageNote, 1);

MERGE dbo.Units AS t
USING (VALUES (N'UNITS', N'Units'), (N'ML', N'Millilitres'), (N'BEDS', N'Beds'),
              (N'CYL', N'Cylinders'), (N'NOS', N'Numbers'), (N'LTR', N'Litres')) AS s (Code, Name)
ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET Name = s.Name
WHEN NOT MATCHED THEN INSERT (Code, Name, IsActive) VALUES (s.Code, s.Name, 1);

MERGE dbo.ResourceCategories AS t
USING (VALUES
    (N'Critical Care', N'Intensive care capacity and life-support equipment.'),
    (N'Beds',          N'General ward and step-down beds.'),
    (N'Oxygen',        N'Medical oxygen cylinders and concentrators.'),
    (N'Equipment',     N'Diagnostic and therapeutic equipment.'),
    (N'Transport',     N'Ambulances and patient transport.')
) AS s (Name, Description)
ON t.Name = s.Name
WHEN MATCHED THEN UPDATE SET Description = s.Description
WHEN NOT MATCHED THEN INSERT (Name, Description, IsActive) VALUES (s.Name, s.Description, 1);

MERGE dbo.MedicalResourceTypes AS t
USING (
    SELECT c.CategoryId, s.Code, s.Name, u.UnitId, s.TrackingMode
    FROM (VALUES
        (N'ICU_BED',    N'ICU Bed',              N'Critical Care', N'BEDS', N'Capacity'),
        (N'NICU_BED',   N'NICU Bed',             N'Critical Care', N'BEDS', N'Capacity'),
        (N'GEN_BED',    N'General Ward Bed',     N'Beds',          N'BEDS', N'Capacity'),
        (N'VENTILATOR', N'Ventilator',           N'Critical Care', N'NOS',  N'Count'),
        (N'O2_CYL',     N'Oxygen Cylinder',      N'Oxygen',        N'CYL',  N'Count'),
        (N'O2_CONC',    N'Oxygen Concentrator',  N'Oxygen',        N'NOS',  N'Count'),
        (N'DIALYSIS',   N'Dialysis Machine',     N'Equipment',     N'NOS',  N'Capacity'),
        (N'AMBULANCE',  N'Ambulance',            N'Transport',     N'NOS',  N'Status'),
        (N'CT_SCAN',    N'CT Scanner',           N'Equipment',     N'NOS',  N'Status'),
        (N'DEFIB',      N'Defibrillator',        N'Equipment',     N'NOS',  N'Count')
    ) AS s (Code, Name, CategoryName, UnitCode, TrackingMode)
    INNER JOIN dbo.ResourceCategories c ON c.Name = s.CategoryName
    INNER JOIN dbo.Units u ON u.Code = s.UnitCode
) AS s ON t.Code = s.Code
WHEN MATCHED THEN UPDATE SET CategoryId = s.CategoryId, Name = s.Name, DefaultUnitId = s.UnitId, TrackingMode = s.TrackingMode
WHEN NOT MATCHED THEN INSERT (CategoryId, Code, Name, DefaultUnitId, TrackingMode, IsActive)
                      VALUES (s.CategoryId, s.Code, s.Name, s.UnitId, s.TrackingMode, 1);
GO

/*---------------------------------------------------------------------
  Demo users (fixed ids 1..10, inserted only when missing).
  UserId order matters for the DevHeader login page.
---------------------------------------------------------------------*/
DECLARE @Users TABLE (UserId INT, DisplayName NVARCHAR(150), GivenName NVARCHAR(100), FamilyName NVARCHAR(100), Email NVARCHAR(320),
                      Phone NVARCHAR(30), OrganizationName NVARCHAR(200), AreaName NVARCHAR(100), RoleCode NVARCHAR(50), IsSelfRegistered BIT);
INSERT INTO @Users VALUES
    (1,  N'Dr. Ananya Rao',    N'Ananya',    N'Rao',     N'ananya.rao@sbmras.example',     N'+91-40-5550-1001', N'SBMRAS Health Data Office (Demo)',    N'Banjara Hills', N'Admin',              0),
    (2,  N'System Steward',    N'System',    N'Steward', N'steward@sbmras.example',        N'+91-40-5550-1002', N'SBMRAS Health Data Office (Demo)',    N'Ameerpet',      N'Admin',              0),
    (3,  N'Dr. Karthik Menon', N'Karthik',   N'Menon',   N'karthik.menon@sbmras.example',  N'+91-40-5550-1003', N'Banjara Care Hospital (Demo)',        N'Banjara Hills', N'HospitalManagement', 0),
    (4,  N'Meera Joseph',      N'Meera',     N'Joseph',  N'meera.joseph@sbmras.example',   N'+91-40-5550-1004', N'Banjara Care Hospital (Demo)',        N'Banjara Hills', N'HospitalManagement', 0),
    (5,  N'Ravi Teja Kumar',   N'Ravi Teja', N'Kumar',   N'ravi.kumar@sbmras.example',     N'+91-40-5550-1005', N'Hyderabad Central Blood Bank (Demo)', N'Ameerpet',      N'BloodBank',          0),
    (6,  N'Sana Fatima',       N'Sana',      N'Fatima',  N'sana.fatima@sbmras.example',    N'+91-40-5550-1006', N'Hyderabad Central Blood Bank (Demo)', N'Ameerpet',      N'BloodBank',          0),
    (7,  N'Priya Sharma',      N'Priya',     N'Sharma',  N'priya.sharma@sbmras.example',   N'+91-90000-10007',  NULL,                                   N'Gachibowli',    N'PublicUser',         1),
    (8,  N'Rahul Verma',       N'Rahul',     N'Verma',   N'rahul.verma@sbmras.example',    N'+91-90000-10008',  NULL,                                   N'Secunderabad',  N'PublicUser',         1),
    (9,  N'Sneha Patil',       N'Sneha',     N'Patil',   N'sneha.patil@sbmras.example',    N'+91-90000-10009',  NULL,                                   N'Kukatpally',    N'PublicUser',         1),
    (10, N'Mohammed Irfan',    N'Mohammed',  N'Irfan',   N'mohammed.irfan@sbmras.example', N'+91-90000-10010',  NULL,                                   N'Dilsukhnagar',  N'PublicUser',         1);

SET IDENTITY_INSERT dbo.Users ON;
INSERT INTO dbo.Users (UserId, DisplayName, GivenName, FamilyName, Email, Phone, OrganizationName, AreaId,
                       IsSelfRegistered, IsActive, LastLoginAt, CreatedAt)
SELECT u.UserId, u.DisplayName, u.GivenName, u.FamilyName, u.Email, u.Phone, u.OrganizationName, a.AreaId,
       u.IsSelfRegistered, 1, DATEADD(MINUTE, -(u.UserId * 37), SYSUTCDATETIME()), DATEADD(DAY, -(90 - u.UserId * 3), SYSUTCDATETIME())
FROM @Users u
LEFT JOIN dbo.Areas a ON a.Name = u.AreaName
WHERE NOT EXISTS (SELECT 1 FROM dbo.Users x WHERE x.UserId = u.UserId OR x.Email = u.Email);
SET IDENTITY_INSERT dbo.Users OFF;

-- Primary role + PublicUser for everybody (institutional users are also public users).
INSERT INTO dbo.UserRoles (UserId, RoleId, Source, AssignedAt, AssignedBy)
SELECT DISTINCT x.UserId, r.RoleId, N'Local', DATEADD(DAY, -60, SYSUTCDATETIME()), CASE WHEN x.UserId = 1 THEN NULL ELSE 1 END
FROM @Users u
INNER JOIN dbo.Users x ON x.Email = u.Email
CROSS APPLY (VALUES (u.RoleCode), (N'PublicUser')) AS rc (RoleCode)
INNER JOIN dbo.Roles r ON r.RoleCode = rc.RoleCode
WHERE NOT EXISTS (SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId = x.UserId AND ur.RoleId = r.RoleId);
GO

/*---------------------------------------------------------------------
  Facilities: 6 hospitals + 6 blood banks across Hyderabad areas.
  HSP-0005 and BBK-0005 are Pending, BBK-0006 is Suspended.
---------------------------------------------------------------------*/
DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

MERGE dbo.Facilities AS t
USING (
    SELECT s.*, a.AreaId
    FROM (VALUES
        (N'HSP-0001', N'Banjara Care Hospital (Demo)',            N'Hospital',  N'TS-HOSP-DEMO-1101', N'Road No. 12, Banjara Hills',           N'Banjara Hills', N'500034', 17.415600, 78.434700, N'+91-40-5550-0101', N'care.banjara@sbmras.example',    1, N'Verified'),
        (N'HSP-0002', N'Secunderabad General Hospital (Demo)',    N'Hospital',  N'TS-HOSP-DEMO-1102', N'SD Road, near Clock Tower, Secunderabad', N'Secunderabad', N'500003', 17.439900, 78.498300, N'+91-40-5550-0102', N'general.secbad@sbmras.example', 1, N'Verified'),
        (N'HSP-0003', N'Gachibowli Multispeciality Hospital (Demo)', N'Hospital', N'TS-HOSP-DEMO-1103', N'Old Mumbai Highway, Gachibowli',     N'Gachibowli',    N'500032', 17.440100, 78.348900, N'+91-40-5550-0103', N'multi.gachi@sbmras.example',     1, N'Verified'),
        (N'HSP-0004', N'Kukatpally City Hospital (Demo)',         N'Hospital',  N'TS-HOSP-DEMO-1104', N'KPHB Phase 3, Kukatpally',             N'Kukatpally',    N'500072', 17.494800, 78.399600, N'+91-40-5550-0104', N'city.kukat@sbmras.example',      0, N'Verified'),
        (N'HSP-0005', N'LB Nagar Community Hospital (Demo)',      N'Hospital',  N'TS-HOSP-DEMO-1105', N'Sagar Ring Road, LB Nagar',            N'LB Nagar',      N'500074', 17.345700, 78.552200, N'+91-40-5550-0105', N'community.lbn@sbmras.example',   0, N'Pending'),
        (N'HSP-0006', N'Ameerpet Medical Centre (Demo)',          N'Hospital',  N'TS-HOSP-DEMO-1106', N'Satyam Theatre Road, Ameerpet',        N'Ameerpet',      N'500016', 17.437500, 78.448200, N'+91-40-5550-0106', N'medical.ameerpet@sbmras.example',1, N'Verified'),
        (N'BBK-0001', N'Hyderabad Central Blood Bank (Demo)',     N'BloodBank', N'TS-BB-DEMO-2201',   N'Mythrivanam Road, Ameerpet',           N'Ameerpet',      N'500016', 17.436800, 78.445100, N'+91-40-5550-0201', N'central.bb@sbmras.example',      1, N'Verified'),
        (N'BBK-0002', N'Madhapur Blood Centre (Demo)',            N'BloodBank', N'TS-BB-DEMO-2202',   N'Ayyappa Society Main Road, Madhapur',  N'Madhapur',      N'500081', 17.448300, 78.391500, N'+91-40-5550-0202', N'madhapur.bc@sbmras.example',     1, N'Verified'),
        (N'BBK-0003', N'Dilsukhnagar Blood Bank (Demo)',          N'BloodBank', N'TS-BB-DEMO-2203',   N'Kothapet X Road, Dilsukhnagar',        N'Dilsukhnagar',  N'500060', 17.368800, 78.524700, N'+91-40-5550-0203', N'dsnr.bb@sbmras.example',         0, N'Verified'),
        (N'BBK-0004', N'Secunderabad Red Cross Blood Bank (Demo)',N'BloodBank', N'TS-BB-DEMO-2204',   N'Paradise Circle, Secunderabad',        N'Secunderabad',  N'500003', 17.443300, 78.487500, N'+91-40-5550-0204', N'redcross.secbad@sbmras.example', 1, N'Verified'),
        (N'BBK-0005', N'Kukatpally Blood Services (Demo)',        N'BloodBank', N'TS-BB-DEMO-2205',   N'JNTU Road, Kukatpally',                N'Kukatpally',    N'500072', 17.493000, 78.391000, N'+91-40-5550-0205', N'kukat.bs@sbmras.example',        0, N'Pending'),
        (N'BBK-0006', N'Banjara Hills Blood Bank (Demo)',         N'BloodBank', N'TS-BB-DEMO-2206',   N'Road No. 3, Banjara Hills',            N'Banjara Hills', N'500034', 17.418000, 78.440000, N'+91-40-5550-0206', N'banjara.bb@sbmras.example',      0, N'Suspended')
    ) AS s (FacilityCode, Name, FacilityType, LicenseNo, AddressLine, AreaName, Pincode, Latitude, Longitude, ContactPhone, ContactEmail, Is24x7, VerificationStatus)
    INNER JOIN dbo.Areas a ON a.Name = s.AreaName
) AS s ON t.FacilityCode = s.FacilityCode
WHEN NOT MATCHED THEN INSERT (FacilityCode, Name, FacilityType, LicenseNo, AddressLine, AreaId, City, Pincode, Latitude, Longitude,
                              ContactPhone, ContactEmail, Is24x7, VerificationStatus, VerifiedAt, VerifiedBy, VerificationNotes, IsActive,
                              CreatedAt, CreatedBy)
    VALUES (s.FacilityCode, s.Name, s.FacilityType, s.LicenseNo, s.AddressLine, s.AreaId, N'Hyderabad', s.Pincode, s.Latitude, s.Longitude,
            s.ContactPhone, s.ContactEmail, s.Is24x7, s.VerificationStatus,
            CASE WHEN s.VerificationStatus IN (N'Verified', N'Suspended') THEN DATEADD(DAY, -45, @Now) END,
            CASE WHEN s.VerificationStatus IN (N'Verified', N'Suspended') THEN 1 END,
            CASE s.VerificationStatus
                WHEN N'Verified'  THEN N'Licence and registration documents verified (Demo).'
                WHEN N'Suspended' THEN N'Suspended: licence renewal documents overdue (Demo).'
                ELSE NULL END,
            1, DATEADD(DAY, -75, @Now), 1);

/* Facility user assignments */
INSERT INTO dbo.FacilityUserAssignments (FacilityId, UserId, AssignmentRole, IsActive, AssignedAt, AssignedBy)
SELECT f.FacilityId, s.UserId, s.AssignmentRole, 1, DATEADD(DAY, -40, @Now), 1
FROM (VALUES
    (N'HSP-0001', 3, N'Manager'),  (N'HSP-0002', 3, N'Manager'),
    (N'HSP-0001', 4, N'Verifier'), (N'HSP-0003', 4, N'Manager'),
    (N'BBK-0001', 5, N'Operator'), (N'BBK-0002', 5, N'Manager'),
    (N'BBK-0001', 6, N'Verifier'), (N'BBK-0003', 6, N'Operator')
) AS s (FacilityCode, UserId, AssignmentRole)
INNER JOIN dbo.Facilities f ON f.FacilityCode = s.FacilityCode
INNER JOIN dbo.Users u ON u.UserId = s.UserId
WHERE NOT EXISTS (SELECT 1 FROM dbo.FacilityUserAssignments x WHERE x.FacilityId = f.FacilityId AND x.UserId = s.UserId);
GO

/*---------------------------------------------------------------------
  Blood inventory: full matrix (6 components x 4 ABO x 2 Rh) for every
  verified blood bank. Freshness bucket per row (0-4 Fresh, 5-6 Aging,
  7-8 Stale, 9 never updated / Unknown); some zero and low quantities.
  Blood TTL = 360 minutes; Aging >= 75% of window elapsed.
---------------------------------------------------------------------*/
DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
DECLARE @UnitsId INT = (SELECT UnitId FROM dbo.Units WHERE Code = N'UNITS');

;WITH F AS (
    SELECT f.FacilityId, CAST(RIGHT(f.FacilityCode, 4) AS INT) AS Fx,
           CASE CAST(RIGHT(f.FacilityCode, 4) AS INT) WHEN 1 THEN 5 WHEN 2 THEN 5 WHEN 3 THEN 6 ELSE 2 END AS UpdaterId,
           CASE CAST(RIGHT(f.FacilityCode, 4) AS INT) WHEN 1 THEN 2.20 WHEN 2 THEN 1.70 WHEN 3 THEN 1.20 ELSE 1.50 END AS Scale
    FROM dbo.Facilities f
    WHERE f.FacilityType = N'BloodBank' AND f.VerificationStatus = N'Verified'
), C AS (
    SELECT c.ComponentId, c.Code, c.ShelfLifeDays,
           CASE c.Code WHEN N'PRBC' THEN 1.00 WHEN N'WB' THEN 0.35 WHEN N'FFP' THEN 0.80 WHEN N'PLT' THEN 0.45 WHEN N'CRYO' THEN 0.30 ELSE 0.15 END AS Cm,
           CASE c.Code WHEN N'WB' THEN 1 WHEN N'PRBC' THEN 2 WHEN N'FFP' THEN 3 WHEN N'PLT' THEN 4 WHEN N'CRYO' THEN 5 ELSE 6 END AS Cx
    FROM dbo.BloodComponents c
    WHERE c.Code IN (N'WB', N'PRBC', N'FFP', N'PLT', N'CRYO', N'SDP')
), G AS (
    SELECT * FROM (VALUES (N'O', N'Positive', 38, 1), (N'B', N'Positive', 32, 2), (N'A', N'Positive', 24, 3), (N'AB', N'Positive', 9, 4),
                          (N'O', N'Negative', 5, 5),  (N'B', N'Negative', 4, 6),  (N'A', N'Negative', 3, 7),  (N'AB', N'Negative', 2, 8)
    ) AS g (AboGroup, RhFactor, Base, Gx)
), M AS (
    SELECT F.FacilityId, F.Fx, F.UpdaterId, F.Scale, C.ComponentId, C.Code, C.ShelfLifeDays, C.Cm, C.Cx, G.AboGroup, G.RhFactor, G.Base, G.Gx,
           (F.Fx * 7 + C.Cx * 3 + G.Gx * 5) % 10 AS Bucket,
           ABS(CAST(CHECKSUM(CONCAT(N'blood-', F.Fx, N'-', C.Cx, N'-', G.Gx)) AS BIGINT)) % 100 AS J
    FROM F CROSS JOIN C CROSS JOIN G
), Q AS (
    SELECT M.*,
           CASE WHEN M.Bucket = 9 THEN NULL
                WHEN M.Bucket <= 4 THEN 10 + M.J * 1.5
                WHEN M.Bucket <= 6 THEN 280 + M.J / 2
                ELSE 420 + M.J * 30 END AS MinutesAgo,
           CASE WHEN M.Bucket = 9 THEN 0
                WHEN M.J % 11 = 0 THEN 0
                ELSE CAST(ROUND(M.Base * M.Cm * M.Scale * (0.6 + M.J / 110.0), 0) AS DECIMAL(12, 2)) END AS Qty
    FROM M
)
INSERT INTO dbo.BloodInventory (FacilityId, ComponentId, AboGroup, RhFactor, Quantity, UnitId, EarliestExpiryDate, SourceType,
                                VerificationStatus, LastUpdatedAt, LastUpdatedBy, ValidUntil, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy)
SELECT q.FacilityId, q.ComponentId, q.AboGroup, q.RhFactor, q.Qty, @UnitsId,
       CASE WHEN q.Qty > 0 THEN CAST(DATEADD(DAY, 1 + q.J % CASE WHEN q.ShelfLifeDays > 40 THEN 40 ELSE q.ShelfLifeDays END, @Now) AS DATE) END,
       CASE WHEN q.Fx = 2 AND q.Cx IN (2, 3) THEN N'CSVImport' WHEN q.Fx = 4 AND q.Gx = 1 THEN N'AdminCorrection' ELSE N'ManualPortal' END,
       CASE WHEN q.MinutesAgo IS NULL THEN N'Unverified' ELSE N'Confirmed' END,
       DATEADD(MINUTE, -CAST(q.MinutesAgo AS INT), @Now),
       CASE WHEN q.MinutesAgo IS NULL THEN NULL ELSE q.UpdaterId END,
       DATEADD(MINUTE, 360 - CAST(q.MinutesAgo AS INT), @Now),
       DATEADD(DAY, -30, @Now), 1,
       COALESCE(DATEADD(MINUTE, -CAST(q.MinutesAgo AS INT), @Now), DATEADD(DAY, -30, @Now)),
       COALESCE(CASE WHEN q.MinutesAgo IS NULL THEN NULL ELSE q.UpdaterId END, 1)
FROM Q q
WHERE NOT EXISTS (SELECT 1 FROM dbo.BloodInventory b
                  WHERE b.FacilityId = q.FacilityId AND b.ComponentId = q.ComponentId AND b.AboGroup = q.AboGroup AND b.RhFactor = q.RhFactor);
GO

/*---------------------------------------------------------------------
  Medical resource inventory for every hospital (TTL 240 minutes).
  A few types are deliberately not recorded (shown as "Not reported").
  Data of a suspended facility (if any) is entirely stale.
---------------------------------------------------------------------*/
DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

;WITH F AS (
    SELECT f.FacilityId, f.VerificationStatus, CAST(RIGHT(f.FacilityCode, 4) AS INT) AS Fx,
           CASE CAST(RIGHT(f.FacilityCode, 4) AS INT) WHEN 1 THEN 3 WHEN 2 THEN 3 WHEN 3 THEN 4 ELSE 2 END AS UpdaterId,
           CASE CAST(RIGHT(f.FacilityCode, 4) AS INT) WHEN 1 THEN 1.5 WHEN 2 THEN 1.0 WHEN 3 THEN 1.2 WHEN 4 THEN 0.8 WHEN 5 THEN 0.6 ELSE 0.7 END AS Scale
    FROM dbo.Facilities f
    WHERE f.FacilityType = N'Hospital'
), T AS (
    SELECT t.ResourceTypeId, t.Code, t.DefaultUnitId, t.TrackingMode, s.BaseTotal, s.Tx
    FROM dbo.MedicalResourceTypes t
    INNER JOIN (VALUES (N'ICU_BED', 20, 1), (N'NICU_BED', 10, 2), (N'GEN_BED', 150, 3), (N'VENTILATOR', 12, 4), (N'O2_CYL', 60, 5),
                       (N'O2_CONC', 15, 6), (N'DIALYSIS', 8, 7), (N'AMBULANCE', 4, 8), (N'CT_SCAN', 1, 9), (N'DEFIB', 6, 10)
               ) AS s (Code, BaseTotal, Tx) ON s.Code = t.Code
), M AS (
    SELECT F.*, T.ResourceTypeId, T.Code, T.DefaultUnitId, T.TrackingMode, T.Tx,
           CASE WHEN T.Code = N'CT_SCAN' THEN CASE WHEN F.Fx IN (1, 3) THEN 2 ELSE 1 END
                ELSE CEILING(T.BaseTotal * F.Scale) END AS Total,
           CASE WHEN F.VerificationStatus = N'Suspended' THEN 7 ELSE (F.Fx * 3 + T.Tx * 7) % 10 END AS Bucket,
           ABS(CAST(CHECKSUM(CONCAT(N'res-', F.Fx, N'-', T.Tx)) AS BIGINT)) % 100 AS J
    FROM F CROSS JOIN T
    WHERE (F.Fx + T.Tx) % 11 <> 0
), Q AS (
    SELECT M.*,
           CASE WHEN M.Bucket = 9 THEN NULL
                WHEN M.Bucket <= 4 THEN 5 + M.J
                WHEN M.Bucket <= 6 THEN 190 + M.J / 3
                ELSE 300 + M.J * 25 END AS MinutesAgo,
           CASE WHEN M.Bucket = 9 THEN 0
                WHEN M.J % 9 = 0 THEN 0
                ELSE FLOOR(M.Total * (M.J % 80 + 5) / 100.0) END AS Avail
    FROM M
)
INSERT INTO dbo.MedicalResourceInventory (FacilityId, ResourceTypeId, TotalQuantity, AvailableQuantity, UnitId, OperationalStatus, Notes,
                                          SourceType, VerificationStatus, LastUpdatedAt, LastUpdatedBy, ValidUntil,
                                          CreatedAt, CreatedBy, UpdatedAt, UpdatedBy)
SELECT q.FacilityId, q.ResourceTypeId,
       CASE WHEN q.MinutesAgo IS NULL THEN 0 ELSE q.Total END,
       q.Avail, q.DefaultUnitId,
       CASE WHEN q.MinutesAgo IS NULL THEN N'Unknown'
            WHEN q.Avail = 0 THEN N'Unavailable'
            WHEN q.Avail * 4 < q.Total THEN N'Limited'
            ELSE N'Available' END,
       CASE WHEN q.Code = N'CT_SCAN' AND q.Avail = 0 AND q.MinutesAgo IS NOT NULL THEN N'Scheduled maintenance window (Demo).'
            WHEN q.Code = N'AMBULANCE' AND q.MinutesAgo IS NOT NULL THEN N'BLS and ALS units; call the facility desk to dispatch.'
            WHEN q.Code = N'O2_CYL' AND q.MinutesAgo IS NOT NULL THEN N'Type D cylinders; refill vendor visits daily.'
            END,
       CASE WHEN q.Fx = 1 AND q.Tx IN (5, 6) THEN N'CSVImport' ELSE N'ManualPortal' END,
       CASE WHEN q.MinutesAgo IS NULL THEN N'Unverified' ELSE N'Confirmed' END,
       DATEADD(MINUTE, -CAST(q.MinutesAgo AS INT), @Now),
       CASE WHEN q.MinutesAgo IS NULL THEN NULL ELSE q.UpdaterId END,
       DATEADD(MINUTE, 240 - CAST(q.MinutesAgo AS INT), @Now),
       DATEADD(DAY, -30, @Now), 1,
       COALESCE(DATEADD(MINUTE, -CAST(q.MinutesAgo AS INT), @Now), DATEADD(DAY, -30, @Now)),
       COALESCE(CASE WHEN q.MinutesAgo IS NULL THEN NULL ELSE q.UpdaterId END, 1)
FROM Q q
WHERE NOT EXISTS (SELECT 1 FROM dbo.MedicalResourceInventory r WHERE r.FacilityId = q.FacilityId AND r.ResourceTypeId = q.ResourceTypeId);
GO

/*---------------------------------------------------------------------
  Blood requests (21, every status) with full status history.
  Generated only when dbo.BloodRequests is empty.
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.BloodRequests)
BEGIN
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Year NVARCHAR(4) = CAST(YEAR(@Now) AS NVARCHAR(4));
    DECLARE @UnitsId INT = (SELECT UnitId FROM dbo.Units WHERE Code = N'UNITS');

    DECLARE @Req TABLE (Seq INT, RequesterUserId INT, PatientReference NVARCHAR(50), AboGroup NVARCHAR(2), RhFactor NVARCHAR(10),
                        ComponentCode NVARCHAR(10), Qty DECIMAL(12, 2), Urgency NVARCHAR(20), NeededHours INT, AreaName NVARCHAR(100),
                        HospitalName NVARCHAR(200), PreferredCode NVARCHAR(20), MatchedCode NVARCHAR(20), ContactName NVARCHAR(150),
                        ContactPhone NVARCHAR(30), Status NVARCHAR(20), StatusReason NVARCHAR(500), CoordinatorId INT, MinutesAgo INT,
                        Notes NVARCHAR(500));
    INSERT INTO @Req VALUES
        (1,  7,  N'PT-GCB-0412', N'O',  N'Positive', N'PRBC', 2, N'Emergency', 6,   N'Gachibowli',    N'Gachibowli Multispeciality Hospital (Demo)', N'BBK-0002', NULL,       N'Priya Sharma',   N'+91-90000-10007', N'Submitted',      NULL, NULL, 25,    N'Post-operative bleed; ward has requested two units urgently.'),
        (2,  8,  N'PT-SEC-1177', N'B',  N'Negative', N'PRBC', 3, N'Urgent',    20,  N'Secunderabad',  N'Secunderabad General Hospital (Demo)',       N'BBK-0004', NULL,       N'Rahul Verma',    N'+91-90000-10008', N'Submitted',      NULL, NULL, 140,   NULL),
        (3,  9,  N'PT-KPY-0233', N'A',  N'Positive', N'PLT',  4, N'Routine',   48,  N'Kukatpally',    N'Kukatpally City Hospital (Demo)',            NULL,       NULL,       N'Sneha Patil',    N'+91-90000-10009', N'Submitted',      NULL, NULL, 600,   N'Dengue patient, platelet count trending down.'),
        (4,  10, N'PT-BJH-0871', N'AB', N'Positive', N'FFP',  2, N'Urgent',    24,  N'Banjara Hills', N'Banjara Care Hospital (Demo)',               NULL,       NULL,       N'Mohammed Irfan', N'+91-90000-10010', N'Submitted',      NULL, NULL, 1500,  NULL),
        (5,  7,  N'PT-AMP-0590', N'O',  N'Negative', N'PRBC', 2, N'Emergency', 8,   N'Ameerpet',      N'Ameerpet Medical Centre (Demo)',             N'BBK-0001', NULL,       N'Priya Sharma',   N'+91-90000-10007', N'UnderReview',    NULL, 5,    300,   N'Trauma case, O negative preferred.'),
        (6,  8,  N'PT-DSN-0148', N'B',  N'Positive', N'WB',   1, N'Routine',   72,  N'Dilsukhnagar',  N'Dilsukhnagar Nursing Home (Demo)',           N'BBK-0003', NULL,       N'Rahul Verma',    N'+91-90000-10008', N'UnderReview',    NULL, 6,    2900,  NULL),
        (7,  3,  N'PT-BJH-0932', N'A',  N'Negative', N'PRBC', 2, N'Urgent',    30,  N'Banjara Hills', N'Banjara Care Hospital (Demo)',               NULL,       NULL,       N'Dr. Karthik Menon', N'+91-40-5550-1003', N'UnderReview', NULL, 1,    4300,  N'Elective surgery tomorrow morning.'),
        (8,  9,  N'PT-MDP-0321', N'O',  N'Positive', N'PLT',  6, N'Urgent',    18,  N'Madhapur',      N'Madhapur Women and Child Clinic (Demo)',     N'BBK-0002', N'BBK-0002', N'Sneha Patil',    N'+91-90000-10009', N'Matched',        NULL, 5,    3000,  NULL),
        (9,  10, N'PT-DSN-0655', N'B',  N'Positive', N'PRBC', 2, N'Routine',   60,  N'Dilsukhnagar',  N'Dilsukhnagar Nursing Home (Demo)',           NULL,       N'BBK-0003', N'Mohammed Irfan', N'+91-90000-10010', N'Matched',        NULL, 6,    5800,  NULL),
        (10, 7,  N'PT-AMP-0712', N'AB', N'Negative', N'FFP',  2, N'Emergency', 5,   N'Ameerpet',      N'Ameerpet Medical Centre (Demo)',             N'BBK-0001', N'BBK-0001', N'Priya Sharma',   N'+91-90000-10007', N'Matched',        NULL, 5,    900,   N'Rare group; please confirm availability by phone.'),
        (11, 8,  N'PT-SEC-1290', N'O',  N'Positive', N'PRBC', 3, N'Urgent',    12,  N'Secunderabad',  N'Secunderabad General Hospital (Demo)',       N'BBK-0004', N'BBK-0004', N'Rahul Verma',    N'+91-90000-10008', N'Contacted',      NULL, 1,    7000,  NULL),
        (12, 9,  N'PT-AMP-0804', N'A',  N'Positive', N'CRYO', 4, N'Routine',   48,  N'Ameerpet',      N'Ameerpet Medical Centre (Demo)',             NULL,       N'BBK-0001', N'Sneha Patil',    N'+91-90000-10009', N'Contacted',      NULL, 6,    8600,  NULL),
        (13, 10, N'PT-BJH-0999', N'O',  N'Positive', N'PRBC', 2, N'Emergency', 4,   N'Banjara Hills', N'Banjara Care Hospital (Demo)',               N'BBK-0001', N'BBK-0001', N'Mohammed Irfan', N'+91-90000-10010', N'Fulfilled',      NULL, 5,    10200, NULL),
        (14, 7,  N'PT-MDP-0410', N'B',  N'Positive', N'SDP',  1, N'Urgent',    16,  N'Madhapur',      N'Madhapur Women and Child Clinic (Demo)',     N'BBK-0002', N'BBK-0002', N'Priya Sharma',   N'+91-90000-10007', N'Fulfilled',      NULL, 5,    12500, NULL),
        (15, 5,  N'PT-DSN-0702', N'A',  N'Positive', N'PRBC', 2, N'Routine',   36,  N'Dilsukhnagar',  N'Dilsukhnagar Nursing Home (Demo)',           NULL,       N'BBK-0003', N'Ravi Teja Kumar', N'+91-40-5550-1005', N'Fulfilled',     NULL, 6,    15000, NULL),
        (16, 8,  N'PT-LBN-0119', N'AB', N'Negative', N'PLT',  3, N'Urgent',    10,  N'LB Nagar',      N'LB Nagar Community Hospital (Demo)',         NULL,       NULL,       N'Rahul Verma',    N'+91-90000-10008', N'UnableToFulfil', N'No compatible platelets reported by verified facilities within the requested time.', 1, 11000, NULL),
        (17, 9,  N'PT-KPY-0388', N'O',  N'Negative', N'WB',   2, N'Emergency', 6,   N'Kukatpally',    N'Kukatpally City Hospital (Demo)',            NULL,       NULL,       N'Sneha Patil',    N'+91-90000-10009', N'UnableToFulfil', N'Whole blood O negative not available; family advised to arrange replacement donors.', 6, 17000, NULL),
        (18, 10, N'PT-GCB-0127', N'A',  N'Negative', N'FFP',  2, N'Routine',   48,  N'Gachibowli',    N'Gachibowli Multispeciality Hospital (Demo)', N'BBK-0002', N'BBK-0002', N'Mohammed Irfan', N'+91-90000-10010', N'Closed',         N'Fulfilled and confirmed by hospital.', 5, 18500, NULL),
        (19, 7,  N'PT-SEC-1012', N'B',  N'Negative', N'PRBC', 1, N'Urgent',    24,  N'Secunderabad',  N'Secunderabad General Hospital (Demo)',       NULL,       N'BBK-0004', N'Priya Sharma',   N'+91-90000-10007', N'Closed',         N'Fulfilled and confirmed by hospital.', 1, 19500, NULL),
        (20, 8,  N'PT-GCB-0555', N'O',  N'Positive', N'PLT',  2, N'Routine',   48,  N'Gachibowli',    N'Gachibowli Multispeciality Hospital (Demo)', NULL,       NULL,       N'Rahul Verma',    N'+91-90000-10008', N'Cancelled',      N'Patient transferred to another city.', NULL, 6000, NULL),
        (21, 9,  N'PT-MDP-0640', N'AB', N'Positive', N'PRBC', 1, N'Routine',   72,  N'Madhapur',      N'Madhapur Women and Child Clinic (Demo)',     NULL,       NULL,       N'Sneha Patil',    N'+91-90000-10009', N'Cancelled',      N'Requirement met by a family donor.', NULL, 13000, NULL);

    DECLARE @Paths TABLE (Status NVARCHAR(20), Step INT, ToStatus NVARCHAR(20));
    INSERT INTO @Paths VALUES
        (N'Submitted', 1, N'Submitted'),
        (N'UnderReview', 1, N'Submitted'), (N'UnderReview', 2, N'UnderReview'),
        (N'Matched', 1, N'Submitted'), (N'Matched', 2, N'UnderReview'), (N'Matched', 3, N'Matched'),
        (N'Contacted', 1, N'Submitted'), (N'Contacted', 2, N'UnderReview'), (N'Contacted', 3, N'Matched'), (N'Contacted', 4, N'Contacted'),
        (N'Fulfilled', 1, N'Submitted'), (N'Fulfilled', 2, N'UnderReview'), (N'Fulfilled', 3, N'Matched'), (N'Fulfilled', 4, N'Contacted'), (N'Fulfilled', 5, N'Fulfilled'),
        (N'UnableToFulfil', 1, N'Submitted'), (N'UnableToFulfil', 2, N'UnderReview'), (N'UnableToFulfil', 3, N'UnableToFulfil'),
        (N'Closed', 1, N'Submitted'), (N'Closed', 2, N'UnderReview'), (N'Closed', 3, N'Matched'), (N'Closed', 4, N'Contacted'), (N'Closed', 5, N'Fulfilled'), (N'Closed', 6, N'Closed'),
        (N'Cancelled', 1, N'Submitted'), (N'Cancelled', 2, N'Cancelled');

    DECLARE @Steps TABLE (Status NVARCHAR(20) PRIMARY KEY, Steps INT);
    INSERT INTO @Steps SELECT Status, MAX(Step) FROM @Paths GROUP BY Status;

    INSERT INTO dbo.BloodRequests (RequestNo, RequesterUserId, PatientReference, AboGroup, RhFactor, ComponentId, QuantityRequested, UnitId,
                                   Urgency, NeededBy, AreaId, HospitalName, PreferredFacilityId, MatchedFacilityId, ContactName, ContactPhone,
                                   ContactConsent, Notes, Status, StatusReason, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy)
    SELECT N'BRQ-' + @Year + N'-' + RIGHT(N'0000' + CAST(ROW_NUMBER() OVER (ORDER BY r.MinutesAgo DESC) AS NVARCHAR(10)), 4),
           r.RequesterUserId, r.PatientReference, r.AboGroup, r.RhFactor, c.ComponentId, r.Qty, @UnitsId, r.Urgency,
           CASE WHEN r.Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted')
                THEN DATEADD(HOUR, r.NeededHours, @Now)
                ELSE DATEADD(HOUR, r.NeededHours, DATEADD(MINUTE, -r.MinutesAgo, @Now)) END,
           a.AreaId, r.HospitalName, pf.FacilityId, mf.FacilityId, r.ContactName, r.ContactPhone, 1, r.Notes, r.Status, r.StatusReason,
           DATEADD(MINUTE, -r.MinutesAgo, @Now), r.RequesterUserId,
           DATEADD(MINUTE, -r.MinutesAgo + (s.Steps - 1) * (r.MinutesAgo / (s.Steps + 1)), @Now),
           CASE WHEN s.Steps = 1 OR r.Status = N'Cancelled' THEN r.RequesterUserId ELSE r.CoordinatorId END
    FROM @Req r
    INNER JOIN @Steps s ON s.Status = r.Status
    INNER JOIN dbo.BloodComponents c ON c.Code = r.ComponentCode
    INNER JOIN dbo.Areas a ON a.Name = r.AreaName
    LEFT JOIN dbo.Facilities pf ON pf.FacilityCode = r.PreferredCode
    LEFT JOIN dbo.Facilities mf ON mf.FacilityCode = r.MatchedCode;

    INSERT INTO dbo.BloodRequestHistory (RequestId, FromStatus, ToStatus, Note, FacilityId, ChangedBy, ChangedAt)
    SELECT br.RequestId,
           LAG(p.ToStatus) OVER (PARTITION BY br.RequestId ORDER BY p.Step),
           p.ToStatus,
           CASE p.ToStatus
               WHEN N'Submitted'      THEN N'Request submitted.'
               WHEN N'UnderReview'    THEN N'Picked up for coordination; checking reported availability.'
               WHEN N'Matched'        THEN N'Matched with a verified facility reporting fresh stock.'
               WHEN N'Contacted'      THEN N'Facility contacted; requester informed to reconfirm and collect.'
               WHEN N'Fulfilled'      THEN N'Facility confirmed the units were issued.'
               WHEN N'UnableToFulfil' THEN r.StatusReason
               WHEN N'Closed'         THEN r.StatusReason
               WHEN N'Cancelled'      THEN r.StatusReason END,
           CASE WHEN p.ToStatus IN (N'Matched', N'Contacted', N'Fulfilled', N'Closed') THEN br.MatchedFacilityId END,
           CASE WHEN p.Step = 1 OR p.ToStatus = N'Cancelled' THEN r.RequesterUserId ELSE r.CoordinatorId END,
           DATEADD(MINUTE, -r.MinutesAgo + (p.Step - 1) * (r.MinutesAgo / (s.Steps + 1)), @Now)
    FROM @Req r
    INNER JOIN @Steps s ON s.Status = r.Status
    INNER JOIN @Paths p ON p.Status = r.Status
    INNER JOIN dbo.BloodRequests br ON br.PatientReference = r.PatientReference AND br.RequesterUserId = r.RequesterUserId;
END
GO

/*---------------------------------------------------------------------
  Inventory changes: applied history, one rejected anomaly and three
  PendingReview LARGE_JUMP changes (inventory rows -> PendingReview).
  Generated only when dbo.InventoryChanges is empty.
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.InventoryChanges)
BEGIN
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Year NVARCHAR(4) = CAST(YEAR(@Now) AS NVARCHAR(4));

    DECLARE @Chg TABLE (Id INT IDENTITY(1, 1), FacilityId INT, InventoryKind NVARCHAR(10), InventoryId INT, ComponentId INT NULL,
                        AboGroup NVARCHAR(2) NULL, RhFactor NVARCHAR(10) NULL, ResourceTypeId INT NULL,
                        PreviousQuantity DECIMAL(12, 2) NULL, ProposedQuantity DECIMAL(12, 2) NULL,
                        PreviousAvailable DECIMAL(12, 2) NULL, ProposedAvailable DECIMAL(12, 2) NULL, ProposedTotal DECIMAL(12, 2) NULL,
                        ProposedStatus NVARCHAR(20) NULL, EarliestExpiryDate DATE NULL, ValidUntil DATETIME2(0) NULL,
                        SourceType NVARCHAR(20), Reason NVARCHAR(500), AnomalyFlags NVARCHAR(400) NULL, Status NVARCHAR(20),
                        SubmittedBy INT, SubmittedAt DATETIME2(0), DecidedBy INT NULL, DecidedAt DATETIME2(0) NULL, DecisionReason NVARCHAR(500) NULL);

    /* Applied blood changes: the latest update of the 3 most recently updated rows per verified blood bank. */
    INSERT INTO @Chg (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, PreviousQuantity, ProposedQuantity,
                      EarliestExpiryDate, ValidUntil, SourceType, Reason, Status, SubmittedBy, SubmittedAt)
    SELECT x.FacilityId, N'Blood', x.InventoryId, x.ComponentId, x.AboGroup, x.RhFactor,
           CASE WHEN x.Quantity >= 3 THEN x.Quantity - 2 ELSE x.Quantity + 1 END, x.Quantity,
           x.EarliestExpiryDate, x.ValidUntil, x.SourceType, N'Routine stock count after issue/receipt.', N'Applied', x.LastUpdatedBy, x.LastUpdatedAt
    FROM (SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.FacilityId ORDER BY b.LastUpdatedAt DESC, b.InventoryId) AS Rn
          FROM dbo.BloodInventory b
          WHERE b.LastUpdatedAt IS NOT NULL AND b.VerificationStatus = N'Confirmed') x
    WHERE x.Rn <= 3;

    /* Applied resource changes: latest 2 per hospital. */
    INSERT INTO @Chg (FacilityId, InventoryKind, InventoryId, ResourceTypeId, PreviousAvailable, ProposedAvailable, ProposedTotal, ProposedStatus,
                      ValidUntil, SourceType, Reason, Status, SubmittedBy, SubmittedAt)
    SELECT x.FacilityId, N'Resource', x.ResourceInventoryId, x.ResourceTypeId,
           CASE WHEN x.AvailableQuantity >= 1 THEN x.AvailableQuantity - 1 ELSE x.AvailableQuantity + 1 END,
           x.AvailableQuantity, x.TotalQuantity, x.OperationalStatus, x.ValidUntil, x.SourceType,
           N'Shift handover census.', N'Applied', x.LastUpdatedBy, x.LastUpdatedAt
    FROM (SELECT r.*, ROW_NUMBER() OVER (PARTITION BY r.FacilityId ORDER BY r.LastUpdatedAt DESC, r.ResourceInventoryId) AS Rn
          FROM dbo.MedicalResourceInventory r
          INNER JOIN dbo.Facilities f ON f.FacilityId = r.FacilityId AND f.VerificationStatus = N'Verified'
          WHERE r.LastUpdatedAt IS NOT NULL AND r.VerificationStatus = N'Confirmed') x
    WHERE x.Rn <= 2;

    /* Rejected anomaly (BBK-0003, CRYO A+) decided by an admin two days ago. */
    INSERT INTO @Chg (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, PreviousQuantity, ProposedQuantity,
                      ValidUntil, SourceType, Reason, AnomalyFlags, Status, SubmittedBy, SubmittedAt, DecidedBy, DecidedAt, DecisionReason)
    SELECT b.FacilityId, N'Blood', b.InventoryId, b.ComponentId, b.AboGroup, b.RhFactor, b.Quantity, b.Quantity + 80,
           DATEADD(MINUTE, 360, DATEADD(DAY, -2, @Now)), N'ManualPortal', N'Stock count after camp collection.', N'LARGE_JUMP', N'Rejected',
           6, DATEADD(MINUTE, -60, DATEADD(DAY, -2, @Now)), 1, DATEADD(DAY, -2, @Now), N'Typo in quantity (extra zero); operator to resubmit.'
    FROM dbo.BloodInventory b
    INNER JOIN dbo.Facilities f ON f.FacilityId = b.FacilityId AND f.FacilityCode = N'BBK-0003'
    INNER JOIN dbo.BloodComponents c ON c.ComponentId = b.ComponentId AND c.Code = N'CRYO'
    WHERE b.AboGroup = N'A' AND b.RhFactor = N'Positive';

    /* Three PendingReview LARGE_JUMP changes (submitted recently). */
    INSERT INTO @Chg (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, PreviousQuantity, ProposedQuantity,
                      EarliestExpiryDate, ValidUntil, SourceType, Reason, AnomalyFlags, Status, SubmittedBy, SubmittedAt)
    SELECT b.FacilityId, N'Blood', b.InventoryId, b.ComponentId, b.AboGroup, b.RhFactor, b.Quantity, b.Quantity + s.Jump,
           CAST(DATEADD(DAY, s.ExpiryDays, @Now) AS DATE), DATEADD(MINUTE, 360 - s.MinutesAgo, @Now), N'ManualPortal', s.Reason,
           N'LARGE_JUMP', N'PendingReview', 5, DATEADD(MINUTE, -s.MinutesAgo, @Now)
    FROM (VALUES (N'BBK-0001', N'PRBC', N'O', N'Positive', 65, 35, 18, N'Received inter-bank transfer from state blood transfusion council.'),
                 (N'BBK-0002', N'PLT',  N'B', N'Positive', 40, 4,  42, N'Platelet apheresis drive at IT park.')
         ) AS s (FacilityCode, ComponentCode, AboGroup, RhFactor, Jump, ExpiryDays, MinutesAgo, Reason)
    INNER JOIN dbo.Facilities f ON f.FacilityCode = s.FacilityCode
    INNER JOIN dbo.BloodComponents c ON c.Code = s.ComponentCode
    INNER JOIN dbo.BloodInventory b ON b.FacilityId = f.FacilityId AND b.ComponentId = c.ComponentId AND b.AboGroup = s.AboGroup AND b.RhFactor = s.RhFactor;

    INSERT INTO @Chg (FacilityId, InventoryKind, InventoryId, ResourceTypeId, PreviousAvailable, ProposedAvailable, ProposedTotal, ProposedStatus,
                      ValidUntil, SourceType, Reason, AnomalyFlags, Status, SubmittedBy, SubmittedAt)
    SELECT r.FacilityId, N'Resource', r.ResourceInventoryId, r.ResourceTypeId, r.AvailableQuantity, r.TotalQuantity + 24, r.TotalQuantity + 30,
           N'Available', DATEADD(MINUTE, 240 - 75, @Now), N'ManualPortal', N'New ICU block commissioned; beds added to census.',
           N'LARGE_JUMP', N'PendingReview', 3, DATEADD(MINUTE, -75, @Now)
    FROM dbo.MedicalResourceInventory r
    INNER JOIN dbo.Facilities f ON f.FacilityId = r.FacilityId AND f.FacilityCode = N'HSP-0001'
    INNER JOIN dbo.MedicalResourceTypes t ON t.ResourceTypeId = r.ResourceTypeId AND t.Code = N'ICU_BED';

    INSERT INTO dbo.InventoryChanges (ChangeNo, FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, ResourceTypeId,
                                      PreviousQuantity, ProposedQuantity, PreviousAvailable, ProposedAvailable, ProposedTotal, ProposedStatus,
                                      EarliestExpiryDate, ValidUntil, BeforeJson, AfterJson, SourceType, Reason, AnomalyFlags, Status,
                                      ImportBatchId, IdempotencyKey, SubmittedBy, SubmittedAt, DecidedBy, DecidedAt, DecisionReason)
    SELECT N'CHG-' + @Year + N'-' + RIGHT(N'0000' + CAST(ROW_NUMBER() OVER (ORDER BY c.SubmittedAt, c.Id) AS NVARCHAR(10)), 4),
           c.FacilityId, c.InventoryKind, c.InventoryId, c.ComponentId, c.AboGroup, c.RhFactor, c.ResourceTypeId,
           c.PreviousQuantity, c.ProposedQuantity, c.PreviousAvailable, c.ProposedAvailable, c.ProposedTotal, c.ProposedStatus,
           c.EarliestExpiryDate, c.ValidUntil,
           CASE WHEN c.InventoryKind = N'Blood'
                THEN N'{"quantity":' + CAST(c.PreviousQuantity AS NVARCHAR(20)) + N'}'
                ELSE N'{"availableQuantity":' + CAST(c.PreviousAvailable AS NVARCHAR(20)) + N'}' END,
           CASE WHEN c.InventoryKind = N'Blood'
                THEN N'{"quantity":' + CAST(c.ProposedQuantity AS NVARCHAR(20)) + N'}'
                ELSE N'{"totalQuantity":' + CAST(c.ProposedTotal AS NVARCHAR(20)) + N',"availableQuantity":' + CAST(c.ProposedAvailable AS NVARCHAR(20))
                     + N',"operationalStatus":"' + c.ProposedStatus + N'"}' END,
           c.SourceType, c.Reason, c.AnomalyFlags, c.Status, NULL, NULL, c.SubmittedBy, c.SubmittedAt, c.DecidedBy, c.DecidedAt, c.DecisionReason
    FROM @Chg c;

    /* Inventory rows awaiting review (values unchanged). */
    UPDATE b SET VerificationStatus = N'PendingReview'
    FROM dbo.BloodInventory b
    INNER JOIN dbo.InventoryChanges ic ON ic.InventoryKind = N'Blood' AND ic.InventoryId = b.InventoryId AND ic.Status = N'PendingReview';

    UPDATE r SET VerificationStatus = N'PendingReview'
    FROM dbo.MedicalResourceInventory r
    INNER JOIN dbo.InventoryChanges ic ON ic.InventoryKind = N'Resource' AND ic.InventoryId = r.ResourceInventoryId AND ic.Status = N'PendingReview';
END
GO

/*---------------------------------------------------------------------
  Import batches: one committed blood import (BBK-0002) and one
  validated resource import awaiting commit (HSP-0001).
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.ImportBatches)
BEGIN
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Year NVARCHAR(4) = CAST(YEAR(@Now) AS NVARCHAR(4));
    DECLARE @Bbk2 INT = (SELECT FacilityId FROM dbo.Facilities WHERE FacilityCode = N'BBK-0002');
    DECLARE @Hsp1 INT = (SELECT FacilityId FROM dbo.Facilities WHERE FacilityCode = N'HSP-0001');

    INSERT INTO dbo.ImportBatches (BatchNo, FacilityId, InventoryKind, FileName, FileHash, TotalRows, ValidRows, InvalidRows, DuplicateRows,
                                   AppliedRows, ReviewRows, Status, IdempotencyKey, SubmittedBy, SubmittedAt, CommittedBy, CommittedAt)
    VALUES (N'IMP-' + @Year + N'-0001', @Bbk2, N'Blood', N'madhapur_blood_stock.csv',
            N'5f2b8c1e9a7d4e3f8b6a1c0d2e4f6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f', 6, 4, 1, 1, 4, 0, N'Committed', N'seed-imp-0001',
            5, DATEADD(HOUR, -30, @Now), 5, DATEADD(MINUTE, -1790, @Now)),
           (N'IMP-' + @Year + N'-0002', @Hsp1, N'Resource', N'banjara_resources_evening.csv',
            N'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9', 5, 3, 1, 1, 0, 0, N'Validated', NULL,
            3, DATEADD(MINUTE, -50, @Now), NULL, NULL);

    DECLARE @B1 INT = (SELECT BatchId FROM dbo.ImportBatches WHERE BatchNo = N'IMP-' + @Year + N'-0001');
    DECLARE @B2 INT = (SELECT BatchId FROM dbo.ImportBatches WHERE BatchNo = N'IMP-' + @Year + N'-0002');
    DECLARE @Vu NVARCHAR(30) = CONVERT(NVARCHAR(30), DATEADD(MINUTE, 330, DATEADD(HOUR, -30, @Now)), 126);
    DECLARE @Ex NVARCHAR(10) = CONVERT(NVARCHAR(10), DATEADD(DAY, 20, @Now), 23);

    INSERT INTO dbo.ImportRows (BatchId, RowNumber, RawData, ComponentCode, AboGroup, RhFactor, ResourceTypeCode, Quantity, TotalQuantity,
                                AvailableQuantity, OperationalStatus, EarliestExpiryDate, ValidUntil, ValidationStatus, ErrorCodes, ErrorMessages)
    VALUES
        (@B1, 1, N'PRBC,O,Positive,22,' + @Ex + N',' + @Vu, N'PRBC', N'O', N'Positive', NULL, 22, NULL, NULL, NULL, CAST(@Ex AS DATE), CAST(@Vu AS DATETIME2(0)), N'Applied', NULL, NULL),
        (@B1, 2, N'PRBC,B,Positive,18,' + @Ex + N',' + @Vu, N'PRBC', N'B', N'Positive', NULL, 18, NULL, NULL, NULL, CAST(@Ex AS DATE), CAST(@Vu AS DATETIME2(0)), N'Applied', NULL, NULL),
        (@B1, 3, N'FFP,A,Positive,15,' + @Ex + N',' + @Vu,  N'FFP',  N'A', N'Positive', NULL, 15, NULL, NULL, NULL, CAST(@Ex AS DATE), CAST(@Vu AS DATETIME2(0)), N'Applied', NULL, NULL),
        (@B1, 4, N'FFP,O,Negative,3,' + @Ex + N',' + @Vu,   N'FFP',  N'O', N'Negative', NULL, 3,  NULL, NULL, NULL, CAST(@Ex AS DATE), CAST(@Vu AS DATETIME2(0)), N'Applied', NULL, NULL),
        (@B1, 5, N'PRBC,O,Positive,22,' + @Ex + N',' + @Vu, N'PRBC', N'O', N'Positive', NULL, 22, NULL, NULL, NULL, CAST(@Ex AS DATE), CAST(@Vu AS DATETIME2(0)), N'Duplicate', N'DUPLICATE', N'Row duplicates row 1 (PRBC O+).'),
        (@B1, 6, N'PRBX,A,Positive,-4,,',                    N'PRBX', N'A', N'Positive', NULL, -4, NULL, NULL, NULL, NULL, NULL, N'Invalid', N'UNKNOWN_COMPONENT,NEGATIVE', N'Unknown component code ''PRBX''.;Quantity must be zero or greater.'),
        (@B2, 1, N'GEN_BED,225,61,Available,', NULL, NULL, NULL, N'GEN_BED', NULL, 225, 61, N'Available', NULL, NULL, N'Valid', NULL, NULL),
        (@B2, 2, N'VENTILATOR,18,4,Limited,',  NULL, NULL, NULL, N'VENTILATOR', NULL, 18, 4, N'Limited', NULL, NULL, N'Valid', NULL, NULL),
        (@B2, 3, N'O2_CONC,23,15,Available,',  NULL, NULL, NULL, N'O2_CONC', NULL, 23, 15, N'Available', NULL, NULL, N'Valid', NULL, NULL),
        (@B2, 4, N'DEFIB,9,12,Available,',     NULL, NULL, NULL, N'DEFIB', NULL, 9, 12, N'Available', NULL, NULL, N'Invalid', N'AVAILABLE_GT_TOTAL', N'Available quantity cannot exceed total quantity.'),
        (@B2, 5, N'O2_CONC,23,15,Available,',  NULL, NULL, NULL, N'O2_CONC', NULL, 23, 15, N'Available', NULL, NULL, N'Duplicate', N'DUPLICATE', N'Row duplicates row 3 (O2_CONC).');
END
GO

/*---------------------------------------------------------------------
  Validation issues (open + resolved/dismissed history).
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.ValidationIssues)
BEGIN
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    /* LARGE_JUMP for each pending change (open) and the rejected one (dismissed). */
    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt,
                                      ResolvedBy, ResolvedAt, Resolution)
    SELECT ic.FacilityId, N'InventoryChange', ic.ChangeId, N'LARGE_JUMP', N'High',
           CASE WHEN ic.InventoryKind = N'Blood'
                THEN CAST(ic.PreviousQuantity AS NVARCHAR(20)) + N' -> ' + CAST(ic.ProposedQuantity AS NVARCHAR(20))
                ELSE CAST(ic.PreviousAvailable AS NVARCHAR(20)) + N' -> ' + CAST(ic.ProposedAvailable AS NVARCHAR(20)) END,
           N'Change ' + ic.ChangeNo + N' differs sharply from the previous value and is held for verification.',
           CASE WHEN ic.Status = N'PendingReview' THEN N'Open' ELSE N'Dismissed' END,
           ic.SubmittedAt, ic.DecidedBy, ic.DecidedAt, CASE WHEN ic.Status = N'Rejected' THEN ic.DecisionReason END
    FROM dbo.InventoryChanges ic
    WHERE ic.AnomalyFlags LIKE N'%LARGE_JUMP%';

    /* STALE: confirmed blood rows older than the TTL at BBK-0003/BBK-0004 (open), plus a few resolved ones. */
    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt,
                                      ResolvedBy, ResolvedAt, Resolution)
    SELECT TOP (8) b.FacilityId, N'BloodInventory', b.InventoryId, N'STALE', N'Medium',
           CAST(DATEDIFF(MINUTE, b.LastUpdatedAt, @Now) AS NVARCHAR(20)) + N' min',
           c.Code + N' ' + b.AboGroup + CASE b.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END + N' has not been updated within the validity window.',
           N'Open', DATEADD(MINUTE, 30, b.ValidUntil), NULL, NULL, NULL
    FROM dbo.BloodInventory b
    INNER JOIN dbo.BloodComponents c ON c.ComponentId = b.ComponentId
    WHERE b.ValidUntil < DATEADD(MINUTE, -30, @Now) AND b.VerificationStatus = N'Confirmed'
    ORDER BY b.ValidUntil, b.InventoryId;

    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt,
                                      ResolvedBy, ResolvedAt, Resolution)
    SELECT TOP (3) b.FacilityId, N'BloodInventory', b.InventoryId, N'STALE', N'Medium', N'410 min',
           N'Record was stale and has since been re-confirmed.', N'Resolved', DATEADD(DAY, -3, @Now), b.LastUpdatedBy, DATEADD(MINUTE, 90, DATEADD(DAY, -3, @Now)),
           N'Stock re-confirmed by the blood bank.'
    FROM dbo.BloodInventory b
    WHERE b.LastUpdatedAt > DATEADD(MINUTE, -180, @Now) AND b.VerificationStatus = N'Confirmed'
    ORDER BY b.InventoryId;

    /* EXPIRING: stock expiring within 3 days. */
    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt)
    SELECT TOP (4) b.FacilityId, N'BloodInventory', b.InventoryId, N'EXPIRING', N'Low', CONVERT(NVARCHAR(10), b.EarliestExpiryDate, 23),
           c.Code + N' ' + b.AboGroup + CASE b.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END + N' has units expiring on '
               + CONVERT(NVARCHAR(10), b.EarliestExpiryDate, 23) + N'.',
           N'Open', DATEADD(MINUTE, -45, @Now)
    FROM dbo.BloodInventory b
    INNER JOIN dbo.BloodComponents c ON c.ComponentId = b.ComponentId
    WHERE b.Quantity > 0 AND b.EarliestExpiryDate <= CAST(DATEADD(DAY, 3, @Now) AS DATE)
    ORDER BY b.EarliestExpiryDate, b.InventoryId;

    /* MISSING_FIELD: never-reported resource rows. */
    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt)
    SELECT TOP (3) r.FacilityId, N'ResourceInventory', r.ResourceInventoryId, N'MISSING_FIELD', N'Low', NULL,
           t.Name + N' has never been reported by this facility.', N'Open', DATEADD(HOUR, -5, @Now)
    FROM dbo.MedicalResourceInventory r
    INNER JOIN dbo.MedicalResourceTypes t ON t.ResourceTypeId = r.ResourceTypeId
    WHERE r.LastUpdatedAt IS NULL
    ORDER BY r.ResourceInventoryId;

    /* DUPLICATE from the committed import (dismissed). */
    INSERT INTO dbo.ValidationIssues (FacilityId, EntityType, EntityId, IssueCode, Severity, ObservedValue, Message, Status, DetectedAt,
                                      ResolvedBy, ResolvedAt, Resolution)
    SELECT b.FacilityId, N'ImportRow', r.ImportRowId, N'DUPLICATE', N'Low', r.RawData, N'Duplicate row in import ' + b.BatchNo + N'.',
           N'Dismissed', b.SubmittedAt, b.CommittedBy, b.CommittedAt, N'Duplicate row ignored during commit.'
    FROM dbo.ImportRows r
    INNER JOIN dbo.ImportBatches b ON b.BatchId = r.BatchId
    WHERE r.ValidationStatus = N'Duplicate' AND b.Status = N'Committed';
END
GO

/*---------------------------------------------------------------------
  Availability snapshots: one per reported inventory row per day for the
  last 14 days (charts/trends). Day 0 = the current value.
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.AvailabilitySnapshots)
BEGIN
    DECLARE @Days TABLE (D INT PRIMARY KEY);
    INSERT INTO @Days (D) VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13);

    INSERT INTO dbo.AvailabilitySnapshots (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, ResourceTypeId, Quantity,
                                           AvailableQuantity, TotalQuantity, OperationalStatus, SourceType, VerificationStatus, RecordedAt,
                                           ValidUntil, ChangeId, RecordedBy)
    SELECT b.FacilityId, N'Blood', b.InventoryId, b.ComponentId, b.AboGroup, b.RhFactor, NULL,
           CASE WHEN d.D = 0 THEN b.Quantity
                ELSE CAST(ROUND(b.Quantity * (0.65 + (ABS(CAST(CHECKSUM(CONCAT(N'sb-', b.InventoryId, N'-', d.D)) AS BIGINT)) % 70) / 100.0)
                                + CASE WHEN b.Quantity = 0 AND d.D % 4 = 0 THEN 2 ELSE 0 END, 0) AS DECIMAL(12, 2)) END,
           NULL, NULL, NULL, b.SourceType, N'Confirmed',
           DATEADD(DAY, -d.D, b.LastUpdatedAt), DATEADD(MINUTE, 360, DATEADD(DAY, -d.D, b.LastUpdatedAt)), NULL, ISNULL(b.LastUpdatedBy, 1)
    FROM dbo.BloodInventory b
    CROSS JOIN @Days d
    WHERE b.LastUpdatedAt IS NOT NULL;

    INSERT INTO dbo.AvailabilitySnapshots (FacilityId, InventoryKind, InventoryId, ComponentId, AboGroup, RhFactor, ResourceTypeId, Quantity,
                                           AvailableQuantity, TotalQuantity, OperationalStatus, SourceType, VerificationStatus, RecordedAt,
                                           ValidUntil, ChangeId, RecordedBy)
    SELECT x.FacilityId, N'Resource', x.ResourceInventoryId, NULL, NULL, NULL, x.ResourceTypeId, NULL,
           x.Avail, x.TotalQuantity,
           CASE WHEN x.Avail = 0 THEN N'Unavailable' WHEN x.Avail * 4 < x.TotalQuantity THEN N'Limited' ELSE N'Available' END,
           x.SourceType, N'Confirmed', x.RecordedAt, DATEADD(MINUTE, 240, x.RecordedAt), NULL, x.RecordedBy
    FROM (SELECT r.FacilityId, r.ResourceInventoryId, r.ResourceTypeId, r.TotalQuantity, r.SourceType,
                 DATEADD(DAY, -d.D, r.LastUpdatedAt) AS RecordedAt, ISNULL(r.LastUpdatedBy, 1) AS RecordedBy,
                 CASE WHEN d.D = 0 THEN r.AvailableQuantity
                      ELSE FLOOR(r.TotalQuantity * (ABS(CAST(CHECKSUM(CONCAT(N'sr-', r.ResourceInventoryId, N'-', d.D)) AS BIGINT)) % 90) / 100.0) END AS Avail
          FROM dbo.MedicalResourceInventory r
          CROSS JOIN @Days d
          WHERE r.LastUpdatedAt IS NOT NULL) x;

    /* Link the current-value snapshot to the applied change that produced it. */
    UPDATE s SET ChangeId = ic.ChangeId
    FROM dbo.AvailabilitySnapshots s
    INNER JOIN dbo.InventoryChanges ic ON ic.InventoryKind = s.InventoryKind AND ic.InventoryId = s.InventoryId
                                       AND ic.SubmittedAt = s.RecordedAt AND ic.Status = N'Applied';
END
GO

/*---------------------------------------------------------------------
  Notifications (several per user, mixed read/unread).
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.Notifications)
BEGIN
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    /* Requester: submission confirmation + latest status update. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT br.RequesterUserId, N'Blood request submitted',
           N'Your request ' + br.RequestNo + N' has been submitted. Coordinators in your area have been notified.',
           N'Success', N'BloodRequest', CAST(br.RequestId AS NVARCHAR(50)), N'/requests/' + CAST(br.RequestId AS NVARCHAR(20)),
           CASE WHEN br.Status = N'Submitted' THEN 0 ELSE 1 END,
           CASE WHEN br.Status = N'Submitted' THEN NULL ELSE DATEADD(MINUTE, 5, br.CreatedAt) END,
           br.CreatedAt
    FROM dbo.BloodRequests br;

    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT br.RequesterUserId, N'Request ' + br.RequestNo + N' is now ' + br.Status,
           CASE br.Status
               WHEN N'Matched'        THEN N'A verified facility (' + ISNULL(f.Name, N'-') + N') reports matching stock. Please call to reconfirm.'
               WHEN N'Contacted'      THEN N'The coordinator has contacted ' + ISNULL(f.Name, N'the facility') + N'. Please proceed to collect.'
               WHEN N'Fulfilled'      THEN N'Your request has been fulfilled. Thank you for using SBMRAS.'
               WHEN N'UnableToFulfil' THEN N'We could not find matching stock: ' + ISNULL(br.StatusReason, N'')
               WHEN N'Closed'         THEN N'Your request has been closed.'
               WHEN N'Cancelled'      THEN N'Your request has been cancelled.'
               ELSE N'Your request is being reviewed by a coordinator.' END,
           CASE br.Status WHEN N'Fulfilled' THEN N'Success' WHEN N'Closed' THEN N'Success' WHEN N'UnableToFulfil' THEN N'Warning'
                          WHEN N'Matched' THEN N'Action' ELSE N'Info' END,
           N'BloodRequest', CAST(br.RequestId AS NVARCHAR(50)), N'/requests/' + CAST(br.RequestId AS NVARCHAR(20)),
           CASE WHEN br.UpdatedAt < DATEADD(DAY, -3, @Now) THEN 1 ELSE 0 END,
           CASE WHEN br.UpdatedAt < DATEADD(DAY, -3, @Now) THEN DATEADD(MINUTE, 20, br.UpdatedAt) END,
           br.UpdatedAt
    FROM dbo.BloodRequests br
    LEFT JOIN dbo.Facilities f ON f.FacilityId = br.MatchedFacilityId
    WHERE br.Status <> N'Submitted';

    /* Coordinators: new open requests in their area (facility users) and for admins. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT DISTINCT x.UserId, N'New ' + LOWER(br.Urgency) + N' blood request ' + br.RequestNo,
           br.AboGroup + CASE br.RhFactor WHEN N'Positive' THEN N'+' ELSE N'-' END + N' ' + c.Code + N' x '
               + CAST(CAST(br.QuantityRequested AS INT) AS NVARCHAR(10)) + N' needed at ' + br.HospitalName + N'.',
           N'Action', N'BloodRequest', CAST(br.RequestId AS NVARCHAR(50)), N'/coordination/' + CAST(br.RequestId AS NVARCHAR(20)),
           0, NULL, DATEADD(MINUTE, 1, br.CreatedAt)
    FROM dbo.BloodRequests br
    INNER JOIN dbo.BloodComponents c ON c.ComponentId = br.ComponentId
    CROSS APPLY (
        SELECT fa.UserId FROM dbo.FacilityUserAssignments fa
        INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId
        WHERE fa.IsActive = 1 AND f.AreaId = br.AreaId
        UNION SELECT 1 UNION SELECT 2
    ) x
    WHERE br.Status IN (N'Submitted', N'UnderReview');

    /* Verifiers/managers + admins: changes awaiting review. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT DISTINCT x.UserId, N'Change ' + ic.ChangeNo + N' needs verification',
           N'A ' + LOWER(ic.InventoryKind) + N' update at ' + f.Name + N' was flagged LARGE_JUMP and is held for review.',
           N'Action', N'InventoryChange', CAST(ic.ChangeId AS NVARCHAR(50)), N'/verifications', 0, NULL, DATEADD(MINUTE, 1, ic.SubmittedAt)
    FROM dbo.InventoryChanges ic
    INNER JOIN dbo.Facilities f ON f.FacilityId = ic.FacilityId
    CROSS APPLY (
        SELECT fa.UserId FROM dbo.FacilityUserAssignments fa
        WHERE fa.FacilityId = ic.FacilityId AND fa.IsActive = 1 AND fa.AssignmentRole IN (N'Verifier', N'Manager') AND fa.UserId <> ic.SubmittedBy
        UNION SELECT 1 UNION SELECT 2
    ) x
    WHERE ic.Status = N'PendingReview';

    /* Submitter of the rejected change. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT ic.SubmittedBy, N'Change ' + ic.ChangeNo + N' was rejected', N'Reason: ' + ISNULL(ic.DecisionReason, N'-'),
           N'Warning', N'InventoryChange', CAST(ic.ChangeId AS NVARCHAR(50)), N'/verifications', 1, DATEADD(HOUR, 2, ic.DecidedAt), ic.DecidedAt
    FROM dbo.InventoryChanges ic WHERE ic.Status = N'Rejected';

    /* Admins: facilities pending verification. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT u.UserId, N'Facility awaiting verification', f.Name + N' (' + f.FacilityCode + N') registered and is pending verification.',
           N'Action', N'Facility', CAST(f.FacilityId AS NVARCHAR(50)), N'/admin/facilities', CASE WHEN u.UserId = 2 THEN 1 ELSE 0 END,
           CASE WHEN u.UserId = 2 THEN DATEADD(DAY, -1, @Now) END, DATEADD(DAY, -2, @Now)
    FROM dbo.Facilities f CROSS JOIN (VALUES (1), (2)) AS u (UserId)
    WHERE f.VerificationStatus = N'Pending';

    /* Facility users: imports and stale stock. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT b.SubmittedBy,
           CASE b.Status WHEN N'Committed' THEN N'Import ' + b.BatchNo + N' committed' ELSE N'Import ' + b.BatchNo + N' validated' END,
           CASE b.Status WHEN N'Committed' THEN CAST(b.AppliedRows AS NVARCHAR(10)) + N' rows applied, ' + CAST(b.InvalidRows AS NVARCHAR(10)) + N' invalid, '
                                              + CAST(b.DuplicateRows AS NVARCHAR(10)) + N' duplicate.'
                ELSE CAST(b.ValidRows AS NVARCHAR(10)) + N' valid rows ready to commit; ' + CAST(b.InvalidRows AS NVARCHAR(10)) + N' invalid.' END,
           CASE b.Status WHEN N'Committed' THEN N'Success' ELSE N'Info' END,
           N'ImportBatch', CAST(b.BatchId AS NVARCHAR(50)), N'/imports/' + CAST(b.BatchId AS NVARCHAR(20)),
           CASE b.Status WHEN N'Committed' THEN 1 ELSE 0 END, CASE b.Status WHEN N'Committed' THEN b.CommittedAt END,
           ISNULL(b.CommittedAt, b.SubmittedAt)
    FROM dbo.ImportBatches b;

    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT fa.UserId, N'Stale stock at ' + f.Name,
           CAST(COUNT(*) AS NVARCHAR(10)) + N' inventory records are past their validity window. Please re-confirm current values.',
           N'Warning', N'Facility', CAST(f.FacilityId AS NVARCHAR(50)),
           CASE WHEN f.FacilityType = N'BloodBank' THEN N'/blood-stock?facilityId=' ELSE N'/resource-inventory?facilityId=' END + CAST(f.FacilityId AS NVARCHAR(20)),
           0, NULL, DATEADD(MINUTE, -20, @Now)
    FROM dbo.FacilityUserAssignments fa
    INNER JOIN dbo.Facilities f ON f.FacilityId = fa.FacilityId
    INNER JOIN (SELECT FacilityId, ValidUntil FROM dbo.BloodInventory
                UNION ALL SELECT FacilityId, ValidUntil FROM dbo.MedicalResourceInventory) inv ON inv.FacilityId = f.FacilityId
    WHERE inv.ValidUntil < @Now
    GROUP BY fa.UserId, f.FacilityId, f.Name, f.FacilityType;

    /* Welcome message for everyone. */
    INSERT INTO dbo.Notifications (UserId, Title, Message, Type, EntityType, EntityId, Route, IsRead, ReadAt, CreatedAt)
    SELECT u.UserId, N'Welcome to SBMRAS',
           N'SBMRAS shows reported availability. Always reconfirm with the facility before travelling.',
           N'Info', NULL, NULL, N'/dashboard', 1, DATEADD(HOUR, 1, u.CreatedAt), u.CreatedAt
    FROM dbo.Users u WHERE u.UserId BETWEEN 1 AND 10;
END
GO

/*---------------------------------------------------------------------
  Audit logs (~60) derived from the seeded business rows.
---------------------------------------------------------------------*/
IF NOT EXISTS (SELECT 1 FROM dbo.AuditLogs WHERE CorrelationId LIKE N'seed-%')
BEGIN
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @A TABLE (EntityType NVARCHAR(50), EntityId NVARCHAR(50), ReferenceNo NVARCHAR(50), FacilityId INT, Action NVARCHAR(50),
                      Description NVARCHAR(500), OldValues NVARCHAR(MAX), NewValues NVARCHAR(MAX), SourceType NVARCHAR(20),
                      Reason NVARCHAR(500), UserId INT, CreatedAt DATETIME2(0));

    /* Facility registrations and verifications. */
    INSERT INTO @A
    SELECT N'Facility', CAST(f.FacilityId AS NVARCHAR(50)), f.FacilityCode, f.FacilityId, N'Create', N'Facility ' + f.Name + N' registered.',
           NULL, N'{"verificationStatus":"Pending"}', NULL, NULL, 1, f.CreatedAt
    FROM dbo.Facilities f WHERE f.VerificationStatus = N'Pending';

    INSERT INTO @A
    SELECT N'Facility', CAST(f.FacilityId AS NVARCHAR(50)), f.FacilityCode, f.FacilityId,
           CASE f.VerificationStatus WHEN N'Suspended' THEN N'Suspend' ELSE N'Verify' END,
           N'Facility ' + f.Name + N' ' + LOWER(f.VerificationStatus) + N'.',
           N'{"verificationStatus":"Pending"}', N'{"verificationStatus":"' + f.VerificationStatus + N'"}', NULL, f.VerificationNotes, 1,
           CASE f.VerificationStatus WHEN N'Suspended' THEN DATEADD(DAY, -10, @Now) ELSE f.VerifiedAt END
    FROM dbo.Facilities f WHERE f.VerificationStatus IN (N'Verified', N'Suspended');

    /* Requests: creation + latest transition. */
    INSERT INTO @A
    SELECT N'BloodRequest', CAST(br.RequestId AS NVARCHAR(50)), br.RequestNo, NULL, N'Create',
           N'Blood request ' + br.RequestNo + N' submitted.', NULL, N'{"status":"Submitted"}', N'ManualPortal', NULL, br.RequesterUserId, br.CreatedAt
    FROM dbo.BloodRequests br;

    INSERT INTO @A
    SELECT N'BloodRequest', CAST(h.RequestId AS NVARCHAR(50)), br.RequestNo, h.FacilityId,
           CASE h.ToStatus WHEN N'Cancelled' THEN N'Cancel' ELSE N'StatusChange' END,
           N'Request ' + br.RequestNo + N' moved from ' + h.FromStatus + N' to ' + h.ToStatus + N'.',
           N'{"status":"' + h.FromStatus + N'"}', N'{"status":"' + h.ToStatus + N'"}', NULL, h.Note, h.ChangedBy, h.ChangedAt
    FROM dbo.BloodRequestHistory h
    INNER JOIN dbo.BloodRequests br ON br.RequestId = h.RequestId
    WHERE h.FromStatus IS NOT NULL
      AND h.HistoryId = (SELECT MAX(x.HistoryId) FROM dbo.BloodRequestHistory x WHERE x.RequestId = h.RequestId);

    /* Inventory changes. */
    INSERT INTO @A
    SELECT CASE ic.InventoryKind WHEN N'Blood' THEN N'BloodInventory' ELSE N'ResourceInventory' END,
           CAST(ic.InventoryId AS NVARCHAR(50)), ic.ChangeNo, ic.FacilityId,
           CASE ic.Status WHEN N'Applied' THEN N'Update' WHEN N'PendingReview' THEN N'SubmitForReview' ELSE N'Submit' END,
           CASE ic.Status WHEN N'Applied' THEN N'Inventory updated via ' + ic.ChangeNo + N'.'
                          ELSE N'Inventory change ' + ic.ChangeNo + N' flagged ' + ISNULL(ic.AnomalyFlags, N'') + N' and held for review.' END,
           ic.BeforeJson, ic.AfterJson, ic.SourceType, ic.Reason, ic.SubmittedBy, ic.SubmittedAt
    FROM (SELECT x.*, ROW_NUMBER() OVER (PARTITION BY x.FacilityId, x.Status ORDER BY x.SubmittedAt DESC) AS Rn
          FROM dbo.InventoryChanges x) ic
    WHERE ic.Status <> N'Applied' OR ic.Rn = 1;

    INSERT INTO @A
    SELECT N'InventoryChange', CAST(ic.ChangeId AS NVARCHAR(50)), ic.ChangeNo, ic.FacilityId, N'Reject',
           N'Inventory change ' + ic.ChangeNo + N' rejected.', ic.AfterJson, ic.BeforeJson, ic.SourceType, ic.DecisionReason, ic.DecidedBy, ic.DecidedAt
    FROM dbo.InventoryChanges ic WHERE ic.Status = N'Rejected';

    /* Imports. */
    INSERT INTO @A
    SELECT N'ImportBatch', CAST(b.BatchId AS NVARCHAR(50)), b.BatchNo, b.FacilityId, N'Stage',
           N'Import ' + b.BatchNo + N' staged (' + CAST(b.TotalRows AS NVARCHAR(10)) + N' rows).', NULL, NULL, N'CSVImport', NULL, b.SubmittedBy, b.SubmittedAt
    FROM dbo.ImportBatches b;

    INSERT INTO @A
    SELECT N'ImportBatch', CAST(b.BatchId AS NVARCHAR(50)), b.BatchNo, b.FacilityId, N'Commit',
           N'Import ' + b.BatchNo + N' committed (' + CAST(b.AppliedRows AS NVARCHAR(10)) + N' rows applied).', NULL, NULL, N'CSVImport', NULL,
           b.CommittedBy, b.CommittedAt
    FROM dbo.ImportBatches b WHERE b.Status = N'Committed';

    /* Administration. */
    INSERT INTO @A VALUES
        (N'User', N'3', NULL, NULL, N'AssignFacilities', N'Facility assignments updated for Dr. Karthik Menon.', NULL, N'[{"facility":"HSP-0001","role":"Manager"},{"facility":"HSP-0002","role":"Manager"}]', NULL, NULL, 1, DATEADD(DAY, -40, @Now)),
        (N'User', N'6', NULL, NULL, N'AssignFacilities', N'Facility assignments updated for Sana Fatima.', NULL, N'[{"facility":"BBK-0001","role":"Verifier"},{"facility":"BBK-0003","role":"Operator"}]', NULL, NULL, 1, DATEADD(DAY, -40, @Now)),
        (N'SystemSetting', N'BLOOD_STOCK_TTL_MINUTES', NULL, NULL, N'Update', N'Setting BLOOD_STOCK_TTL_MINUTES reviewed.', N'{"value":"360"}', N'{"value":"360"}', NULL, N'Quarterly review.', 2, DATEADD(DAY, -20, @Now)),
        (N'User', N'1', NULL, NULL, N'Login', N'Dr. Ananya Rao signed in.', NULL, NULL, NULL, NULL, 1, DATEADD(MINUTE, -37, @Now)),
        (N'User', N'5', NULL, NULL, N'Login', N'Ravi Teja Kumar signed in.', NULL, NULL, NULL, NULL, 5, DATEADD(MINUTE, -185, @Now));

    INSERT INTO dbo.AuditLogs (EntityType, EntityId, ReferenceNo, FacilityId, Action, Description, OldValues, NewValues, SourceType, Reason,
                               CorrelationId, UserId, ActorRole, CreatedAt)
    SELECT a.EntityType, a.EntityId, a.ReferenceNo, a.FacilityId, a.Action, a.Description, a.OldValues, a.NewValues, a.SourceType, a.Reason,
           N'seed-' + RIGHT(N'0000' + CAST(ROW_NUMBER() OVER (ORDER BY a.CreatedAt, a.EntityType, a.EntityId) AS NVARCHAR(10)), 4),
           a.UserId,
           CASE WHEN a.UserId IN (1, 2) THEN N'Admin' WHEN a.UserId IN (3, 4) THEN N'HospitalManagement'
                WHEN a.UserId IN (5, 6) THEN N'BloodBank' ELSE N'PublicUser' END,
           a.CreatedAt
    FROM @A a
    ORDER BY a.CreatedAt;
END
GO

/*---------------------------------------------------------------------
  Reference sequences: never lower than the highest number in use.
---------------------------------------------------------------------*/
;WITH Used AS (
    SELECT LEFT(RequestNo, 3) AS Prefix, CAST(SUBSTRING(RequestNo, 5, 4) AS INT) AS [Year], CAST(RIGHT(RequestNo, 4) AS INT) AS N
    FROM dbo.BloodRequests WHERE RequestNo LIKE N'BRQ-[0-9][0-9][0-9][0-9]-%'
    UNION ALL
    SELECT LEFT(ChangeNo, 3), CAST(SUBSTRING(ChangeNo, 5, 4) AS INT), CAST(RIGHT(ChangeNo, 4) AS INT)
    FROM dbo.InventoryChanges WHERE ChangeNo LIKE N'CHG-[0-9][0-9][0-9][0-9]-%'
    UNION ALL
    SELECT LEFT(BatchNo, 3), CAST(SUBSTRING(BatchNo, 5, 4) AS INT), CAST(RIGHT(BatchNo, 4) AS INT)
    FROM dbo.ImportBatches WHERE BatchNo LIKE N'IMP-[0-9][0-9][0-9][0-9]-%'

), MaxUsed AS (
    SELECT Prefix, [Year], MAX(N) AS LastNumber FROM Used GROUP BY Prefix, [Year]
)
MERGE dbo.ReferenceSequences AS t
USING MaxUsed AS s ON t.Prefix = s.Prefix AND t.[Year] = s.[Year]
WHEN MATCHED AND t.LastNumber < s.LastNumber THEN UPDATE SET LastNumber = s.LastNumber
WHEN NOT MATCHED THEN INSERT (Prefix, [Year], LastNumber) VALUES (s.Prefix, s.[Year], s.LastNumber);
GO

PRINT N'SBMRAS seed data applied.';
GO
