using './main.bicep'

// Tenant-specific values come from the dev GitHub environment variables (see infra/README.md).
// readEnvironmentVariable() fails the deployment when a variable without a default is missing.
param environmentName = 'dev'
param location = readEnvironmentVariable('AZURE_LOCATION', 'centralindia')
// Keep in sync with foundation.dev.bicepparam (stage 1 creates the identity and host storage with these names).
param namePrefix = 'sbmras'

// Azure SQL server and database (created or updated by Bicep). The admin password comes from the SQL_ADMIN_PASSWORD
// environment secret. SQL_LOCATION overrides the region when the main region does not accept new SQL servers.
param sqlServerName = readEnvironmentVariable('SQL_SERVER_NAME', 'sbmras-sql-dev')
param sqlDatabaseName = readEnvironmentVariable('SQL_DATABASE_NAME', 'SBMRAS')
param sqlServerResourceGroup = readEnvironmentVariable('SQL_SERVER_RESOURCE_GROUP', '')
param sqlLocation = readEnvironmentVariable('SQL_LOCATION', '')
param sqlAdministratorLogin = readEnvironmentVariable('SQL_ADMIN_LOGIN', 'sbmrasadmin')
param sqlAdministratorPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')
param sqlEntraAdminLogin = readEnvironmentVariable('SQL_ENTRA_ADMIN_LOGIN', '')
param sqlEntraAdminObjectId = readEnvironmentVariable('SQL_ENTRA_ADMIN_OBJECT_ID', '')
param sqlDatabaseSkuName = 'GP_S_Gen5_1'
param sqlDatabaseSkuTier = 'GeneralPurpose'
param sqlAutoPauseDelayMinutes = 60
param sqlUseFreeLimit = toLower(readEnvironmentVariable('SQL_USE_FREE_LIMIT', 'false')) == 'true'
param sqlBackupStorageRedundancy = 'Local'

// Microsoft Entra External ID tenant that holds SBMRAS-Web, SBMRAS-API and the SBMRAS-* groups
// (usually different from the Azure subscription tenant). See deploy/entra-external-id-setup.md.
param authInstance = readEnvironmentVariable('ENTRA_AUTHORITY')
param authTenantId = readEnvironmentVariable('ENTRA_TENANT_ID')
param authClientId = readEnvironmentVariable('ENTRA_API_CLIENT_ID')
param authSpaClientId = readEnvironmentVariable('ENTRA_SPA_CLIENT_ID')
param authAudience = readEnvironmentVariable('ENTRA_API_AUDIENCE', '')
// ENTRA_API_SCOPE may be the full api://<API-CLIENT-ID>/access_as_user; the API checks the scope name in the scp claim.
param authRequiredScope = last(split(readEnvironmentVariable('ENTRA_API_SCOPE', 'access_as_user'), '/'))
param authUserFlow = readEnvironmentVariable('ENTRA_USER_FLOW', 'B2X_1_SBMRAS-SignUpSignIn')
param authGroupHospitalManagementId = readEnvironmentVariable('ENTRA_GROUP_HOSPITAL_ID', '')
param authGroupBloodBankId = readEnvironmentVariable('ENTRA_GROUP_BLOODBANK_ID', '')
param authGroupAdminId = readEnvironmentVariable('ENTRA_GROUP_ADMIN_ID', '')

// Freshness defaults and import limit (database SystemSettings stay authoritative for freshness).
param bloodStockTtlMinutes = int(readEnvironmentVariable('BLOOD_STOCK_TTL_MINUTES', '360'))
param resourceTtlMinutes = int(readEnvironmentVariable('RESOURCE_TTL_MINUTES', '240'))
param importMaxRows = int(readEnvironmentVariable('MAX_IMPORT_ROWS', '500'))

// Optional comma-separated extra CORS origins (e.g. a Cloudflare hostname).
var webOrigins = readEnvironmentVariable('WEB_ORIGINS', '')
param additionalCorsOrigins = empty(webOrigins) ? [] : split(webOrigins, ',')

// Optional Key Vault and Key Vault reference for SqlConnectionString (managed identity is preferred).
param createKeyVault = toLower(readEnvironmentVariable('CREATE_KEY_VAULT', 'false')) == 'true'
param sqlConnectionStringSecretName = readEnvironmentVariable('SQL_CONNECTION_SECRET_NAME', '')

param webSkuName = 'F1'
param functionMaximumInstanceCount = 40
