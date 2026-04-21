using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Pyroscope.OpenTelemetry;
using Serilog;
using Serilog.Formatting.Compact;
using Serilog.Sinks.Grafana.Loki;
using System.Net.Http.Headers;

namespace Mvc.Extensions;

internal static class ObservabilityExtensions
{
    internal static WebApplicationBuilder AddObservability(this WebApplicationBuilder builder)
    {
        var config = builder.Configuration;

        var serviceName    = config["Observability:ServiceName"]    ?? "api";
        var serviceVersion = config["Observability:ServiceVersion"] ?? "1.0.0";
        var otlpEndpoint   = config["Observability:Otlp:Endpoint"]  ?? "http://localhost:4317";

        // Structured JSON logs to stdout.
        // In cluster: Grafana Alloy (loki.source.kubernetes) collects pod stdout and pushes to Loki.
        // In Development (local): Alloy cannot reach local stdout, so the Loki sink pushes directly.
        builder.Host.UseSerilog((ctx, services, logConfig) =>
        {
            logConfig
                .ReadFrom.Configuration(ctx.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                .Enrich.WithMachineName()
                .Enrich.WithThreadId()
                .WriteTo.Console(new CompactJsonFormatter());

            // Direct Loki push only in Development — avoids duplicate logs when deployed to cluster.
            // X-Scope-OrgID must match the tenant written by Alloy and read by the Grafana datasource.
            var lokiUri = ctx.Configuration["Observability:Loki:Uri"];
            if (ctx.HostingEnvironment.IsDevelopment() && !string.IsNullOrEmpty(lokiUri))
            {
                logConfig.WriteTo.GrafanaLoki(
                    lokiUri,
                    labels: [new LokiLabel { Key = "app", Value = serviceName }],
                    httpClient: new WorkshopLokiHttpClient());
            }
        });

        var resourceBuilder = ResourceBuilder
            .CreateDefault()
            .AddService(serviceName, serviceVersion: serviceVersion)
            .AddTelemetrySdk()
            .AddEnvironmentVariableDetector();

        // Pyroscope: profiling continuo enviado ao servidor via push.
        // A configuração é feita por variáveis de ambiente antes do profiler iniciar.
        // Em Development usa o ingress HTTP (pyroscope.monitoramento.local).
        var pyroscopeAddress = config["Observability:Pyroscope:ServerAddress"];
        if (!string.IsNullOrEmpty(pyroscopeAddress))
        {
            Environment.SetEnvironmentVariable("PYROSCOPE_APPLICATION_NAME",
                config["Observability:Pyroscope:ApplicationName"] ?? serviceName);
            Environment.SetEnvironmentVariable("PYROSCOPE_SERVER_ADDRESS", pyroscopeAddress);
        }

        builder.Services
            .AddOpenTelemetry()
            .WithTracing(tracing => tracing
                .SetResourceBuilder(resourceBuilder)
                .AddAspNetCoreInstrumentation(opts => opts.RecordException = true)
                .AddHttpClientInstrumentation()
                // Traces de queries EF Core -> Tempo
                .AddEntityFrameworkCoreInstrumentation()
                // Traces ADO.NET diretos do Npgsql (conexão, comandos) via ActivitySource nativo
                .AddSource("Npgsql")
                // Traces de comandos Redis -> Tempo; IConnectionMultiplexer resolvido via IServiceProvider
                .AddRedisInstrumentation(opts => opts.FlushInterval = TimeSpan.FromSeconds(1))
                .AddSource(serviceName)
                // Correlaciona spans com perfis do Pyroscope
                .AddProcessor(new PyroscopeSpanProcessor())
                // Exports spans to Alloy/Tempo via OTLP/gRPC
                .AddOtlpExporter(opts => opts.Endpoint = new Uri(otlpEndpoint)))
            .WithMetrics(metrics => metrics
                .SetResourceBuilder(resourceBuilder)
                .AddAspNetCoreInstrumentation()
                .AddHttpClientInstrumentation()
                .AddRuntimeInstrumentation()
                // Métricas nativas do Npgsql: pool de conexões (db.client.connections.*)
                .AddMeter("Npgsql")
                // Exposes /metrics for Prometheus scraping (fallback / cluster)
                .AddPrometheusExporter()
                // Push de métricas via OTLP ao Alloy -> Prometheus (necessário em dev local
                // onde não há Prometheus raspando diretamente o /metrics da aplicação)
                .AddOtlpExporter(opts => opts.Endpoint = new Uri(otlpEndpoint)));

        // Health checks: liveness e readiness
        builder.Services.AddHealthChecks();

        return builder;
    }

    internal static WebApplication UseObservability(this WebApplication app)
    {
        app.UseSerilogRequestLogging(opts =>
        {
            opts.MessageTemplate =
                "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms";
        });

        // Prometheus metrics scrape endpoint
        app.MapPrometheusScrapingEndpoint("/metrics");

        // Kubernetes liveness / readiness probes
        app.MapHealthChecks("/health");
        app.MapHealthChecks("/ready");

        return app;
    }
}

/// <summary>
/// Loki HTTP client that adds the X-Scope-OrgID tenant header required by the Loki gateway,
/// even when auth_enabled is false (without the header, pushes go to the "fake" tenant).
/// </summary>
file sealed class WorkshopLokiHttpClient : ILokiHttpClient
{
    private readonly HttpClient _http = new();

    public WorkshopLokiHttpClient()
        => _http.DefaultRequestHeaders.Add("X-Scope-OrgID", "workshop");

    public void SetAuthenticationHeader(string type, string credentials)
        => _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(type, credentials);

    public void SetCredentials(LokiCredentials? credentials)
    {
        if (credentials is null) return;
        var encoded = Convert.ToBase64String(
            System.Text.Encoding.UTF8.GetBytes($"{credentials.Login}:{credentials.Password}"));
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", encoded);
    }

    public void SetTenant(string? tenant)
    {
        _http.DefaultRequestHeaders.Remove("X-Scope-OrgID");
        if (tenant is not null)
            _http.DefaultRequestHeaders.Add("X-Scope-OrgID", tenant);
    }

    public Task<HttpResponseMessage> PostAsync(string requestUri, Stream contentStream)
    {
        var content = new StreamContent(contentStream);
        content.Headers.ContentType = MediaTypeHeaderValue.Parse("application/json");
        return _http.PostAsync(requestUri, content);
    }

    public void Dispose() => _http.Dispose();
}
