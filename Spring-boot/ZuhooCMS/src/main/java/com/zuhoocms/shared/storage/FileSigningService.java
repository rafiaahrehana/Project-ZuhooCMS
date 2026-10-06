package com.zuhoocms.shared.storage;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;

/**
 * Short-lived signed links for private files, so an {@code <img src>} or download link works without an Authorization header.
 * sig = base64url(HMAC-SHA256(key, subject + "|" + exp)), subject {@code file:{id}} or {@code legacy:{name}}, exp epoch seconds, valid for {@link #VALIDITY_SECONDS}.
 * With {@code app.files.signing-key} (env FILE_SIGNING_KEY) unset a random key is generated per start, so links break on restart and differ between instances - dev only.
 */
@Slf4j
@Service
public class FileSigningService {

    public static final long VALIDITY_SECONDS = 600; // 10 minutes

    private final byte[] key;

    public FileSigningService(@Value("${app.files.signing-key:${FILE_SIGNING_KEY:}}") String configuredKey) {
        if (configuredKey == null || configuredKey.isBlank()) {
            byte[] random = new byte[32];
            new SecureRandom().nextBytes(random);
            this.key = random;
            log.warn("app.files.signing-key / FILE_SIGNING_KEY is not set - generated a random file-signing key. "
                    + "Signed file links will not survive a restart or work across instances; set a fixed key in production.");
        } else {
            this.key = configuredKey.getBytes(StandardCharsets.UTF_8);
        }
    }

    public long newExpiry() {
        return Instant.now().getEpochSecond() + VALIDITY_SECONDS;
    }

    public String sign(String subject, long exp) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            byte[] raw = mac.doFinal((subject + "|" + exp).getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        } catch (Exception ex) {
            throw new IllegalStateException("Could not sign file link", ex);
        }
    }

    /** Valid = well-formed, not expired, not absurdly far in the future, and the HMAC matches. */
    public boolean verify(String subject, String expRaw, String sig) {
        if (expRaw == null || sig == null || sig.isBlank()) return false;
        long exp;
        try {
            exp = Long.parseLong(expRaw);
        } catch (NumberFormatException ex) {
            return false;
        }
        long now = Instant.now().getEpochSecond();
        if (exp < now || exp > now + VALIDITY_SECONDS + 60) return false;
        byte[] expected = sign(subject, exp).getBytes(StandardCharsets.US_ASCII);
        return MessageDigest.isEqual(expected, sig.getBytes(StandardCharsets.US_ASCII));
    }

    public static String fileSubject(Long id) { return "file:" + id; }

    public static String legacySubject(String name) { return "legacy:" + name; }
}
