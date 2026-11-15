# SBMRAS API implementation guide

This project is the .NET 10 Azure Functions isolated-worker HTTP API. The shared implementation contract at the
repository root (`SBMRAS_CONTRACT.md`) is the source of truth for routes, permissions, stored procedure names, request
and response shapes, and database behavior.

## Layer boundaries

- `SBMRAS.API`: Function entry points, authorization attributes, and HTTP/worker middleware.
- `SBMRAS.Application`: DTOs, validators, constants, and service/repository abstractions.
- `SBMRAS.Domain`: validation and use-case orchestration; no SQL access.
- `SBMRAS.Infrastructure`: Dapper repositories, SQL connection management, and stored-procedure execution.

Use the existing interfaces and DTOs before adding new ones. Keep dependencies flowing API → Application/Domain/
Infrastructure, Domain → Application, and Infrastructure → Application. Do not reference SQL Server or Dapper from
the API, Application, or Domain layers.

## API conventions

- Every HTTP-triggered function must have exactly one of `[AllowAnonymousEndpoint]`,
  `[AuthenticatedEndpoint]`, or `[RequirePermission("permission.code")]` from
  `SBMRAS.API.Authorization`. Startup validates this for all registered HTTP functions.
- Use `FunctionBase` response helpers (or the same `ApiResponse<T>` envelope): `{ success, message, data, errors }`.
- Do not duplicate identity resolution in functions. `RequestContextMiddleware` resolves an optional
  `CurrentUser` for anonymous routes and requires a valid identity for authenticated routes.
- Add the `CancellationToken` from the HTTP request to database/service calls where applicable.
- Use only Dapper stored-procedure calls. Never add EF Core, inline SQL, or call stored procedures by composing
  arbitrary user-provided procedure names.
- Keep authorization decisions server-side; UI visibility is not an authorization boundary.

## Local development

The Functions host uses `host.json` with route prefix `api/v1` and local HTTP port `7073`. Copy
`local.settings.sample.json` to `local.settings.json` and set the local SQL connection string as needed. Local auth
defaults to `DevHeader`; the development login uses `X-User-Id`. Do not commit credentials or local settings.
For local Core Tools only, the sample uses file-based host secret storage and disables the health monitor because this
project intentionally has no Azure Storage/Azurite dependency. Do not copy those two host settings into deployed
environments. Admin routes use a constrained route token for the reserved `admin` segment; their effective URLs remain
`/api/v1/admin/...`.

Build from the repository root with:

```powershell
dotnet build SBMRAS.API.slnx
```
