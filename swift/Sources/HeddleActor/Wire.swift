// The Heddle v1 wire frame (WireEnvelope) and its strict codec.
//
// Mirrors heddle/src/heddle/core/envelope.py. Every message on the bus is a
// frame: identity, causation, two timestamps, a `payload_type`
// discriminator, the typed body in `payload`, and the Middleware Lane
// (top-level `_`-prefixed keys, carried as opaque JSON).
//
// Parsing has two steps, as upstream: validate the frame, then pick the body
// model by `payload_type` and validate the body. Errors carry the layer that
// rejected the message (frame / body / dispatch), matching the `rejected_at`
// column of schemas/v1/fixtures/manifest.json.
//
// The codec reads a generic `JSONValue` tree and checks every field by hand,
// so the rules are identical to the .NET and JVM SDKs. Codable cannot
// capture unknown keys, and Foundation's ISO 8601 strategies either reject
// or require fractional seconds and keep only milliseconds; `WireTimestamp`
// parses RFC 3339 itself. See schemas/v1/fixtures/README.md for the rules.

import Foundation

/// The layer at which an inbound message was rejected.
public enum WireLayer: String, Sendable, Equatable {
    /// The frame is invalid (missing or ill-typed field, unknown non-`_` key, bad timestamp).
    case frame
    /// The frame is valid, but the body fails its model.
    case body
    /// The frame is valid, but no body model is registered for its `payload_type`.
    case dispatch
}

/// An inbound message that does not satisfy the v1 wire contract.
public struct WireFormatError: Error, Equatable, CustomStringConvertible {
    public let layer: WireLayer
    public let message: String

    public init(_ layer: WireLayer, _ message: String) {
        self.layer = layer
        self.message = message
    }

    public var description: String { "\(layer.rawValue): \(message)" }
}

/// The `payload_type` discriminators this SDK registers.
public enum PayloadTypes {
    public static let taskMessage = "core.TaskMessage"
    public static let taskResult = "core.TaskResult"
    public static let orchestratorGoal = "core.OrchestratorGoal"

    /// Every registered discriminator. Anything else is a dispatch rejection.
    public static let all = [taskMessage, taskResult, orchestratorGoal]
}

