using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Interfaces;

public interface IDashboardRepository
{
    Task<IDictionary<string, object?>?> GetSummaryAsync(int actorUserId, CancellationToken ct = default);
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> GetChartsAsync(int actorUserId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetWorklistAsync(int actorUserId, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetActivityAsync(int actorUserId, int top, CancellationToken ct = default);
}

public interface IDashboardService
{
    Task<DashboardSummaryDto> GetSummaryAsync(CurrentUser actor, CancellationToken ct = default);
    Task<DashboardChartsDto> GetChartsAsync(CurrentUser actor, CancellationToken ct = default);
    Task<IReadOnlyList<DashboardWorklistItemDto>> GetWorklistAsync(CurrentUser actor, CancellationToken ct = default);
    Task<IReadOnlyList<DashboardActivityDto>> GetActivityAsync(CurrentUser actor, int top, CancellationToken ct = default);
}

public interface IReportRepository
{
    Task<IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>>> RunAsync(int actorUserId, ReportQuery query, CancellationToken ct = default);
}

public interface IReportService
{
    Task<IReadOnlyList<ReportDefinitionDto>> GetDefinitionsAsync(CurrentUser actor, CancellationToken ct = default);
    Task<ReportResultDto> RunAsync(CurrentUser actor, ReportQuery query, CancellationToken ct = default);
    Task<ReportExportDto> ExportAsync(CurrentUser actor, ReportQuery query, CancellationToken ct = default);
}

public interface IAuditRepository
{
    Task<PagedResult<IDictionary<string, object?>>> SearchAsync(int actorUserId, AuditSearchQuery query, CancellationToken ct = default);
    Task<IReadOnlyList<IDictionary<string, object?>>> GetEntityTimelineAsync(int actorUserId, string entityType, string entityId, CancellationToken ct = default);
}

public interface IAuditService
{
    Task<PagedResult<AuditLogDto>> SearchAsync(CurrentUser actor, AuditSearchQuery query, CancellationToken ct = default);
    Task<IReadOnlyList<AuditLogDto>> GetEntityTimelineAsync(CurrentUser actor, string entityType, string entityId, CancellationToken ct = default);
}
