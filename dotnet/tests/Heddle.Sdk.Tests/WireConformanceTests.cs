using System.Text.Json;
using System.Text.Json.Nodes;
using Heddle.Sdk;
using Xunit;

namespace Heddle.Sdk.Tests;

/// <summary>
/// Holds the SDK to the vendored v1 conformance fixtures
/// (schemas/v1/fixtures, driven by manifest.json), the same files
/// heddle's own runtime is tested against.
/// </summary>
public sealed class WireConformanceTests
{
    public static IEnumerable<object[]> ValidFixtures() => Fixtures("valid");

    public static IEnumerable<object[]> InvalidFixtures() => Fixtures("invalid");

    [Fact]
    public void ManifestRegistersExactlyTheSdkPayloadTypes()
    {
        var registered = Manifest()["payload_types"]!.AsObject().Select(p => p.Key).OrderBy(k => k);
        Assert.Equal(PayloadTypes.All.OrderBy(k => k), registered);
    }

    [Theory]
    [MemberData(nameof(ValidFixtures))]
    public void ValidFixtureParsesAndRoundTrips(string file)
    {
        var entry = Entry(file);
        var bytes = File.ReadAllBytes(Path.Combine(FixtureDir, file));

        var (envelope, body) = HeddleWire.Parse(bytes);
        Assert.Equal(entry["payload_type"]!.GetValue<string>(), envelope.PayloadType);

        // Re-serialize from the typed body, not the raw payload.
        var reframed = HeddleWire.Wrap(body, envelope.Lane, envelope.Origin, envelope.CorrelationId, envelope.CausationId)
            with
            {
                MessageId = envelope.MessageId,
                OccurredAt = envelope.OccurredAt,
                RecordedAt = envelope.RecordedAt,
            };
        var actual = HeddleWire.ToJsonObject(reframed);
        var expected = JsonNode.Parse(bytes)!.AsObject();

        foreach (var path in (entry["may_drop"]?.AsArray() ?? []).Select(p => p!.GetValue<string>()))
        {
            Drop(expected, path);
            Drop(actual, path);
        }

        foreach (var key in new[] { "occurred_at", "recorded_at" })
        {
            Assert.True(HeddleWire.TryParseTimestamp(expected[key]!.GetValue<string>(), out var want));
            Assert.True(HeddleWire.TryParseTimestamp(actual[key]!.GetValue<string>(), out var got));
            Assert.Equal(want, got);
            expected.Remove(key);
            actual.Remove(key);
        }

        Assert.True(
            JsonValueEquals(expected, actual),
            $"round-trip mismatch for {file}:\nexpected {expected.ToJsonString()}\nactual   {actual.ToJsonString()}");
    }

    [Theory]
    [MemberData(nameof(InvalidFixtures))]
    public void InvalidFixtureIsRejectedAtTheNamedLayer(string file)
    {
        var entry = Entry(file);
        var bytes = File.ReadAllBytes(Path.Combine(FixtureDir, file));

        var error = Assert.Throws<WireFormatException>(() => HeddleWire.Parse(bytes));
        var want = Enum.Parse<WireLayer>(entry["rejected_at"]!.GetValue<string>(), ignoreCase: true);
        Assert.Equal(want, error.Layer);
    }

    [Theory]
    [InlineData("2026-01-01T00:00:00Z", true)]
    [InlineData("2026-01-01t00:00:00z", true)]
    [InlineData("2026-01-01T00:00:00.123456789+02:00", true)]
    [InlineData("2026-01-01T00:00:00", false)]
    [InlineData("2026-01-01T00:00:00+0200", false)]
    [InlineData("2026-01-01T00:00:60Z", false)]
    [InlineData("2026-02-30T00:00:00Z", false)]
    [InlineData("2026-01-01T00:00:00Z\n", false)]
    [InlineData("0001-01-01T00:00:00+01:00", false)]
    [InlineData("9999-12-31T23:59:59-01:00", false)]
    [InlineData("0001-01-01T00:00:00Z", true)]
    [InlineData("9999-12-31T23:59:59.999999Z", true)]
    public void TimestampsFollowRfc3339WithOffset(string text, bool ok)
    {
        Assert.Equal(ok, HeddleWire.TryParseTimestamp(text, out _));
    }

