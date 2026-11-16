using FluentValidation;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Validators;

public sealed class ReportQueryValidator : AbstractValidator<ReportQuery>
{
    public ReportQueryValidator()
    {
        RuleFor(x => x.Code).NotEmpty().Must(v => ReportCodes.All.Contains(v, StringComparer.OrdinalIgnoreCase))
            .WithMessage("Report code is not valid.");
        RuleFor(x => x.ToDate).GreaterThanOrEqualTo(x => x.FromDate)
            .When(x => x.FromDate.HasValue && x.ToDate.HasValue).WithMessage("To date must be on or after from date.");
    }
}

public sealed class AuditSearchQueryValidator : AbstractValidator<AuditSearchQuery>
{
    public AuditSearchQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.EntityType).MaximumLength(50);
        RuleFor(x => x.Action).MaximumLength(50);
        RuleFor(x => x.CorrelationId).MaximumLength(64);
        RuleFor(x => x.ToDate).GreaterThanOrEqualTo(x => x.FromDate)
            .When(x => x.FromDate.HasValue && x.ToDate.HasValue).WithMessage("To date must be on or after from date.");
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}

public sealed class NotificationQueryValidator : AbstractValidator<NotificationQuery>
{
    public NotificationQueryValidator()
    {
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, PublicValues.MaxPageSize);
    }
}