/// A frame timestamp: an instant with microsecond precision.
///
/// Parsed from RFC 3339 with a mandatory offset (`Z` or `±HH:MM`, `T`/`Z` in
/// either case). Fractional seconds beyond microseconds are truncated, as
/// upstream does. A leap second (`:60`) and impossible dates are rejected.
/// Emitted as UTC with six fractional digits and `Z`; any instant-equal form
/// is conformant.
public struct WireTimestamp: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// Microseconds since 1970-01-01T00:00:00Z.
    public let epochMicroseconds: Int64

    public init(epochMicroseconds: Int64) {
        self.epochMicroseconds = epochMicroseconds
    }

    /// The current instant, truncated to microseconds.
    public static func now() -> WireTimestamp {
        WireTimestamp(epochMicroseconds: Int64((Date().timeIntervalSince1970 * 1_000_000).rounded(.down)))
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(epochMicroseconds) / 1_000_000)
    }

    public var description: String { rfc3339 }

    public static func parse(_ text: String) -> WireTimestamp? {
        let c = Array(text.utf8)
        func digits(_ start: Int, _ count: Int) -> Int? {
            guard start + count <= c.count else { return nil }
            var value = 0
            for i in start..<(start + count) {
                guard c[i] >= 48, c[i] <= 57 else { return nil }
                value = value * 10 + Int(c[i] - 48)
            }
            return value
        }
        func at(_ i: Int, _ ch: Character) -> Bool { i < c.count && c[i] == ch.asciiValue! }

        guard let year = digits(0, 4), at(4, "-"), let month = digits(5, 2), at(7, "-"),
              let day = digits(8, 2), at(10, "T") || at(10, "t"),
              let hour = digits(11, 2), at(13, ":"), let minute = digits(14, 2), at(16, ":"),
              let second = digits(17, 2)
        else { return nil }

        var i = 19
        var micros = 0
        if at(i, ".") {
            i += 1
            var count = 0
            while i < c.count, c[i] >= 48, c[i] <= 57 {
                if count < 6 { micros = micros * 10 + Int(c[i] - 48) }
                count += 1
                i += 1
            }
            guard count > 0 else { return nil }
            for _ in min(count, 6)..<6 { micros *= 10 }
        }

        var offsetMinutes = 0
        if at(i, "Z") || at(i, "z") {
            i += 1
        } else if at(i, "+") || at(i, "-") {
            let sign = at(i, "-") ? -1 : 1
            guard let oh = digits(i + 1, 2), at(i + 3, ":"), let om = digits(i + 4, 2), oh <= 23, om <= 59
            else { return nil }
            offsetMinutes = sign * (oh * 60 + om)
            i += 6
        } else {
            return nil
        }
        guard i == c.count else { return nil }

        guard year >= 1, (1...12).contains(month), day >= 1, day <= daysIn(year: year, month: month),
              hour <= 23, minute <= 59, second <= 59
        else { return nil }

        let days = Int64(daysFromCivil(year: year, month: month, day: day))
        let seconds = days * 86_400 + Int64(hour * 3_600 + minute * 60 + second) - Int64(offsetMinutes * 60)
        // The instant must be representable in UTC (years 0001-9999), since
        // frames are written in UTC.
        guard seconds >= minUtcSeconds, seconds <= maxUtcSeconds else { return nil }
        return WireTimestamp(epochMicroseconds: seconds * 1_000_000 + Int64(micros))
    }

    public var rfc3339: String {
        let (secondsOfEpoch, micros) = floorDivMod(epochMicroseconds, 1_000_000)
        let (days, secondOfDay) = floorDivMod(secondsOfEpoch, 86_400)
        let (year, month, day) = civilFromDays(Int(days))
        let s = Int(secondOfDay)
        func pad(_ v: Int, _ width: Int) -> String {
            let text = String(v)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(s / 3_600, 2)):\(pad(s / 60 % 60, 2)):\(pad(s % 60, 2)).\(pad(Int(micros), 6))Z"
    }
}

/// The generic frame every Heddle message rides. Use ``HeddleWire`` to build
/// and read frames.
public struct WireEnvelope: Equatable, Sendable {
    public var messageId: String
    /// Dotted discriminator, e.g. `core.TaskMessage`.
    public var payloadType: String
    /// The body as JSON. Validated by ``HeddleWire/parseBody(_:)``.
    public var payload: [String: JSONValue]
    public var origin: String?
    public var correlationId: String?
    public var causationId: String?
    /// Domain time: when the thing this message is about happened.
    public var occurredAt: WireTimestamp
    /// Bus time: when this message was recorded onto the transport.
    public var recordedAt: WireTimestamp
    /// The Middleware Lane: every top-level `_`-prefixed key, as opaque JSON.
    /// Actors that publish a message because of an inbound one copy this onto
    /// the new frame (heddle DESIGN_INVARIANTS #22).
    public var lane: [String: JSONValue]

    public init(
        messageId: String = UUID().uuidString.lowercased(),
        payloadType: String,
        payload: [String: JSONValue],
        origin: String? = nil,
        correlationId: String? = nil,
        causationId: String? = nil,
        occurredAt: WireTimestamp,
        recordedAt: WireTimestamp,
        lane: [String: JSONValue] = [:]
    ) {
        self.messageId = messageId
        self.payloadType = payloadType
        self.payload = payload
        self.origin = origin
        self.correlationId = correlationId
        self.causationId = causationId
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.lane = lane
    }
}

/// A typed v1 body, discriminated by `payload_type`.
public enum WireBody: Equatable, Sendable {
    case taskMessage(TaskMessage)
    case taskResult(TaskResult)
    case orchestratorGoal(OrchestratorGoal)

