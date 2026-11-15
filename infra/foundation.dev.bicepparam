using './foundation.bicep'

// Stage 1 (runtime identity + Function host storage) for dev. Keep namePrefix and location in sync with main.dev.bicepparam.
param environmentName = 'dev'
param location = readEnvironmentVariable('AZURE_LOCATION', 'centralindia')
param namePrefix = 'sbmras'
