import Foundation

public enum ModelTier: String, Codable, Sendable {
    case local
    case standard
    case frontier
}

public enum TaskPriority: String, Codable, Sendable {
    case low
    case normal
    case high
    case critical
}

public enum TaskStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

public struct TaskMessage: Codable, Equatable, Sendable {
    public var taskId: String
    public var parentTaskId: String?
    public var workerType: String
    public var payload: [String: JSONValue]
    public var modelTier: ModelTier
    public var priority: TaskPriority
    public var createdAt: String
    public var requestId: String?
    public var metadata: [String: JSONValue]
    public var traceContext: [String: String]?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case parentTaskId = "parent_task_id"
        case workerType = "worker_type"
        case payload
        case modelTier = "model_tier"
        case priority
        case createdAt = "created_at"
        case requestId = "request_id"
        case metadata
        case traceContext = "_trace_context"
    }

    public init(
        taskId: String = UUID().uuidString,
        parentTaskId: String? = nil,
        workerType: String,
        payload: [String: JSONValue],
        modelTier: ModelTier = .standard,
        priority: TaskPriority = .normal,
        createdAt: String = HeddleClock.nowIso8601(),
        requestId: String? = nil,
        metadata: [String: JSONValue] = [:],
        traceContext: [String: String]? = nil
    ) {
        self.taskId = taskId
        self.parentTaskId = parentTaskId
        self.workerType = workerType
        self.payload = payload
        self.modelTier = modelTier
        self.priority = priority
        self.createdAt = createdAt
        self.requestId = requestId
        self.metadata = metadata
        self.traceContext = traceContext
    }
}

public struct TaskResult: Codable, Equatable, Sendable {
    public var taskId: String
    public var parentTaskId: String?
    public var workerType: String
    public var status: TaskStatus
    public var output: [String: JSONValue]?
    public var error: String?
    public var modelUsed: String?
    public var tokenUsage: [String: Int]
    public var metadata: [String: JSONValue]
    public var processingTimeMs: Int
    public var completedAt: String
    public var traceContext: [String: String]?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case parentTaskId = "parent_task_id"
        case workerType = "worker_type"
        case status
        case output
        case error
        case modelUsed = "model_used"
        case tokenUsage = "token_usage"
        case metadata
        case processingTimeMs = "processing_time_ms"
        case completedAt = "completed_at"
        case traceContext = "_trace_context"
    }

    public init(
        taskId: String,
        parentTaskId: String? = nil,
        workerType: String,
        status: TaskStatus,
        output: [String: JSONValue]? = nil,
        error: String? = nil,
        modelUsed: String? = nil,
        tokenUsage: [String: Int] = [:],
        metadata: [String: JSONValue] = [:],
        processingTimeMs: Int = 0,
        completedAt: String = HeddleClock.nowIso8601(),
        traceContext: [String: String]? = nil
    ) {
        self.taskId = taskId
        self.parentTaskId = parentTaskId
        self.workerType = workerType
        self.status = status
        self.output = output
        self.error = error
        self.modelUsed = modelUsed
        self.tokenUsage = tokenUsage
        self.metadata = metadata
        self.processingTimeMs = processingTimeMs
        self.completedAt = completedAt
        self.traceContext = traceContext
    }
}

public struct OrchestratorGoal: Codable, Equatable, Sendable {
    public var goalId: String
    public var instruction: String
    public var context: [String: JSONValue]
    public var requestId: String?
    public var priority: TaskPriority
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case goalId = "goal_id"
        case instruction
        case context
        case requestId = "request_id"
        case priority
        case createdAt = "created_at"
    }
}

public struct CheckpointState: Codable, Equatable, Sendable {
    public var goalId: String
    public var originalInstruction: String
    public var executiveSummary: String
    public var completedTasks: [[String: JSONValue]]
    public var pendingTasks: [[String: JSONValue]]
    public var openIssues: [String]
    public var decisionsMade: [String]
    public var contextTokenCount: Int
    public var checkpointNumber: Int
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case goalId = "goal_id"
        case originalInstruction = "original_instruction"
        case executiveSummary = "executive_summary"
        case completedTasks = "completed_tasks"
        case pendingTasks = "pending_tasks"
        case openIssues = "open_issues"
        case decisionsMade = "decisions_made"
        case contextTokenCount = "context_token_count"
        case checkpointNumber = "checkpoint_number"
        case createdAt = "created_at"
    }

    public init(
        goalId: String = "",
        originalInstruction: String = "",
        executiveSummary: String = "",
        completedTasks: [[String: JSONValue]] = [],
        pendingTasks: [[String: JSONValue]] = [],
        openIssues: [String] = [],
        decisionsMade: [String] = [],
        contextTokenCount: Int = 0,
        checkpointNumber: Int = 0,
        createdAt: String = HeddleClock.nowIso8601()
    ) {
        self.goalId = goalId
        self.originalInstruction = originalInstruction
        self.executiveSummary = executiveSummary
        self.completedTasks = completedTasks
        self.pendingTasks = pendingTasks
        self.openIssues = openIssues
        self.decisionsMade = decisionsMade
        self.contextTokenCount = contextTokenCount
        self.checkpointNumber = checkpointNumber
        self.createdAt = createdAt
    }
}

public struct WorkerOutput<Output: Encodable & Sendable>: Sendable {
    public var output: Output
    public var modelUsed: String?
    public var tokenUsage: [String: Int]
    public var metadata: [String: JSONValue]

    public init(
        output: Output,
        modelUsed: String? = nil,
        tokenUsage: [String: Int] = [:],
        metadata: [String: JSONValue] = [:]
    ) {
        self.output = output
        self.modelUsed = modelUsed
        self.tokenUsage = tokenUsage
        self.metadata = metadata
    }
}

public enum HeddleClock {
    public static func nowIso8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