    [Theory]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{},"_x":{"a":1,"\u0061":2}}""")]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"n":1e400}}}""")]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"n":NaN}}}""")]
    public void TextThatIsNotIJsonIsAFrameError(string raw)
    {
        var error = Assert.Throws<WireFormatException>(() => HeddleWire.Parse(System.Text.Encoding.UTF8.GetBytes(raw)));
        Assert.Equal(WireLayer.Frame, error.Layer);
    }

    [Fact]
    public void SameNameInSiblingObjectsAndLargeIntegersAreFine()
    {
        var (_, body) = HeddleWire.Parse(
            """{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"a":{"k":1},"b":{"k":2},"big":123456789012345678901234567890}}}"""u8);
        var task = Assert.IsType<TaskMessage>(body);
        Assert.Equal("123456789012345678901234567890", task.Input["big"]!.ToJsonString());
    }

    [Fact]
    public void NestingDeeperThanTheLimitIsAFrameError()
    {
        var deep = new string('[', 2000) + new string(']', 2000);
        var raw = """{"payload_type":"core.TaskMessage","payload":{"worker_type":"w","input":{"d":""" + deep + "}}}";
        var error = Assert.Throws<WireFormatException>(() => HeddleWire.Parse(System.Text.Encoding.UTF8.GetBytes(raw)));
        Assert.Equal(WireLayer.Frame, error.Layer);
    }

    [Fact]
    public void FractionBeyondMicrosecondsIsTruncated()
    {
        Assert.True(HeddleWire.TryParseTimestamp("2026-01-01T00:00:00.1234569Z", out var value));
        Assert.Equal("2026-01-01T00:00:00.123456Z", HeddleWire.FormatTimestamp(value));
    }

    [Fact]
    public void MissingTimestampsAreFilledTogether()
    {
        var none = HeddleWire.ParseFrame("""{"payload_type":"core.TaskMessage","payload":{}}"""u8);
        Assert.Equal(none.OccurredAt, none.RecordedAt);

        var one = HeddleWire.ParseFrame(
            """{"payload_type":"core.TaskMessage","payload":{},"occurred_at":"2026-01-01T00:00:00Z"}"""u8);
        Assert.Equal(one.OccurredAt, one.RecordedAt);
    }

    // ------------------------------------------------------------------

    internal static string FixtureDir { get; } = Path.Combine(RepoRoot(), "schemas", "v1", "fixtures");

    private static JsonObject Manifest() =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(FixtureDir, "manifest.json")))!.AsObject();

    private static IEnumerable<object[]> Fixtures(string expect) =>
        Manifest()["fixtures"]!.AsArray()
            .Where(f => f!["expect"]!.GetValue<string>() == expect)
            .Select(f => new object[] { f!["file"]!.GetValue<string>() });

    private static JsonObject Entry(string file) =>
        Manifest()["fixtures"]!.AsArray().Single(f => f!["file"]!.GetValue<string>() == file)!.AsObject();

    private static string RepoRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "schemas", "manifest.json")))
            {
                return dir.FullName;
            }
        }

        throw new InvalidOperationException("repository root (schemas/manifest.json) not found");
    }

    private static void Drop(JsonObject root, string dottedPath)
    {
        var parts = dottedPath.Split('.');
        JsonObject? node = root;
        foreach (var part in parts[..^1])
        {
            node = node?[part] as JsonObject;
        }

        node?.Remove(parts[^1]);
    }

    /// <summary>JSON equality by value: key order is ignored and numbers compare numerically.</summary>
    internal static bool JsonValueEquals(JsonNode? a, JsonNode? b)
    {
        switch (a, b)
        {
            case (null, null):
                return true;
            case (JsonObject oa, JsonObject ob):
                return oa.Count == ob.Count
                    && oa.All(p => ob.ContainsKey(p.Key) && JsonValueEquals(p.Value, ob[p.Key]));
            case (JsonArray aa, JsonArray ab):
                return aa.Count == ab.Count && aa.Zip(ab).All(p => JsonValueEquals(p.First, p.Second));
            case (JsonValue va, JsonValue vb):
                var ka = va.GetValueKind();
                if (ka != vb.GetValueKind())
                {
                    return false;
                }

                return ka == JsonValueKind.Number
                    ? double.Parse(va.ToJsonString(), System.Globalization.CultureInfo.InvariantCulture)
                        == double.Parse(vb.ToJsonString(), System.Globalization.CultureInfo.InvariantCulture)
                    : va.ToJsonString() == vb.ToJsonString();
            default:
                return false;
        }
    }
}
