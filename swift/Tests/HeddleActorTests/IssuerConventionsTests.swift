import Foundation
@testable import HeddleActor

#if canImport(Testing)
import Testing

// MARK: - Required multi-segment-suffix cases (sprint-1 §6)

@Test func isUserIssuerAcceptsEmergencyCorrectionSegments() {
    #expect(IssuerConventions.isUserIssuer("user:system:emergency_correction:eng-42"))
}

@Test func isFrameworkIssuerAcceptsCascadeRetrySegments() {
    #expect(IssuerConventions.isFrameworkIssuer("framework:cascade:retry:3"))
}

// MARK: - Canonical positive coverage

@Test func acceptsCanonicalFormsForEveryPrefix() {
    #expect(IssuerConventions.isFrameworkIssuer("framework:cascade"))
    #expect(IssuerConventions.isObserverIssuer("observer:pf_job_status"))
    #expect(IssuerConventions.isProjectorIssuer("projector:operation_labor_projector"))
    #expect(IssuerConventions.isUserIssuer("user:badge:206"))
    #expect(IssuerConventions.isUserIssuer("user:system:shoppulse_admin"))
    #expect(IssuerConventions.isSystemIssuer("user:system:shoppulse_admin"))
    #expect(IssuerConventions.isBridgeIssuer("bridge:fault_classifier_llm"))
}

// MARK: - Bare-prefix and empty-string negatives

@Test func rejectsBarePrefixes() {
    #expect(!IssuerConventions.isFrameworkIssuer("framework:"))
    #expect(!IssuerConventions.isObserverIssuer("observer:"))
    #expect(!IssuerConventions.isProjectorIssuer("projector:"))
    #expect(!IssuerConventions.isUserIssuer("user:"))
    #expect(!IssuerConventions.isSystemIssuer("user:system:"))
    #expect(!IssuerConventions.isBridgeIssuer("bridge:"))
}

@Test func rejectsEmptyStrings() {
    #expect(!IssuerConventions.isFrameworkIssuer(""))
    #expect(!IssuerConventions.isObserverIssuer(""))
    #expect(!IssuerConventions.isProjectorIssuer(""))
    #expect(!IssuerConventions.isUserIssuer(""))
    #expect(!IssuerConventions.isSystemIssuer(""))
    #expect(!IssuerConventions.isBridgeIssuer(""))
}

// MARK: - Cross-prefix negatives

@Test func eachValidatorRejectsOtherPrefixes() {
    #expect(!IssuerConventions.isFrameworkIssuer("observer:x"))
    #expect(!IssuerConventions.isObserverIssuer("framework:x"))
    #expect(!IssuerConventions.isProjectorIssuer("user:badge:1"))
    #expect(!IssuerConventions.isUserIssuer("framework:x"))
    #expect(!IssuerConventions.isBridgeIssuer("user:system:x"))
}

// MARK: - isSystemIssuer strict subcheck

@Test func isSystemIssuerRejectsUserBadgeButAcceptsBothSystemForms() {
    #expect(!IssuerConventions.isSystemIssuer("user:badge:206"))
    #expect(IssuerConventions.isSystemIssuer("user:system:shoppulse_admin"))
    #expect(IssuerConventions.isSystemIssuer("user:system:emergency_correction:eng-42"))
}

@Test func isUserIssuerAcceptsBothSubkinds() {
    #expect(IssuerConventions.isUserIssuer("user:badge:206"))
    #expect(IssuerConventions.isUserIssuer("user:system:shoppulse_admin"))
}

// MARK: - isRecognizedIssuer

@Test func isRecognizedIssuerAcceptsAllReservedPrefixes() {
    #expect(IssuerConventions.isRecognizedIssuer("framework:cascade"))
    #expect(IssuerConventions.isRecognizedIssuer("observer:pf_job_status"))
    #expect(IssuerConventions.isRecognizedIssuer("projector:operation_labor_projector"))
    #expect(IssuerConventions.isRecognizedIssuer("user:badge:206"))
    #expect(IssuerConventions.isRecognizedIssuer("user:system:shoppulse_admin"))
    #expect(IssuerConventions.isRecognizedIssuer("bridge:fault_classifier_llm"))
}

@Test func isRecognizedIssuerRejectsOtherStrings() {
    #expect(!IssuerConventions.isRecognizedIssuer("arbitrary:value"))
    #expect(!IssuerConventions.isRecognizedIssuer(""))
    #expect(!IssuerConventions.isRecognizedIssuer("user"))
    #expect(!IssuerConventions.isRecognizedIssuer("framework"))
}
#endif
