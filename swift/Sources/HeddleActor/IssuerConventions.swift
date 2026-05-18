// Issuer-prefix validators for the events wire contract.
//
// Mirrors `heddle.contrib.events.issuer_conventions` in the upstream
// Python repo. Every event and command carries `metadata.issued_by`
// with one of six reserved prefixes; this module is the runtime check.
//
// Multi-segment suffix rule: each prefix governs only the leading
// segment(s) up to and including its named scope. Everything after is
// opaque to the validator and may contain additional colons. For
// example, `isUserIssuer` accepts:
//
//     user:badge:206
//     user:system:emergency_correction:eng-42
//     user:system:tool:abc:def
//
// Validators MUST NOT cap segment count.

import Foundation

public enum IssuerConventions {
    public static let frameworkPrefix = "framework:"
    public static let observerPrefix = "observer:"
    public static let projectorPrefix = "projector:"
    public static let userPrefix = "user:"
    public static let userSystemPrefix = "user:system:"
    public static let userBadgePrefix = "user:badge:"
    public static let bridgePrefix = "bridge:"

    /// Top-level reserved prefixes used by ``isRecognizedIssuer``.
    /// Sub-prefixes (`user:badge:`, `user:system:`) are intentionally
    /// not listed here — they're sub-namespaces of `user:`.
    public static let reservedPrefixes: [String] = [
        frameworkPrefix,
        observerPrefix,
        projectorPrefix,
        userPrefix,
        bridgePrefix,
    ]

    /// True iff `issuedBy` is framework-internal (P1/P2/P3, bootstrap, etc.).
    public static func isFrameworkIssuer(_ issuedBy: String) -> Bool {
        issuedBy.hasPrefix(frameworkPrefix) && issuedBy.count > frameworkPrefix.count
    }

    /// True iff `issuedBy` is a scheduled PF observer.
    public static func isObserverIssuer(_ issuedBy: String) -> Bool {
        issuedBy.hasPrefix(observerPrefix) && issuedBy.count > observerPrefix.count
    }

    /// True iff `issuedBy` is an application projector emitting events.
    public static func isProjectorIssuer(_ issuedBy: String) -> Bool {
        issuedBy.hasPrefix(projectorPrefix) && issuedBy.count > projectorPrefix.count
    }

    /// True iff `issuedBy` is user-mediated. Covers both `user:badge:*`
    /// and `user:system:*` — use ``isSystemIssuer`` for the strict
    /// `user:system:*` subcheck.
    public static func isUserIssuer(_ issuedBy: String) -> Bool {
        issuedBy.hasPrefix(userPrefix) && issuedBy.count > userPrefix.count
    }

    /// Strict subcheck of ``isUserIssuer`` — accepts only
    /// `user:system:*` (rejects shop-floor `user:badge:*`).
    public static func isSystemIssuer(_ issuedBy: String) -> Bool {
        issuedBy.hasPrefix(userSystemPrefix) && issuedBy.count > userSystemPrefix.count
    }

    /// True iff `issuedBy` is a gateway/bridge (post-M2; reserved).
    public static func isBridgeIssuer(_ issuedBy: String) -> Bool {
        issuedBy.hasPrefix(bridgePrefix) && issuedBy.count > bridgePrefix.count
    }

    /// True iff `issuedBy` starts with any reserved top-level prefix.
    public static func isRecognizedIssuer(_ issuedBy: String) -> Bool {
        reservedPrefixes.contains { issuedBy.hasPrefix($0) }
    }
}
