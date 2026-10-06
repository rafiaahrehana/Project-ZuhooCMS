package com.zuhoocms.security;


import com.zuhoocms.auth.token.TokenType;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.security.Key;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

@Service
public class JwtService {

    @Value("${jwt.secret:}")
    private String secret;

    /** Fails fast at startup: jwt.secret has no committed default and must come from JWT_SECRET, and HS256 needs at least 32 bytes. */
    @jakarta.annotation.PostConstruct
    void requireSecret() {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException(
                "JWT_SECRET is not set. Set the JWT_SECRET environment variable (or add it to the "
                    + "gitignored Spring-boot/ZuhooCMS/.env - see .env.example), e.g. a value from "
                    + "'openssl rand -hex 32'.");
        }
        if (secret.getBytes().length < 32) {
            throw new IllegalStateException(
                "JWT_SECRET is too short - it must be at least 32 bytes (256 bits) for HS256.");
        }
    }

    @Value("${jwt.access-expiration-ms:900000}")
    private long accessExpirationMs;

    @Value("${jwt.refresh-expiration-ms:604800000}")
    private long refreshExpirationMs;

    @Value("${jwt.impersonation-expiration-ms:1800000}")
    private long impersonationExpirationMs;


    // "typ" claim, checked by JwtAuthFilter: refresh/action tokens carry no companyId, so accepting one as a Bearer token would grant the holder's DB-wide role with the tenant filter never enabled.
    // Impersonation tokens do authenticate requests, so they are stamped "access" too.
    private static final String TYP_ACCESS = "access";
    private static final String TYP_REFRESH = "refresh";
    private static final String TYP_ACTION = "action";

    public String generateAccessToken(String email, String role, Long companyId) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("typ", TYP_ACCESS);
        claims.put("role", role);
        if (companyId != null) {
            claims.put("companyId", companyId);
        }
        return buildToken(claims, email, accessExpirationMs);
    }

    /**
     * A refresh token carries a random id, so two minted for one account in the same second are different strings.
     *
     * Without it they were byte-identical: the only varying input was issuedAt/expiration, which JJWT stamps from
     * java.util.Date at one-second resolution, and refresh_tokens.token is UNIQUE. So the second insert inside one
     * second was a constraint violation surfacing as 409 "This action conflicts with existing data ... please use a
     * different value" - blaming the caller's data for a collision it had no part in. It hit anyone who double-tapped
     * Sign In, any client retrying a login after a dropped response, and logging in then immediately refreshing.
     */
    public String generateRefreshToken(String email) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("typ", TYP_REFRESH);
        claims.put("jti", java.util.UUID.randomUUID().toString());
        return buildToken(claims, email, refreshExpirationMs);
    }

    /** Access token with a caller-chosen lifetime, for the public demo session which expires on its own schedule without touching the app-wide access expiry. */
    public String generateAccessToken(String email, String role, Long companyId, long expirationMs) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("typ", TYP_ACCESS);
        claims.put("role", role);
        if (companyId != null) {
            claims.put("companyId", companyId);
        }
        return buildToken(claims, email, expirationMs);
    }

    public String generateActionToken(String email, TokenType actionType, long expirationMs) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("typ", TYP_ACTION);
        claims.put("actionType", actionType.name());
        return buildToken(claims, email, expirationMs);
    }

    /** Short-lived tenant-access token: the impersonated company rides the ordinary "companyId" claim so existing tenant scoping picks it up unchanged, plus impersonatedBy/impersonationSessionId for the JWT filter. */
    public String generateImpersonationToken(String email, String role, Long companyId,
                                              Long impersonatedBy, String impersonationSessionId) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("typ", TYP_ACCESS);
        claims.put("role", role);
        if (companyId != null) {
            claims.put("companyId", companyId);
        }
        claims.put("impersonatedBy", impersonatedBy);
        claims.put("impersonationSessionId", impersonationSessionId);
        return buildToken(claims, email, impersonationExpirationMs);
    }

    /** True only for access and impersonation tokens - never a refresh or action (reset/verify) token, which may not authenticate an API request. */
    public boolean isAccessToken(String token) {
        return TYP_ACCESS.equals(extractClaims(token).get("typ", String.class));
    }

    public long getImpersonationExpirationMs() {
        return impersonationExpirationMs;
    }


    public String extractEmail(String token) {
        return extractClaims(token).getSubject();
    }

    public String extractRole(String token) {
        return extractClaims(token).get("role", String.class);
    }

    public Long extractCompanyId(String token) {
        Object raw = extractClaims(token).get("companyId");
        if (raw == null) return null;
        if (raw instanceof Long l) return l;
        if (raw instanceof Integer i) return i.longValue();
        return Long.parseLong(raw.toString());
    }

    public TokenType extractActionType(String token) {
        String type = extractClaims(token).get("actionType", String.class);
        return type != null ? TokenType.valueOf(type) : null;
    }

    public Long extractImpersonatedBy(String token) {
        Object raw = extractClaims(token).get("impersonatedBy");
        if (raw == null) return null;
        if (raw instanceof Long l) return l;
        if (raw instanceof Integer i) return i.longValue();
        return Long.parseLong(raw.toString());
    }

    public String extractImpersonationSessionId(String token) {
        return extractClaims(token).get("impersonationSessionId", String.class);
    }

    public boolean isTokenValid(String token) {
        try {
            return !extractClaims(token).getExpiration().before(new Date());
        } catch (Exception e) {
            return false;
        }
    }

    private String buildToken(Map<String, Object> extraClaims, String subject, long expirationMs) {
        return Jwts.builder()
                .claims(extraClaims)
                .subject(subject)
                .issuedAt(new Date())
                .expiration(new Date(System.currentTimeMillis() + expirationMs))
                .signWith(getSigningKey())
                .compact();
    }

    private Claims extractClaims(String token) {
        return Jwts.parser().verifyWith((javax.crypto.SecretKey) getSigningKey()).build().parseSignedClaims(token).getPayload();
    }

    private Key getSigningKey() {
        return Keys.hmacShaKeyFor(secret.getBytes());
    }
}
