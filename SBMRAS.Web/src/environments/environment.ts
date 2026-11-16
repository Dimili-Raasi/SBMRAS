// local environment. Auth mode is discovered at runtime from GET auth/config; the `auth` block is the
// fallback used when the API does not provide values (mirrors the FRRMS approach).
export const environment = {
  name: 'local',
  production: false,
  apiBaseUrl: '/api/v1',
  auth: {
    mode: 'DevHeader' as 'DevHeader' | 'EntraId',
    clientId: '<SBMRAS-WEB-CLIENT-ID>',
    authority: 'https://<tenant-subdomain>.ciamlogin.com/<tenant-id>',
    knownAuthorities: ['<tenant-subdomain>.ciamlogin.com'],
    apiScope: 'api://<SBMRAS-API-CLIENT-ID>/access_as_user',
    userFlow: 'B2X_1_SBMRAS-SignUpSignIn',
  },
};
