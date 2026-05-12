using System.Text.Json.Nodes;

namespace Heddle.Sdk;

/// <summary>
/// Matches Heddle's intentionally shallow JSON Schema validation:
/// required fields plus top-level property type checks.
/// </summary>
public static class ShallowSchemaValidator
{
    public static IReadOnlyList<string> Validate(
        JsonObject data,
        JsonObject? schema,
        string context)
    {
        var errors = new List<string>();
        if (schema is null || schema.Count == 0)
        {
            return errors;
        }

        var expectedType = schema["type"]?.GetValue<string>();
        if (expectedType is not null && expectedType != "object")
        {
            return errors;
        }

        if (schema["required"] is JsonArray required)
        {
            foreach (var item in required)
            {
                var field = item?.GetValue<string>();
                if (field is not null && !data.ContainsKey(field))
                {
                    errors.Add($"{context}: missing required field '{field}'");
                }
            }
        }

        if (schema["properties"] is not JsonObject properties)
        {
            return errors;
        }

        foreach (var property in properties)
        {
            if (!data.TryGetPropertyValue(property.Key, out var value) || value is null)
            {
                continue;
            }
            if (property.Value is not JsonObject fieldSchema)
            {
                continue;
            }

            var fieldType = fieldSchema["type"]?.GetValue<string>();
            if (fieldType is not null && !MatchesType(value, fieldType))
            {
                errors.Add($"{context}.{property.Key}: expected {fieldType}");
            }
        }

        return errors;
    }

    private static bool MatchesType(JsonNode value, string fieldType)
    {
        return fieldType switch
        {
            "object" => value is JsonObject,
            "array" => value is JsonArray,
            "string" => value is JsonValue text && text.TryGetValue<string>(out _),
            "boolean" => value is JsonValue boolean && boolean.TryGetValue<bool>(out _),
            "integer" => value is JsonValue integer && integer.TryGetValue<long>(out _),
            "number" => value is JsonValue number
                && (number.TryGetValue<int>(out _)
                    || number.TryGetValue<long>(out _)
                    || number.TryGetValue<double>(out _)
                    || number.TryGetValue<decimal>(out _)),
            "null" => value.GetValue<object?>() is null,
            _ => true,
        };
    }
}

