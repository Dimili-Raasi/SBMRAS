// Stage 2: Azure SQL server and database, Function App, web app, monitoring and (optionally) Key Vault. Run foundation.bicep
// (stage 1) and grant the runtime identity's host storage roles first. Creates no role assignments.
targetScope = 'resourceGroup'

import { resourceNames, deploymentContainerName, keyVaultSecretsUserRole } from 'naming.bicep'

@description('Deployment environment.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string

@description('Region for all resources.')
param location string = resourceGroup().location

@description('Lowercase prefix used in resource names, e.g. sbmras -> sbmras-func-dev.')
@minLength(2)
@maxLength(8)
param namePrefix string = 'sbmras'

@description('Azure SQL logical server name (short name, e.g. sbmras-sql-dev). Created or updated by this template.')
param sqlServerName string

@description('Database name on that server. Created or updated by this template.')
param sqlDatabaseName string

@description('Resource group for the SQL server. Empty means the deployment resource group.')
param sqlServerResourceGroup string = ''

@description('Region for the SQL server and database. Empty means the same region as the other resources.')
param sqlLocation string = ''

@description('SQL authentication admin login. Cannot be changed after the server is created.')
param sqlAdministratorLogin string = 'sbmrasadmin'

@description('SQL authentication admin password.')
@secure()
param sqlAdministratorPassword string

@description('Microsoft Entra admin of the SQL server (UPN or group name). Empty leaves the Entra admin unmanaged.')
param sqlEntraAdminLogin string = ''

@description('Object id of the Microsoft Entra admin. Required when sqlEntraAdminLogin is set.')
param sqlEntraAdminObjectId string = ''

@description('Database SKU name, e.g. GP_S_Gen5_1 (serverless), Basic, S0.')
param sqlDatabaseSkuName string = 'GP_S_Gen5_1'

@description('Database SKU tier matching sqlDatabaseSkuName, e.g. GeneralPurpose, Basic, Standard.')
param sqlDatabaseSkuTier string = 'GeneralPurpose'

@description('Serverless only: minutes of inactivity before auto-pause (-1 disables it).')
param sqlAutoPauseDelayMinutes int = 60

@description('Serverless only: use the Azure SQL Database free offer.')
param sqlUseFreeLimit bool = false

@allowed([
  'Local'
  'Zone'
  'Geo'
])
param sqlBackupStorageRedundancy string = 'Local'

@description('Adds the "Allow Azure services" firewall rule on the SQL server so the Function App can connect.')
param sqlAllowAzureServices bool = true

@description('Microsoft Entra External ID authority host, https://<tenant-subdomain>.ciamlogin.com/ (Auth:Entra:Instance).')
param authInstance string

@description('External ID tenant id that issues user tokens (the tenant holding SBMRAS-Web, SBMRAS-API and the SBMRAS-* groups).')
param authTenantId string

@description('SBMRAS-API app registration (client) id.')
param authClientId string

@description('SBMRAS-Web SPA app registration (client) id, returned to the browser by /api/v1/auth/config.')
param authSpaClientId string

@description('Expected token audience. Empty means api://<authClientId>.')
param authAudience string = ''

@description('Scope that must be present in the scp claim.')
param authRequiredScope string = 'access_as_user'

@description('External ID sign-up/sign-in user flow name.')
param authUserFlow string = 'B2X_1_SBMRAS-SignUpSignIn'

@description('Object id of the SBMRAS-HospitalManagement security group. Empty = not mapped (app-role claims still apply).')
param authGroupHospitalManagementId string = ''

@description('Object id of the SBMRAS-BloodBank security group. Empty = not mapped.')
param authGroupBloodBankId string = ''

@description('Object id of the SBMRAS-Admin security group. Empty = not mapped.')
param authGroupAdminId string = ''

@description('Default blood stock validity in minutes (the database SystemSettings value BLOOD_STOCK_TTL_MINUTES is authoritative).')
@minValue(1)
param bloodStockTtlMinutes int = 360

@description('Default medical resource validity in minutes (the database SystemSettings value RESOURCE_TTL_MINUTES is authoritative).')
@minValue(1)
param resourceTtlMinutes int = 240

@description('Maximum rows accepted by one bulk import request.')
@minValue(1)
param importMaxRows int = 500

param functionMaximumInstanceCount int = 40

@description('App Service plan SKU for the web front end (F1 = free).')
param webSkuName string = 'F1'

@description('Extra browser origins allowed by the API CORS policy, e.g. http://localhost:4400 or a Cloudflare hostname.')
param additionalCorsOrigins array = []

@description('Creates an RBAC Key Vault (sbmras-kv-<env>-<suffix>) for secrets the Function App reads through Key Vault references.')
param createKeyVault bool = false

@description('Optional. Name of a Key Vault secret holding the SQL connection string. When set (requires createKeyVault), SqlConnectionString becomes a Key Vault reference instead of the managed identity connection string.')
param sqlConnectionStringSecretName string = ''

var names = resourceNames(namePrefix, environmentName, take(uniqueString(subscription().id, resourceGroup().id, environmentName), 6))
var tags = {
  application: 'SBMRAS'
  environment: environmentName
  'managed-by': 'bicep'
}

// Created by stage 1 (foundation.bicep). The three host storage role assignments for the identity are granted
// manually by an Owner; .github/workflows/deploy-infra.yml checks they exist before applying this stage.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: names.identity
}

resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: names.hostStorage
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: names.logAnalytics
    applicationInsightsName: names.applicationInsights
    location: location
    tags: tags
  }
}

module keyVault 'modules/keyvault.bicep' = if (createKeyVault) {
  name: 'key-vault'
  params: {
    name: names.keyVault
    location: location
    tags: tags
    enablePurgeProtection: environmentName == 'prod'
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sql'
  scope: resourceGroup(empty(sqlServerResourceGroup) ? resourceGroup().name : sqlServerResourceGroup)
  params: {
    serverName: sqlServerName
    databaseName: sqlDatabaseName
    location: empty(sqlLocation) ? location : sqlLocation
    tags: tags
    administratorLogin: sqlAdministratorLogin
    administratorPassword: sqlAdministratorPassword
    entraAdminLogin: sqlEntraAdminLogin
    entraAdminObjectId: sqlEntraAdminObjectId
    skuName: sqlDatabaseSkuName
    skuTier: sqlDatabaseSkuTier
    autoPauseDelayMinutes: sqlAutoPauseDelayMinutes
    useFreeLimit: sqlUseFreeLimit
    backupStorageRedundancy: sqlBackupStorageRedundancy
    allowAzureServices: sqlAllowAzureServices
  }
}

module webApp 'modules/webapp.bicep' = {
  name: 'web-app'
  params: {
    name: names.webApp
    planName: names.webPlan
    location: location
    tags: tags
    skuName: webSkuName
  }
}

var sqlServerFqdn = sql.outputs.fullyQualifiedDomainName
var useKeyVaultSqlConnection = createKeyVault && !empty(sqlConnectionStringSecretName)
var managedIdentitySqlConnection = 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};Authentication=Active Directory Managed Identity;User Id=${identity.properties.clientId};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var corsOrigins = concat([
  'https://${webApp.outputs.defaultHostName}'
], additionalCorsOrigins)

// Keep in sync with .github/workflows/deploy-api.yml and deploy/environment-variables.md.
// Linux plans require "__" instead of ":" in keys.
var applicationSettings = {
  Auth__Mode: 'EntraId'
  Auth__Entra__Instance: authInstance
  Auth__Entra__TenantId: authTenantId
  Auth__Entra__ClientId: authClientId
  Auth__Entra__SpaClientId: authSpaClientId
  Auth__Entra__Audience: empty(authAudience) ? 'api://${authClientId}' : authAudience
  Auth__Entra__RequiredScope: authRequiredScope
  Auth__Entra__UserFlow: authUserFlow
  Auth__Entra__Groups__HospitalManagement: authGroupHospitalManagementId
  Auth__Entra__Groups__BloodBank: authGroupBloodBankId
  Auth__Entra__Groups__Admin: authGroupAdminId
  Cors__AllowedOrigins: join(corsOrigins, ',')
  Freshness__BloodStockTtlMinutes: string(bloodStockTtlMinutes)
  Freshness__ResourceTtlMinutes: string(resourceTtlMinutes)
  Import__MaxRows: string(importMaxRows)
  SqlConnectionString: useKeyVaultSqlConnection
    ? '@Microsoft.KeyVault(VaultName=${names.keyVault};SecretName=${sqlConnectionStringSecretName})'
    : managedIdentitySqlConnection
}

module functionApp 'modules/functionapp.bicep' = {
  name: 'function-app'
  dependsOn: [
    keyVault
  ]
  params: {
    name: names.functionApp
    planName: names.functionPlan
    location: location
    tags: tags
    identityId: identity.id
    identityClientId: identity.properties.clientId
    hostStorageName: hostStorage.name
    hostBlobEndpoint: hostStorage.properties.primaryEndpoints.blob
    deploymentContainerName: deploymentContainerName
    applicationInsightsConnectionString: monitoring.outputs.connectionString
    maximumInstanceCount: functionMaximumInstanceCount
    appSettings: applicationSettings
    corsAllowedOrigins: corsOrigins
  }
}

output functionAppName string = functionApp.outputs.name
output functionAppHostName string = functionApp.outputs.defaultHostName
output apiBaseUrl string = 'https://${functionApp.outputs.defaultHostName}/api/v1'
output webAppName string = webApp.outputs.name
output webAppHostName string = webApp.outputs.defaultHostName
output sqlServerName string = sql.outputs.serverName
output sqlServerFqdn string = sqlServerFqdn
output sqlDatabaseName string = sql.outputs.databaseName
output runtimeIdentityName string = identity.name
output runtimeIdentityClientId string = identity.properties.clientId
output applicationInsightsName string = monitoring.outputs.applicationInsightsName
output keyVaultName string = createKeyVault ? names.keyVault : ''
output keyVaultRequiredRoleAssignments array = createKeyVault
  ? [
      {
        role: keyVaultSecretsUserRole.name
        roleDefinitionId: keyVaultSecretsUserRole.id
        scope: resourceId('Microsoft.KeyVault/vaults', names.keyVault)
      }
    ]
  : []
