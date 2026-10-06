package com.zuhoocms.config;


import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
public class CorsConfig {

    // Comma-separated origin patterns; setAllowedOriginPatterns (not setAllowedOrigins) is required for the wildcard to work alongside allowCredentials(true).
    @Value("${app.frontend-url:http://localhost:4200,http://localhost:*}")
    private String frontendUrl;

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOriginPatterns(
                Arrays.stream(frontendUrl.split(",")).map(String::trim).toList());
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setExposedHeaders(List.of("Authorization", "Content-Disposition"));
        config.setAllowCredentials(true);
        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();

        // SSLCommerz redirects the payer's browser here with a cross-origin POST; the frontend-only rule below rejects it as "Invalid CORS request" and the invoice is never credited.
        // Safe because the endpoint is permitAll and sends no credentials. Must be registered BEFORE "/**": UrlBasedCorsConfigurationSource takes the FIRST matching pattern in registration order, not the most specific.
        CorsConfiguration gatewayCallbackConfig = new CorsConfiguration();
        gatewayCallbackConfig.setAllowedOriginPatterns(List.of("*"));
        gatewayCallbackConfig.setAllowedMethods(List.of("GET", "POST", "OPTIONS"));
        gatewayCallbackConfig.setAllowedHeaders(List.of("*"));
        gatewayCallbackConfig.setAllowCredentials(false);
        gatewayCallbackConfig.setMaxAge(3600L);
        source.registerCorsConfiguration("/api/payments/sslcommerz/callback/**", gatewayCallbackConfig);
        source.registerCorsConfiguration("/api/payments/sslcommerz/ipn", gatewayCallbackConfig);

        source.registerCorsConfiguration("/**", config);

        return source;
    }
}
