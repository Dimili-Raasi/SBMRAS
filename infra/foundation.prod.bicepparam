using './foundation.bicep'

// Stage 1 (runtime identity + Function host storage) for prod. Keep namePrefix and location in sync with main.prod.bicepparam.
param environmentName = 'prod'
param location = readEnvironmentVariable('AZURE_LOCATION', 'indiasouthcentral')
param namePrefix = 'sbmras'
