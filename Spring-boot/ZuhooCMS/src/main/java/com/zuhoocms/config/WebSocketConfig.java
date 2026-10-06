package com.zuhoocms.config;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.support.DefaultHandshakeHandler;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

import java.security.Principal;
import java.util.Map;

@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final WebSocketAuthInterceptor webSocketAuthInterceptor;

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue");
        config.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // Both "/ws" (servicedesk) and "/ws/support" (platform-support chat) share one broker, auth and handshake so the same Angular app works against either backend; SecurityConfig's "/ws/**" covers both.
        registry.addEndpoint("/ws", "/ws/support")
                .setAllowedOriginPatterns("*")
                .addInterceptors(webSocketAuthInterceptor)
                .setHandshakeHandler(new DefaultHandshakeHandler() {
                    // The handshake carries no Spring Security Authentication (/ws is permitAll), so the principal WebSocketAuthInterceptor stashed in `attributes` is pulled back out here to become the STOMP session's Principal.
                    @Override
                    protected Principal determineUser(ServerHttpRequest request, WebSocketHandler wsHandler,
                                                       Map<String, Object> attributes) {
                        Object principal = attributes.get("principal");
                        return principal instanceof Principal p ? p : super.determineUser(request, wsHandler, attributes);
                    }
                });
        // Deliberately NOT .withSockJS(): its client assumes a Node-style `global` that Angular's esbuild bundler doesn't polyfill, breaking at runtime.
    }
}
