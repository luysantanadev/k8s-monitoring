using Api.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Api.Extensions;

internal static class DatabaseExtensions
{
    /// <summary>
    /// Registra o AppDbContext com pool de conexões Npgsql.
    /// Lê credenciais exclusivamente de variáveis de ambiente:
    ///   PG_HOST, PG_PORT, PG_DATABASE, PG_USER, PG_PASSWD
    /// </summary>
    internal static WebApplicationBuilder AddDatabase(this WebApplicationBuilder builder)
    {
        var host     = Environment.GetEnvironmentVariable("PG_HOST")     ?? "localhost";
        var port     = Environment.GetEnvironmentVariable("PG_PORT")     ?? "5432";
        var database = Environment.GetEnvironmentVariable("PG_DATABASE") ?? "monitoring";
        var user     = Environment.GetEnvironmentVariable("PG_USER")     ?? "postgres";
        var password = Environment.GetEnvironmentVariable("PG_PASSWD")   ?? string.Empty;

        // NpgsqlDataSourceBuilder permite configurar o pool e desativar TLS antes de criar o DataSource.
        // O DataSource é registrado como singleton e compartilhado entre todas as instâncias do pool.
        var dataSourceBuilder = new NpgsqlDataSourceBuilder()
        {
            ConnectionStringBuilder =
            {
                Host            = host,
                Port            = int.Parse(port),
                Database        = database,
                Username        = user,
                Password        = password,
                // Sem TLS: conexão local dentro do cluster / localhost
                SslMode         = SslMode.Disable,
                // Pool de conexões
                Pooling         = true,
                MinPoolSize     = 2,
                MaxPoolSize     = 50,
                ConnectionIdleLifetime    = 300,  // segundos
                ConnectionPruningInterval = 10,
                // Timeout de aquisição de conexão do pool
                Timeout        = 30,
                CommandTimeout = 30,
            }
        };

        // Filtra spans internos de heartbeat/health do Npgsql para não poluir o Tempo.
        dataSourceBuilder.ConfigureTracing(tracing =>
            tracing.ConfigureCommandFilter(cmd =>
                !cmd.CommandText.StartsWith("-- health", StringComparison.OrdinalIgnoreCase)));

        var dataSource = dataSourceBuilder.Build();

        // AddDbContextPool reutiliza instâncias do DbContext (recomendado para APIs de alta carga).
        // O tamanho padrão do pool é 1024; ajuste via poolSize se necessário.
        builder.Services.AddDbContextPool<AppDbContext>(options =>
        {
            options.UseNpgsql(dataSource, npgsql =>
            {
                // Retry automático em falhas transientes (ex: restart do pod do Postgres)
                npgsql.EnableRetryOnFailure(
                    maxRetryCount: 5,
                    maxRetryDelay: TimeSpan.FromSeconds(10),
                    errorCodesToAdd: null);

                npgsql.CommandTimeout(30);
            });

            // Em desenvolvimento, loga queries SQL e habilita verificações detalhadas
            if (builder.Environment.IsDevelopment())
            {
                options.EnableSensitiveDataLogging();
                options.EnableDetailedErrors();
            }
        });

        // Health check: testa conectividade real com o banco (usado pelo endpoint /ready)
        builder.Services.AddHealthChecks()
            .AddDbContextCheck<AppDbContext>(
                name: "postgres",
                tags: ["ready", "db"]);

        return builder;
    }

    /// <summary>
    /// Aplica migrations pendentes na inicialização.
    /// Seguro para ambientes com múltiplas réplicas: EF Core usa lock no banco.
    /// </summary>
    internal static async Task MigrateDatabaseAsync(this WebApplication app)
    {
        await using var scope = app.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();
    }
}
