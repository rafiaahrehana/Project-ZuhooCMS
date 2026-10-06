package com.zuhoocms.modules.hrm.attendance.biometric.verification;

import com.zuhoocms.shared.exception.BadRequestException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The single gate every biometric verification path goes through.
 *
 * <p>No real fingerprint matcher is integrated. What this app has is a character-by-character comparison of the stored and
 * submitted template strings - a string equality test, not a biometric match. Gating attendance on it is worse than useless:
 * anyone who can read or guess an enrolled template string verifies as that employee, and two genuine captures of the same
 * finger never produce identical strings, so the honest path fails while the replay path passes.
 *
 * <p>Therefore matching is <b>disabled by default and fails closed</b>: with no matcher configured, verification is refused
 * outright rather than silently answering "not a match" (or, worse, "a match"). The stub can only be switched on deliberately,
 * through {@code hrm.biometric.stub-matcher.enabled}, whose name says what it is; it exists for local demos, never production.
 *
 * <p>A real implementation replaces {@link #score} with a call to a fingerprint SDK (SourceAFIS, or the capture device's own
 * SDK) that takes the enrolled and captured ISO/ANSI minutiae templates - not the base64 string this app stores today - and
 * returns that library's similarity score. It also needs the device's own match threshold expressed in that library's scale
 * (BiometricDevice.matchThreshold is a bare "95" with no matcher behind it), liveness/anti-spoof handling, and enrolled
 * templates stored encrypted at rest.
 */
@Component
public class BiometricMatcher {

    /** Off unless explicitly enabled: with no real matcher wired in, the only safe answer is to refuse. */
    private final boolean stubEnabled;

    public BiometricMatcher(@Value("${hrm.biometric.stub-matcher.enabled:false}") boolean stubEnabled) {
        this.stubEnabled = stubEnabled;
    }

    public boolean isAvailable() {
        return stubEnabled;
    }

    /**
     * Similarity of two templates on the 0-100 scale {@code BiometricDevice.matchThreshold} is expressed in.
     *
     * @throws BadRequestException when no matcher is configured - callers must not fall back to a default score.
     */
    public double score(String enrolledTemplate, String capturedTemplate) {
        requireAvailable();
        if (enrolledTemplate == null || capturedTemplate == null) {
            return 0.0;
        }
        int matchPoints = 0;
        int totalPoints = Math.min(enrolledTemplate.length(), capturedTemplate.length());
        for (int i = 0; i < totalPoints; i++) {
            if (enrolledTemplate.charAt(i) == capturedTemplate.charAt(i)) {
                matchPoints++;
            }
        }
        return totalPoints > 0 ? (matchPoints * 100.0 / totalPoints) : 0.0;
    }

    /** Fails the request before any enrollment row is read or any match counter is touched. */
    public void requireAvailable() {
        if (!stubEnabled) {
            throw new BadRequestException(
                    "Biometric verification is not available: no fingerprint matcher is configured on this server.");
        }
    }
}
