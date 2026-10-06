package com.zuhoocms.modules.crm.capture;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/**
 * Registers {@link PublicCrmRateLimitFilter} against the two unauthenticated CRM routes only; as a bare @Component it would apply to every request and throttle authenticated traffic.
 *
 * Runs ahead of the security filter chain, since there is nothing to authenticate on these routes.
 */
@Configuration
public class PublicCrmRateLimitConfig {

    @Bean
    public FilterRegistrationBean<PublicCrmRateLimitFilter> publicCrmRateLimitFilter() {
        FilterRegistrationBean<PublicCrmRateLimitFilter> registration =
                new FilterRegistrationBean<>(new PublicCrmRateLimitFilter());
        registration.addUrlPatterns("/api/public/crm/*", "/api/clients/public/*");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
        registration.setName("publicCrmRateLimitFilter");
        return registration;
    }
}
