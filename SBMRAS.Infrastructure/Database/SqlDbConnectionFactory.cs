using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace SBMRAS.Infrastructure.Database;

public interface ISqlDbConnectionFactory
{
    SqlConnection CreateConnection();
}

public sealed class SqlDbConnectionFactory : ISqlDbConnectionFactory
{
    private readonly string _connectionString;

    public SqlDbConnectionFactory(IConfiguration configuration)
    {
        _connectionString = configuration["SqlConnectionString"]
            ?? throw new InvalidOperationException("Configuration value 'SqlConnectionString' is required.");
    }

    public SqlConnection CreateConnection() => new(_connectionString);
}
