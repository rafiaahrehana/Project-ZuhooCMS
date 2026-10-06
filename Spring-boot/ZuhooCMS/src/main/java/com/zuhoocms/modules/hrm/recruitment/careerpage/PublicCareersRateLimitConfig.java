package com.zuhoocms.modules.hrm.recruitment.careerpage;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/** Registers {@link PublicCareersRateLimitFilter} on the public careers routes only (an explicit URL pattern, not a @Component filter) ahead of the security chain, so a flood is rejected before any work. */
@Configuration
public class PublicCareersRateLimitConfig {

    @Bean
    public FilterRegistrationBean<PublicCareersRateLimitFilter> publicCareersRateLimitFilter() {
        FilterRegistrationBean<PublicCareersRateLimitFilter> registration =
                new FilterRegistrationBean<>(new PublicCareersRateLimitFilter());
        registration.addUrlPatterns("/api/public/careers/*");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
        registration.setName("publicCareersRateLimitFilter");
        return registration;
    }
}
