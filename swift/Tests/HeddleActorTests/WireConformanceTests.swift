import Foundation
import Testing
@testable import HeddleActor

/// Holds the SDK to the vendored v1 conformance fixtures
/// (schemas/v1/fixtures, driven by manifest.json), the same files heddle's
/// own runtime is tested against.
enum Fixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("schemas/v1/fixtures")
    }()

    static let manifest: [String: JSONValue] = {
        let data = try! Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        return try! JSONDecoder().decode(JSONValue.self, from: data).objectValue!
    }()

    static var entries: [[String: JSONValue]] {
        guard case let .array(items) = manifest["fixtures"] else { return [] }
        return items.compactMap(\.objectValue)
    }

    static func files(_ expect: String) -> [String] {
        entries.filter { $0["expect"]?.stringValue == expect }.compactMap { $0["file"]?.stringValue }
    }

    static func entry(_ file: String) -> [String: JSONValue] {
        entries.first { $0["file"]?.stringValue == file }!
    }

    static func data(_ file: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(file))
    }
}

@Test func manifestRegistersExactlyTheSdkPayloadTypes() {
    let registered = Fixtures.manifest["payload_types"]?.objectValue?.keys.sorted() ?? []
    #expect(registered == PayloadTypes.all.sorted())
}

@Test func manifestListsTwentySevenFixtures() {
    #expect(Fixtures.files("valid").count + Fixtures.files("invalid").count == 27)
}

@Test(arguments: [
    #"{"payload_type":"core.TaskMessage","payload":{},"_x":{"a":1,"\u0061":2}}"#,
    #"{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"n":1e400}}}"#,
    #"{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"n":NaN}}}"#,
    #"{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"t":"a\"b","t":1}}}"#,
])
func textThatIsNotIJsonIsAFrameError(raw: String) {
    #expect(throws: WireFormatError.self) { try HeddleWire.parse(Data(raw.utf8)) }
    do { _ = try HeddleWire.parse(Data(raw.utf8)) } catch let error as WireFormatError {
        #expect(error.layer == .frame)
    } catch {
        Issue.record("unexpected error \(error)")
    }
}

@Test func sameNameInSiblingObjectsAndEscapedQuotesAreFine() throws {
    let raw = #"{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"a":{"k":1},"b":{"k":"x\"k\":"}}}}"#
    let (_, body) = try HeddleWire.parse(Data(raw.utf8))
    guard case .taskMessage = body else {
        Issue.record("expected a TaskMessage")
        return
    }
}

@Test func nestingDeeperThanTheLimitIsAFrameError() {
    let deep = String(repeating: "[", count: 2_000) + String(repeating: "]", count: 2_000)
    let raw = #"{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"d":"# + deep + "}}}"
    do {
        _ = try HeddleWire.parse(Data(raw.utf8))
        Issue.record("accepted")
    } catch let error as WireFormatError {
        #expect(error.layer == .frame)
    } catch {
        Issue.record("unexpected error \(error)")
    }
}

@Test(arguments: Fixtures.files("valid"))
func validFixtureParsesAndRoundTrips(file: String) throws {
    let entry = Fixtures.entry(file)
    let data = try Fixtures.data(file)

    let (envelope, body) = try HeddleWire.parse(data)
    #expect(envelope.payloadType == entry["payload_type"]?.stringValue)

    // Re-serialize from the typed body, not the raw payload.
    var reframed = HeddleWire.wrap(
        body, lane: envelope.lane, origin: envelope.origin,
        correlationId: envelope.correlationId, causationId: envelope.causationId
    )
    reframed.messageId = envelope.messageId
    reframed.occurredAt = envelope.occurredAt
    reframed.recordedAt = envelope.recordedAt

    var actual = HeddleWire.jsonObject(reframed)
    var expected = try JSONDecoder().decode(JSONValue.self, from: data).objectValue!

    if case let .array(paths) = entry["may_drop"] {
        for path in paths.compactMap(\.stringValue) {
            drop(&expected, path)
            drop(&actual, path)
        }
    }
    for key in ["occurred_at", "recorded_at"] {
        let want = try #require(expected[key]?.stringValue.flatMap(WireTimestamp.parse))
        let got = try #require(actual[key]?.stringValue.flatMap(WireTimestamp.parse))
        #expect(want == got, "\(key) in \(file)")
        expected[key] = nil
        actual[key] = nil
    }
    // JSONValue compares numbers by case; the decoder already maps integral
    // floats (420.0) to .int, so equal values compare equal.
    #expect(JSONValue.object(expected) == JSONValue.object(actual), "round-trip mismatch for \(file)")
}

@Test(arguments: Fixtures.files("invalid"))
func invalidFixtureIsRejectedAtTheNamedLayer(file: String) throws {
    let want = WireLayer(rawValue: Fixtures.entry(file)["rejected_at"]?.stringValue ?? "")
    let data = try Fixtures.data(file)
    do {
        _ = try HeddleWire.parse(data)
        Issue.record("\(file) was accepted")
    } catch let error as WireFormatError {
        #expect(error.layer == want, "\(file): \(error)")
    }
}

@Test(arguments: [
    ("2026-01-01T00:00:00Z", true),
    ("2026-01-01t00:00:00z", true),
    ("2026-01-01T00:00:00.123456789+02:00", true),
    ("2024-02-29T23:59:59-23:59", true),
    ("2026-01-01T00:00:00", false),
    ("2026-01-01T00:00:00+0200", false),
    ("2026-01-01T00:00:60Z", false),
    ("2026-02-30T00:00:00Z", false),
    ("2026-01-01T00:00:00Z\n", false),
    ("2026-01-01T00:00:00.Z", false),
    ("0001-01-01T00:00:00+01:00", false),
    ("9999-12-31T23:59:59-01:00", false),
    ("0001-01-01T00:00:00Z", true),
    ("9999-12-31T23:59:59.999999Z", true),
])
func timestampsFollowRfc3339WithOffset(text: String, ok: Bool) {
    #expect((WireTimestamp.parse(text) != nil) == ok, "\(text)")
}

@Test func timestampFormattingIsUtcWithMicroseconds() throws {
    let value = try #require(WireTimestamp.parse("2026-01-01T02:00:00.1234569+02:00"))
    #expect(value.rfc3339 == "2026-01-01T00:00:00.123456Z")
    let early = try #require(WireTimestamp.parse("1969-12-31T23:59:59.5Z"))
    #expect(early.rfc3339 == "1969-12-31T23:59:59.500000Z")
}

@Test func missingTimestampsAreFilledTogether() throws {
    let none = try HeddleWire.parseFrame(Data(#"{"payload_type":"core.TaskMessage","payload":{}}"#.utf8))
    #expect(none.occurredAt == none.recordedAt)
    let one = try HeddleWire.parseFrame(
        Data(#"{"payload_type":"core.TaskMessage","payload":{},"occurred_at":"2026-01-01T00:00:00Z"}"#.utf8)
    )
    #expect(one.occurredAt == one.recordedAt)
}

private func drop(_ object: inout [String: JSONValue], _ dottedPath: String) {
    let parts = dottedPath.split(separator: ".").map(String.init)
    if parts.count == 1 {
        object[parts[0]] = nil
    } else if case var .object(child) = object[parts[0]] {
        drop(&child, parts.dropFirst().joined(separator: "."))
        object[parts[0]] = .object(child)
    }
}
