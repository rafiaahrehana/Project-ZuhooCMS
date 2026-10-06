package com.zuhoocms.security;

import com.zuhoocms.auth.user.User;
import org.slf4j.MDC;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

/** While impersonating, the principal is the admin's own User flagged with the tenant role (see JwtAuthFilter) and the credentials hold the impersonated company id, so getCurrentCompanyId() is the effective company and isPlatformUser() is false. */
@Component
public class SecurityUtil {

    public User getCurrentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated())
            return null;
        Object principal = auth.getPrincipal();
        return (principal instanceof User u) ? u : null;
    }

    public Long getCurrentCompanyId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null)
            return null;
        Object credentials = auth.getCredentials();
        return (credentials instanceof Long id) ? id : null;
    }

    public boolean isImpersonating() {
        User user = getCurrentUser();
        if (user != null && user.isImpersonationPrincipal()) {
            return true;
        }
        return MDC.get("impersonatedBy") != null;
    }

    public Long getImpersonatedByUserId() {
        User user = getCurrentUser();
        if (user != null && user.isImpersonationPrincipal()) {
            return user.getId();
        }
        String raw = MDC.get("impersonatedBy");
        return raw != null ? Long.parseLong(raw) : null;
    }

    /** The impersonation session id of the current request, or null when not impersonating. */
    public String getImpersonationSessionId() {
        User user = getCurrentUser();
        if (user != null && user.getImpersonationSessionId() != null) {
            return user.getImpersonationSessionId();
        }
        return MDC.get("impersonationSessionId");
    }
}
