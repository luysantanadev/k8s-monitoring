using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Formatting.Compact;

namespace Api.Extensions;

internal static class ObservabilityExtensions
{
    internal static WebApplicationBuilder AddObservability(this WebApplicationBuilder builder)
    {
        var config = builder.Configuration;

        var serviceName    = config["Observability:ServiceName"]    ?? "api";
        var serviceVersion = config["Observability:ServiceVersion"] ?? "1.0.0";
        var otlpEndpoint   = config["Observability:Otlp:Endpoint"]  ?? "http://localhost:4317";

        // Structured JSON logs to stdout.
        // Grafana Alloy (or Promtail) running in the cluster collects pod stdout and pushes to Loki.
        // Alloy pipeline-stage label: { service="monitoring-dotnet-api", namespace="<ns>" }
        builder.Host.UseSerilog((ctx, services, logConfig) =>
        {
            logConfig
                .ReadFrom.Configuration(ctx.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                .Enrich.WithMachineName()
                .Enrich.WithThreadId()
                .WriteTo.Console(new CompactJsonFormatter());
        });

        var resourceBuilder = ResourceBuilder
            .CreateDefault()
            .AddService(serviceName, serviceVersion: serviceVersion)
            .AddTelemetrySdk()
            .AddEnvironmentVariableDetector();

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
                // Exports spans to Tempo via OTLP/gRPC
                .AddOtlpExporter(opts => opts.Endpoint = new Uri(otlpEndpoint)))
            .WithMetrics(metrics => metrics
                .SetResourceBuilder(resourceBuilder)
                .AddAspNetCoreInstrumentation()
                .AddHttpClientInstrumentation()
                .AddRuntimeInstrumentation()
                // Métricas nativas do Npgsql: pool de conexões (db.client.connections.*)
                .AddMeter("Npgsql")
                // Exposes /metrics for Prometheus scraping
                .AddPrometheusExporter());

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
