using System.Text.Json;
using System.Text.Json.Nodes;
using Heddle.Sdk;
using Xunit;

namespace Heddle.Sdk.Tests;

public sealed class EnvelopeRoundTripTests
{
    private static EventEnvelope MakeEventEnvelope() => new()
    {
        EventId = "evt-1",
        AggregateType = "Job",
        AggregateId = "39174-004",
        AggregateVersion = 1,
        EventType = "JobClockedIn",
        Payload = new JsonObject { ["badge"] = "206" },
        Metadata = new EventMetadata { IssuedBy = "user:badge:206" },
        OccurredAt = "2026-05-16T12:00:00Z",
        RecordedAt = "2026-05-16T12:00:01Z",
    };

    private static CommandMessage MakeCommandMessage(
        int? expectedAggregateVersion = 7,
        string? issuedByLegacy = null) => new()
    {
        CommandId = "cmd-1",
        AggregateType = "Job",
        AggregateId = "39174-004",
        CommandType = "JobClockIn",
        Payload = new JsonObject { ["badge"] = "206" },
        Metadata = new CommandMetadata
        {
            IssuedBy = "user:badge:206",
            IssuedByLegacy = issuedByLegacy,
        },
        IssuedAt = "2026-05-16T12:00:00Z",
        ExpectedAggregateVersion = expectedAggregateVersion,
    };

    [Fact]
    public void EventEnvelopeRoundTripUsesSnakeCaseWireKeys()
    {
        var env = MakeEventEnvelope();
        var data = HeddleJson.SerializeToBytes(env);
        var json = JsonSerializer.Deserialize<JsonObject>(data, HeddleJson.Options)
            ?? throw new JsonException("Unable to read envelope JSON.");

        Assert.Equal("evt-1", json["event_id"]?.GetValue<string>());
        Assert.Equal("Job", json["aggregate_type"]?.GetValue<string>());
        Assert.Equal("39174-004", json["aggregate_id"]?.GetValue<string>());
        Assert.Equal(1, json["aggregate_version"]?.GetValue<int>());
        Assert.Equal("JobClockedIn", json["event_type"]?.GetValue<string>());
        Assert.Equal("2026-05-16T12:00:00Z", json["occurred_at"]?.GetValue<string>());
        Assert.Equal("2026-05-16T12:00:01Z", json["recorded_at"]?.GetValue<string>());

        var metadata = json["metadata"]?.AsObject();
        Assert.NotNull(metadata);
        Assert.Equal("user:badge:206", metadata!["issued_by"]?.GetValue<string>());

        var decoded = HeddleJson.Deserialize<EventEnvelope>(data);
        Assert.Equal(env.EventId, decoded.EventId);
        Assert.Equal(env.AggregateVersion, decoded.AggregateVersion);
        Assert.Equal("user:badge:206", decoded.Metadata.IssuedBy);
    }

    [Fact]
    public void CommandMessageRoundTripPreservesReservedLegacySlot()
    {
        var cmd = MakeCommandMessage(issuedByLegacy: "legacy-value");
        var data = HeddleJson.SerializeToBytes(cmd);
        var json = JsonSerializer.Deserialize<JsonObject>(data, HeddleJson.Options)
            ?? throw new JsonException("Unable to read command JSON.");

        var metadata = json["metadata"]?.AsObject();
        Assert.NotNull(metadata);
        Assert.Equal("legacy-value", metadata!["issued_by_legacy"]?.GetValue<string>());
        Assert.Equal(7, json["expected_aggregate_version"]?.GetValue<int>());

        var decoded = HeddleJson.Deserialize<CommandMessage>(data);
        Assert.Equal(cmd.CommandId, decoded.CommandId);
        Assert.Equal(7, decoded.ExpectedAggregateVersion);
        Assert.Equal("legacy-value", decoded.Metadata.IssuedByLegacy);
    }

    [Fact]
    public void CommandMessageNilExpectedAggregateVersion()
    {
        var cmd = MakeCommandMessage(expectedAggregateVersion: null);
        var data = HeddleJson.SerializeToBytes(cmd);
        var decoded = HeddleJson.Deserialize<CommandMessage>(data);
        Assert.Null(decoded.ExpectedAggregateVersion);
    }

    [Fact]
    public void EventSubjectFormation()
    {
        Assert.Equal(
            "heddle.events.Job.39174-004.JobShippedFromPF",
            EventSubjects.Event("Job", "39174-004", "JobShippedFromPF"));
        Assert.Equal(
            "heddle.commands.Operation.39174-004:laser-cut.RecordLabor",
            EventSubjects.Command("Operation", "39174-004:laser-cut", "RecordLabor"));
        Assert.Equal(
            "heddle.rejections.Job.39174-004.JobClockIn",
            EventSubjects.Rejection("Job", "39174-004", "JobClockIn"));
    }

    [Fact]
    public void EventStreamNamesUseUppercaseAggregateType()
    {
        Assert.Equal("HEDDLE_EVENTS_OPERATION", EventSubjects.EventStream("Operation"));
        Assert.Equal("HEDDLE_COMMANDS_JOB", EventSubjects.CommandStream("Job"));
        Assert.Equal(
            "HEDDLE_REJECTIONS_OPERATORJOBSESSION",
            EventSubjects.RejectionStream("OperatorJobSession"));
    }

    [Fact]
    public void EventSubjectFilterUsesGreaterThanWildcard()
    {
        Assert.Equal("heddle.events.Job.>", EventSubjects.EventFilter("Job"));
        Assert.Equal("heddle.commands.Job.>", EventSubjects.CommandFilter("Job"));
        Assert.Equal("heddle.rejections.Job.>", EventSubjects.RejectionFilter("Job"));
    }

    [Fact]
    public void EventSubjectRejectsForbiddenCharacters()
    {
        Assert.Throws<ArgumentException>(() => EventSubjects.Event("Job.Bad", "x", "Y"));
        Assert.Throws<ArgumentException>(() => EventSubjects.Event("Job", "*", "Y"));
        Assert.Throws<ArgumentException>(() => EventSubjects.Event("Job", "x", ">"));
    }

    [Fact]
    public void EventSubjectRejectsEmptyToken()
    {
        Assert.Throws<ArgumentException>(() => EventSubjects.Event("Job", "", "Y"));
    }
}
