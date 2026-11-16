using FluentValidation;
using SBMRAS.Application.Constants;
using SBMRAS.Application.DTOs;

namespace SBMRAS.Application.Validators;

/// <summary>Mirrors usp_Admin_SearchUsers inputs (11_StoredProcedures_Admin.sql).</summary>
public sealed class AdminUserSearchQueryValidator : AbstractValidator<AdminUserSearchQuery>
{
    public AdminUserSearchQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.RoleCode).MaximumLength(50);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 100);
    }
}

/// <summary>Mirrors usp_Admin_SaveUser checks.</summary>
public sealed class UserSaveValidator : AbstractValidator<UserSaveDto>
{
    public UserSaveValidator()
    {
        RuleFor(x => x.DisplayName).NotEmpty().WithMessage("Display name is required.").MaximumLength(150);
        RuleFor(x => x.GivenName).MaximumLength(100);
        RuleFor(x => x.FamilyName).MaximumLength(100);
        RuleFor(x => x.Email).NotEmpty().WithMessage("E-mail is required.").MaximumLength(320)
            .Matches(AdminValues.EmailPattern).WithMessage("A valid e-mail address is required.");
        RuleFor(x => x.Phone).MaximumLength(30)
            .Matches(AdminValues.PhonePattern).When(x => !string.IsNullOrWhiteSpace(x.Phone))
            .WithMessage("Phone must be a valid phone number.");
        RuleFor(x => x.OrganizationName).MaximumLength(200);
        RuleFor(x => x.AreaId).GreaterThan(0).When(x => x.AreaId.HasValue).WithMessage("Select a valid area.");
        RuleForEach(x => x.RoleCodes)
            .Must(code => Roles.All.Contains(code))
            .WithMessage("Role '{PropertyValue}' is not valid.");
        RuleFor(x => x.RoleCodes).Must(r => r is null || string.Join(',', r).Length <= 400)
            .WithMessage("Too many roles.");
    }
}

public sealed class UserStatusValidator : AbstractValidator<UserStatusDto>
{
    public UserStatusValidator() => RuleFor(x => x.IsActive).NotNull().WithMessage("isActive is required.");
}

/// <summary>Mirrors usp_Admin_SetUserFacilities checks.</summary>
public sealed class UserFacilitiesValidator : AbstractValidator<UserFacilitiesDto>
{
    public UserFacilitiesValidator()
    {
        RuleFor(x => x.Assignments).NotNull().WithMessage("Assignments are required (use an empty list to remove all).");
        RuleForEach(x => x.Assignments).ChildRules(a =>
        {
            a.RuleFor(x => x.FacilityId).GreaterThan(0).WithMessage("Each assignment requires a facility.");
            a.RuleFor(x => x.AssignmentRole).Must(r => AdminValues.AssignmentRoles.Contains(r))
                .WithMessage("Assignment role must be Manager, Operator or Verifier.");
        });
        RuleFor(x => x.Assignments)
            .Must(list => list is null || list.Select(a => a.FacilityId).Distinct().Count() == list.Count)
            .WithMessage("A facility can only be assigned once per user.");
    }
}

public sealed class RolePermissionsValidator : AbstractValidator<RolePermissionsDto>
{
    public RolePermissionsValidator()
    {
        RuleFor(x => x.PermissionCodes).NotNull().WithMessage("permissionCodes is required.");
        RuleForEach(x => x.PermissionCodes)
            .Must(code => Permissions.All.Contains(code))
            .WithMessage("Permission '{PropertyValue}' is not valid.");
    }
}

public sealed class AdminFacilitySearchQueryValidator : AbstractValidator<AdminFacilitySearchQuery>
{
    public AdminFacilitySearchQueryValidator()
    {
        RuleFor(x => x.Status).Must(s => AdminValues.FacilityStatuses.Contains(s))
            .When(x => !string.IsNullOrWhiteSpace(x.Status)).WithMessage("Status is not valid.");
        RuleFor(x => x.FacilityType).Must(t => PublicValues.FacilityTypes.Contains(t))
            .When(x => !string.IsNullOrWhiteSpace(x.FacilityType)).WithMessage("Facility type must be Hospital or BloodBank.");
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 100);
    }
}

