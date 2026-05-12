using System.Runtime.CompilerServices;
using System.Threading.Channels;

namespace Heddle.Sdk;

/// <summary>
/// In-process transport for tests, examples, and local Workshop-style harnesses.
/// </summary>
public sealed class InMemoryHeddleTransport : IHeddleTransport
{
    private readonly object gate = new();
    private readonly List<Subscriber> subscribers = [];
    private readonly Dictionary<(string Subject, string QueueGroup), int> groupCounters = [];
    private bool disposed;

    public async Task PublishAsync(
        string subject,
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken = default)
    {
        var message = new HeddleMessage(subject, payload.ToArray());
        List<Subscriber> targets;

        lock (gate)
        {
            ThrowIfDisposed();
            targets = GetTargets(subject);
        }

        foreach (var target in targets)
        {
            await target.Channel.Writer.WriteAsync(message, cancellationToken);
        }
    }

    public IAsyncEnumerable<HeddleMessage> SubscribeAsync(
        string subject,
        string? queueGroup = null,
        CancellationToken cancellationToken = default)
    {
        var subscriber = new Subscriber(
            Guid.NewGuid(),
            subject,
            queueGroup,
            Channel.CreateUnbounded<HeddleMessage>(
                new UnboundedChannelOptions
                {
                    SingleReader = true,
                    SingleWriter = false,
                }));

        lock (gate)
        {
            ThrowIfDisposed();
            subscribers.Add(subscriber);
        }

        return ReadMessagesAsync(subscriber, cancellationToken);
    }

    /// <summary>
    /// Counts active in-memory subscribers for local tests and examples.
    /// </summary>
    public int SubscriberCount(string subject, string? queueGroup = null)
    {
        lock (gate)
        {
            return subscribers.Count(subscriber =>
                string.Equals(subscriber.Subject, subject, StringComparison.Ordinal)
                && string.Equals(subscriber.QueueGroup, queueGroup, StringComparison.Ordinal));
        }
    }

    public ValueTask DisposeAsync()
    {
        List<Subscriber> active;
        lock (gate)
        {
            if (disposed)
            {
                return ValueTask.CompletedTask;
            }

            disposed = true;
            active = [.. subscribers];
            subscribers.Clear();
            groupCounters.Clear();
        }

        foreach (var subscriber in active)
        {
            subscriber.Channel.Writer.TryComplete();
        }

        return ValueTask.CompletedTask;
    }

    private async IAsyncEnumerable<HeddleMessage> ReadMessagesAsync(
        Subscriber subscriber,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        try
        {
            await foreach (var message in subscriber.Channel.Reader.ReadAllAsync(cancellationToken))
            {
                yield return message;
            }
        }
        finally
        {
            lock (gate)
            {
                subscribers.RemoveAll(item => item.Id == subscriber.Id);
            }

            subscriber.Channel.Writer.TryComplete();
        }
    }

    private List<Subscriber> GetTargets(string subject)
    {
        var targets = new List<Subscriber>();
        var grouped = new Dictionary<string, List<Subscriber>>();

        foreach (var subscriber in subscribers)
        {
            if (!string.Equals(subscriber.Subject, subject, StringComparison.Ordinal))
            {
                continue;
            }

            if (subscriber.QueueGroup is null)
            {
                targets.Add(subscriber);
                continue;
            }

            if (!grouped.TryGetValue(subscriber.QueueGroup, out var groupMembers))
            {
                groupMembers = [];
                grouped[subscriber.QueueGroup] = groupMembers;
            }

            groupMembers.Add(subscriber);
        }

        foreach (var (queueGroup, groupMembers) in grouped)
        {
            if (groupMembers.Count == 0)
            {
                continue;
            }

            var key = (subject, queueGroup);
            var counter = groupCounters.TryGetValue(key, out var value) ? value : 0;
            targets.Add(groupMembers[counter % groupMembers.Count]);
            groupCounters[key] = counter + 1;
        }

        return targets;
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
    }

    private sealed record Subscriber(
        Guid Id,
        string Subject,
        string? QueueGroup,
        Channel<HeddleMessage> Channel);
}
