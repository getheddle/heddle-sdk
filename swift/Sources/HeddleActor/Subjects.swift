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

