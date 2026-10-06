package com.zuhoocms.shared.ratelimit;

import com.zuhoocms.shared.ratelimit.PublicEndpointRateLimitFilter.Rule;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

import java.time.Duration;
import java.util.List;

/** Registers {@link PublicEndpointRateLimitFilter} on explicit auth, demo and public-website patterns only (see PublicCrmRateLimitConfig for why not a bare {@code @Component}); limits are per IP via app.ratelimit.*. */
@Configuration
public class PublicEndpointRateLimitConfig {

    @Bean
    public FilterRegistrationBean<PublicEndpointRateLimitFilter> publicEndpointRateLimitFilter(
            ClientIpResolver ipResolver,
            @Value("${app.ratelimit.login-per-minute:20}") int loginPerMinute,
            @Value("${app.ratelimit.register-per-hour:10}") int registerPerHour,
            @Value("${app.ratelimit.password-reset-per-15min:10}") int resetPer15Min,
            @Value("${app.ratelimit.demo-session-per-hour:20}") int demoPerHour,
            @Value("${app.ratelimit.website-post-per-minute:10}") int websitePostPerMinute,
            @Value("${app.ratelimit.website-track-per-minute:20}") int websiteTrackPerMinute) {
        Duration minute = Duration.ofMinutes(1);
        Duration hour = Duration.ofHours(1);
        Duration quarter = Duration.ofMinutes(15);
        List<Rule> rules = List.of(
                new Rule("login", "POST", "/api/auth/login", true, loginPerMinute, minute),
                new Rule("google", "POST", "/api/auth/google", false, loginPerMinute, minute),
                new Rule("register", "POST", "/api/auth/register", true, registerPerHour, hour),
                new Rule("reset", "POST", "/api/auth/forgot-password", true, resetPer15Min, quarter),
                new Rule("reset", "POST", "/api/auth/verify-reset-code", true, resetPer15Min, quarter),
                new Rule("reset", "POST", "/api/auth/reset-password", true, resetPer15Min, quarter),
                new Rule("verify", "POST", "/api/auth/verify-email", true, resetPer15Min, quarter),
                new Rule("verify", "POST", "/api/auth/resend-verification", true, resetPer15Min, quarter),
                new Rule("demo", "POST", "/api/public/demo/", false, demoPerHour, hour),
                new Rule("site-track", "GET", "/api/website/service-requests/track/", false, websiteTrackPerMinute, minute),
                new Rule("site-post", "POST", "/api/website/", false, websitePostPerMinute, minute));

        FilterRegistrationBean<PublicEndpointRateLimitFilter> registration =
                new FilterRegistrationBean<>(new PublicEndpointRateLimitFilter(rules, ipResolver));
        registration.addUrlPatterns("/api/auth/*", "/api/public/demo/*", "/api/website/*");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
        registration.setName("publicEndpointRateLimitFilter");
        return registration;
    }
}
