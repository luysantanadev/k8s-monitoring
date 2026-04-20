# Stage: runtime base
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8080

# Stage: build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["src/Api/Api.csproj", "src/Api/"]
RUN dotnet restore "./src/Api/Api.csproj"
COPY . .
WORKDIR "/src/src/Api"
RUN dotnet build "./Api.csproj" -c $BUILD_CONFIGURATION -o /app/build

# Stage: publish
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./Api.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# Stage: final
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Default observability endpoints — override via k8s ConfigMap / env vars
ENV ASPNETCORE_URLS=http://+:8080 \
    DOTNET_ENVIRONMENT=Production \
    Observability__Otlp__Endpoint=http://tempo:4317 \
    Observability__Loki__Uri=http://loki:3100 \
    Observability__Pyroscope__ServerAddress=http://pyroscope:4040

# Kubernetes uses httpGet probes on /health and /ready — HEALTHCHECK covers plain Docker
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "Api.dll"]
