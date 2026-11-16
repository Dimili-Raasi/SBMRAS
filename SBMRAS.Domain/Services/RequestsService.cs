using System.Globalization;
using FluentValidation;
using SBMRAS.Application.Common;
using SBMRAS.Application.DTOs;
using SBMRAS.Application.Interfaces;
using SBMRAS.Application.Validators;

namespace SBMRAS.Domain.Services;

/// <summary>Blood request + coordination orchestration (contract §4.5, §6). Business rules are enforced by usp_Request_* SPs.</summary>
public sealed class RequestsService(IRequestsRepository repository) : IRequestsService
{
    private static readonly BloodRequestSearchQueryValidator SearchValidator = new();
    private static readonly BloodRequestSaveValidator SaveValidator = new();
    private static readonly BloodRequestCancelValidator CancelValidator = new();
    private static readonly BloodRequestStatusChangeValidator StatusValidator = new();

    public async Task<PagedResult<BloodRequestDto>> SearchAsync(CurrentUser actor, BloodRequestSearchQuery query, CancellationToken cancellationToken = default)
    {
        query ??= new BloodRequestSearchQuery();
        RequestRowMapper.Validate(SearchValidator, query);
        var paged = await repository.SearchAsync(actor.UserId, query with
        {
            Status = RequestRowMapper.Trim(query.Status),
            Urgency = RequestRowMapper.Trim(query.Urgency),
            AboGroup = RequestRowMapper.Trim(query.AboGroup),
            Search = RequestRowMapper.Trim(query.Search),
        }, cancellationToken);
        return new PagedResult<BloodRequestDto>(paged.Items.Select(MapRequest).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    public async Task<BloodRequestDetailDto> GetAsync(CurrentUser actor, int requestId, CancellationToken cancellationToken = default)
    {
        RequestRowMapper.RequireId(requestId, "Blood request");
        var sets = await repository.GetByIdAsync(actor.UserId, requestId, cancellationToken);
        var row = SqlRows.Set(sets, 0).FirstOrDefault() ?? throw AppException.NotFound("Blood request not found.");
        var history = SqlRows.Set(sets, 1).Select(h => new BloodRequestHistoryDto(
            RequestRowMapper.Long(h, "HistoryId"), RequestRowMapper.NStr(h, "FromStatus"), SqlRows.Str(h, "ToStatus"), RequestRowMapper.NStr(h, "Note"),
            RequestRowMapper.NStr(h, "FacilityName"), RequestRowMapper.NStr(h, "ChangedByName"), RequestRowMapper.Date(h, "ChangedAt") ?? default)).ToArray();
        var transitions = SqlRows.Set(sets, 2).Select(t => SqlRows.Str(t, "ToStatus")).Where(s => s.Length > 0).ToArray();
        return new BloodRequestDetailDto(MapRequest(row), history, transitions);
    }

    public async Task<BloodRequestDto> CreateAsync(CurrentUser actor, BloodRequestSaveDto body, string? idempotencyKey,
        CancellationToken cancellationToken = default)
    {
        if (body is null) throw AppException.BadRequest("Request body is required.");
        RequestRowMapper.Validate(SaveValidator, body);
        idempotencyKey = RequestRowMapper.Trim(idempotencyKey);
        if (idempotencyKey is { Length: > BloodRequestValues.MaxIdempotencyKeyLength })
            throw AppException.BadRequest($"Idempotency-Key must not exceed {BloodRequestValues.MaxIdempotencyKeyLength} characters.");

        var normalized = body with
        {
            PatientReference = RequestRowMapper.Trim(body.PatientReference),
            AboGroup = body.AboGroup.Trim(),
            RhFactor = body.RhFactor.Trim(),
            Urgency = body.Urgency.Trim(),
            HospitalName = body.HospitalName.Trim(),
            PreferredFacilityId = body.PreferredFacilityId is > 0 ? body.PreferredFacilityId : null,
            ContactName = body.ContactName.Trim(),
            ContactPhone = body.ContactPhone.Trim(),
            Notes = RequestRowMapper.Trim(body.Notes),
        };
        return MapRequired(await repository.CreateAsync(actor.UserId, normalized, idempotencyKey, cancellationToken));
    }

    public async Task<BloodRequestDto> CancelAsync(CurrentUser actor, int requestId, BloodRequestCancelDto body,
        CancellationToken cancellationToken = default)
    {
        RequestRowMapper.RequireId(requestId, "Blood request");
        body ??= new BloodRequestCancelDto();
        RequestRowMapper.Validate(CancelValidator, body);
        return MapRequired(await repository.CancelAsync(actor.UserId, requestId, RequestRowMapper.Trim(body.Reason), cancellationToken));
    }

    public async Task<BloodRequestDto> ChangeStatusAsync(CurrentUser actor, int requestId, BloodRequestStatusChangeDto body,
        CancellationToken cancellationToken = default)
    {
        RequestRowMapper.RequireId(requestId, "Blood request");
        if (body is null) throw AppException.BadRequest("Request body is required.");
        RequestRowMapper.Validate(StatusValidator, body);
        var rowVersion = RowVersion.FromBase64(body.RowVersion);
        var normalized = body with
        {
            ToStatus = body.ToStatus.Trim(),
            Note = RequestRowMapper.Trim(body.Note),
            MatchedFacilityId = body.MatchedFacilityId is > 0 ? body.MatchedFacilityId : null,
        };
        return MapRequired(await repository.ChangeStatusAsync(actor.UserId, requestId, normalized, rowVersion, cancellationToken));
    }

    public async Task<IReadOnlyList<BloodAvailabilityDto>> GetMatchesAsync(CurrentUser actor, int requestId, CancellationToken cancellationToken = default)
    {
        RequestRowMapper.RequireId(requestId, "Blood request");
        return (await repository.GetMatchesAsync(actor.UserId, requestId, cancellationToken)).Select(MapAvailability).ToArray();
    }

    private static BloodRequestDto MapRequired(IDictionary<string, object?>? row)
        => row is null ? throw AppException.NotFound("Blood request not found.") : MapRequest(row);

    internal static BloodRequestDto MapRequest(IDictionary<string, object?> r) => new(
        SqlRows.Int(r, "RequestId"), SqlRows.Str(r, "RequestNo"), SqlRows.Int(r, "RequesterUserId"), RequestRowMapper.NStr(r, "RequesterName"),
        RequestRowMapper.NStr(r, "PatientReference"), SqlRows.Str(r, "AboGroup"), SqlRows.Str(r, "RhFactor"), SqlRows.Str(r, "BloodGroup"),
        SqlRows.Int(r, "ComponentId"), SqlRows.Str(r, "ComponentCode"), SqlRows.Str(r, "ComponentName"),
        RequestRowMapper.Decimal(r, "QuantityRequested") ?? 0m, SqlRows.Int(r, "UnitId"), SqlRows.Str(r, "UnitCode"), SqlRows.Str(r, "Urgency"),
        RequestRowMapper.Date(r, "NeededBy") ?? default, SqlRows.Int(r, "AreaId"), SqlRows.Str(r, "AreaName"), SqlRows.Str(r, "HospitalName"),
        RequestRowMapper.NInt(r, "PreferredFacilityId"), RequestRowMapper.NStr(r, "PreferredFacilityName"), RequestRowMapper.NInt(r, "MatchedFacilityId"),
        RequestRowMapper.NStr(r, "MatchedFacilityName"), RequestRowMapper.NStr(r, "MatchedFacilityPhone"), SqlRows.Str(r, "ContactName"),
        RequestRowMapper.NStr(r, "ContactPhone"), RequestRowMapper.NStr(r, "Notes"), SqlRows.Str(r, "Status"), RequestRowMapper.NStr(r, "StatusReason"),
        RequestRowMapper.Bool(r, "IsOwner"), RequestRowMapper.Date(r, "CreatedAt") ?? default, RequestRowMapper.Date(r, "UpdatedAt"), RequestRowMapper.RowVer(r, "RowVersion"));

    internal static BloodAvailabilityDto MapAvailability(IDictionary<string, object?> r) => new(
        SqlRows.Int(r, "InventoryId"), SqlRows.Int(r, "FacilityId"), SqlRows.Str(r, "FacilityName"), SqlRows.Str(r, "FacilityType"),
        SqlRows.Int(r, "AreaId"), SqlRows.Str(r, "AreaName"), SqlRows.Str(r, "City"), SqlRows.Str(r, "AddressLine"),
        SqlRows.Str(r, "ContactPhone"), RequestRowMapper.Bool(r, "Is24x7"), SqlRows.Int(r, "ComponentId"), SqlRows.Str(r, "ComponentCode"),
        SqlRows.Str(r, "ComponentName"), SqlRows.Str(r, "AboGroup"), SqlRows.Str(r, "RhFactor"), SqlRows.Str(r, "BloodGroup"),
        RequestRowMapper.Decimal(r, "Quantity") ?? 0m, SqlRows.Str(r, "UnitCode"), SqlRows.Str(r, "AvailabilityStatus"),
        SqlRows.Str(r, "FreshnessStatus"), SqlRows.Str(r, "VerificationStatus"), SqlRows.Str(r, "SourceType"),
        RequestRowMapper.Date(r, "LastUpdatedAt"), RequestRowMapper.Date(r, "ValidUntil"), RequestRowMapper.NInt(r, "MinutesSinceUpdate"),
        RequestRowMapper.Date(r, "EarliestExpiryDate"), RequestRowMapper.Decimal(r, "QualityScore"));
}

/// <summary>In-app notifications of the signed-in user (always scoped to the caller by the SPs).</summary>
public sealed class NotificationsService(INotificationsRepository repository) : INotificationsService
{
    private static readonly NotificationQueryValidator QueryValidator = new();

    public async Task<PagedResult<NotificationDto>> SearchAsync(CurrentUser actor, NotificationQuery query, CancellationToken cancellationToken = default)
    {
        query ??= new NotificationQuery();
        RequestRowMapper.Validate(QueryValidator, query);
        var paged = await repository.SearchAsync(actor.UserId, query, cancellationToken);
        return new PagedResult<NotificationDto>(paged.Items.Select(n => new NotificationDto(
            RequestRowMapper.Long(n, "NotificationId"), SqlRows.Str(n, "Title"), SqlRows.Str(n, "Message"), SqlRows.Str(n, "Type"),
            RequestRowMapper.NStr(n, "EntityType"), RequestRowMapper.NStr(n, "EntityId"), RequestRowMapper.NStr(n, "Route"), RequestRowMapper.Bool(n, "IsRead"),
            RequestRowMapper.Date(n, "CreatedAt") ?? default)).ToArray(), paged.TotalCount, paged.Page, paged.PageSize);
    }

    public async Task<UnreadCountDto> GetUnreadCountAsync(CurrentUser actor, CancellationToken cancellationToken = default)
        => new(await repository.GetUnreadCountAsync(actor.UserId, cancellationToken));

    public async Task<UnreadCountDto> MarkReadAsync(CurrentUser actor, long notificationId, CancellationToken cancellationToken = default)
    {
        if (notificationId <= 0) throw AppException.BadRequest("Notification id is invalid.");
        return new(await repository.MarkReadAsync(actor.UserId, notificationId, cancellationToken));
    }

    public Task<int> MarkAllReadAsync(CurrentUser actor, CancellationToken cancellationToken = default)
        => repository.MarkAllReadAsync(actor.UserId, cancellationToken);
}

/// <summary>Row → DTO conversion helpers for SQL result dictionaries.</summary>
internal static class RequestRowMapper
{
    public static void Validate<T>(IValidator<T> validator, T instance)
    {
        var result = validator.Validate(instance);
        if (!result.IsValid)
            throw AppException.Validation("Validation failed.", result.Errors.Select(e => e.ErrorMessage).Distinct());
    }

    public static int RequireId(int id, string entity)
        => id > 0 ? id : throw AppException.BadRequest($"{entity} id is invalid.");

    public static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    public static string? NStr(IDictionary<string, object?> row, string key)
        => SqlRows.Value(row, key) is null or DBNull ? null : SqlRows.Str(row, key);

    public static int? NInt(IDictionary<string, object?> row, string key) => SqlRows.ToInt(SqlRows.Value(row, key));

    public static long Long(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        null or DBNull => 0,
        long l => l,
        var v when SqlRows.IsNumeric(v) => Convert.ToInt64(v, CultureInfo.InvariantCulture),
        string s when long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var l) => l,
        _ => 0,
    };

    public static decimal? Decimal(IDictionary<string, object?> row, string key) => SqlRows.Dec(SqlRows.Value(row, key));

    public static bool Bool(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        bool b => b,
        null or DBNull => false,
        string s => bool.TryParse(s, out var b) ? b : s == "1",
        var v when SqlRows.IsNumeric(v) => Convert.ToInt64(v, CultureInfo.InvariantCulture) != 0,
        _ => false,
    };

    public static DateTime? Date(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        DateTime d => DateTime.SpecifyKind(d, DateTimeKind.Utc),
        DateTimeOffset o => o.UtcDateTime,
        DateOnly d => DateTime.SpecifyKind(d.ToDateTime(TimeOnly.MinValue), DateTimeKind.Utc),
        string s when DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var d) => d,
        _ => null,
    };

    public static string? RowVer(IDictionary<string, object?> row, string key) => SqlRows.Value(row, key) switch
    {
        byte[] bytes => Convert.ToBase64String(bytes),
        string s when s.Length > 0 => s,
        _ => null,
    };
}