    public var payloadType: String {
        switch self {
        case .taskMessage: PayloadTypes.taskMessage
        case .taskResult: PayloadTypes.taskResult
        case .orchestratorGoal: PayloadTypes.orchestratorGoal
        }
    }
}

/// Strict reader and writer for the v1 wire frame and the core bodies.
public enum HeddleWire {
    static let frameFields: Set<String> = [
        "message_id", "payload_type", "payload", "origin", "correlation_id",
        "causation_id", "occurred_at", "recorded_at",
    ]

    // MARK: Frame

    /// Two-step parse: the frame, then the body chosen by `payload_type`.
    public static func parse(_ data: Data) throws -> (WireEnvelope, WireBody) {
        let envelope = try parseFrame(data)
        return (envelope, try parseBody(envelope))
    }

    /// Validate the frame only. The body stays unvalidated JSON.
    public static func parseFrame(_ data: Data) throws -> WireEnvelope {
        try WireTextScanner.check(data)
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw WireFormatError(.frame, "message is not valid JSON")
        }
        guard case let .object(root) = value else {
            throw WireFormatError(.frame, "message is not a JSON object")
        }
        return try parseFrame(root)
    }

    /// Validate a frame that is already a JSON object.
    public static func parseFrame(_ root: [String: JSONValue]) throws -> WireEnvelope {
        let unknown = root.keys.filter { !$0.hasPrefix("_") && !frameFields.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw WireFormatError(
                .frame,
                "unknown top-level key(s) \(unknown); only declared fields and `_`-prefixed Middleware-Lane keys are accepted"
            )
        }
        let f = Fields(root, .frame)
        guard root["payload_type"] != nil else { throw WireFormatError(.frame, "payload_type is required") }
        guard root["payload"] != nil else { throw WireFormatError(.frame, "payload is required") }

        let occurred: WireTimestamp
        let recorded: WireTimestamp
        switch (root["occurred_at"] != nil, root["recorded_at"] != nil) {
        case (false, false):
            occurred = .now()
            recorded = occurred
        case (true, false):
            occurred = try timestamp(f, "occurred_at")
            recorded = occurred
        case (false, true):
            recorded = try timestamp(f, "recorded_at")
            occurred = recorded
        case (true, true):
            occurred = try timestamp(f, "occurred_at")
            recorded = try timestamp(f, "recorded_at")
        }

        return WireEnvelope(
            messageId: root["message_id"] == nil ? UUID().uuidString.lowercased() : try f.string("message_id"),
            payloadType: try f.string("payload_type"),
            payload: try f.object("payload"),
            origin: try f.optionalString("origin"),
            correlationId: try f.optionalString("correlation_id"),
            causationId: try f.optionalString("causation_id"),
            occurredAt: occurred,
            recordedAt: recorded,
            lane: root.filter { $0.key.hasPrefix("_") }
        )
    }

    /// Validate the body for the frame's `payload_type` (step two).
    public static func parseBody(_ envelope: WireEnvelope) throws -> WireBody {
        let f = Fields(envelope.payload, .body)
        switch envelope.payloadType {
        case PayloadTypes.taskMessage:
            return .taskMessage(TaskMessage(
                taskId: try f.string("task_id", default: UUID().uuidString.lowercased()),
                parentTaskId: try f.optionalString("parent_task_id"),
                workerType: try f.string("worker_type"),
                input: try f.object("input"),
                modelTier: try f.enumValue("model_tier", default: ModelTier.standard),
                priority: try f.enumValue("priority", default: TaskPriority.normal),
                requestId: try f.optionalString("request_id"),
                metadata: try f.object("metadata", default: [:])
            ))
        case PayloadTypes.taskResult:
            var tokens: [String: Int] = [:]
            for (key, value) in try f.object("token_usage", default: [:]) {
                tokens[key] = try integer(value, "token_usage.\(key)")
            }
            let output: [String: JSONValue]?
            switch envelope.payload["output"] {
            case nil, .some(.null): output = nil
            default: output = try f.object("output")
            }
            return .taskResult(TaskResult(
                taskId: try f.string("task_id"),
                parentTaskId: try f.optionalString("parent_task_id"),
                workerType: try f.string("worker_type"),
                status: try f.enumValue("status"),
                output: output,
                error: try f.optionalString("error"),
                modelUsed: try f.optionalString("model_used"),
                tokenUsage: tokens,
                metadata: try f.object("metadata", default: [:]),
                processingTimeMs: try envelope.payload["processing_time_ms"].map { try integer($0, "processing_time_ms") } ?? 0
            ))
        case PayloadTypes.orchestratorGoal:
            return .orchestratorGoal(OrchestratorGoal(
                goalId: try f.string("goal_id", default: UUID().uuidString.lowercased()),
                instruction: try f.string("instruction"),
                context: try f.object("context", default: [:]),
                requestId: try f.optionalString("request_id"),
                priority: try f.enumValue("priority", default: TaskPriority.normal)
            ))
        default:
            throw WireFormatError(.dispatch, "no payload model registered for '\(envelope.payloadType)'")
        }
    }

    /// Build a frame around a typed body. Both timestamps take one fresh
    /// instant. `lane` is copied onto the frame; every key must start with `_`.
    public static func wrap(
        _ body: WireBody,
        lane: [String: JSONValue] = [:],
        origin: String? = nil,
        correlationId: String? = nil,
        causationId: String? = nil
    ) -> WireEnvelope {
        precondition(lane.keys.allSatisfy { $0.hasPrefix("_") }, "Middleware-Lane keys must start with '_'")
        let now = WireTimestamp.now()
        return WireEnvelope(
            payloadType: body.payloadType,
            payload: bodyObject(body),
            origin: origin,
            correlationId: correlationId,
            causationId: causationId,
            occurredAt: now,
            recordedAt: now,
            lane: lane
        )
    }

    /// The frame as a JSON object. Every field is written, nulls included.
    public static func jsonObject(_ envelope: WireEnvelope) -> [String: JSONValue] {
        var root = envelope.lane
        root["message_id"] = .string(envelope.messageId)
        root["payload_type"] = .string(envelope.payloadType)
        root["payload"] = .object(envelope.payload)
        root["origin"] = optional(envelope.origin)
        root["correlation_id"] = optional(envelope.correlationId)
        root["causation_id"] = optional(envelope.causationId)
        root["occurred_at"] = .string(envelope.occurredAt.rfc3339)
        root["recorded_at"] = .string(envelope.recordedAt.rfc3339)
        return root
    }

    /// The frame as UTF-8 JSON, ready to publish.
    public static func serialize(_ envelope: WireEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(jsonObject(envelope)))
    }

    /// The body as JSON, every field written.
    public static func bodyObject(_ body: WireBody) -> [String: JSONValue] {
        switch body {
        case let .taskMessage(t):
            return [
                "task_id": .string(t.taskId),
                "parent_task_id": optional(t.parentTaskId),
                "worker_type": .string(t.workerType),
                "input": .object(t.input),
                "model_tier": .string(t.modelTier.rawValue),
                "priority": .string(t.priority.rawValue),
                "request_id": optional(t.requestId),
                "metadata": .object(t.metadata),
            ]
        case let .taskResult(r):
            return [
                "task_id": .string(r.taskId),
                "parent_task_id": optional(r.parentTaskId),
                "worker_type": .string(r.workerType),
                "status": .string(r.status.rawValue),
                "output": r.output.map { .object($0) } ?? .null,
                "error": optional(r.error),
                "model_used": optional(r.modelUsed),
                "token_usage": .object(r.tokenUsage.mapValues { .int($0) }),
                "metadata": .object(r.metadata),
                "processing_time_ms": .int(r.processingTimeMs),
            ]
        case let .orchestratorGoal(g):
            return [
                "goal_id": .string(g.goalId),
                "instruction": .string(g.instruction),
                "context": .object(g.context),
                "request_id": optional(g.requestId),
                "priority": .string(g.priority.rawValue),
            ]
        }
    }

    // MARK: Helpers

    private static func optional(_ value: String?) -> JSONValue {
        value.map { .string($0) } ?? .null
    }

    private static func timestamp(_ f: Fields, _ key: String) throws -> WireTimestamp {
        // A present key must be a valid timestamp: an explicit null is not "absent".
        guard let value = WireTimestamp.parse(try f.string(key)) else {
            throw WireFormatError(.frame, "\(key) must be an RFC 3339 date-time string with a UTC offset")
        }
        return value
    }

    /// A JSON integer. As in JSON Schema's `integer`, an integral number
    /// written as a float (`420.0`, `1e3`) is accepted; strings, booleans,
    /// fractions and null are rejected.
    static func integer(_ value: JSONValue, _ path: String) throws -> Int {
        switch value {
        case let .int(v):
            return v
        case let .double(d) where d.rounded() == d && abs(d) < 9.2e18:
            return Int(d)
        default:
            throw WireFormatError(.body, "\(path) must be an integer")
        }
    }

    /// Typed, layer-tagged field readers over one JSON object.
    struct Fields {
        let object: [String: JSONValue]
        let layer: WireLayer

        init(_ object: [String: JSONValue], _ layer: WireLayer) {
            self.object = object
            self.layer = layer
        }

        func string(_ key: String, default fallback: @autoclosure () -> String? = nil) throws -> String {
            switch object[key] {
            case let .some(.string(value)): return value
            case nil:
                if let fallback = fallback() { return fallback }
                throw WireFormatError(layer, "\(key) is required")
            default: throw WireFormatError(layer, "\(key) must be a string")
            }
        }

        func optionalString(_ key: String) throws -> String? {
            switch object[key] {
            case nil, .some(.null): return nil
            case let .some(.string(value)): return value
            default: throw WireFormatError(layer, "\(key) must be a string")
            }
        }

        func object(_ key: String, default fallback: [String: JSONValue]? = nil) throws -> [String: JSONValue] {
            switch object[key] {
            case let .some(.object(value)): return value
            case nil:
                if let fallback { return fallback }
                throw WireFormatError(layer, "\(key) is required")
            default: throw WireFormatError(layer, "\(key) must be a JSON object")
            }
        }

        func enumValue<E: RawRepresentable>(_ key: String, default fallback: E? = nil) throws -> E
            where E.RawValue == String
        {
            if object[key] == nil, let fallback { return fallback }
            let text = try string(key)
            guard let value = E(rawValue: text) else {
                throw WireFormatError(layer, "\(key): unknown value '\(text)'")
            }
            return value
        }
    }
}

