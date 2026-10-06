package com.zuhoocms.core.interceptor;

import com.zuhoocms.auth.user.User;
import jakarta.persistence.EntityManager;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.hibernate.Session;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.orm.jpa.AbstractEntityManagerFactoryBean;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * Enables Hibernate's {@code tenantFilter} for tenant users via an entityManagerInitializer, so every EntityManager gets it.
 * Not in {@link #preHandle}: with {@code open-in-view=false} the filter went onto a throwaway Session and no {@code @Transactional} query ever saw it (a company A owner could read company B's salary structure).
 * Platform staff and unauthenticated threads (schedulers) keep the unfiltered session.
 * Hibernate filters apply to HQL/Criteria only, not {@code em.find}/{@code findById} - by-id lookups must still constrain company_id (the {@code findByIdAndCompanyId} convention).
 */
@Slf4j
@Component
public class TenantFilterInterceptor implements HandlerInterceptor, BeanPostProcessor {

    public static final String FILTER_NAME = "tenantFilter";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // Intentionally a no-op - see class comment. Kept registered so WebMvcConfig is unchanged.
        return true;
    }

    @Override
    public Object postProcessBeforeInitialization(Object bean, String beanName) throws BeansException {
        if (bean instanceof AbstractEntityManagerFactoryBean emfBean) {
            emfBean.setEntityManagerInitializer(TenantFilterInterceptor::enableTenantFilter);
        }
        return bean;
    }

    /** Enables the tenant filter on a freshly created EntityManager when a tenant user is authenticated on this thread. */
    static void enableTenantFilter(EntityManager em) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) return;
        // isTenantUser() uses the EFFECTIVE role, so a platform admin on an impersonation token is filtered to the impersonated company.
        if (!(auth.getPrincipal() instanceof User user) || !user.isTenantUser()) return;
        if (!(auth.getCredentials() instanceof Long companyId)) return;
        try {
            em.unwrap(Session.class).enableFilter(FILTER_NAME).setParameter("companyId", companyId);
        } catch (RuntimeException ex) {
            log.warn("Could not enable tenant filter for company {}: {}", companyId, ex.getMessage());
        }
    }
}
