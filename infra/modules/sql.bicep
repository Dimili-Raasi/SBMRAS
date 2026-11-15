@description('Logical SQL server name (short name, e.g. sbmras-sql-dev).')
param serverName string

param databaseName string
param location string
param tags object

@description('SQL authentication admin login. Cannot be changed after the server is created.')
param administratorLogin string

@description('SQL authentication admin password. Re-applied on every deployment.')
@secure()
param administratorPassword string

@description('Microsoft Entra admin (user or group) display name / UPN. Empty leaves the Entra admin unmanaged.')
param entraAdminLogin string = ''

@description('Object id of the Entra admin. Required when entraAdminLogin is set.')
param entraAdminObjectId string = ''

@description('Database SKU name, e.g. GP_S_Gen5_1 (serverless), Basic, S0.')
param skuName string

@description('Database SKU tier, e.g. GeneralPurpose, Basic, Standard.')
param skuTier string

@description('Serverless only: minutes of inactivity before auto-pause (-1 disables it).')
param autoPauseDelayMinutes int = 60

@description('Serverless only: use the Azure SQL free offer (one free serverless database per subscription and region set).')
param useFreeLimit bool = false

@allowed([
  'Local'
  'Zone'
  'Geo'
])
param backupStorageRedundancy string = 'Local'

@description('Adds the "Allow Azure services and resources to access this server" rule (AllowAllWindowsAzureIps).')
param allowAzureServices bool = true

var isServerless = startsWith(skuName, 'GP_S_')

resource server 'Microsoft.Sql/servers@2023-08-01' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    version: '12.0'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// SQL authentication stays enabled: deploy-database connects as the contained user sbmras_migrator.
resource entraAdmin 'Microsoft.Sql/servers/administrators@2023-08-01' = if (!empty(entraAdminObjectId)) {
  parent: server
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: entraAdminLogin
    sid: entraAdminObjectId
    tenantId: subscription().tenantId
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: server
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: union(
    {
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      requestedBackupStorageRedundancy: backupStorageRedundancy
    },
    isServerless
      ? {
          autoPauseDelay: autoPauseDelayMinutes
          minCapacity: json('0.5')
        }
      : {},
    isServerless && useFreeLimit
      ? {
          useFreeLimit: true
          freeLimitExhaustionBehavior: 'AutoPause'
        }
      : {}
  )
}

// Uses the portal's rule name, so an existing portal setting is reported as unchanged by what-if.
resource allowAllAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01' = if (allowAzureServices) {
  parent: server
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverName string = server.name
output fullyQualifiedDomainName string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