// MARK: - Wire-text rules (I-JSON subset)

/// Enforces the two I-JSON rules the v1 contract takes (fixtures README,
/// "Message text"): member names are unique in every object at every depth
/// (compared after unescaping), and a number with a fraction or exponent
/// must not overflow a double. Integer literals are exempt. Nesting deeper
/// than ``maxDepth`` is rejected too. `JSONDecoder` cannot see repeated names
/// (it keeps one silently), so this runs first; it does not validate full
/// JSON syntax, which the decoder does afterwards.
enum WireTextScanner {
    static let maxDepth = 1_000

    private enum Container {
        case object(Set<String>, expectingName: Bool)
        case array
    }

    static func check(_ data: Data) throws {
        let b = [UInt8](data)
        var stack: [Container] = []
        var i = 0
        func fail(_ message: String) -> WireFormatError { WireFormatError(.frame, message) }

        while i < b.count {
            let c = b[i]
            switch c {
            case UInt8(ascii: "{"):
                stack.append(.object([], expectingName: true))
                guard stack.count <= maxDepth else { throw fail("JSON nesting is too deep") }
                i += 1
            case UInt8(ascii: "["):
                stack.append(.array)
                guard stack.count <= maxDepth else { throw fail("JSON nesting is too deep") }
                i += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if !stack.isEmpty { stack.removeLast() }
                i += 1
            case UInt8(ascii: ","):
                if case let .object(names, _) = stack.last {
                    stack[stack.count - 1] = .object(names, expectingName: true)
                }
                i += 1
            case UInt8(ascii: "\""):
                let (text, next) = try readString(b, from: i)
                if case .object(var names, true) = stack.last {
                    guard names.insert(text).inserted else { throw fail("repeated member name '\(text)'") }
                    stack[stack.count - 1] = .object(names, expectingName: false)
                }
                i = next
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                var j = i
                while j < b.count, isNumberByte(b[j]) { j += 1 }
                let literal = String(decoding: b[i..<j], as: UTF8.self)
                if literal.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }),
                   let value = Double(literal), value.isInfinite
                {
                    throw fail("number \(literal) is outside the IEEE 754 double range")
                }
                i = j
            default:
                i += 1
            }
        }
    }

    private static func isNumberByte(_ c: UInt8) -> Bool {
        (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
            || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
            || c == UInt8(ascii: "e") || c == UInt8(ascii: "E")
    }

    /// Read the JSON string starting at `start` (a quote) and return its
    /// unescaped text and the index just past the closing quote.
    private static func readString(_ b: [UInt8], from start: Int) throws -> (String, Int) {
        var units: [UInt16] = []
        var i = start + 1
        func hex4(_ at: Int) throws -> UInt16 {
            guard at + 4 <= b.count, let v = UInt16(String(decoding: b[at..<(at + 4)], as: UTF8.self), radix: 16)
            else { throw WireFormatError(.frame, "message is not valid JSON") }
            return v
        }
        var raw: [UInt8] = []
        func flushRaw() {
            if !raw.isEmpty {
                units.append(contentsOf: String(decoding: raw, as: UTF8.self).utf16)
                raw.removeAll()
            }
        }
        while i < b.count {
            let c = b[i]
            if c == UInt8(ascii: "\"") {
                flushRaw()
                return (String(decoding: units, as: UTF16.self), i + 1)
            }
            if c == UInt8(ascii: "\\"), i + 1 < b.count {
                flushRaw()
                let e = b[i + 1]
                switch e {
                case UInt8(ascii: "u"):
                    units.append(try hex4(i + 2))
                    i += 6
                    continue
                case UInt8(ascii: "n"): units.append(0x0A)
                case UInt8(ascii: "t"): units.append(0x09)
                case UInt8(ascii: "r"): units.append(0x0D)
                case UInt8(ascii: "b"): units.append(0x08)
                case UInt8(ascii: "f"): units.append(0x0C)
                default: units.append(UInt16(e))
                }
                i += 2
                continue
            }
            raw.append(c)
            i += 1
        }
        throw WireFormatError(.frame, "message is not valid JSON")
    }
}

// MARK: - Calendar arithmetic (proleptic Gregorian, UTC)

private let minUtcSeconds = Int64(daysFromCivil(year: 1, month: 1, day: 1)) * 86_400
private let maxUtcSeconds = Int64(daysFromCivil(year: 9_999, month: 12, day: 31)) * 86_400 + 86_399

private func isLeap(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

private func daysIn(year: Int, month: Int) -> Int {
    switch month {
    case 2: isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}

// Howard Hinnant's days_from_civil / civil_from_days.
private func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}

private func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
    let z = z0 + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
}

private func floorDivMod(_ a: Int64, _ b: Int64) -> (Int64, Int64) {
    var q = a / b
    var r = a % b
    if r < 0 {
        q -= 1
        r += b
    }
    return (q, r)
}
