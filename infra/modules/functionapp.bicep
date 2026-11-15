@description('Function App name (globally unique).')
param name string

param planName string
param location string
param tags object

@description('Resource id of the user-assigned identity used for host storage, deployment storage and SQL.')
param identityId string

@description('Client id of the user-assigned identity.')
param identityClientId string

param hostStorageName string
param hostBlobEndpoint string
param deploymentContainerName string
param applicationInsightsConnectionString string

@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 100

@description('Application settings owned by the application (Auth, Cors, Freshness, Import, SQL). Merged with the host settings below.')
param appSettings object

@description('Browser origins allowed to call the API (the web app). Bearer tokens only, so credentials are not allowed.')
param corsAllowedOrigins array

var hostSettings = {
  AzureWebJobsStorage__accountName: hostStorageName
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: identityClientId
  APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
  AZURE_CLIENT_ID: identityClientId
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    // Resolves @Microsoft.KeyVault(...) app settings (optional Key Vault option in main.bicep) with the runtime identity.
    keyVaultReferenceIdentity: identityId
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      cors: {
        allowedOrigins: corsAllowedOrigins
        supportCredentials: false
      }
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${hostBlobEndpoint}${deploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identityId
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
    }
  }

  resource settings 'config' = {
    name: 'appsettings'
    properties: union(hostSettings, appSettings)
  }
}

resource basicPublishingScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource basicPublishingFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

output id string = functionApp.id
output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
