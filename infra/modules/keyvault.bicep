@description('Optional Key Vault (RBAC authorization) for secrets the Function App reads through Key Vault references, e.g. a SQL connection string when managed identity cannot be used. Creates no role assignments: an Owner grants "Key Vault Secrets User" to the runtime identity (see infra/README.md).')
param name string

param location string
param tags object

@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 7

param enablePurgeProtection bool = false

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

output id string = vault.id
output name string = vault.name
output vaultUri string = vault.properties.vaultUri
