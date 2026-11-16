@description('Web App name (globally unique). Serves the prebuilt Angular SPA.')
param name string

param planName string
param location string
param tags object

@description('App Service plan SKU, e.g. F1 (free), B1.')
param skuName string = 'F1'

@description('Linux runtime used only to run the static file server.')
param linuxFxVersion string = 'NODE|22-lts'

var isFreeTier = contains([
  'F1'
  'D1'
], skuName)

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      // pm2 ships with the App Service Node image; --spa returns index.html for client-side routes.
      appCommandLine: 'pm2 serve /home/site/wwwroot --no-daemon --spa'
      alwaysOn: !isFreeTier
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
    }
  }

  resource settings 'config' = {
    name: 'appsettings'
    properties: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    }
  }
}

resource basicPublishingScm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: webApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource basicPublishingFtp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: webApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

output id string = webApp.id
output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
