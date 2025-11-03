using Prometheus;
using PrtgExporter.ConsoleApp.Options;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace PrtgExporter.ConsoleApp;

internal class PrtgExporter
{
    private readonly PrtgOptions _prtgOptions;
    private readonly ExporterOptions _exporterOptions;
    private readonly MetricServer _metricServer;
    private readonly HttpClient _httpClient;

    // ---- Tunables ----
    private const int SensorPageSize = 10000;
    private const int ChannelPageSize = 1000;
    private const int MaxConcurrentChannelCalls = 6;
    private static readonly TimeSpan HttpTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan RetryBaseDelay = TimeSpan.FromMilliseconds(250);
    private const int MaxRetries = 3;

    // ---- Metrics ----
    // Channel-level metrics (main metric)
    private static readonly Gauge ChannelGauge = Metrics.CreateGauge(
        "prtg_channel_value",
        "PRTG channel last numeric value",
        new GaugeConfiguration
        {
            LabelNames = new[] { "sensor_id", "device", "sensor", "channel", "unit", "probe", "group" }
        });

    // Sensor-level metric (backward compatibility and fallback)
    private static readonly Gauge SensorLastValue = Metrics.CreateGauge(
        "prtg_sensor_lastvalue",
        "PRTG sensor lastvalue (best-effort numeric of the primary channel)",
        new GaugeConfiguration { LabelNames = new[] { "sensor_id", "device", "sensor", "probe", "group" } });

    public PrtgExporter(PrtgOptions prtgOptions, ExporterOptions exporterOptions)
    {
        _prtgOptions = prtgOptions;
        _exporterOptions = exporterOptions;

        // Create HTTP client with timeout
        _httpClient = new HttpClient
        {
            Timeout = HttpTimeout
        };

        // Start the MetricServer
        _metricServer = new MetricServer("*", _exporterOptions.Port);
        _metricServer.Start();
    }

    private string BaseUrl => _prtgOptions.Server.TrimEnd('/');
    private string ApiToken => _prtgOptions.Password; // Passhash is used as API token

