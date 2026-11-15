using System.Collections;
using System.Globalization;
using SBMRAS.Application.Common;

namespace SBMRAS.Application.Interfaces;

/// <summary>
/// Normalises the loosely-typed results of <see cref="IStoredProcedureExecutor"/> into row dictionaries
/// (keys = SQL column names, case-insensitive) used by the Public/Requests/Insights repositories and services.
/// </summary>
public static class SqlRows
{
    public static IDictionary<string, object?>? AsRow(object? value) => value switch
    {
        null => null,
        IDictionary<string, object?> map => new Dictionary<string, object?>(map, StringComparer.OrdinalIgnoreCase),
        IDictionary legacy => legacy.Keys.Cast<object>()
            .ToDictionary(k => Convert.ToString(k, CultureInfo.InvariantCulture)!, k => legacy[k], StringComparer.OrdinalIgnoreCase),
        IEnumerable sequence and not string => AsRows(sequence).FirstOrDefault(),
        _ => null,
    };

    public static IReadOnlyList<IDictionary<string, object?>> AsRows(object? value) => value switch
    {
        null => [],
        IDictionary<string, object?> or IDictionary => [AsRow(value)!],
        IEnumerable sequence and not string => sequence.Cast<object?>().Select(AsRow).OfType<IDictionary<string, object?>>().ToArray(),
        _ => [],
    };

    public static IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>> AsSets(object? value) => value switch
    {
        null => [],
        IEnumerable sequence and not string and not IDictionary => sequence.Cast<object?>().Select(AsRows).ToArray(),
        _ => [],
    };

    public static IReadOnlyList<IDictionary<string, object?>> Set(IReadOnlyList<IReadOnlyList<IDictionary<string, object?>>> sets, int index)
        => index >= 0 && index < sets.Count ? sets[index] : [];

    /// <summary>Accepts PagedResult&lt;T&gt;, an anonymous { items, totalCount, page, pageSize } or a dictionary.</summary>
    public static PagedResult<IDictionary<string, object?>> AsPaged(object? value, int page, int pageSize)
    {
        if (value is null) return new PagedResult<IDictionary<string, object?>>([], 0, page, pageSize);
        object? items, total, pg, size;
        if (value is IDictionary<string, object?> map)
        {
            var row = new Dictionary<string, object?>(map, StringComparer.OrdinalIgnoreCase);
            row.TryGetValue("Items", out items); row.TryGetValue("TotalCount", out total);
            row.TryGetValue("Page", out pg); row.TryGetValue("PageSize", out size);
        }
        else
        {
            var props = value.GetType().GetProperties();
            object? Get(string name) => props.FirstOrDefault(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))?.GetValue(value);
            items = Get("Items"); total = Get("TotalCount"); pg = Get("Page"); size = Get("PageSize");
        }
        return new PagedResult<IDictionary<string, object?>>(AsRows(items), ToInt(total) ?? 0, ToInt(pg) ?? page, ToInt(size) ?? pageSize);
    }

    public static object? Value(IDictionary<string, object?>? row, string key)
    {
        if (row is null) return null;
        if (row.TryGetValue(key, out var direct)) return direct;
        return row.FirstOrDefault(x => string.Equals(x.Key, key, StringComparison.OrdinalIgnoreCase)).Value;
    }

    public static string Str(IDictionary<string, object?>? row, string key)
        => Convert.ToString(Value(row, key), CultureInfo.InvariantCulture) ?? "";

    public static int Int(IDictionary<string, object?>? row, string key) => ToInt(Value(row, key)) ?? 0;

    public static decimal? Dec(object? value) => value switch
    {
        null or DBNull => null,
        decimal d => d,
        double or float or int or long or short or byte => Convert.ToDecimal(value, CultureInfo.InvariantCulture),
        string s when decimal.TryParse(s, NumberStyles.Number, CultureInfo.InvariantCulture, out var d) => d,
        _ => null,
    };

    public static int? ToInt(object? value) => value switch
    {
        null or DBNull => null,
        int i => i,
        long or short or byte or decimal or double or float => Convert.ToInt32(value, CultureInfo.InvariantCulture),
        string s when int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var i) => i,
        _ => null,
    };

    public static bool IsNumeric(object? value) => value is byte or short or int or long or decimal or double or float;

    /// <summary>Converts a base64 ROWVERSION from JSON into VARBINARY(8) bytes; null/empty → null.</summary>
    public static byte[]? RowVersionBytes(string? base64)
    {
        if (string.IsNullOrWhiteSpace(base64)) return null;
        try { return Convert.FromBase64String(base64.Trim()); }
        catch (FormatException) { throw AppException.Validation("Row version is not valid."); }
    }
}
