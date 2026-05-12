using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Heddle.Sdk;

/// <summary>
/// Shared JSON options and helpers for the Heddle wire format.
/// </summary>
public static class HeddleJson
{
    public static readonly JsonSerializerOptions Options = CreateOptions();

    public static byte[] SerializeToBytes<T>(T value)
    {
        return JsonSerializer.SerializeToUtf8Bytes(value, Options);
    }

    public static T Deserialize<T>(ReadOnlySpan<byte> bytes)
    {
        return JsonSerializer.Deserialize<T>(bytes, Options)
            ?? throw new JsonException($"Unable to deserialize {typeof(T).Name}");
    }

    public static string NowIso8601()
    {
        return DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture);
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = false,
        };
        options.Converters.Add(new LowerCaseEnumJsonConverter<ModelTier>());
        options.Converters.Add(new LowerCaseEnumJsonConverter<TaskPriority>());
        options.Converters.Add(new LowerCaseEnumJsonConverter<TaskStatus>());
        return options;
    }
}

internal sealed class LowerCaseEnumJsonConverter<TEnum> : JsonConverter<TEnum>
    where TEnum : struct, Enum
{
    public override TEnum Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (value is null)
        {
            throw new JsonException($"Expected string for {typeof(TEnum).Name}");
        }

        foreach (var candidate in Enum.GetValues<TEnum>())
        {
            if (ToWire(candidate) == value)
            {
                return candidate;
            }
        }

        throw new JsonException($"Unknown {typeof(TEnum).Name} value: {value}");
    }

    public override void Write(
        Utf8JsonWriter writer,
        TEnum value,
        JsonSerializerOptions options)
    {
        writer.WriteStringValue(ToWire(value));
    }

    private static string ToWire(TEnum value)
    {
        return value.ToString().ToLowerInvariant();
    }
}

