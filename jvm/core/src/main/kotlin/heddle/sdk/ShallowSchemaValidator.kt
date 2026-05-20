package heddle.sdk

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.ObjectNode

/**
 * Heddle's runtime intentionally uses shallow JSON Schema checks.
 */
object ShallowSchemaValidator {

    /**
     * Validates that the input is a JSON object and contains the required fields.
     */
    fun validate(
        name: String,
        node: JsonNode,
        requiredFields: List<String> = emptyList()
    ) {
        if (!node.isObject) {
            throw IllegalArgumentException("$name must be a JSON object")
        }

        val objectNode = node as ObjectNode
        for (field in requiredFields) {
            if (!objectNode.has(field) || objectNode.get(field).isNull) {
                throw IllegalArgumentException("$name is missing required field: $field")
            }
        }
    }
}
