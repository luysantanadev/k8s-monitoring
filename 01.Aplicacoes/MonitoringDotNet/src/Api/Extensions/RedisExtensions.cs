using Microsoft.Extensions.Diagnostics.HealthChecks;
using StackExchange.Redis;

namespace Api.Extensions;

internal static class RedisExtensions
{
    /// <summary>
    /// Registra IConnectionMultiplexer como singleton e health check do Redis.
    /// Lê configuração exclusivamente de variáveis de ambiente:
    ///   REDIS_HOST, REDIS_PORT, REDIS_PASSWORD (opcional)
    /// </summary>
    internal static WebApplicationBuilder AddRedis(this WebApplicationBuilder builder)
    {
        var host     = Environment.GetEnvironmentVariable("REDIS_HOST")     ?? "localhost";
        var port     = int.Parse(Environment.GetEnvironmentVariable("REDIS_PORT") ?? "6379");
        var password = Environment.GetEnvironmentVariable("REDIS_PASSWORD");

        var options = new ConfigurationOptions
        {
            EndPoints           = { { host, port } },
            // Sem TLS: conexão local dentro do cluster
            Ssl                 = false,
            AbortOnConnectFail  = false,
            // Reconexão exponencial: começa em 1s, máximo de 30s entre tentativas
            ReconnectRetryPolicy = new ExponentialRetry(1_000, 30_000),
            ConnectTimeout      = 5_000,   // ms para estabelecer conexão
            SyncTimeout         = 5_000,   // ms para comandos síncronos
            AsyncTimeout        = 5_000,   // ms para comandos assíncronos
            KeepAlive           = 60,      // segundos de keepalive
            // Identifica a aplicação no Redis (CLIENT LIST / CLIENT INFO)
            ClientName          = "monitoring-dotnet-api",
            // Protocolo RESP3 quando disponível (Redis 6+)
            Protocol            = RedisProtocol.Resp3,
        };

        if (!string.IsNullOrWhiteSpace(password))
            options.Password = password;

        // IConnectionMultiplexer deve ser singleton — é thread-safe e gerencia o pool interno.
        var multiplexer = ConnectionMultiplexer.Connect(options);
        builder.Services.AddSingleton<IConnectionMultiplexer>(multiplexer);

        // IDatabase é obtido do multiplexer via GetDatabase() — leve e reutilizável por request.
        builder.Services.AddScoped<IDatabase>(sp =>
            sp.GetRequiredService<IConnectionMultiplexer>().GetDatabase());

        // Health check
        builder.Services.AddHealthChecks()
            .Add(new HealthCheckRegistration(
                name: "redis",
                factory: sp => new RedisHealthCheck(
                    sp.GetRequiredService<IConnectionMultiplexer>()),
                failureStatus: HealthStatus.Unhealthy,
                tags: ["ready", "cache"],
                timeout: TimeSpan.FromSeconds(5)));

        return builder;
    }
}

/// <summary>
/// Health check que executa PING no Redis e reporta a latência no campo de dados.
/// </summary>
file sealed class RedisHealthCheck(IConnectionMultiplexer multiplexer) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var db = multiplexer.GetDatabase();
            var latency = await db.PingAsync().WaitAsync(cancellationToken);

            var data = new Dictionary<string, object>
            {
                ["latency_ms"] = latency.TotalMilliseconds,
                ["endpoint"]   = multiplexer.Configuration,
                ["status"]     = multiplexer.GetStatus(),
            };

            return HealthCheckResult.Healthy($"Redis OK — {latency.TotalMilliseconds:F1} ms", data);
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Redis unreachable", ex);
        }
    }
}
