
using DotNetEnv;
using Mvc.Extensions;

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

var mvc = builder.Services.AddControllersWithViews();

// Hot reload de Razor Views sem necessidade de recompilar o projeto
if (builder.Environment.IsDevelopment())
    mvc.AddRazorRuntimeCompilation();

builder.Services.AddAuthorization();
builder.AddObservability();
builder.AddDatabase();
builder.AddRedis();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseObservability();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

//await app.MigrateDatabaseAsync();

await app.RunAsync();
