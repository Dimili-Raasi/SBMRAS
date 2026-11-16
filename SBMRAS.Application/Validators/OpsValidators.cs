using FluentValidation;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Validators;

internal static class OpsRules
{
    public static bool BeBase64RowVersion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        Span<byte> buffer = stackalloc byte[64];
        return Convert.TryFromBase64String(value.Trim(), buffer, out var written) && written > 0 && written <= 8;
    }

    public static bool BeWithinValidityWindow(DateTime? value, TimeProvider time)
    {
        if (value is null) return true;
        var utc = value.Value.Kind switch
        {
            DateTimeKind.Utc => value.Value,
            DateTimeKind.Local => value.Value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(value.Value, DateTimeKind.Utc),
        };
        var now = time.GetUtcNow().UtcDateTime;
        return utc > now && utc <= now.AddDays(InventoryValues.MaxValidityDays).AddMinutes(5);
    }
}

public sealed class FacilitySearchQueryValidator : AbstractValidator<FacilitySearchQuery>
{
    public FacilitySearchQueryValidator()
    {
        RuleFor(x => x.FacilityType).Must(v => FacilityValues.FacilityTypes.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.FacilityType)).WithMessage("Facility type must be Hospital or BloodBank.");
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class FacilityUpdateValidator : AbstractValidator<FacilityUpdateDto>
{
    public FacilityUpdateValidator()
    {
        RuleFor(x => x.Name).NotEmpty().WithMessage("Facility name is required.").MaximumLength(200);
        RuleFor(x => x.LicenseNo).MaximumLength(50);
        RuleFor(x => x.AddressLine).NotEmpty().WithMessage("Address is required.").MaximumLength(300);
        RuleFor(x => x.AreaId).GreaterThan(0).WithMessage("Area is required.");
        RuleFor(x => x.City).NotEmpty().WithMessage("City is required.").MaximumLength(100);
        RuleFor(x => x.Pincode).MaximumLength(10);
        RuleFor(x => x.Latitude).InclusiveBetween(-90m, 90m).When(x => x.Latitude.HasValue);
        RuleFor(x => x.Longitude).InclusiveBetween(-180m, 180m).When(x => x.Longitude.HasValue);
        RuleFor(x => x.ContactPhone).NotEmpty().WithMessage("Contact phone is required.").MaximumLength(30)
            .Matches(BloodRequestValues.PhonePattern).WithMessage("Contact phone must be a valid phone number.");
        RuleFor(x => x.ContactEmail).MaximumLength(320).EmailAddress().When(x => !string.IsNullOrWhiteSpace(x.ContactEmail));
        RuleFor(x => x.RowVersion).NotEmpty().WithMessage("Row version is required.")
            .Must(OpsRules.BeBase64RowVersion).WithMessage("Row version is not valid.");
    }
}

public sealed class InventoryHistoryQueryValidator : AbstractValidator<InventoryHistoryQuery>
{
    public InventoryHistoryQueryValidator()
    {
        RuleFor(x => x.Kind).Must(v => FacilityValues.InventoryKinds.Contains(v, StringComparer.OrdinalIgnoreCase))
            .When(x => !string.IsNullOrWhiteSpace(x.Kind)).WithMessage("Kind must be Blood or Resource.");
        RuleFor(x => x.Top).InclusiveBetween(1, FacilityValues.MaxHistoryTop).When(x => x.Top.HasValue);
    }
}

public sealed class ResourceUpdateValidator : AbstractValidator<ResourceUpdateDto>
{
    public ResourceUpdateValidator(TimeProvider? clock = null)
    {
        var time = clock ?? TimeProvider.System;
        RuleFor(x => x.ResourceTypeId).GreaterThan(0).WithMessage("Resource type is required.");
        RuleFor(x => x.TotalQuantity).GreaterThanOrEqualTo(0).WithMessage("Total quantity cannot be negative.");
        RuleFor(x => x.AvailableQuantity).GreaterThanOrEqualTo(0).WithMessage("Available quantity cannot be negative.")
            .LessThanOrEqualTo(x => x.TotalQuantity).WithMessage("Available quantity cannot exceed total quantity.");
        RuleFor(x => x.OperationalStatus).NotEmpty().Must(v => InventoryValues.OperationalStatuses.Contains(v))
            .WithMessage("Operational status must be Available, Limited, Unavailable or Unknown.");
        RuleFor(x => x.ValidUntil).Must(v => OpsRules.BeWithinValidityWindow(v, time))
            .WithMessage("Valid-until must be in the future and within 7 days.");
        RuleFor(x => x.Notes).MaximumLength(InventoryValues.MaxNotesLength);
        RuleFor(x => x.Reason).MaximumLength(InventoryValues.MaxReasonLength);
        RuleFor(x => x.RowVersion).Must(OpsRules.BeBase64RowVersion).WithMessage("Row version is not valid.");
    }
}

public sealed class BloodStockUpdateValidator : AbstractValidator<BloodStockUpdateDto>
{
    public BloodStockUpdateValidator(TimeProvider? clock = null)
    {
        var time = clock ?? TimeProvider.System;
        RuleFor(x => x.ComponentId).GreaterThan(0).WithMessage("Blood component is required.");
        RuleFor(x => x.AboGroup).NotEmpty().Must(v => InventoryValues.AboGroups.Contains(v))
            .WithMessage("ABO group must be A, B, AB or O.");
        RuleFor(x => x.RhFactor).NotEmpty().Must(v => InventoryValues.RhFactors.Contains(v))
            .WithMessage("Rh factor must be Positive or Negative.");
        RuleFor(x => x.Quantity).GreaterThanOrEqualTo(0).WithMessage("Quantity cannot be negative.");
        RuleFor(x => x.ValidUntil).Must(v => OpsRules.BeWithinValidityWindow(v, time))
            .WithMessage("Valid-until must be in the future and within 7 days.");
        RuleFor(x => x.Reason).MaximumLength(InventoryValues.MaxReasonLength);
        RuleFor(x => x.RowVersion).Must(OpsRules.BeBase64RowVersion).WithMessage("Row version is not valid.");
    }
}

public sealed class BloodStockConfirmValidator : AbstractValidator<BloodStockConfirmDto>
{
    public BloodStockConfirmValidator()
    {
        RuleFor(x => x.InventoryIds).NotNull().NotEmpty().WithMessage("Select at least one stock row to confirm.")
            .Must(ids => ids.Count <= InventoryValues.MaxConfirmIds).WithMessage("Too many rows selected.");
        RuleForEach(x => x.InventoryIds).GreaterThan(0).WithMessage("Inventory id is not valid.");
    }
}

public sealed class InventoryChangeSearchQueryValidator : AbstractValidator<InventoryChangeSearchQuery>
{
    public InventoryChangeSearchQueryValidator()
    {
        RuleFor(x => x.Status).Must(v => InventoryValues.ChangeStatuses.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.Status)).WithMessage("Status is not valid.");
        RuleFor(x => x.InventoryKind).Must(v => FacilityValues.InventoryKinds.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.InventoryKind)).WithMessage("Inventory kind must be Blood or Resource.");
        RuleFor(x => x.FacilityId).GreaterThan(0).When(x => x.FacilityId.HasValue);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class InventoryChangeDecisionValidator : AbstractValidator<InventoryChangeDecisionDto>
{
    public InventoryChangeDecisionValidator()
    {
        RuleFor(x => x.Decision).NotEmpty().Must(v => InventoryValues.Decisions.Contains(v))
            .WithMessage("Decision must be Approve or Reject.");
        RuleFor(x => x.Reason).NotEmpty().When(x => x.Decision == "Reject")
            .WithMessage("A reason is required to reject a change.");
        RuleFor(x => x.Reason).MaximumLength(InventoryValues.MaxReasonLength);
    }
}

public sealed class ImportSearchQueryValidator : AbstractValidator<ImportSearchQuery>
{
    public ImportSearchQueryValidator()
    {
        RuleFor(x => x.Status).Must(v => ImportValues.Statuses.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.Status)).WithMessage("Status is not valid.");
        RuleFor(x => x.FacilityId).GreaterThan(0).When(x => x.FacilityId.HasValue);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class ImportCreateValidator : AbstractValidator<ImportCreateDto>
{
    public ImportCreateValidator(int maxRows = ImportValues.DefaultMaxRows)
    {
        var limit = maxRows > 0 ? maxRows : ImportValues.DefaultMaxRows;
        RuleFor(x => x.FacilityId).GreaterThan(0).WithMessage("Facility is required.");
        RuleFor(x => x.InventoryKind).NotEmpty().Must(v => ImportValues.InventoryKinds.Contains(v))
            .WithMessage("Inventory kind must be Blood or Resource.");
        RuleFor(x => x.FileName).NotEmpty().WithMessage("File name is required.").MaximumLength(ImportValues.MaxFileNameLength);
        RuleFor(x => x.FileHash).NotEmpty().WithMessage("File hash is required.").MaximumLength(ImportValues.MaxFileHashLength);
        RuleFor(x => x.Rows).NotNull().NotEmpty().WithMessage("The file contains no data rows.")
            .Must(r => r.Count <= limit).WithMessage($"A batch may contain at most {limit} rows.")
            .Must(r => r.Select(x => x.RowNumber).Distinct().Count() == r.Count).WithMessage("Row numbers must be unique.");
        RuleForEach(x => x.Rows).ChildRules(row =>
        {
            row.RuleFor(r => r.RowNumber).GreaterThan(0).WithMessage("Row number must be positive.");
            row.RuleFor(r => r.RawData).MaximumLength(ImportValues.MaxRawDataLength);
        });
    }
}

public sealed class DataQualityIssueQueryValidator : AbstractValidator<DataQualityIssueQuery>
{
    public DataQualityIssueQueryValidator()
    {
        RuleFor(x => x.Status).Must(v => DataQualityValues.IssueStatuses.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.Status)).WithMessage("Status is not valid.");
        RuleFor(x => x.Severity).Must(v => DataQualityValues.Severities.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.Severity)).WithMessage("Severity is not valid.");
        RuleFor(x => x.IssueCode).Must(v => DataQualityValues.IssueCodes.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.IssueCode)).WithMessage("Issue code is not valid.");
        RuleFor(x => x.FacilityId).GreaterThan(0).When(x => x.FacilityId.HasValue);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class DataQualityResolveValidator : AbstractValidator<DataQualityResolveDto>
{
    public DataQualityResolveValidator()
    {
        RuleFor(x => x.Resolution).NotEmpty().WithMessage("A resolution note is required.")
            .MaximumLength(DataQualityValues.MaxResolutionLength);
    }
}

public sealed class DataQualityScanValidator : AbstractValidator<DataQualityScanDto>
{
    public DataQualityScanValidator() => RuleFor(x => x.FacilityId).GreaterThan(0).When(x => x.FacilityId.HasValue);
}
