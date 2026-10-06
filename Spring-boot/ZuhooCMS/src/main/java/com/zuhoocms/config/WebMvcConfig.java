package com.zuhoocms.config;

import com.zuhoocms.core.interceptor.PaginationBoundsInterceptor;
import com.zuhoocms.core.interceptor.TenantFilterInterceptor;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
@RequiredArgsConstructor
public class WebMvcConfig implements WebMvcConfigurer {

    private final TenantFilterInterceptor tenantFilterInterceptor;
    private final PaginationBoundsInterceptor paginationBoundsInterceptor;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(tenantFilterInterceptor)
                .addPathPatterns("/api/**");
        // Rejects an out-of-range ?page=/?size= before any handler builds a PageRequest from it; see the class comment.
        registry.addInterceptor(paginationBoundsInterceptor)
                .addPathPatterns("/api/**");
    }

    // Deliberately no static resource handler for /uploads/**: that served every file to anyone as "public, max-age=365d, immutable". FileServeController now serves them and marks non-public files "private, no-store".
}
