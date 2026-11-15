using FluentValidation;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Validators;

/// <summary>Mirrors usp_Request_Create checks (09_StoredProcedures_Public_Requests.sql).</summary>
public sealed class BloodRequestSaveValidator : AbstractValidator<BloodRequestSaveDto>
{
    public BloodRequestSaveValidator(TimeProvider? clock = null)
    {
        var time = clock ?? TimeProvider.System;
        RuleFor(x => x.PatientReference).MaximumLength(50);
        RuleFor(x => x.AboGroup).NotEmpty().Must(v => BloodRequestValues.AboGroups.Contains(v))
            .WithMessage("ABO group must be A, B, AB or O.");
        RuleFor(x => x.RhFactor).NotEmpty().Must(v => BloodRequestValues.RhFactors.Contains(v))
            .WithMessage("Rh factor must be Positive or Negative.");
        RuleFor(x => x.ComponentId).GreaterThan(0).WithMessage("Blood component is required.");
        RuleFor(x => x.QuantityRequested).GreaterThan(0).LessThanOrEqualTo(BloodRequestValues.MaxQuantity)
            .WithMessage("Quantity requested must be greater than 0 and not more than 50.");
        RuleFor(x => x.UnitId).GreaterThan(0).WithMessage("Unit is required.");
        RuleFor(x => x.Urgency).NotEmpty().Must(v => BloodRequestValues.Urgencies.Contains(v))
            .WithMessage("Urgency must be Routine, Urgent or Emergency.");
        RuleFor(x => x.NeededBy).Must(v => ToUtc(v) > time.GetUtcNow().UtcDateTime)
            .WithMessage("Needed-by date must be in the future.");
        RuleFor(x => x.AreaId).GreaterThan(0).WithMessage("Area is required.");
        RuleFor(x => x.HospitalName).NotEmpty().WithMessage("Hospital name is required.").MaximumLength(200);
        RuleFor(x => x.PreferredFacilityId).GreaterThan(0).When(x => x.PreferredFacilityId.HasValue && x.PreferredFacilityId != 0);
        RuleFor(x => x.ContactName).NotEmpty().WithMessage("Contact name is required.").MaximumLength(150);
        RuleFor(x => x.ContactPhone).NotEmpty().WithMessage("Contact phone is required.").MaximumLength(30)
            .Matches(BloodRequestValues.PhonePattern).WithMessage("Contact phone must be a valid phone number.");
        RuleFor(x => x.ContactConsent).Equal(true).WithMessage("Contact consent is required to submit a blood request.");
        RuleFor(x => x.Notes).MaximumLength(1000);
    }

    private static DateTime ToUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };
}

public sealed class BloodRequestCancelValidator : AbstractValidator<BloodRequestCancelDto>
{
    public BloodRequestCancelValidator() => RuleFor(x => x.Reason).MaximumLength(500);
}

public sealed class BloodRequestStatusChangeValidator : AbstractValidator<BloodRequestStatusChangeDto>
{
    public BloodRequestStatusChangeValidator()
    {
        RuleFor(x => x.ToStatus).NotEmpty().Must(v => BloodRequestValues.Statuses.Contains(v))
            .WithMessage("Target status is not valid.");
        RuleFor(x => x.Note).MaximumLength(500);
        RuleFor(x => x.MatchedFacilityId).NotNull().GreaterThan(0)
            .When(x => x.ToStatus == "Matched").WithMessage("A matched facility is required for status Matched.");
        RuleFor(x => x.RowVersion).Must(BeBase64).When(x => !string.IsNullOrWhiteSpace(x.RowVersion))
            .WithMessage("Row version is not valid.");
    }

    private static bool BeBase64(string? value)
    {
        var buffer = new Span<byte>(new byte[64]);
        return Convert.TryFromBase64String(value!, buffer, out _);
    }
}

public sealed class BloodRequestSearchQueryValidator : AbstractValidator<BloodRequestSearchQuery>
{
    public BloodRequestSearchQueryValidator()
    {
        RuleFor(x => x.Scope).Must(v => BloodRequestValues.Scopes.Contains(v, StringComparer.OrdinalIgnoreCase))
            .When(x => !string.IsNullOrWhiteSpace(x.Scope)).WithMessage("Scope must be mine or all.");
        RuleFor(x => x.Status).Must(v => BloodRequestValues.Statuses.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.Status)).WithMessage("Status is not valid.");
        RuleFor(x => x.Urgency).Must(v => BloodRequestValues.Urgencies.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.Urgency)).WithMessage("Urgency is not valid.");
        RuleFor(x => x.AboGroup).Must(v => BloodRequestValues.AboGroups.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.AboGroup)).WithMessage("ABO group must be A, B, AB or O.");
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}
