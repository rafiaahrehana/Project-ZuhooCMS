package com.zuhoocms.modules.hrm.recruitment.careerpage;

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
 * Sliding-window rate limiting for the unauthenticated careers endpoints ({@code /api/public/careers/**}), same approach as PublicCrmRateLimitFilter.
 *
 * <p>Writes (apply, resume upload) can flood a pipeline or fill the disk, so they get a tight per-IP limit plus a per-careers-page limit capping a distributed flood against one tenant; reads get a looser per-IP limit.
 * <p>In-memory and per-instance, with the same trade-offs documented on PublicCrmRateLimitFilter.
 */
@Slf4j
public class PublicCareersRateLimitFilter extends OncePerRequestFilter {

    static final int PER_IP_WRITE_LIMIT = 10;
    static final int PER_PAGE_WRITE_LIMIT = 60;
    static final int PER_IP_READ_LIMIT = 60;
    private static final Duration WINDOW = Duration.ofMinutes(1);
    private static final int MAX_TRACKED_KEYS = 50_000;
    private static final String PREFIX = "/api/public/careers/";

    private final Map<String, Deque<Instant>> hits = new ConcurrentHashMap<>();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String ip = clientIp(request);
        boolean write = !"GET".equalsIgnoreCase(request.getMethod()) && !"OPTIONS".equalsIgnoreCase(request.getMethod());
        boolean allowed;
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            allowed = true; // CORS preflight carries no payload
        } else if (write) {
            String slug = slugOf(request.getRequestURI());
            allowed = allow("w-ip:" + ip, PER_IP_WRITE_LIMIT)
                    && (slug == null || allow("w-page:" + slug, PER_PAGE_WRITE_LIMIT));
        } else {
            allowed = allow("r-ip:" + ip, PER_IP_READ_LIMIT);
        }
        if (!allowed) {
            log.warn("Careers rate limit hit on {} {} (ip={})", request.getMethod(), request.getRequestURI(), ip);
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.setHeader("Retry-After", String.valueOf(WINDOW.toSeconds()));
            response.getWriter().write(
                    "{\"success\":false,\"message\":\"Too many requests. Please wait a moment and try again.\"}");
            return;
        }
        chain.doFilter(request, response);
    }

    private boolean allow(String key, int limit) {
        Instant now = Instant.now();
        Instant cutoff = now.minus(WINDOW);
        if (hits.size() > MAX_TRACKED_KEYS) {
            hits.entrySet().removeIf(e -> {
                synchronized (e.getValue()) {
                    return e.getValue().isEmpty() || e.getValue().peekLast().isBefore(cutoff);
                }
            });
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

    private String slugOf(String uri) {
        int i = uri.indexOf(PREFIX);
        if (i < 0) return null;
        String rest = uri.substring(i + PREFIX.length());
        int slash = rest.indexOf('/');
        String slug = slash >= 0 ? rest.substring(0, slash) : rest;
        return slug.isBlank() ? null : slug.toLowerCase();
    }

    /** First X-Forwarded-For entry when present (expected behind a reverse proxy), else the socket address. */
    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
