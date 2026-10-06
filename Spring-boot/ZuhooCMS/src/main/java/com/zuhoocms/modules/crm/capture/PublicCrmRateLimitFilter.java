package com.zuhoocms.modules.crm.capture;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-IP and per-company rate limiting for the two unauthenticated CRM endpoints:
 * {@code /api/public/crm/**} (website lead capture) and
 * {@code /api/clients/public/**} (client self-registration).
 *
 * <p>Unlimited, a script could fill a company's pipeline overnight and bury the owner's notification feed with it; the capture form's honeypot stops only careless bots.
 *
 * <p>A request must pass both windows: per-IP stops one host hammering the endpoint, per-company stops a distributed flood landing on one tenant.
 *
 * <p>Counters are in-JVM, so N instances multiply the effective limit by N and a restart forgets everything; a scaled-out deployment needs a shared limiter (WAF or gateway) in front.
 */
@Slf4j
public class PublicCrmRateLimitFilter extends OncePerRequestFilter {

    /** Requests one client address may make in a window. */
    private static final int PER_IP_LIMIT = 10;

    /** Requests one company may RECEIVE in a window across all addresses; above the per-IP limit because a busy company hears from many visitors at once. */
    private static final int PER_COMPANY_LIMIT = 60;

    private static final Duration WINDOW = Duration.ofMinutes(1);

    /** Stops the map itself becoming the denial of service: a distributed flood mints one entry per source address, so past this many keys the stalest are dropped. */
    private static final int MAX_TRACKED_KEYS = 50_000;

    private final Map<String, Deque<Instant>> hits = new ConcurrentHashMap<>();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {

        String ipKey = "ip:" + clientIp(request);
        String companyKey = companyKey(request);

        if (!allow(ipKey, PER_IP_LIMIT) || (companyKey != null && !allow(companyKey, PER_COMPANY_LIMIT))) {
            log.warn("Rate limit hit on {} (ip={}, target={})",
                    request.getRequestURI(), clientIp(request), companyKey);
            tooManyRequests(response);
            return;
        }
        chain.doFilter(request, response);
    }

    /** Sliding window: drop timestamps older than WINDOW, then admit if under the cap. */
    private boolean allow(String key, int limit) {
        Instant now = Instant.now();
        Instant cutoff = now.minus(WINDOW);

        if (hits.size() > MAX_TRACKED_KEYS) {
            evictStale(cutoff);
        }

        Deque<Instant> window = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (window) {
            while (!window.isEmpty() && window.peekFirst().isBefore(cutoff)) {
                window.pollFirst();
            }
            if (window.size() >= limit) {
                return false;
            }
            window.addLast(now);
            return true;
        }
    }

    private void evictStale(Instant cutoff) {
        hits.entrySet().removeIf(entry -> {
            Deque<Instant> window = entry.getValue();
            synchronized (window) {
                return window.isEmpty() || window.peekLast().isBefore(cutoff);
            }
        });
    }

    /** Which tenant the request targets; falls back to the Host subdomain because reading the companyId from the body would consume the stream the controller needs. Null means only the per-IP limit applies. */
    private String companyKey(HttpServletRequest request) {
        String subdomain = null;
        try {
            subdomain = request.getParameter("subdomain");
        } catch (org.apache.tomcat.util.http.InvalidParameterException ex) {
            // Tomcat cannot decode this query string (e.g. a lone UTF-16 surrogate escape). Thrown from a filter the
            // exception bypasses Spring MVC entirely and becomes a container ERROR dispatch, so the caller got
            // Tomcat's /error body instead of GlobalExceptionHandler's. Fall back to the per-IP limit and let the
            // controller's own parameter binding raise it inside MVC, where it answers a clean 400.
            log.debug("Undecodable parameters on {}; per-IP limit only", request.getRequestURI());
        }
        if (subdomain != null && !subdomain.isBlank()) {
            return "company:" + subdomain.trim().toLowerCase();
        }
        String host = request.getHeader("Host");
        if (host != null && !host.isBlank()) {
            String name = host.split(":")[0];
            int dot = name.indexOf('.');
            if (dot > 0) {
                return "company:" + name.substring(0, dot).toLowerCase();
            }
            return "company:" + name.toLowerCase();
        }
        return null;
    }

    /** X-Forwarded-For's FIRST entry is the original client; trusted only because these routes sit behind a reverse proxy, since exposed directly the header is caller-supplied. */
    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }

    private void tooManyRequests(HttpServletResponse response) throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setHeader("Retry-After", String.valueOf(WINDOW.toSeconds()));
        response.getWriter().write(
                "{\"success\":false,\"message\":\"Too many requests. Please wait a moment and try again.\"}");
    }
}
