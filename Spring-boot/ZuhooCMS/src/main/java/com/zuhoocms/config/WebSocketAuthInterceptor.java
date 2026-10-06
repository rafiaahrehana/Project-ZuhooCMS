package com.zuhoocms.config;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.security.JwtService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.util.MultiValueMap;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.List;
import java.util.Map;

/** Stands in for JwtAuthFilter on /ws (permitAll in SecurityConfig): browsers cannot send an Authorization header on a handshake, so the JWT arrives as ?token= and the upgrade is refused if it is missing or invalid. */
@Slf4j
@Component
@RequiredArgsConstructor
public class WebSocketAuthInterceptor implements HandshakeInterceptor {

    private final JwtService jwtService;
    private final UserRepository userRepository;

    @Override
    public boolean beforeHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                    WebSocketHandler wsHandler, Map<String, Object> attributes) {
        String token = extractToken(request);
        if (token == null || !jwtService.isTokenValid(token)) {
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }

        try {
            // Same rule as JwtAuthFilter: a refresh/reset/verify token has no companyId claim and must not open a socket either.
            if (!jwtService.isAccessToken(token)) {
                response.setStatusCode(HttpStatus.UNAUTHORIZED);
                return false;
            }

            String email = jwtService.extractEmail(token);
            User user = email != null ? userRepository.findByEmail(email).orElse(null) : null;
            if (user == null || !user.isEnabled()) {
                response.setStatusCode(HttpStatus.UNAUTHORIZED);
                return false;
            }
            attributes.put("principal", new StompPrincipal(String.valueOf(user.getId())));
            return true;
        } catch (Exception e) {
            log.warn("WebSocket handshake auth failed: {}", e.getMessage());
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }
    }

    @Override
    public void afterHandshake(ServerHttpRequest request, ServerHttpResponse response,
                                WebSocketHandler wsHandler, Exception exception) {
    }

    private String extractToken(ServerHttpRequest request) {
        MultiValueMap<String, String> params =
            UriComponentsBuilder.fromUri(request.getURI()).build().getQueryParams();
        List<String> values = params.get("token");
        return values != null && !values.isEmpty() ? values.get(0) : null;
    }
}
