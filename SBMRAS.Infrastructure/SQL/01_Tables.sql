/*=====================================================================
  SBMRAS - 01_Tables.sql
  Smart Blood and Medical Resource Availability System - schema.
  Idempotent: every object is created only when missing.
  All timestamps are UTC (DATETIME2(0), SYSUTCDATETIME()). Quantities are DECIMAL(12,2).
=====================================================================*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/*---------------------------------------------------------------------
  Security: roles, permissions, areas, users
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.Roles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Roles
    (
        RoleId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,
        RoleCode        NVARCHAR(50)  NOT NULL CONSTRAINT UQ_Roles_RoleCode UNIQUE,
        RoleName        NVARCHAR(100) NOT NULL,
        Description     NVARCHAR(400) NULL,
        EntraAppRole    NVARCHAR(100) NULL,
        EntraGroupName  NVARCHAR(150) NULL,
        IsSystem        BIT           NOT NULL CONSTRAINT DF_Roles_IsSystem DEFAULT (0),
        IsActive        BIT           NOT NULL CONSTRAINT DF_Roles_IsActive DEFAULT (1),
        CreatedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_Roles_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF OBJECT_ID(N'dbo.Permissions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Permissions
    (
        PermissionId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Permissions PRIMARY KEY,
        PermissionCode NVARCHAR(60)  NOT NULL CONSTRAINT UQ_Permissions_PermissionCode UNIQUE,
        PermissionName NVARCHAR(150) NOT NULL,
        Module         NVARCHAR(60)  NOT NULL,
        Description    NVARCHAR(400) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.RolePermissions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RolePermissions
    (
        RoleId       INT NOT NULL CONSTRAINT FK_RolePermissions_Roles REFERENCES dbo.Roles (RoleId),
        PermissionId INT NOT NULL CONSTRAINT FK_RolePermissions_Permissions REFERENCES dbo.Permissions (PermissionId),
        CONSTRAINT PK_RolePermissions PRIMARY KEY (RoleId, PermissionId)
    );
END
GO

IF OBJECT_ID(N'dbo.Areas', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Areas
    (
        AreaId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Areas PRIMARY KEY,
        Name     NVARCHAR(100) NOT NULL CONSTRAINT UQ_Areas_Name UNIQUE,
        City     NVARCHAR(100) NOT NULL,
        State    NVARCHAR(100) NOT NULL,
        Pincode  NVARCHAR(10)  NULL,
        IsActive BIT           NOT NULL CONSTRAINT DF_Areas_IsActive DEFAULT (1)
    );
END
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users
    (
        UserId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
        DisplayName      NVARCHAR(150)    NOT NULL,
        GivenName        NVARCHAR(100)    NULL,
        FamilyName       NVARCHAR(100)    NULL,
        Email            NVARCHAR(320)    NULL,
        Phone            NVARCHAR(30)     NULL,
        OrganizationName NVARCHAR(200)    NULL,
        AreaId           INT              NULL CONSTRAINT FK_Users_Areas REFERENCES dbo.Areas (AreaId),
        EntraTenantId    UNIQUEIDENTIFIER NULL,
        EntraObjectId    UNIQUEIDENTIFIER NULL,
        IsSelfRegistered BIT              NOT NULL CONSTRAINT DF_Users_IsSelfRegistered DEFAULT (0),
        IsActive         BIT              NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
        LastLoginAt      DATETIME2(0)     NULL,
        CreatedAt        DATETIME2(0)     NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy        INT              NULL CONSTRAINT FK_Users_CreatedBy REFERENCES dbo.Users (UserId),
        UpdatedAt        DATETIME2(0)     NULL,
        UpdatedBy        INT              NULL CONSTRAINT FK_Users_UpdatedBy REFERENCES dbo.Users (UserId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Users_Email' AND object_id = OBJECT_ID(N'dbo.Users'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_Users_Email ON dbo.Users (Email) WHERE Email IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Users_Entra' AND object_id = OBJECT_ID(N'dbo.Users'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_Users_Entra ON dbo.Users (EntraTenantId, EntraObjectId)
        WHERE EntraTenantId IS NOT NULL AND EntraObjectId IS NOT NULL;
GO

IF OBJECT_ID(N'dbo.UserRoles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserRoles
    (
        UserId     INT           NOT NULL CONSTRAINT FK_UserRoles_Users REFERENCES dbo.Users (UserId),
        RoleId     INT           NOT NULL CONSTRAINT FK_UserRoles_Roles REFERENCES dbo.Roles (RoleId),
        Source     NVARCHAR(10)  NOT NULL CONSTRAINT DF_UserRoles_Source DEFAULT (N'Local')
                                 CONSTRAINT CK_UserRoles_Source CHECK (Source IN (N'Local', N'Entra')),
        AssignedAt DATETIME2(0)  NOT NULL CONSTRAINT DF_UserRoles_AssignedAt DEFAULT (SYSUTCDATETIME()),
        AssignedBy INT           NULL CONSTRAINT FK_UserRoles_AssignedBy REFERENCES dbo.Users (UserId),
        CONSTRAINT PK_UserRoles PRIMARY KEY (UserId, RoleId)
    );
END
GO

/*---------------------------------------------------------------------
  Menu
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.MenuItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuItems
    (
        MenuItemId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MenuItems PRIMARY KEY,
        Code         NVARCHAR(60)  NOT NULL CONSTRAINT UQ_MenuItems_Code UNIQUE,
        Section      NVARCHAR(60)  NOT NULL,
        SectionOrder INT           NOT NULL CONSTRAINT DF_MenuItems_SectionOrder DEFAULT (0),
        Label        NVARCHAR(100) NOT NULL,
        Icon         NVARCHAR(60)  NULL,
        Route        NVARCHAR(200) NOT NULL,
        SortOrder    INT           NOT NULL CONSTRAINT DF_MenuItems_SortOrder DEFAULT (0),
        IsActive     BIT           NOT NULL CONSTRAINT DF_MenuItems_IsActive DEFAULT (1)
    );
END
GO

IF OBJECT_ID(N'dbo.MenuPermissions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuPermissions
    (
        MenuItemId   INT NOT NULL CONSTRAINT FK_MenuPermissions_MenuItems REFERENCES dbo.MenuItems (MenuItemId),
        PermissionId INT NOT NULL CONSTRAINT FK_MenuPermissions_Permissions REFERENCES dbo.Permissions (PermissionId),
        CONSTRAINT PK_MenuPermissions PRIMARY KEY (MenuItemId, PermissionId)
    );
END
GO

/*---------------------------------------------------------------------
  Master data
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.Units', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Units
    (
        UnitId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Units PRIMARY KEY,
        Code     NVARCHAR(20)  NOT NULL CONSTRAINT UQ_Units_Code UNIQUE,
        Name     NVARCHAR(100) NOT NULL,
        IsActive BIT           NOT NULL CONSTRAINT DF_Units_IsActive DEFAULT (1)
    );
END
GO

IF OBJECT_ID(N'dbo.BloodComponents', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BloodComponents
    (
        ComponentId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BloodComponents PRIMARY KEY,
        Code          NVARCHAR(20)  NOT NULL CONSTRAINT UQ_BloodComponents_Code UNIQUE,
        Name          NVARCHAR(100) NOT NULL,
        ShelfLifeDays INT           NOT NULL CONSTRAINT CK_BloodComponents_ShelfLifeDays CHECK (ShelfLifeDays > 0),
        StorageNote   NVARCHAR(400) NULL,
        IsActive      BIT           NOT NULL CONSTRAINT DF_BloodComponents_IsActive DEFAULT (1)
    );
END
GO

IF OBJECT_ID(N'dbo.ResourceCategories', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ResourceCategories
    (
        CategoryId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ResourceCategories PRIMARY KEY,
        Name        NVARCHAR(100) NOT NULL CONSTRAINT UQ_ResourceCategories_Name UNIQUE,
        Description NVARCHAR(400) NULL,
        IsActive    BIT           NOT NULL CONSTRAINT DF_ResourceCategories_IsActive DEFAULT (1)
    );
END
GO

IF OBJECT_ID(N'dbo.MedicalResourceTypes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MedicalResourceTypes
    (
        ResourceTypeId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MedicalResourceTypes PRIMARY KEY,
        CategoryId     INT           NOT NULL CONSTRAINT FK_MedicalResourceTypes_Categories REFERENCES dbo.ResourceCategories (CategoryId),
        Code           NVARCHAR(30)  NOT NULL CONSTRAINT UQ_MedicalResourceTypes_Code UNIQUE,
        Name           NVARCHAR(100) NOT NULL,
        DefaultUnitId  INT           NOT NULL CONSTRAINT FK_MedicalResourceTypes_Units REFERENCES dbo.Units (UnitId),
        TrackingMode   NVARCHAR(20)  NOT NULL CONSTRAINT DF_MedicalResourceTypes_TrackingMode DEFAULT (N'Count')
                                     CONSTRAINT CK_MedicalResourceTypes_TrackingMode CHECK (TrackingMode IN (N'Count', N'Status', N'Capacity')),
        IsActive       BIT           NOT NULL CONSTRAINT DF_MedicalResourceTypes_IsActive DEFAULT (1)
    );
END
GO

/*---------------------------------------------------------------------
  Facilities
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.Facilities', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Facilities
    (
        FacilityId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Facilities PRIMARY KEY,
        FacilityCode       NVARCHAR(20)   NOT NULL CONSTRAINT UQ_Facilities_FacilityCode UNIQUE,
        Name               NVARCHAR(200)  NOT NULL,
        FacilityType       NVARCHAR(20)   NOT NULL CONSTRAINT CK_Facilities_FacilityType CHECK (FacilityType IN (N'Hospital', N'BloodBank')),
        LicenseNo          NVARCHAR(60)   NULL,
        AddressLine        NVARCHAR(300)  NOT NULL,
        AreaId             INT            NOT NULL CONSTRAINT FK_Facilities_Areas REFERENCES dbo.Areas (AreaId),
        City               NVARCHAR(100)  NOT NULL,
        Pincode            NVARCHAR(10)   NULL,
        Latitude           DECIMAL(9,6)   NULL CONSTRAINT CK_Facilities_Latitude CHECK (Latitude BETWEEN -90 AND 90),
        Longitude          DECIMAL(9,6)   NULL CONSTRAINT CK_Facilities_Longitude CHECK (Longitude BETWEEN -180 AND 180),
        ContactPhone       NVARCHAR(30)   NOT NULL,
        ContactEmail       NVARCHAR(320)  NULL,
        Is24x7             BIT            NOT NULL CONSTRAINT DF_Facilities_Is24x7 DEFAULT (0),
        VerificationStatus NVARCHAR(20)   NOT NULL CONSTRAINT DF_Facilities_VerificationStatus DEFAULT (N'Pending')
                                          CONSTRAINT CK_Facilities_VerificationStatus CHECK (VerificationStatus IN (N'Pending', N'Verified', N'Rejected', N'Suspended')),
        VerifiedAt         DATETIME2(0)   NULL,
        VerifiedBy         INT            NULL CONSTRAINT FK_Facilities_VerifiedBy REFERENCES dbo.Users (UserId),
        VerificationNotes  NVARCHAR(500)  NULL,
        IsActive           BIT            NOT NULL CONSTRAINT DF_Facilities_IsActive DEFAULT (1),
        RowVer             ROWVERSION     NOT NULL,
        CreatedAt          DATETIME2(0)   NOT NULL CONSTRAINT DF_Facilities_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy          INT            NULL CONSTRAINT FK_Facilities_CreatedBy REFERENCES dbo.Users (UserId),
        UpdatedAt          DATETIME2(0)   NULL,
        UpdatedBy          INT            NULL CONSTRAINT FK_Facilities_UpdatedBy REFERENCES dbo.Users (UserId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Facilities_Area_Type' AND object_id = OBJECT_ID(N'dbo.Facilities'))
    CREATE NONCLUSTERED INDEX IX_Facilities_Area_Type ON dbo.Facilities (AreaId, FacilityType)
        INCLUDE (Name, VerificationStatus, IsActive);
GO

IF OBJECT_ID(N'dbo.FacilityUserAssignments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FacilityUserAssignments
    (
        AssignmentId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FacilityUserAssignments PRIMARY KEY,
        FacilityId     INT          NOT NULL CONSTRAINT FK_FacilityUserAssignments_Facilities REFERENCES dbo.Facilities (FacilityId),
        UserId         INT          NOT NULL CONSTRAINT FK_FacilityUserAssignments_Users REFERENCES dbo.Users (UserId),
        AssignmentRole NVARCHAR(20) NOT NULL CONSTRAINT DF_FacilityUserAssignments_Role DEFAULT (N'Operator')
                                    CONSTRAINT CK_FacilityUserAssignments_Role CHECK (AssignmentRole IN (N'Manager', N'Operator', N'Verifier')),
        IsActive       BIT          NOT NULL CONSTRAINT DF_FacilityUserAssignments_IsActive DEFAULT (1),
        AssignedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_FacilityUserAssignments_AssignedAt DEFAULT (SYSUTCDATETIME()),
        AssignedBy     INT          NULL CONSTRAINT FK_FacilityUserAssignments_AssignedBy REFERENCES dbo.Users (UserId),
        EndedAt        DATETIME2(0) NULL,
        CONSTRAINT UQ_FacilityUserAssignments_Facility_User UNIQUE (FacilityId, UserId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FacilityUserAssignments_User' AND object_id = OBJECT_ID(N'dbo.FacilityUserAssignments'))
    CREATE NONCLUSTERED INDEX IX_FacilityUserAssignments_User ON dbo.FacilityUserAssignments (UserId, IsActive)
        INCLUDE (FacilityId, AssignmentRole);
GO

/*---------------------------------------------------------------------
  Inventory
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.BloodInventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BloodInventory
    (
        InventoryId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BloodInventory PRIMARY KEY,
        FacilityId         INT           NOT NULL CONSTRAINT FK_BloodInventory_Facilities REFERENCES dbo.Facilities (FacilityId),
        ComponentId        INT           NOT NULL CONSTRAINT FK_BloodInventory_Components REFERENCES dbo.BloodComponents (ComponentId),
        AboGroup           NVARCHAR(2)   NOT NULL CONSTRAINT CK_BloodInventory_AboGroup CHECK (AboGroup IN (N'A', N'B', N'AB', N'O')),
        RhFactor           NVARCHAR(10)  NOT NULL CONSTRAINT CK_BloodInventory_RhFactor CHECK (RhFactor IN (N'Positive', N'Negative')),
        Quantity           DECIMAL(12,2) NOT NULL CONSTRAINT DF_BloodInventory_Quantity DEFAULT (0)
                                         CONSTRAINT CK_BloodInventory_Quantity CHECK (Quantity >= 0),
        UnitId             INT           NOT NULL CONSTRAINT FK_BloodInventory_Units REFERENCES dbo.Units (UnitId),
        EarliestExpiryDate DATE          NULL,
        SourceType         NVARCHAR(20)  NOT NULL CONSTRAINT DF_BloodInventory_SourceType DEFAULT (N'ManualPortal')
                                         CONSTRAINT CK_BloodInventory_SourceType CHECK (SourceType IN (N'ManualPortal', N'CSVImport', N'PartnerAPI', N'AdminCorrection')),
        VerificationStatus NVARCHAR(20)  NOT NULL CONSTRAINT DF_BloodInventory_VerificationStatus DEFAULT (N'Unverified')
                                         CONSTRAINT CK_BloodInventory_VerificationStatus CHECK (VerificationStatus IN (N'Confirmed', N'PendingReview', N'Unverified')),
        LastUpdatedAt      DATETIME2(0)  NULL,
        LastUpdatedBy      INT           NULL CONSTRAINT FK_BloodInventory_LastUpdatedBy REFERENCES dbo.Users (UserId),
        ValidUntil         DATETIME2(0)  NULL,
        RowVer             ROWVERSION    NOT NULL,
        CreatedAt          DATETIME2(0)  NOT NULL CONSTRAINT DF_BloodInventory_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy          INT           NULL CONSTRAINT FK_BloodInventory_CreatedBy REFERENCES dbo.Users (UserId),
        UpdatedAt          DATETIME2(0)  NULL,
        UpdatedBy          INT           NULL CONSTRAINT FK_BloodInventory_UpdatedBy REFERENCES dbo.Users (UserId),
        CONSTRAINT UQ_BloodInventory_Facility_Component_Group UNIQUE (FacilityId, ComponentId, AboGroup, RhFactor)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BloodInventory_Search' AND object_id = OBJECT_ID(N'dbo.BloodInventory'))
    CREATE NONCLUSTERED INDEX IX_BloodInventory_Search ON dbo.BloodInventory (FacilityId, AboGroup, RhFactor, ComponentId)
        INCLUDE (Quantity, LastUpdatedAt, ValidUntil);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BloodInventory_Group_Component' AND object_id = OBJECT_ID(N'dbo.BloodInventory'))
    CREATE NONCLUSTERED INDEX IX_BloodInventory_Group_Component ON dbo.BloodInventory (AboGroup, RhFactor, ComponentId)
        INCLUDE (FacilityId, Quantity, LastUpdatedAt, ValidUntil, VerificationStatus);
GO

IF OBJECT_ID(N'dbo.MedicalResourceInventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MedicalResourceInventory
    (
        ResourceInventoryId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MedicalResourceInventory PRIMARY KEY,
        FacilityId          INT           NOT NULL CONSTRAINT FK_MedicalResourceInventory_Facilities REFERENCES dbo.Facilities (FacilityId),
        ResourceTypeId      INT           NOT NULL CONSTRAINT FK_MedicalResourceInventory_Types REFERENCES dbo.MedicalResourceTypes (ResourceTypeId),
        TotalQuantity       DECIMAL(12,2) NOT NULL CONSTRAINT DF_MedicalResourceInventory_Total DEFAULT (0)
                                          CONSTRAINT CK_MedicalResourceInventory_Total CHECK (TotalQuantity >= 0),
        AvailableQuantity   DECIMAL(12,2) NOT NULL CONSTRAINT DF_MedicalResourceInventory_Available DEFAULT (0)
                                          CONSTRAINT CK_MedicalResourceInventory_Available CHECK (AvailableQuantity >= 0),
        UnitId              INT           NOT NULL CONSTRAINT FK_MedicalResourceInventory_Units REFERENCES dbo.Units (UnitId),
        OperationalStatus   NVARCHAR(20)  NOT NULL CONSTRAINT DF_MedicalResourceInventory_OpStatus DEFAULT (N'Unknown')
                                          CONSTRAINT CK_MedicalResourceInventory_OpStatus CHECK (OperationalStatus IN (N'Available', N'Limited', N'Unavailable', N'Unknown')),
        Notes               NVARCHAR(500) NULL,
        SourceType          NVARCHAR(20)  NOT NULL CONSTRAINT DF_MedicalResourceInventory_SourceType DEFAULT (N'ManualPortal')
                                          CONSTRAINT CK_MedicalResourceInventory_SourceType CHECK (SourceType IN (N'ManualPortal', N'CSVImport', N'PartnerAPI', N'AdminCorrection')),
        VerificationStatus  NVARCHAR(20)  NOT NULL CONSTRAINT DF_MedicalResourceInventory_VerificationStatus DEFAULT (N'Unverified')
                                          CONSTRAINT CK_MedicalResourceInventory_VerificationStatus CHECK (VerificationStatus IN (N'Confirmed', N'PendingReview', N'Unverified')),
        LastUpdatedAt       DATETIME2(0)  NULL,
        LastUpdatedBy       INT           NULL CONSTRAINT FK_MedicalResourceInventory_LastUpdatedBy REFERENCES dbo.Users (UserId),
        ValidUntil          DATETIME2(0)  NULL,
        RowVer              ROWVERSION    NOT NULL,
        CreatedAt           DATETIME2(0)  NOT NULL CONSTRAINT DF_MedicalResourceInventory_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT           NULL CONSTRAINT FK_MedicalResourceInventory_CreatedBy REFERENCES dbo.Users (UserId),
        UpdatedAt           DATETIME2(0)  NULL,
        UpdatedBy           INT           NULL CONSTRAINT FK_MedicalResourceInventory_UpdatedBy REFERENCES dbo.Users (UserId),
        CONSTRAINT CK_MedicalResourceInventory_AvailableLeTotal CHECK (AvailableQuantity <= TotalQuantity),
        CONSTRAINT UQ_MedicalResourceInventory_Facility_Type UNIQUE (FacilityId, ResourceTypeId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MedicalResourceInventory_Type' AND object_id = OBJECT_ID(N'dbo.MedicalResourceInventory'))
    CREATE NONCLUSTERED INDEX IX_MedicalResourceInventory_Type ON dbo.MedicalResourceInventory (ResourceTypeId, FacilityId)
        INCLUDE (AvailableQuantity, TotalQuantity, OperationalStatus, LastUpdatedAt, ValidUntil);
GO

/*---------------------------------------------------------------------
  Imports (before InventoryChanges, which references ImportBatches)
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.ImportBatches', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ImportBatches
    (
        BatchId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImportBatches PRIMARY KEY,
        BatchNo        NVARCHAR(20)  NOT NULL CONSTRAINT UQ_ImportBatches_BatchNo UNIQUE,
        FacilityId     INT           NOT NULL CONSTRAINT FK_ImportBatches_Facilities REFERENCES dbo.Facilities (FacilityId),
        InventoryKind  NVARCHAR(10)  NOT NULL CONSTRAINT CK_ImportBatches_InventoryKind CHECK (InventoryKind IN (N'Blood', N'Resource')),
        FileName       NVARCHAR(260) NOT NULL,
        FileHash       NVARCHAR(64)  NOT NULL,
        TotalRows      INT           NOT NULL CONSTRAINT DF_ImportBatches_TotalRows DEFAULT (0),
        ValidRows      INT           NOT NULL CONSTRAINT DF_ImportBatches_ValidRows DEFAULT (0),
        InvalidRows    INT           NOT NULL CONSTRAINT DF_ImportBatches_InvalidRows DEFAULT (0),
        DuplicateRows  INT           NOT NULL CONSTRAINT DF_ImportBatches_DuplicateRows DEFAULT (0),
        AppliedRows    INT           NOT NULL CONSTRAINT DF_ImportBatches_AppliedRows DEFAULT (0),
        ReviewRows     INT           NOT NULL CONSTRAINT DF_ImportBatches_ReviewRows DEFAULT (0),
        Status         NVARCHAR(20)  NOT NULL CONSTRAINT DF_ImportBatches_Status DEFAULT (N'Validated')
                                     CONSTRAINT CK_ImportBatches_Status CHECK (Status IN (N'Validated', N'Committed', N'Cancelled')),
        IdempotencyKey NVARCHAR(100) NULL,
        SubmittedBy    INT           NOT NULL CONSTRAINT FK_ImportBatches_SubmittedBy REFERENCES dbo.Users (UserId),
        SubmittedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_ImportBatches_SubmittedAt DEFAULT (SYSUTCDATETIME()),
        CommittedBy    INT           NULL CONSTRAINT FK_ImportBatches_CommittedBy REFERENCES dbo.Users (UserId),
        CommittedAt    DATETIME2(0)  NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ImportBatches_Facility_FileHash' AND object_id = OBJECT_ID(N'dbo.ImportBatches'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_ImportBatches_Facility_FileHash ON dbo.ImportBatches (FacilityId, FileHash)
        WHERE Status <> N'Cancelled';
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ImportBatches_Facility_SubmittedAt' AND object_id = OBJECT_ID(N'dbo.ImportBatches'))
    CREATE NONCLUSTERED INDEX IX_ImportBatches_Facility_SubmittedAt ON dbo.ImportBatches (FacilityId, SubmittedAt DESC);
GO

IF OBJECT_ID(N'dbo.ImportRows', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ImportRows
    (
        ImportRowId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImportRows PRIMARY KEY,
        BatchId            INT            NOT NULL CONSTRAINT FK_ImportRows_ImportBatches REFERENCES dbo.ImportBatches (BatchId),
        RowNumber          INT            NOT NULL,
        RawData            NVARCHAR(1000) NOT NULL,
        ComponentCode      NVARCHAR(20)   NULL,
        AboGroup           NVARCHAR(2)    NULL,
        RhFactor           NVARCHAR(10)   NULL,
        ResourceTypeCode   NVARCHAR(30)   NULL,
        Quantity           DECIMAL(12,2)  NULL,
        TotalQuantity      DECIMAL(12,2)  NULL,
        AvailableQuantity  DECIMAL(12,2)  NULL,
        OperationalStatus  NVARCHAR(20)   NULL,
        EarliestExpiryDate DATE           NULL,
        ValidUntil         DATETIME2(0)   NULL,
        OriginalRowVersion VARBINARY(8)   NULL,
        ValidationStatus   NVARCHAR(20)   NOT NULL CONSTRAINT DF_ImportRows_ValidationStatus DEFAULT (N'Valid')
                                          CONSTRAINT CK_ImportRows_ValidationStatus CHECK (ValidationStatus IN (N'Valid', N'Invalid', N'Duplicate', N'Applied', N'Review')),
        ErrorCodes         NVARCHAR(400)  NULL,
        ErrorMessages      NVARCHAR(1000) NULL,
        CONSTRAINT UQ_ImportRows_Batch_RowNumber UNIQUE (BatchId, RowNumber)
    );
END
GO

IF COL_LENGTH(N'dbo.ImportRows', N'OriginalRowVersion') IS NULL
    ALTER TABLE dbo.ImportRows ADD OriginalRowVersion VARBINARY(8) NULL;
GO

IF OBJECT_ID(N'dbo.InventoryChanges', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.InventoryChanges
    (
        ChangeId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InventoryChanges PRIMARY KEY,
        ChangeNo           NVARCHAR(20)   NOT NULL CONSTRAINT UQ_InventoryChanges_ChangeNo UNIQUE,
        FacilityId         INT            NOT NULL CONSTRAINT FK_InventoryChanges_Facilities REFERENCES dbo.Facilities (FacilityId),
        InventoryKind      NVARCHAR(10)   NOT NULL CONSTRAINT CK_InventoryChanges_InventoryKind CHECK (InventoryKind IN (N'Blood', N'Resource')),
        InventoryId        INT            NULL,
        ComponentId        INT            NULL CONSTRAINT FK_InventoryChanges_Components REFERENCES dbo.BloodComponents (ComponentId),
        AboGroup           NVARCHAR(2)    NULL CONSTRAINT CK_InventoryChanges_AboGroup CHECK (AboGroup IN (N'A', N'B', N'AB', N'O')),
        RhFactor           NVARCHAR(10)   NULL CONSTRAINT CK_InventoryChanges_RhFactor CHECK (RhFactor IN (N'Positive', N'Negative')),
        ResourceTypeId     INT            NULL CONSTRAINT FK_InventoryChanges_ResourceTypes REFERENCES dbo.MedicalResourceTypes (ResourceTypeId),
        PreviousQuantity   DECIMAL(12,2)  NULL,
        ProposedQuantity   DECIMAL(12,2)  NULL,
        PreviousAvailable  DECIMAL(12,2)  NULL,
        ProposedAvailable  DECIMAL(12,2)  NULL,
        ProposedTotal      DECIMAL(12,2)  NULL,
        ProposedStatus     NVARCHAR(20)   NULL,
        EarliestExpiryDate DATE           NULL,
        ValidUntil         DATETIME2(0)   NULL,
        BeforeJson         NVARCHAR(MAX)  NULL,
        AfterJson          NVARCHAR(MAX)  NULL,
        SourceType         NVARCHAR(20)   NOT NULL CONSTRAINT CK_InventoryChanges_SourceType CHECK (SourceType IN (N'ManualPortal', N'CSVImport', N'PartnerAPI', N'AdminCorrection')),
        Reason             NVARCHAR(500)  NULL,
        AnomalyFlags       NVARCHAR(400)  NULL,
        Status             NVARCHAR(20)   NOT NULL CONSTRAINT CK_InventoryChanges_Status CHECK (Status IN (N'Applied', N'PendingReview', N'Rejected')),
        ImportBatchId      INT            NULL CONSTRAINT FK_InventoryChanges_ImportBatches REFERENCES dbo.ImportBatches (BatchId),
        IdempotencyKey     NVARCHAR(100)  NULL,
        SubmittedBy        INT            NOT NULL CONSTRAINT FK_InventoryChanges_SubmittedBy REFERENCES dbo.Users (UserId),
        SubmittedAt        DATETIME2(0)   NOT NULL CONSTRAINT DF_InventoryChanges_SubmittedAt DEFAULT (SYSUTCDATETIME()),
        DecidedBy          INT            NULL CONSTRAINT FK_InventoryChanges_DecidedBy REFERENCES dbo.Users (UserId),
        DecidedAt          DATETIME2(0)   NULL,
        DecisionReason     NVARCHAR(500)  NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_InventoryChanges_Facility_Status' AND object_id = OBJECT_ID(N'dbo.InventoryChanges'))
    CREATE NONCLUSTERED INDEX IX_InventoryChanges_Facility_Status ON dbo.InventoryChanges (FacilityId, Status, SubmittedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_InventoryChanges_Status_SubmittedAt' AND object_id = OBJECT_ID(N'dbo.InventoryChanges'))
    CREATE NONCLUSTERED INDEX IX_InventoryChanges_Status_SubmittedAt ON dbo.InventoryChanges (Status, SubmittedAt DESC);
GO

IF OBJECT_ID(N'dbo.AvailabilitySnapshots', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AvailabilitySnapshots
    (
        SnapshotId         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AvailabilitySnapshots PRIMARY KEY,
        FacilityId         INT           NOT NULL CONSTRAINT FK_AvailabilitySnapshots_Facilities REFERENCES dbo.Facilities (FacilityId),
        InventoryKind      NVARCHAR(10)  NOT NULL CONSTRAINT CK_AvailabilitySnapshots_InventoryKind CHECK (InventoryKind IN (N'Blood', N'Resource')),
        InventoryId        INT           NOT NULL,
        ComponentId        INT           NULL CONSTRAINT FK_AvailabilitySnapshots_Components REFERENCES dbo.BloodComponents (ComponentId),
        AboGroup           NVARCHAR(2)   NULL,
        RhFactor           NVARCHAR(10)  NULL,
        ResourceTypeId     INT           NULL CONSTRAINT FK_AvailabilitySnapshots_ResourceTypes REFERENCES dbo.MedicalResourceTypes (ResourceTypeId),
        Quantity           DECIMAL(12,2) NULL,
        AvailableQuantity  DECIMAL(12,2) NULL,
        TotalQuantity      DECIMAL(12,2) NULL,
        OperationalStatus  NVARCHAR(20)  NULL,
        SourceType         NVARCHAR(20)  NOT NULL,
        VerificationStatus NVARCHAR(20)  NOT NULL,
        RecordedAt         DATETIME2(0)  NOT NULL CONSTRAINT DF_AvailabilitySnapshots_RecordedAt DEFAULT (SYSUTCDATETIME()),
        ValidUntil         DATETIME2(0)  NULL,
        ChangeId           INT           NULL CONSTRAINT FK_AvailabilitySnapshots_InventoryChanges REFERENCES dbo.InventoryChanges (ChangeId),
        RecordedBy         INT           NULL CONSTRAINT FK_AvailabilitySnapshots_RecordedBy REFERENCES dbo.Users (UserId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AvailabilitySnapshots_Facility_RecordedAt' AND object_id = OBJECT_ID(N'dbo.AvailabilitySnapshots'))
    CREATE NONCLUSTERED INDEX IX_AvailabilitySnapshots_Facility_RecordedAt ON dbo.AvailabilitySnapshots (FacilityId, RecordedAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AvailabilitySnapshots_RecordedAt' AND object_id = OBJECT_ID(N'dbo.AvailabilitySnapshots'))
    CREATE NONCLUSTERED INDEX IX_AvailabilitySnapshots_RecordedAt ON dbo.AvailabilitySnapshots (RecordedAt)
        INCLUDE (FacilityId, InventoryKind, ComponentId, AboGroup, RhFactor, ResourceTypeId, Quantity, AvailableQuantity);
GO

/*---------------------------------------------------------------------
  Data quality
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.ValidationIssues', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ValidationIssues
    (
        IssueId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ValidationIssues PRIMARY KEY,
        FacilityId    INT           NOT NULL CONSTRAINT FK_ValidationIssues_Facilities REFERENCES dbo.Facilities (FacilityId),
        EntityType    NVARCHAR(50)  NOT NULL,
        EntityId      INT           NOT NULL,
        IssueCode     NVARCHAR(20)  NOT NULL CONSTRAINT CK_ValidationIssues_IssueCode CHECK (IssueCode IN (N'STALE', N'NEGATIVE', N'LARGE_JUMP', N'MISSING_FIELD', N'DUPLICATE', N'CONFLICT', N'EXPIRING')),
        Severity      NVARCHAR(10)  NOT NULL CONSTRAINT CK_ValidationIssues_Severity CHECK (Severity IN (N'Low', N'Medium', N'High')),
        ObservedValue NVARCHAR(200) NULL,
        Message       NVARCHAR(500) NOT NULL,
        Status        NVARCHAR(20)  NOT NULL CONSTRAINT DF_ValidationIssues_Status DEFAULT (N'Open')
                                    CONSTRAINT CK_ValidationIssues_Status CHECK (Status IN (N'Open', N'Resolved', N'Dismissed')),
        DetectedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_ValidationIssues_DetectedAt DEFAULT (SYSUTCDATETIME()),
        ResolvedBy    INT           NULL CONSTRAINT FK_ValidationIssues_ResolvedBy REFERENCES dbo.Users (UserId),
        ResolvedAt    DATETIME2(0)  NULL,
        Resolution    NVARCHAR(500) NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ValidationIssues_Open' AND object_id = OBJECT_ID(N'dbo.ValidationIssues'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_ValidationIssues_Open ON dbo.ValidationIssues (EntityType, EntityId, IssueCode)
        WHERE Status = N'Open';
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ValidationIssues_Facility_Status' AND object_id = OBJECT_ID(N'dbo.ValidationIssues'))
    CREATE NONCLUSTERED INDEX IX_ValidationIssues_Facility_Status ON dbo.ValidationIssues (FacilityId, Status)
        INCLUDE (IssueCode, Severity, DetectedAt);
GO

/*---------------------------------------------------------------------
  Blood requests
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.BloodRequests', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BloodRequests
    (
        RequestId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BloodRequests PRIMARY KEY,
        RequestNo           NVARCHAR(20)  NOT NULL CONSTRAINT UQ_BloodRequests_RequestNo UNIQUE,
        RequesterUserId     INT           NOT NULL CONSTRAINT FK_BloodRequests_Requester REFERENCES dbo.Users (UserId),
        PatientReference    NVARCHAR(50)  NULL,
        AboGroup            NVARCHAR(2)   NOT NULL CONSTRAINT CK_BloodRequests_AboGroup CHECK (AboGroup IN (N'A', N'B', N'AB', N'O')),
        RhFactor            NVARCHAR(10)  NOT NULL CONSTRAINT CK_BloodRequests_RhFactor CHECK (RhFactor IN (N'Positive', N'Negative')),
        ComponentId         INT           NOT NULL CONSTRAINT FK_BloodRequests_Components REFERENCES dbo.BloodComponents (ComponentId),
        QuantityRequested   DECIMAL(12,2) NOT NULL CONSTRAINT CK_BloodRequests_Quantity CHECK (QuantityRequested > 0),
        UnitId              INT           NOT NULL CONSTRAINT FK_BloodRequests_Units REFERENCES dbo.Units (UnitId),
        Urgency             NVARCHAR(20)  NOT NULL CONSTRAINT DF_BloodRequests_Urgency DEFAULT (N'Routine')
                                          CONSTRAINT CK_BloodRequests_Urgency CHECK (Urgency IN (N'Routine', N'Urgent', N'Emergency')),
        NeededBy            DATETIME2(0)  NOT NULL,
        AreaId              INT           NOT NULL CONSTRAINT FK_BloodRequests_Areas REFERENCES dbo.Areas (AreaId),
        HospitalName        NVARCHAR(200) NOT NULL,
        PreferredFacilityId INT           NULL CONSTRAINT FK_BloodRequests_PreferredFacility REFERENCES dbo.Facilities (FacilityId),
        MatchedFacilityId   INT           NULL CONSTRAINT FK_BloodRequests_MatchedFacility REFERENCES dbo.Facilities (FacilityId),
        ContactName         NVARCHAR(150) NOT NULL,
        ContactPhone        NVARCHAR(30)  NOT NULL,
        ContactConsent      BIT           NOT NULL CONSTRAINT CK_BloodRequests_ContactConsent CHECK (ContactConsent = 1),
        Notes               NVARCHAR(1000) NULL,
        Status              NVARCHAR(20)  NOT NULL CONSTRAINT DF_BloodRequests_Status DEFAULT (N'Submitted')
                                          CONSTRAINT CK_BloodRequests_Status CHECK (Status IN (N'Submitted', N'UnderReview', N'Matched', N'Contacted', N'Fulfilled', N'UnableToFulfil', N'Closed', N'Cancelled')),
        StatusReason        NVARCHAR(500) NULL,
        IdempotencyKey      NVARCHAR(100) NULL,
        RowVer              ROWVERSION    NOT NULL,
        CreatedAt           DATETIME2(0)  NOT NULL CONSTRAINT DF_BloodRequests_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CreatedBy           INT           NULL CONSTRAINT FK_BloodRequests_CreatedBy REFERENCES dbo.Users (UserId),
        UpdatedAt           DATETIME2(0)  NULL,
        UpdatedBy           INT           NULL CONSTRAINT FK_BloodRequests_UpdatedBy REFERENCES dbo.Users (UserId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_BloodRequests_Requester_IdempotencyKey' AND object_id = OBJECT_ID(N'dbo.BloodRequests'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_BloodRequests_Requester_IdempotencyKey ON dbo.BloodRequests (RequesterUserId, IdempotencyKey)
        WHERE IdempotencyKey IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BloodRequests_Status_CreatedAt' AND object_id = OBJECT_ID(N'dbo.BloodRequests'))
    CREATE NONCLUSTERED INDEX IX_BloodRequests_Status_CreatedAt ON dbo.BloodRequests (Status, CreatedAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BloodRequests_Requester_CreatedAt' AND object_id = OBJECT_ID(N'dbo.BloodRequests'))
    CREATE NONCLUSTERED INDEX IX_BloodRequests_Requester_CreatedAt ON dbo.BloodRequests (RequesterUserId, CreatedAt);
GO

IF OBJECT_ID(N'dbo.BloodRequestHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BloodRequestHistory
    (
        HistoryId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BloodRequestHistory PRIMARY KEY,
        RequestId  INT           NOT NULL CONSTRAINT FK_BloodRequestHistory_BloodRequests REFERENCES dbo.BloodRequests (RequestId),
        FromStatus NVARCHAR(20)  NULL,
        ToStatus   NVARCHAR(20)  NOT NULL,
        Note       NVARCHAR(500) NULL,
        FacilityId INT           NULL CONSTRAINT FK_BloodRequestHistory_Facilities REFERENCES dbo.Facilities (FacilityId),
        ChangedBy  INT           NOT NULL CONSTRAINT FK_BloodRequestHistory_ChangedBy REFERENCES dbo.Users (UserId),
        ChangedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_BloodRequestHistory_ChangedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BloodRequestHistory_Request' AND object_id = OBJECT_ID(N'dbo.BloodRequestHistory'))
    CREATE NONCLUSTERED INDEX IX_BloodRequestHistory_Request ON dbo.BloodRequestHistory (RequestId, ChangedAt);
GO

/*---------------------------------------------------------------------
  Notifications, audit, settings, sequences
---------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.Notifications', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Notifications
    (
        NotificationId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Notifications PRIMARY KEY,
        UserId         INT            NOT NULL CONSTRAINT FK_Notifications_Users REFERENCES dbo.Users (UserId),
        Title          NVARCHAR(200)  NOT NULL,
        Message        NVARCHAR(1000) NOT NULL,
        Type           NVARCHAR(20)   NOT NULL CONSTRAINT DF_Notifications_Type DEFAULT (N'Info')
                                      CONSTRAINT CK_Notifications_Type CHECK (Type IN (N'Info', N'Success', N'Warning', N'Action')),
        EntityType     NVARCHAR(50)   NULL,
        EntityId       NVARCHAR(50)   NULL,
        Route          NVARCHAR(300)  NULL,
        IsRead         BIT            NOT NULL CONSTRAINT DF_Notifications_IsRead DEFAULT (0),
        ReadAt         DATETIME2(0)   NULL,
        CreatedAt      DATETIME2(0)   NOT NULL CONSTRAINT DF_Notifications_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Notifications_User_IsRead_CreatedAt' AND object_id = OBJECT_ID(N'dbo.Notifications'))
    CREATE NONCLUSTERED INDEX IX_Notifications_User_IsRead_CreatedAt ON dbo.Notifications (UserId, IsRead, CreatedAt);
GO

IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditLogs
    (
        AuditId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLogs PRIMARY KEY,
        EntityType    NVARCHAR(50)   NOT NULL,
        EntityId      NVARCHAR(50)   NOT NULL,
        ReferenceNo   NVARCHAR(50)   NULL,
        FacilityId    INT            NULL,
        Action        NVARCHAR(50)   NOT NULL,
        Description   NVARCHAR(1000) NOT NULL,
        OldValues     NVARCHAR(MAX)  NULL,
        NewValues     NVARCHAR(MAX)  NULL,
        SourceType    NVARCHAR(20)   NULL,
        Reason        NVARCHAR(500)  NULL,
        CorrelationId NVARCHAR(64)   NULL,
        UserId        INT            NULL,
        ActorRole     NVARCHAR(50)   NULL,
        CreatedAt     DATETIME2(0)   NOT NULL CONSTRAINT DF_AuditLogs_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AuditLogs_Entity_CreatedAt' AND object_id = OBJECT_ID(N'dbo.AuditLogs'))
    CREATE NONCLUSTERED INDEX IX_AuditLogs_Entity_CreatedAt ON dbo.AuditLogs (EntityType, EntityId, CreatedAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AuditLogs_User_CreatedAt' AND object_id = OBJECT_ID(N'dbo.AuditLogs'))
    CREATE NONCLUSTERED INDEX IX_AuditLogs_User_CreatedAt ON dbo.AuditLogs (UserId, CreatedAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AuditLogs_CreatedAt' AND object_id = OBJECT_ID(N'dbo.AuditLogs'))
    CREATE NONCLUSTERED INDEX IX_AuditLogs_CreatedAt ON dbo.AuditLogs (CreatedAt DESC);
GO

IF OBJECT_ID(N'dbo.SystemSettings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SystemSettings
    (
        SettingKey   NVARCHAR(100) NOT NULL CONSTRAINT PK_SystemSettings PRIMARY KEY,
        SettingValue NVARCHAR(400) NOT NULL,
        DataType     NVARCHAR(10)  NOT NULL CONSTRAINT CK_SystemSettings_DataType CHECK (DataType IN (N'int', N'decimal', N'bool', N'string')),
        Category     NVARCHAR(60)  NOT NULL,
        Description  NVARCHAR(400) NULL,
        UpdatedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_SystemSettings_UpdatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedBy    INT           NULL CONSTRAINT FK_SystemSettings_UpdatedBy REFERENCES dbo.Users (UserId)
    );
END
GO

IF OBJECT_ID(N'dbo.ReferenceSequences', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ReferenceSequences
    (
        Prefix     NVARCHAR(10) NOT NULL,
        [Year]     INT          NOT NULL,
        LastNumber INT          NOT NULL CONSTRAINT DF_ReferenceSequences_LastNumber DEFAULT (0),
        CONSTRAINT PK_ReferenceSequences PRIMARY KEY (Prefix, [Year])
    );
END
GO
