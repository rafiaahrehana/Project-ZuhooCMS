package com.zuhoocms.shared.ratelimit;

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
import java.util.List;

/** Per-IP limits for unauthenticated, abuse-prone endpoints; each rule has its own bucket so a burst of logins does not use up the sign-up allowance (patterns in {@link PublicEndpointRateLimitConfig}). */
@Slf4j
public class PublicEndpointRateLimitFilter extends OncePerRequestFilter {

    /** One throttled endpoint group: method + path, bucket name, limit per window. */
    public record Rule(String bucket, String method, String path, boolean exact, int limit, Duration window) {
        boolean matches(HttpServletRequest request) {
            if (method != null && !method.equalsIgnoreCase(request.getMethod())) return false;
            String uri = request.getRequestURI();
            return exact ? uri.equals(path) : uri.startsWith(path);
        }
    }

    private final List<Rule> rules;
    private final ClientIpResolver ipResolver;
    private final SlidingWindowRateLimiter limiter = new SlidingWindowRateLimiter();

    public PublicEndpointRateLimitFilter(List<Rule> rules, ClientIpResolver ipResolver) {
        this.rules = rules;
        this.ipResolver = ipResolver;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        if (!"OPTIONS".equalsIgnoreCase(request.getMethod())) {
            String ip = ipResolver.resolve(request);
            for (Rule rule : rules) {
                if (rule.matches(request)
                        && !limiter.tryAcquire(rule.bucket() + "|" + ip, rule.limit(), rule.window())) {
                    log.warn("Rate limit '{}' hit on {} from {}", rule.bucket(), request.getRequestURI(), ip);
                    response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
                    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                    response.setHeader("Retry-After", String.valueOf(rule.window().toSeconds()));
                    response.getWriter().write(
                            "{\"success\":false,\"message\":\"Too many requests. Please wait a moment and try again.\"}");
                    return;
                }
            }
        }
        chain.doFilter(request, response);
    }
}
