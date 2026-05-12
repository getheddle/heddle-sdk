public enum ShallowSchemaValidator {
    public static func validate(
        data: [String: JSONValue],
        schema: [String: JSONValue]?,
        context: String
    ) -> [String] {
        guard let schema, !schema.isEmpty else {
            return []
        }

        if let required = schema["required"], case let .array(fields) = required {
            var errors: [String] = []
            for field in fields {
                guard case let .string(name) = field else {
                    continue
                }
                if data[name] == nil {
                    errors.append("\(context): missing required field '\(name)'")
                }
            }
            return errors + validateProperties(data: data, schema: schema, context: context)
        }

        return validateProperties(data: data, schema: schema, context: context)
    }

    private static func validateProperties(
        data: [String: JSONValue],
        schema: [String: JSONValue],
        context: String
    ) -> [String] {
        guard case let .object(properties)? = schema["properties"] else {
            return []
        }

        var errors: [String] = []
        for (field, fieldSchema) in properties {
            guard let value = data[field],
                  case let .object(fieldSchemaObject) = fieldSchema,
                  case let .string(expected)? = fieldSchemaObject["type"] else {
                continue
            }

            if !matches(value, expected: expected) {
                errors.append("\(context).\(field): expected \(expected)")
            }
        }
        return errors
    }

    private static func matches(_ value: JSONValue, expected: String) -> Bool {
        switch (value, expected) {
        case (.object, "object"), (.array, "array"), (.string, "string"),
             (.bool, "boolean"), (.int, "integer"), (.int, "number"),
             (.double, "number"), (.null, "null"):
            true
        default:
            false
        }
    }
}