/// <summary>Mirrors usp_Facility_AdminSave checks. Facility type is mandatory on create (see <see cref="FacilityCreateValidator"/>).</summary>
public class FacilitySaveValidator : AbstractValidator<FacilitySaveDto>
{
    public FacilitySaveValidator()
    {
        RuleFor(x => x.FacilityType).Must(t => PublicValues.FacilityTypes.Contains(t))
            .When(x => !string.IsNullOrWhiteSpace(x.FacilityType)).WithMessage("Facility type must be Hospital or BloodBank.");
        RuleFor(x => x.Name).NotEmpty().WithMessage("Facility name is required.").MaximumLength(200);
        RuleFor(x => x.LicenseNo).MaximumLength(60);
        RuleFor(x => x.AddressLine).NotEmpty().WithMessage("Address is required.").MaximumLength(300);
        RuleFor(x => x.AreaId).GreaterThan(0).WithMessage("Select a valid area.");
        RuleFor(x => x.City).MaximumLength(100);
        RuleFor(x => x.Pincode).MaximumLength(10);
        RuleFor(x => x.Latitude).InclusiveBetween(-90m, 90m).When(x => x.Latitude.HasValue);
        RuleFor(x => x.Longitude).InclusiveBetween(-180m, 180m).When(x => x.Longitude.HasValue);
        RuleFor(x => x.ContactPhone).NotEmpty().WithMessage("Contact phone is required.").MaximumLength(30)
            .Matches(AdminValues.PhonePattern).WithMessage("Contact phone must be a valid phone number.");
        RuleFor(x => x.ContactEmail).MaximumLength(320)
            .Matches(AdminValues.EmailPattern).When(x => !string.IsNullOrWhiteSpace(x.ContactEmail))
            .WithMessage("Contact e-mail is not valid.");
        RuleFor(x => x.RowVersion).Must(BeBase64).When(x => !string.IsNullOrWhiteSpace(x.RowVersion))
            .WithMessage("Row version is not valid.");
    }

    private static bool BeBase64(string? value) => Convert.TryFromBase64String(value!.Trim(), new byte[64], out _);
}

public sealed class FacilityCreateValidator : FacilitySaveValidator
{
    public FacilityCreateValidator()
        => RuleFor(x => x.FacilityType).NotEmpty().WithMessage("Facility type must be Hospital or BloodBank.");
}

public sealed class FacilityVerifyValidator : AbstractValidator<FacilityVerifyDto>
{
    public FacilityVerifyValidator()
    {
        RuleFor(x => x.Decision).Must(d => AdminValues.VerifyDecisions.Contains(d))
            .WithMessage("Decision must be Verify, Reject, Suspend or Reactivate.");
        RuleFor(x => x.Notes).NotEmpty().When(x => x.Decision is "Reject" or "Suspend")
            .WithMessage("Notes are required to reject or suspend a facility.");
        RuleFor(x => x.Notes).MaximumLength(500);
    }
}

public sealed class SettingsUpdateValidator : AbstractValidator<SettingsUpdateDto>
{
    public SettingsUpdateValidator()
    {
        RuleFor(x => x.Settings).NotEmpty().WithMessage("At least one setting is required.");
        RuleForEach(x => x.Settings).ChildRules(s =>
        {
            s.RuleFor(x => x.SettingKey).NotEmpty().WithMessage("Each setting requires a key.").MaximumLength(100);
            s.RuleFor(x => x.SettingValue).NotNull().WithMessage("Each setting requires a value.").MaximumLength(400);
        });
        RuleFor(x => x.Settings)
            .Must(list => list is null || list.Select(s => s.SettingKey).Distinct(StringComparer.OrdinalIgnoreCase).Count() == list.Count)
            .WithMessage("A setting key appears more than once.");
    }
}
