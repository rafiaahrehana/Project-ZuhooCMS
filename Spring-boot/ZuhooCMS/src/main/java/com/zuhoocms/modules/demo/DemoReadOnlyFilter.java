package com.zuhoocms.modules.demo;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.security.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;

/**
 * The choke point that makes the public demo safe: a request authenticated as the demo account may read but never write.
 * A method filter, not a read-only permission set: COMPANY_OWNER bypasses the ~250 permission codes entirely (which the demo relies on to see every module), and GET-or-403 survives a UI gap or a forgotten endpoint.
 * Runs after JwtAuthFilter, which it needs for the authenticated user - see SecurityConfig for the ordering.
 */
@Component
@RequiredArgsConstructor
public class DemoReadOnlyFilter extends OncePerRequestFilter {

    private final SecurityUtil securityUtil;
    // Constructed, not injected: this application exposes no ObjectMapper bean (SubscriptionEnforcementFilter does the same).
    private final ObjectMapper objectMapper = new ObjectMapper();

    /** Paid-AI endpoints, blocked whatever the method: several AI features are GETs, and anyone on the internet can mint a demo session. */
    private static final java.util.List<java.util.regex.Pattern> AI_PATHS = java.util.stream.Stream.of(
            "/api/ai(/.*)?",                                    // chat, agent, threads, briefing, config, usage
            "/api/dashboard/insights",
            "/api/search/ask",
            "/api/crm/activities/summary",
            "/api/crm/leads/[^/]+/summary",
            "/api/company/finance/invoices/[^/]+/ai-summary",
            "/api/hr/performance/[^/]+/summary",
            "/api/service-requests/[^/]+/summary",
            "/api/service-requests/[^/]+/draft-reply",
            "/api/hr/leave-policies/draft",
            "/api/hr/letters/draft",
            "/api/workflows/suggest",
            "/api/.*/ai-(draft|compose|summary)"                // announcements, holidays, timesheets, expenses
        ).map(java.util.regex.Pattern::compile).toList();

    static boolean isAiPath(String uri) {
        if (uri == null) return false;
        String path = uri.length() > 1 && uri.endsWith("/") ? uri.substring(0, uri.length() - 1) : uri;
        return AI_PATHS.stream().anyMatch(p -> p.matcher(path).matches());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String method = request.getMethod();
        User user = securityUtil.getCurrentUser();
        boolean demo = user != null && DemoDataSeeder.DEMO_OWNER_EMAIL.equalsIgnoreCase(user.getEmail());

        // Reads that cost money per call are closed to the demo too, since anyone can mint a demo session.
        if (demo && isAiPath(request.getRequestURI())) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json");
            response.getWriter().write(objectMapper.writeValueAsString(Map.of(
                    "message", "AI features are not available in the demo - sign up free to try them.",
                    "demo", true)));
            return;
        }

        if ("GET".equals(method) || "HEAD".equals(method) || "OPTIONS".equals(method)) {
            chain.doFilter(request, response);
            return;
        }

        if (!demo) {
            chain.doFilter(request, response);
            return;
        }

        // Logout is the one mutation a demo visitor legitimately performs.
        if (request.getRequestURI().equals("/api/auth/logout")) {
            chain.doFilter(request, response);
            return;
        }

        // Some list endpoints are POSTs only because filter criteria travel in the body (e.g. /api/crm/leads/filter); blocking them blanks the page.
        String uri = request.getRequestURI();
        if ("POST".equals(method) && (uri.endsWith("/filter") || uri.endsWith("/search"))) {
            chain.doFilter(request, response);
            return;
        }

        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        response.getWriter().write(objectMapper.writeValueAsString(Map.of(
                "message", "This is a read-only demo - sign up free to try it with your own data.",
                "demo", true)));
    }
}
