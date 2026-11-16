using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace SBMRAS.Infrastructure.Database;

public interface ISqlDbConnectionFactory
{
    SqlConnection CreateConnection();
}

public sealed class SqlDbConnectionFactory : ISqlDbConnectionFactory
{
    // Retries only opening the connection (e.g. 40613 while a serverless database resumes); commands are never re-run.
    private static readonly SqlRetryLogicBaseProvider OpenRetry = SqlConfigurableRetryFactory.CreateExponentialRetryProvider(
        new SqlRetryLogicOption
        {
            NumberOfTries = 6,
            DeltaTime = TimeSpan.FromSeconds(2),
            MaxTimeInterval = TimeSpan.FromSeconds(20),
        });

    private readonly string _connectionString;

    public SqlDbConnectionFactory(IConfiguration configuration)
    {
        _connectionString = configuration["SqlConnectionString"]
            ?? throw new InvalidOperationException("Configuration value 'SqlConnectionString' is required.");
    }

    public SqlConnection CreateConnection() => new(_connectionString) { RetryLogicProvider = OpenRetry };
}
