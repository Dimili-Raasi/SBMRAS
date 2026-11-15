using SBMRAS.Application.Common;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;

namespace SBMRAS.Infrastructure.Repositories;

public sealed class DashboardRepository(IStoredProcedureExecutor executor) : IDashboardRepository
{
    public Task<IDictionary<string, object?>?> GetSummaryAsync(int actorUserId, CancellationToken ct = default)
        => executor.QuerySingleAsync(StoredProcedures.DashboardGetSummary, actorUserId, cancellationToken: ct);

    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetChartsAsync(int actorUserId, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.DashboardGetCharts, actorUserId, cancellationToken: ct);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetWorklistAsync(int actorUserId, CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.DashboardGetWorklist, actorUserId, cancellationToken: ct);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetActivityAsync(int actorUserId, int top, CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.DashboardGetActivity, actorUserId, new Dictionary<string, object?> { ["Top"] = top }, ct);
}

public sealed class ReportRepository(IStoredProcedureExecutor executor) : IReportRepository
{
    public Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> RunAsync(int actorUserId, ReportQuery query, CancellationToken ct = default)
        => executor.QueryMultipleAsync(StoredProcedures.ReportRun, actorUserId, new Dictionary<string, object?>
        {
            ["ReportCode"] = query.Code,
            ["FromDate"] = query.FromDate,
            ["ToDate"] = query.ToDate,
            ["FacilityId"] = query.FacilityId,
            ["AreaId"] = query.AreaId,
        }, ct);
}

public sealed class AuditRepository(IStoredProcedureExecutor executor) : IAuditRepository
{
    public Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, AuditSearchQuery query, CancellationToken ct = default)
        => executor.QueryPagedAsync(StoredProcedures.AuditSearch, actorUserId, new Dictionary<string, object?>
        {
            ["Search"] = query.Search,
            ["EntityType"] = query.EntityType,
            ["Action"] = query.Action,
            ["FacilityId"] = query.FacilityId,
            ["UserId"] = query.UserId,
            ["CorrelationId"] = query.CorrelationId,
            ["FromDate"] = query.FromDate,
            ["ToDate"] = query.ToDate,
        }, query.Page, query.PageSize, ct);

    public Task<IReadOnlyList<IDictionary<string, object?>>> GetEntityTimelineAsync(int actorUserId, string entityType, string entityId,
        CancellationToken ct = default)
        => executor.QueryListAsync(StoredProcedures.AuditGetEntityTimeline, actorUserId,
            new Dictionary<string, object?> { ["EntityType"] = entityType, ["EntityId"] = entityId }, ct);
}
