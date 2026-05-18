public enum HeddleSubjects {
    public static let incomingTasks = "heddle.tasks.incoming"
    public static let deadLetters = "heddle.tasks.dead_letter"
    public static let incomingGoals = "heddle.goals.incoming"
    public static let controlReload = "heddle.control.reload"

    public static func workerTasks(workerType: String, tier: String) -> String {
        "heddle.tasks.\(workerType).\(tier)"
    }

    public static func results(parentTaskId: String?) -> String {
        "heddle.results.\(parentTaskId ?? "default")"
    }

    public static func processorQueueGroup(workerType: String) -> String {
        "processors-\(workerType)"
    }

    public static func llmWorkerQueueGroup(workerType: String) -> String {
        "workers-\(workerType)"
    }
}

/// Subject helpers for the `heddle.contrib.events` wire contract.
///
/// Mirrors `heddle.core.subjects` in the upstream Python repo. Patterns:
///
/// ```
/// heddle.events.{aggregateType}.{aggregateId}.{eventType}
/// heddle.commands.{aggregateType}.{aggregateId}.{commandType}
/// heddle.rejections.{aggregateType}.{aggregateId}.{commandType}
/// ```
///
/// Stream names follow `HEDDLE_{KIND}_{AGGREGATE_TYPE_UPPER}`.
public enum EventSubjects {
    public enum SubjectError: Error, Equatable {
        case emptyToken(label: String)
        case forbiddenCharacters(label: String, value: String)
    }

    private static let forbidden: Set<Character> = [".", " ", "*", ">"]

    private static func validate(_ value: String, label: String) throws {
        if value.isEmpty {
            throw SubjectError.emptyToken(label: label)
        }
        if value.contains(where: forbidden.contains) {
            throw SubjectError.forbiddenCharacters(label: label, value: value)
        }
    }

    public static func event(
        aggregateType: String,
        aggregateId: String,
        eventType: String
    ) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        try validate(aggregateId, label: "aggregateId")
        try validate(eventType, label: "eventType")
        return "heddle.events.\(aggregateType).\(aggregateId).\(eventType)"
    }

    public static func command(
        aggregateType: String,
        aggregateId: String,
        commandType: String
    ) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        try validate(aggregateId, label: "aggregateId")
        try validate(commandType, label: "commandType")
        return "heddle.commands.\(aggregateType).\(aggregateId).\(commandType)"
    }

    public static func rejection(
        aggregateType: String,
        aggregateId: String,
        commandType: String
    ) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        try validate(aggregateId, label: "aggregateId")
        try validate(commandType, label: "commandType")
        return "heddle.rejections.\(aggregateType).\(aggregateId).\(commandType)"
    }

    public static func eventStream(aggregateType: String) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        return "HEDDLE_EVENTS_\(aggregateType.uppercased())"
    }

    public static func commandStream(aggregateType: String) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        return "HEDDLE_COMMANDS_\(aggregateType.uppercased())"
    }

    public static func rejectionStream(aggregateType: String) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        return "HEDDLE_REJECTIONS_\(aggregateType.uppercased())"
    }

    public static func eventFilter(aggregateType: String) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        return "heddle.events.\(aggregateType).>"
    }

    public static func commandFilter(aggregateType: String) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        return "heddle.commands.\(aggregateType).>"
    }

    public static func rejectionFilter(aggregateType: String) throws -> String {
        try validate(aggregateType, label: "aggregateType")
        return "heddle.rejections.\(aggregateType).>"
    }
}

