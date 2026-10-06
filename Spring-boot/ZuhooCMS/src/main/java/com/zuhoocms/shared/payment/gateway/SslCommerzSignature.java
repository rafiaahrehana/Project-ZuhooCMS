package com.zuhoocms.shared.payment.gateway;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.Collectors;

/**
 * Verifies the {@code verify_sign} SSLCommerz attaches to its success/IPN posts, so a request forged by anyone who merely knows a tran_id is rejected.
 * Its documented scheme ({@code _SSLCOMMERZ_hash_varify}): the parameters named in {@code verify_key} plus {@code store_passwd = md5(store password)}, sorted by key, joined {@code key=value&...} and MD5'd.
 */
public final class SslCommerzSignature {

    /** Fields that must be covered by the signature, or a signed post could carry an unsigned tran_id/val_id. */
    private static final Set<String> REQUIRED_SIGNED_KEYS = Set.of("tran_id", "val_id");

    private SslCommerzSignature() {
    }

    public static boolean isValid(Map<String, String> params, String storePassword) {
        if (params == null || storePassword == null || storePassword.isBlank()) {
            return false;
        }
        String verifySign = params.get("verify_sign");
        String verifyKey = params.get("verify_key");
        if (verifySign == null || verifySign.isBlank() || verifyKey == null || verifyKey.isBlank()) {
            return false;
        }

        TreeMap<String, String> signed = new TreeMap<>();
        for (String raw : verifyKey.split(",")) {
            String key = raw.trim();
            if (!key.isEmpty()) {
                signed.put(key, params.getOrDefault(key, ""));
            }
        }
        if (!signed.keySet().containsAll(REQUIRED_SIGNED_KEYS)) {
            return false;
        }
        signed.put("store_passwd", md5Hex(storePassword));

        String joined = signed.entrySet().stream()
                .map(e -> e.getKey() + "=" + e.getValue())
                .collect(Collectors.joining("&"));

        byte[] expected = md5Hex(joined).getBytes(StandardCharsets.US_ASCII);
        byte[] actual = verifySign.trim().toLowerCase().getBytes(StandardCharsets.US_ASCII);
        return MessageDigest.isEqual(expected, actual);
    }

    static String md5Hex(String value) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            return HexFormat.of().formatHex(md.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("MD5 not available", e);
        }
    }
}