    /// <summary>
    /// Refreshes the Gauges-List with both sensor and channel metrics
    /// </summary>
    public async Task RefreshSensorValuesAsync(CancellationToken ct = default)
    {
        try
        {
            var sensors = await GetSensorsAsync(ct);

            // Keep sensor-level metric for backward compatibility
            foreach (var s in sensors)
            {
                if (s.LastValueNumeric.HasValue)
                {
                    SensorLastValue
                        .WithLabels(
                            s.ObjId.ToString(),
                            s.Device ?? "",
                            s.Sensor ?? "",
                            s.Probe ?? "",
                            s.Group ?? "")
                        .Set(s.LastValueNumeric.Value);
                }
            }

            // For each sensor, fetch channels and export them
            using var throttler = new SemaphoreSlim(MaxConcurrentChannelCalls);
            var tasks = sensors.Select(async s =>
            {
                await throttler.WaitAsync(ct).ConfigureAwait(false);
                try
                {
                    var channels = await GetChannelsAsync(s.ObjId, ct);
                    foreach (var ch in channels)
                    {
                        var val = ch.LastValueRawNumeric
                                   ?? TryParseNumber(ch.LastValue)
                                   ?? TryParseNumber(ch.LastValueUnderscore);

                        if (val.HasValue)
                        {
                            ChannelGauge
                                .WithLabels(
                                    s.ObjId.ToString(),
                                    s.Device ?? "",
                                    s.Sensor ?? "",
                                    ch.Name ?? "",
                                    ch.Unit ?? "",
                                    s.Probe ?? "",
                                    s.Group ?? "")
                                .Set(val.Value);
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error fetching channels for sensor {s.ObjId}: {ex.Message}");
                }
                finally
                {
                    throttler.Release();
                }
            });

            await Task.WhenAll(tasks).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error refreshing sensor values: {ex.Message}");
        }
    }

    // ---------- API models ----------

    private sealed record PrtgTableResponse<T>(
        [property: JsonPropertyName("channels")] IReadOnlyList<T>? ChannelsObj,
        [property: JsonPropertyName("sensors")] IReadOnlyList<T>? SensorsObj
    )
    {
        public IReadOnlyList<T> Items => ChannelsObj ?? SensorsObj ?? Array.Empty<T>();
    }

    private sealed record SensorRow(
        [property: JsonPropertyName("objid")] int ObjId,
        [property: JsonPropertyName("device")] string? Device,
        [property: JsonPropertyName("probe")] string? Probe,
        [property: JsonPropertyName("group")] string? Group,
        [property: JsonPropertyName("sensor")] string? Sensor,
        [property: JsonPropertyName("lastvalue")] string? LastValue,
        [property: JsonPropertyName("lastvalue_")] string? LastValueUnderscore
    )
    {
        [JsonIgnore]
        public double? LastValueNumeric =>
            TryParseNumber(LastValue) ?? TryParseNumber(LastValueUnderscore);
    }

    private sealed record ChannelRow(
        [property: JsonPropertyName("objid")] int ObjId,
        [property: JsonPropertyName("name")] string? Name,
        [property: JsonPropertyName("unit")] string? Unit,
        [property: JsonPropertyName("lastvalue")] string? LastValue,
        [property: JsonPropertyName("lastvalue_raw")] object? LastValueRaw,
        [property: JsonPropertyName("lastvalue_")] string? LastValueUnderscore
    )
    {
        [JsonIgnore]
        public double? LastValueRawNumeric => LastValueRaw switch
        {
            double d => d,
            float f => f,
            int i => i,
            long l => l,
            decimal dec => (double)dec,
            string s when double.TryParse(s, out var parsed) => parsed,
            _ => null
        };
    };

    // ---------- API calls ----------

    private async Task<IReadOnlyList<SensorRow>> GetSensorsAsync(CancellationToken ct)
    {
        var url = $"{BaseUrl}/api/table.json" +
                  $"?content=sensors" +
                  $"&columns=objid,device,probe,group,sensor,lastvalue,lastvalue_" +
                  $"&count={SensorPageSize}" +
                  $"&username={WebUtility.UrlEncode(_prtgOptions.Username)}" +
                  $"&passhash={WebUtility.UrlEncode(ApiToken)}";

        var resp = await SendWithRetryAsync(() => new HttpRequestMessage(HttpMethod.Get, url), ct);
        var content = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);

        var opts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var parsed = JsonSerializer.Deserialize<PrtgTableResponse<SensorRow>>(content, opts);
        return parsed?.Items ?? Array.Empty<SensorRow>();
    }

    private async Task<IReadOnlyList<ChannelRow>> GetChannelsAsync(int sensorId, CancellationToken ct)
    {
        var url = $"{BaseUrl}/api/table.json" +
                  $"?content=channels" +
                  $"&id={sensorId}" +
                  $"&columns=objid,name=textraw,unit=textraw,lastvalue,lastvalue_raw,lastvalue_" +
                  $"&count={ChannelPageSize}" +
                  $"&username={WebUtility.UrlEncode(_prtgOptions.Username)}" +
                  $"&passhash={WebUtility.UrlEncode(ApiToken)}";

        var resp = await SendWithRetryAsync(() => new HttpRequestMessage(HttpMethod.Get, url), ct);
        var content = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);

        var opts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var parsed = JsonSerializer.Deserialize<PrtgTableResponse<ChannelRow>>(content, opts);
        return parsed?.Items ?? Array.Empty<ChannelRow>();
    }

    // ---------- Helpers ----------

    private static double? TryParseNumber(string? possiblyFormatted)
    {
        if (string.IsNullOrWhiteSpace(possiblyFormatted)) return null;

        var s = possiblyFormatted.Trim();
        int i = 0;
        while (i < s.Length && (char.IsDigit(s[i]) || s[i] == '.' || s[i] == ',' || s[i] == '-' || s[i] == '+'))
            i++;

        if (i == 0) return null;
        var num = s[..i];

        if (num.Contains(',') && !num.Contains('.'))
            num = num.Replace(',', '.');      // decimal comma → dot

        if (num.Contains(',') && num.Contains('.'))
            num = num.Replace(",", string.Empty); // strip thousands comma

        return double.TryParse(num, NumberStyles.Float | NumberStyles.AllowThousands,
                               CultureInfo.InvariantCulture, out var v)
               ? v : null;
    }

    private async Task<HttpResponseMessage> SendWithRetryAsync(Func<HttpRequestMessage> reqFactory, CancellationToken ct)
    {
        for (int attempt = 0; ; attempt++)
        {
            ct.ThrowIfCancellationRequested();
            using var req = reqFactory();

            try
            {
                var resp = await _httpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
                if ((int)resp.StatusCode >= 500)
                {
                    resp.Dispose();
                    throw new HttpRequestException($"Server error {(int)resp.StatusCode}");
                }
                return resp;
            }
            catch (Exception) when (attempt < MaxRetries)
            {
                var delay = TimeSpan.FromMilliseconds(RetryBaseDelay.TotalMilliseconds * Math.Pow(2, attempt));
                await Task.Delay(delay, ct).ConfigureAwait(false);
            }
        }
    }
}