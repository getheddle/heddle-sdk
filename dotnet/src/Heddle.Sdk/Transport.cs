namespace Heddle.Sdk;

public readonly record struct HeddleMessage(string Subject, ReadOnlyMemory<byte> Payload);

/// <summary>
/// Transport abstraction for Heddle actor runtimes.
/// </summary>
public interface IHeddleTransport : IAsyncDisposable
{
    Task PublishAsync(
        string subject,
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken = default);

    IAsyncEnumerable<HeddleMessage> SubscribeAsync(
        string subject,
        string? queueGroup = null,
        CancellationToken cancellationToken = default);
}

