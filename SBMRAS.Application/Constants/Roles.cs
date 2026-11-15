namespace SBMRAS.Application.Constants;

public static class Roles
{
    public const string PublicUser = "PublicUser";
    public const string HospitalManagement = "HospitalManagement";
    public const string BloodBank = "BloodBank";
    public const string Admin = "Admin";

    public static readonly IReadOnlyList<string> All = [PublicUser, HospitalManagement, BloodBank, Admin];

    /// <summary>Roles that may be granted from Entra app roles / security groups.</summary>
    public static readonly IReadOnlyList<string> EntraAssignable = [HospitalManagement, BloodBank, Admin];
}
