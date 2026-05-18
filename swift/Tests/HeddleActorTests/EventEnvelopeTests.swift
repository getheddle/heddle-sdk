import Foundation
@testable import HeddleActor

#if canImport(Testing)
import Testing

@Test func eventEnvelopeRoundTripUsesSnakeCaseWireKeys() throws {
    let env = makeEventEnvelope()
    let data = try HeddleCoders.encode(env)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(json["event_id"] as? String == "evt-1")
    #expect(json["aggregate_type"] as? String == "Job")
    #expect(json["aggregate_id"] as? String == "39174-004")
    #expect(json["aggregate_version"] as? Int == 1)
    #expect(json["event_type"] as? String == "JobClockedIn")
    #expect(json["occurred_at"] as? String == "2026-05-16T12:00:00Z")
    #expect(json["recorded_at"] as? String == "2026-05-16T12:00:01Z")

    let metadata = try #require(json["metadata"] as? [String: Any])
    #expect(metadata["issued_by"] as? String == "user:badge:206")

    let decoded = try HeddleCoders.decode(EventEnvelope.self, from: data)
    #expect(decoded == env)
}

@Test func commandMessageRoundTripPreservesReservedLegacySlot() throws {
    let cmd = makeCommandMessage(issuedByLegacy: "legacy-value")
    let data = try HeddleCoders.encode(cmd)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let metadata = try #require(json["metadata"] as? [String: Any])
    #expect(metadata["issued_by_legacy"] as? String == "legacy-value")
    #expect(json["expected_aggregate_version"] as? Int == 7)

    let decoded = try HeddleCoders.decode(CommandMessage.self, from: data)
    #expect(decoded == cmd)
}

@Test func commandMessageNilExpectedAggregateVersion() throws {
    let cmd = makeCommandMessage(expectedAggregateVersion: nil)
    let data = try HeddleCoders.encode(cmd)
    let decoded = try HeddleCoders.decode(CommandMessage.self, from: data)
    #expect(decoded.expectedAggregateVersion == nil)
}

@Test func eventSubjectFormation() throws {
    #expect(
        try EventSubjects.event(
            aggregateType: "Job",
            aggregateId: "39174-004",
            eventType: "JobShippedFromPF"
        ) == "heddle.events.Job.39174-004.JobShippedFromPF"
    )
    #expect(
        try EventSubjects.command(
            aggregateType: "Operation",
            aggregateId: "39174-004:laser-cut",
            commandType: "RecordLabor"
        ) == "heddle.commands.Operation.39174-004:laser-cut.RecordLabor"
    )
    #expect(
        try EventSubjects.rejection(
            aggregateType: "Job",
            aggregateId: "39174-004",
            commandType: "JobClockIn"
        ) == "heddle.rejections.Job.39174-004.JobClockIn"
    )
}

@Test func eventStreamNamesUseUppercaseAggregateType() throws {
    #expect(try EventSubjects.eventStream(aggregateType: "Operation") == "HEDDLE_EVENTS_OPERATION")
    #expect(try EventSubjects.commandStream(aggregateType: "Job") == "HEDDLE_COMMANDS_JOB")
    #expect(
        try EventSubjects.rejectionStream(aggregateType: "OperatorJobSession")
            == "HEDDLE_REJECTIONS_OPERATORJOBSESSION"
    )
}

@Test func eventSubjectFilterUsesGreaterThanWildcard() throws {
    #expect(try EventSubjects.eventFilter(aggregateType: "Job") == "heddle.events.Job.>")
    #expect(try EventSubjects.commandFilter(aggregateType: "Job") == "heddle.commands.Job.>")
    #expect(try EventSubjects.rejectionFilter(aggregateType: "Job") == "heddle.rejections.Job.>")
}

@Test func eventSubjectRejectsForbiddenCharacters() {
    #expect(throws: EventSubjects.SubjectError.self) {
        try EventSubjects.event(aggregateType: "Job.Bad", aggregateId: "x", eventType: "Y")
    }
    #expect(throws: EventSubjects.SubjectError.self) {
        try EventSubjects.event(aggregateType: "Job", aggregateId: "*", eventType: "Y")
    }
    #expect(throws: EventSubjects.SubjectError.self) {
        try EventSubjects.event(aggregateType: "Job", aggregateId: "x", eventType: ">")
    }
}

@Test func eventSubjectRejectsEmptyToken() {
    #expect(throws: EventSubjects.SubjectError.self) {
        try EventSubjects.event(aggregateType: "Job", aggregateId: "", eventType: "Y")
    }
}
#endif

private func makeEventEnvelope() -> EventEnvelope {
    EventEnvelope(
        eventId: "evt-1",
        aggregateType: "Job",
        aggregateId: "39174-004",
        aggregateVersion: 1,
        eventType: "JobClockedIn",
        payload: ["badge": .string("206")],
        metadata: EventMetadata(issuedBy: "user:badge:206"),
        occurredAt: "2026-05-16T12:00:00Z",
        recordedAt: "2026-05-16T12:00:01Z"
    )
}

private func makeCommandMessage(
    expectedAggregateVersion: Int? = 7,
    issuedByLegacy: String? = nil
) -> CommandMessage {
    CommandMessage(
        commandId: "cmd-1",
        aggregateType: "Job",
        aggregateId: "39174-004",
        commandType: "JobClockIn",
        payload: ["badge": .string("206")],
        metadata: CommandMetadata(
            issuedBy: "user:badge:206",
            issuedByLegacy: issuedByLegacy
        ),
        issuedAt: "2026-05-16T12:00:00Z",
        expectedAggregateVersion: expectedAggregateVersion
    )
}
