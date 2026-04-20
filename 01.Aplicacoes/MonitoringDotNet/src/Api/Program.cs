
using Api;
using Api.Extensions;
using DotNetEnv;
using Scalar.AspNetCore;

// Precedencia de configuracao:
//   OS env vars (k8s Deployment/ConfigMap) > Vault secrets > .env local (dev fallback)
//
// Vault Agent Injector escreve segredos em /vault/secrets/*.env antes do container iniciar.
// clobberExistingVars: false garante que variaveis ja definidas no ambiente do processo nao sao sobrescritas.
const string vaultSecretsDir = "/vault/secrets";
if (Directory.Exists(vaultSecretsDir))
{
    var opts = new LoadOptions(clobberExistingVars: false);
    foreach (var file in Directory.EnumerateFiles(vaultSecretsDir, "*.env", SearchOption.TopDirectoryOnly))
        Env.Load(file, opts);
}

// Fallback para desenvolvimento local: sobe diretorios ate encontrar o .env (no-op se nao existir)
Env.TraversePath().Load();

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAuthorization();
builder.Services.AddOpenApi();
builder.AddObservability();
builder.AddDatabase();
builder.AddRedis();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference(options =>
    {
        options.Title = "monitoring-dotnet-api";
        options.Theme = ScalarTheme.DeepSpace;
        options.DefaultHttpClient = new(ScalarTarget.CSharp, ScalarClient.HttpClient);
        options.WithPreferredScheme("Bearer");
    });

    // Abre o Scalar automaticamente no browser ao iniciar em Development
    var lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();
    lifetime.ApplicationStarted.Register(() =>
    {
        var url = app.Urls.FirstOrDefault() ?? "http://localhost:8080";
        var scalarUrl = $"{url}/scalar/v1";
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(scalarUrl) { UseShellExecute = true }); }
        catch { /* browser launch é best-effort */ }
    });
}

app.UseObservability();
app.UseAuthorization();

await app.MigrateDatabaseAsync();

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/weatherforecast", (HttpContext httpContext) =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        {
            Date = DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            TemperatureC = Random.Shared.Next(-20, 55),
            Summary = summaries[Random.Shared.Next(summaries.Length)]
        })
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();
