// Issuer-prefix validators for the events wire contract.
//
// Mirrors heddle.contrib.events.issuer_conventions in the upstream
// Python repo. Every event and command carries metadata.issued_by
// with one of six reserved prefixes; this module is the runtime check.
//
// Multi-segment suffix rule: each prefix governs only the leading
// segment(s) up to and including its named scope. Everything after is
// opaque to the validator and may contain additional colons. For
// example, IsUserIssuer accepts:
//
//     user:badge:206
//     user:system:emergency_correction:eng-42
//     user:system:tool:abc:def
//
// Validators MUST NOT cap segment count.

namespace Heddle.Sdk;

public static class IssuerConventions
{
    public const string FrameworkPrefix = "framework:";
    public const string ObserverPrefix = "observer:";
    public const string ProjectorPrefix = "projector:";
    public const string UserPrefix = "user:";
    public const string UserSystemPrefix = "user:system:";
    public const string UserBadgePrefix = "user:badge:";
    public const string BridgePrefix = "bridge:";

    /// <summary>
    /// Top-level reserved prefixes used by <see cref="IsRecognizedIssuer"/>.
    /// Sub-prefixes (<c>user:badge:</c>, <c>user:system:</c>) are
    /// intentionally not listed here — they're sub-namespaces of
    /// <c>user:</c>.
    /// </summary>
    public static readonly IReadOnlyList<string> ReservedPrefixes = new[]
    {
        FrameworkPrefix,
        ObserverPrefix,
        ProjectorPrefix,
        UserPrefix,
        BridgePrefix,
    };

    /// <summary>True iff <paramref name="issuedBy"/> is framework-internal.</summary>
    public static bool IsFrameworkIssuer(string issuedBy) =>
        issuedBy.StartsWith(FrameworkPrefix, StringComparison.Ordinal)
        && issuedBy.Length > FrameworkPrefix.Length;

    /// <summary>True iff <paramref name="issuedBy"/> is a scheduled observer.</summary>
    public static bool IsObserverIssuer(string issuedBy) =>
        issuedBy.StartsWith(ObserverPrefix, StringComparison.Ordinal)
        && issuedBy.Length > ObserverPrefix.Length;

    /// <summary>True iff <paramref name="issuedBy"/> is an application projector.</summary>
    public static bool IsProjectorIssuer(string issuedBy) =>
        issuedBy.StartsWith(ProjectorPrefix, StringComparison.Ordinal)
        && issuedBy.Length > ProjectorPrefix.Length;

    /// <summary>
    /// True iff <paramref name="issuedBy"/> is user-mediated. Covers
    /// both <c>user:badge:*</c> and <c>user:system:*</c>; use
    /// <see cref="IsSystemIssuer"/> for the strict <c>user:system:*</c>
    /// subcheck.
    /// </summary>
    public static bool IsUserIssuer(string issuedBy) =>
        issuedBy.StartsWith(UserPrefix, StringComparison.Ordinal)
        && issuedBy.Length > UserPrefix.Length;

    /// <summary>
    /// Strict subcheck of <see cref="IsUserIssuer"/> — accepts only
    /// <c>user:system:*</c> (rejects shop-floor <c>user:badge:*</c>).
    /// </summary>
    public static bool IsSystemIssuer(string issuedBy) =>
        issuedBy.StartsWith(UserSystemPrefix, StringComparison.Ordinal)
        && issuedBy.Length > UserSystemPrefix.Length;

    /// <summary>True iff <paramref name="issuedBy"/> is a gateway/bridge (post-M2).</summary>
    public static bool IsBridgeIssuer(string issuedBy) =>
        issuedBy.StartsWith(BridgePrefix, StringComparison.Ordinal)
        && issuedBy.Length > BridgePrefix.Length;

    /// <summary>True iff <paramref name="issuedBy"/> starts with any reserved top-level prefix.</summary>
    public static bool IsRecognizedIssuer(string issuedBy) =>
        ReservedPrefixes.Any(p => issuedBy.StartsWith(p, StringComparison.Ordinal));
}
