package com.zuhoocms.security;

import com.zuhoocms.auth.impersonation.ImpersonationAuditLogRepository;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;

import org.slf4j.MDC;
import org.springframework.context.annotation.Lazy;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import tools.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.util.Collection;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

@Slf4j
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final UserRepository userRepository;
    private final ImpersonationAuditLogRepository impersonationAuditLogRepository;
    private final ObjectMapper objectMapper;

    // Manual constructor (as in SubscriptionEnforcementFilter) so ObjectMapper can be @Lazy: this filter runs before the JSON stack has finished initializing, and @RequiredArgsConstructor cannot mark one parameter lazy.
    public JwtAuthFilter(JwtService jwtService, UserRepository userRepository,
            ImpersonationAuditLogRepository impersonationAuditLogRepository,
            @Lazy ObjectMapper objectMapper) {
        this.jwtService = jwtService;
        this.userRepository = userRepository;
        this.impersonationAuditLogRepository = impersonationAuditLogRepository;
        this.objectMapper = objectMapper;
    }

    /** Same set ImpersonationController allows to start a session. */
    private static final Set<Role> IMPERSONATOR_ROLES =
            EnumSet.of(Role.SUPER_ADMIN, Role.SYSTEM_ADMIN, Role.SUPPORT_MANAGER);

    /** Only tenant roles may be impersonated; anything else invalidates the token. */
    private static Role parseTenantRole(String raw) {
        if (raw == null) return null;
        try {
            Role role = Role.valueOf(raw);
            return (role == Role.COMPANY_OWNER || role == Role.EMPLOYEE) ? role : null;
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        final String authHeader = request.getHeader("Authorization");

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        final String token = authHeader.substring(7);
        boolean mdcSet = false;

        try {
            // Must answer 401 here, not fall through: an anonymous request failing @PreAuthorize comes back 403, so the client's refresh-on-401 never fires and an expired token breaks every screen.
            if (!jwtService.isTokenValid(token)) {
                writeUnauthorized(response, "Access token is invalid or expired");
                return;
            }

            // Refresh and action (reset/verify) tokens carry no companyId claim, so authenticating with one would run the request with the tenant filter disabled but the holder's full DB-wide role.
            if (!jwtService.isAccessToken(token)) {
                writeUnauthorized(response, "Not an access token");
                return;
            }

            String email = jwtService.extractEmail(token);

            if (email != null && SecurityContextHolder.getContext().getAuthentication() == null) {
                User user = userRepository.findByEmail(email).orElse(null);

                if (user != null && user.isEnabled()) {
                    Long companyId = jwtService.extractCompanyId(token);
                    Long impersonatedBy = jwtService.extractImpersonatedBy(token);

                    // Impersonation tokens grant the impersonated tenant role (see ImpersonationServiceImpl), not the admin's own DB role, or every tenant endpoint would 403 the platform admin.
                    Collection<? extends GrantedAuthority> authorities;
                    if (impersonatedBy != null) {
                        String sessionId = jwtService.extractImpersonationSessionId(token);
                        Role impersonatedRole = parseTenantRole(jwtService.extractRole(token));
                        // All four conditions are required; the session row is the revocation list for these tokens, since ending a session is what invalidates them.
                        if (sessionId == null || companyId == null || impersonatedRole == null
                                || !impersonatedBy.equals(user.getId())
                                || !IMPERSONATOR_ROLES.contains(user.getRealRole())
                                || !impersonationAuditLogRepository.isSessionActive(sessionId, user.getId(), companyId)) {
                            writeUnauthorized(response, "Impersonation session has ended or is invalid");
                            return;
                        }
                        // Makes the principal a tenant of the impersonated company: isPlatformUser() false, getRole() the tenant role, and TenantFilterInterceptor scopes the Hibernate tenantFilter to the companyId passed as credentials below.
                        user.setImpersonatedRole(impersonatedRole);
                        user.setImpersonationSessionId(sessionId);
                        authorities = user.getAuthorities();

                        MDC.put("impersonatedBy", String.valueOf(impersonatedBy));
                        MDC.put("impersonationSessionId", sessionId);
                        mdcSet = true;
                    } else {
                        authorities = user.getAuthorities();
                    }

                    UsernamePasswordAuthenticationToken authToken = new UsernamePasswordAuthenticationToken(
                            user, companyId, authorities);

                    authToken.setDetails(
                            new WebAuthenticationDetailsSource().buildDetails(request));

                    SecurityContextHolder.getContext().setAuthentication(authToken);
                }
            }
        } catch (Exception e) {
            // Logged so a real bug here (rather than merely a bad token) is visible; deliberately does not log the token itself.
            log.warn("JWT authentication failed: {}", e.getMessage());
        }

        try {
            filterChain.doFilter(request, response);
        } finally {
            if (mdcSet) {
                MDC.remove("impersonatedBy");
                MDC.remove("impersonationSessionId");
            }
        }
    }

    /** Filters run before the DispatcherServlet, so GlobalExceptionHandler never sees this; the body is hand-shaped to {@code ApiResponse.error(...)}'s success/message keys that clients parse. */
    private void writeUnauthorized(HttpServletResponse response, String message) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("success", false);
        body.put("message", message);
        body.put("data", null);
        response.getWriter().write(objectMapper.writeValueAsString(body));
    }
}
