using Api.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<WeatherRecord> WeatherRecords => Set<WeatherRecord>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<WeatherRecord>(entity =>
        {
            entity.ToTable("weather_records");

            entity.HasKey(e => e.Id);

            entity.Property(e => e.Id)
                  .UseIdentityByDefaultColumn();

            entity.Property(e => e.Summary)
                  .HasMaxLength(200)
                  .IsRequired();

            entity.Property(e => e.TemperatureC)
                  .IsRequired();

            entity.Property(e => e.RecordedAt)
                  .IsRequired();

            entity.HasIndex(e => e.RecordedAt)
                  .HasDatabaseName("ix_weather_records_recorded_at");
        });
    }
}
