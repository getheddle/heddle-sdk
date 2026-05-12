using System.Runtime.CompilerServices;
using NATS.Client.Core;

namespace Heddle.Sdk.Nats;

/// <summary>
/// NATS Core transport adapter for Heddle processor workers.
/// </summary>
public sealed class NatsHeddleTransport : IHeddleTransport
{
    private readonly NatsConnection connection;
    private readonly bool ownsConnection;

    public NatsHeddleTransport(string url = "nats://localhost:4222")
        : this(NatsOpts.Default with { Url = url })
    {
    }

    public NatsHeddleTransport(NatsOpts options)
        : this(new NatsConnection(options), ownsConnection: true)
    {
    }

    public NatsHeddleTransport(NatsConnection connection, bool ownsConnection = false)
    {
        this.connection = connection;
        this.ownsConnection = ownsConnection;
    }

    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        await connection.ConnectAsync().AsTask().WaitAsync(cancellationToken);
    }

    public Task PublishAsync(
        string subject,
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken = default)
    {
        return connection
            .PublishAsync(subject, payload.ToArray(), cancellationToken: cancellationToken)
            .AsTask();
    }

    public async IAsyncEnumerable<HeddleMessage> SubscribeAsync(
        string subject,
        string? queueGroup = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (var message in connection
            .SubscribeAsync<byte[]>(subject, queueGroup, cancellationToken: cancellationToken)
            .WithCancellation(cancellationToken))
        {
            message.EnsureSuccess();
            var payload = message.Data is null
                ? ReadOnlyMemory<byte>.Empty
                : message.Data;
            yield return new HeddleMessage(message.Subject, payload);
        }
    }

    public ValueTask DisposeAsync()
    {
        return ownsConnection ? connection.DisposeAsync() : ValueTask.CompletedTask;
    }
}
