using './foundation.bicep'

// Stage 1 (runtime identity + Function host storage) for test. Keep namePrefix and location in sync with main.test.bicepparam.
param environmentName = 'test'
param location = readEnvironmentVariable('AZURE_LOCATION', 'indiasouthcentral')
param namePrefix = 'sbmras'
