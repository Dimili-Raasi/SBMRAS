using FluentValidation;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Validators;

public sealed class BloodAvailabilityQueryValidator : AbstractValidator<BloodAvailabilityQuery>
{
    public BloodAvailabilityQueryValidator()
    {
        RuleFor(x => x.AboGroup).Must(v => BloodRequestValues.AboGroups.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.AboGroup)).WithMessage("ABO group must be A, B, AB or O.");
        RuleFor(x => x.RhFactor).Must(v => BloodRequestValues.RhFactors.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.RhFactor)).WithMessage("Rh factor must be Positive or Negative.");
        RuleFor(x => x.MinQuantity).GreaterThanOrEqualTo(0).When(x => x.MinQuantity.HasValue);
        RuleFor(x => x.Search).MaximumLength(PublicValues.MaxSearchLength);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class ResourceAvailabilityQueryValidator : AbstractValidator<ResourceAvailabilityQuery>
{
    public ResourceAvailabilityQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(PublicValues.MaxSearchLength);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class PublicFacilityQueryValidator : AbstractValidator<PublicFacilityQuery>
{
    public PublicFacilityQueryValidator()
    {
        RuleFor(x => x.FacilityType).Must(v => PublicValues.FacilityTypes.Contains(v))
            .When(x => !string.IsNullOrWhiteSpace(x.FacilityType)).WithMessage("Facility type must be Hospital or BloodBank.");
        RuleFor(x => x.Search).MaximumLength(PublicValues.MaxSearchLength);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}
