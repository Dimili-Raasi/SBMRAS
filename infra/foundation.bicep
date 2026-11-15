// Stage 1: runtime identity and the Function host storage account. Creates no role assignments, so the GitHub
// deployment identity only needs Contributor. After apply, an Owner grants the three roles in the
// "requiredRoleAssignments" output (see README.md), then stage 2 (main.bicep) deploys the Function App and web app.
// The storage account is platform-only (AzureWebJobsStorage + deployment package); SBMRAS stores no application files.
targetScope = 'resourceGroup'

import { resourceNames, deploymentContainerName, runtimeRoles } from 'naming.bicep'

@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string

param location string = resourceGroup().location

@description('Keep in sync with main.<env>.bicepparam.')
@minLength(2)
@maxLength(8)
param namePrefix string = 'sbmras'

var names = resourceNames(namePrefix, environmentName, take(uniqueString(subscription().id, resourceGroup().id, environmentName), 6))
var tags = {
  application: 'SBMRAS'
  environment: environmentName
  'managed-by': 'bicep'
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: names.identity
    location: location
    tags: tags
  }
}

module hostStorage 'modules/storage.bicep' = {
  name: 'host-storage'
  params: {
    name: names.hostStorage
    location: location
    tags: tags
    containerNames: [
      deploymentContainerName
    ]
  }
}

output runtimeIdentityName string = identity.outputs.name
output runtimeIdentityClientId string = identity.outputs.clientId
output runtimeIdentityPrincipalId string = identity.outputs.principalId
output hostStorageAccountName string = hostStorage.outputs.name
output hostStorageAccountId string = hostStorage.outputs.id
output deploymentContainerName string = deploymentContainerName

output requiredRoleAssignments array = [
  {
    role: runtimeRoles.storageBlobDataOwner.name
    roleDefinitionId: runtimeRoles.storageBlobDataOwner.id
    scope: hostStorage.outputs.id
  }
  {
    role: runtimeRoles.storageQueueDataContributor.name
    roleDefinitionId: runtimeRoles.storageQueueDataContributor.id
    scope: hostStorage.outputs.id
  }
  {
    role: runtimeRoles.storageTableDataContributor.name
    roleDefinitionId: runtimeRoles.storageTableDataContributor.id
    scope: hostStorage.outputs.id
  }
]
