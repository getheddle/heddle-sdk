using Heddle.Sdk;
using Xunit;

namespace Heddle.Sdk.Tests;

public sealed class IssuerConventionsTests
{
    // -- Required multi-segment-suffix cases (sprint-1 §6) ----------------

    [Fact]
    public void IsUserIssuerAcceptsEmergencyCorrectionSegments()
    {
        Assert.True(IssuerConventions.IsUserIssuer("user:system:emergency_correction:eng-42"));
    }

    [Fact]
    public void IsFrameworkIssuerAcceptsCascadeRetrySegments()
    {
        Assert.True(IssuerConventions.IsFrameworkIssuer("framework:cascade:retry:3"));
    }

    // -- Canonical positive coverage --------------------------------------

    [Fact]
    public void AcceptsCanonicalFormsForEveryPrefix()
    {
        Assert.True(IssuerConventions.IsFrameworkIssuer("framework:cascade"));
        Assert.True(IssuerConventions.IsObserverIssuer("observer:pf_job_status"));
        Assert.True(IssuerConventions.IsProjectorIssuer("projector:operation_labor_projector"));
        Assert.True(IssuerConventions.IsUserIssuer("user:badge:206"));
        Assert.True(IssuerConventions.IsUserIssuer("user:system:shoppulse_admin"));
        Assert.True(IssuerConventions.IsSystemIssuer("user:system:shoppulse_admin"));
        Assert.True(IssuerConventions.IsBridgeIssuer("bridge:fault_classifier_llm"));
    }

    // -- Bare-prefix and empty-string negatives ---------------------------

    [Fact]
    public void RejectsBarePrefixes()
    {
        Assert.False(IssuerConventions.IsFrameworkIssuer("framework:"));
        Assert.False(IssuerConventions.IsObserverIssuer("observer:"));
        Assert.False(IssuerConventions.IsProjectorIssuer("projector:"));
        Assert.False(IssuerConventions.IsUserIssuer("user:"));
        Assert.False(IssuerConventions.IsSystemIssuer("user:system:"));
        Assert.False(IssuerConventions.IsBridgeIssuer("bridge:"));
    }

    [Fact]
    public void RejectsEmptyStrings()
    {
        Assert.False(IssuerConventions.IsFrameworkIssuer(""));
        Assert.False(IssuerConventions.IsObserverIssuer(""));
        Assert.False(IssuerConventions.IsProjectorIssuer(""));
        Assert.False(IssuerConventions.IsUserIssuer(""));
        Assert.False(IssuerConventions.IsSystemIssuer(""));
        Assert.False(IssuerConventions.IsBridgeIssuer(""));
    }

    // -- Cross-prefix negatives -------------------------------------------

    [Fact]
    public void EachValidatorRejectsOtherPrefixes()
    {
        Assert.False(IssuerConventions.IsFrameworkIssuer("observer:x"));
        Assert.False(IssuerConventions.IsObserverIssuer("framework:x"));
        Assert.False(IssuerConventions.IsProjectorIssuer("user:badge:1"));
        Assert.False(IssuerConventions.IsUserIssuer("framework:x"));
        Assert.False(IssuerConventions.IsBridgeIssuer("user:system:x"));
    }

    // -- IsSystemIssuer strict subcheck -----------------------------------

    [Fact]
    public void IsSystemIssuerRejectsUserBadgeButAcceptsBothSystemForms()
    {
        Assert.False(IssuerConventions.IsSystemIssuer("user:badge:206"));
        Assert.True(IssuerConventions.IsSystemIssuer("user:system:shoppulse_admin"));
        Assert.True(IssuerConventions.IsSystemIssuer("user:system:emergency_correction:eng-42"));
    }

    [Fact]
    public void IsUserIssuerAcceptsBothSubkinds()
    {
        Assert.True(IssuerConventions.IsUserIssuer("user:badge:206"));
        Assert.True(IssuerConventions.IsUserIssuer("user:system:shoppulse_admin"));
    }

    // -- IsRecognizedIssuer -----------------------------------------------

    [Theory]
    [InlineData("framework:cascade")]
    [InlineData("observer:pf_job_status")]
    [InlineData("projector:operation_labor_projector")]
    [InlineData("user:badge:206")]
    [InlineData("user:system:shoppulse_admin")]
    [InlineData("bridge:fault_classifier_llm")]
    public void IsRecognizedIssuerAcceptsAllReservedPrefixes(string value)
    {
        Assert.True(IssuerConventions.IsRecognizedIssuer(value));
    }

    [Theory]
    [InlineData("arbitrary:value")]
    [InlineData("")]
    [InlineData("user")]
    [InlineData("framework")]
    public void IsRecognizedIssuerRejectsOtherStrings(string value)
    {
        Assert.False(IssuerConventions.IsRecognizedIssuer(value));
    }
}
