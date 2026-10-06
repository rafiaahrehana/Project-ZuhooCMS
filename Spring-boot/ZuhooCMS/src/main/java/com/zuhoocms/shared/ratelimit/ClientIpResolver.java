package com.zuhoocms.shared.ratelimit;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * The caller's IP for rate limiting (same rule as SupportContextSwitchController): X-Forwarded-For counts only when the direct peer is a trusted proxy, walking the chain from the right to the first untrusted hop.
 * With no trusted proxies configured the socket address is always used, so a client cannot dodge a per-IP limit with an arbitrary X-Forwarded-For.
 */
@Component
public class ClientIpResolver {

    private final Set<String> trustedProxies;

    public ClientIpResolver(@Value("${app.security.trusted-proxies:}") String trustedProxiesConfig) {
        this.trustedProxies = trustedProxiesConfig == null || trustedProxiesConfig.isBlank()
                ? Set.of()
                : Arrays.stream(trustedProxiesConfig.split(","))
                        .map(String::trim).filter(s -> !s.isEmpty()).collect(Collectors.toSet());
    }

    public String resolve(HttpServletRequest request) {
        String remote = request.getRemoteAddr();
        if (trustedProxies.isEmpty() || !trustedProxies.contains(remote)) {
            return remote;
        }
        String xff = request.getHeader("X-Forwarded-For");
        if (xff == null || xff.isBlank()) {
            return remote;
        }
        String[] hops = xff.split(",");
        for (int i = hops.length - 1; i >= 0; i--) {
            String hop = hops[i].trim();
            if (!hop.isEmpty() && !trustedProxies.contains(hop)) {
                return hop;
            }
        }
        return remote;
    }
}
