// prod environment. Auth mode is discovered at runtime from GET auth/config; the `auth` block is the
// fallback used when the API does not provide values (mirrors the FRRMS approach).
export const environment = {
  name: 'prod',
  production: true,
  apiBaseUrl: 'https://sbmras-func-prod.azurewebsites.net/api/v1',
  auth: {
    mode: 'EntraId' as 'DevHeader' | 'EntraId',
    clientId: '<SBMRAS-WEB-CLIENT-ID>',
    authority: 'https://<tenant-subdomain>.ciamlogin.com/<tenant-id>',
    knownAuthorities: ['<tenant-subdomain>.ciamlogin.com'],
    apiScope: 'api://<SBMRAS-API-CLIENT-ID>/access_as_user',
    userFlow: 'B2X_1_SBMRAS-SignUpSignIn',
  },
};
