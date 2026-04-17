namespace Api.Data.Entities;

/// <summary>
/// Registro persistido de uma leitura climática.
/// </summary>
public sealed class WeatherRecord
{
    public int    Id          { get; set; }
    public string Summary     { get; set; } = string.Empty;
    public int    TemperatureC { get; set; }
    public DateOnly RecordedAt { get; set; }
}
