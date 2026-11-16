// Shared resource names for foundation.bicep (stage 1) and main.bicep (stage 2).
// suffix = take(uniqueString(subscription().id, resourceGroup().id, environmentName), 6), computed by each template.
// Function App and Web App host names are fixed so SBMRAS.Web/src/environments/environment.<env>.ts can reference them
// (https://sbmras-func-<env>.azurewebsites.net/api/v1).

@export()
func resourceNames(namePrefix string, environmentName string, suffix string) object => {
  identity: '${namePrefix}-id-${environmentName}'
  logAnalytics: '${namePrefix}-log-${environmentName}'
  applicationInsights: '${namePrefix}-appi-${environmentName}'
  hostStorage: take('${namePrefix}st${environmentName}${suffix}', 24)
  keyVault: take('${namePrefix}-kv-${environmentName}-${suffix}', 24)
  functionPlan: '${namePrefix}-plan-func-${environmentName}'
  functionApp: '${namePrefix}-func-${environmentName}'
  webPlan: '${namePrefix}-plan-web-${environmentName}'
  webApp: '${namePrefix}-web-${environmentName}'
}

@export()
var deploymentContainerName = 'app-package'

// Data-plane roles the runtime identity needs on the Function host storage account (AzureWebJobsStorage and the
// deployment package). SBMRAS has no application storage. Granted manually by an Owner between stage 1 and stage 2.
@export()
var runtimeRoles = {
  storageBlobDataOwner: {
    name: 'Storage Blob Data Owner'
    id: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  }
  storageQueueDataContributor: {
    name: 'Storage Queue Data Contributor'
    id: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  }
  storageTableDataContributor: {
    name: 'Storage Table Data Contributor'
    id: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  }
}

// Only needed when the optional Key Vault is created (main.bicep createKeyVault = true). Granted manually by an Owner.
@export()
var keyVaultSecretsUserRole = {
  name: 'Key Vault Secrets User'
  id: '4633458b-17de-408a-b874-0445c86b69e6'
}
