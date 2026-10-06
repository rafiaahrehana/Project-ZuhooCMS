package com.zuhoocms.security;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Lazy;
import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

@Component
public class SubscriptionEnforcementFilter extends OncePerRequestFilter {

    private final SecurityUtil securityUtil;
    private final CompanyRepository companyRepository;
    private final ObjectMapper objectMapper;
    private final com.zuhoocms.modules.demo.DemoAccount demoAccount;

    public SubscriptionEnforcementFilter(SecurityUtil securityUtil, 
                                         CompanyRepository companyRepository, 
                                         @Lazy ObjectMapper objectMapper,
                                         @Lazy com.zuhoocms.modules.demo.DemoAccount demoAccount) {
        this.securityUtil = securityUtil;
        this.companyRepository = companyRepository;
        this.objectMapper = objectMapper;
        this.demoAccount = demoAccount;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String method = request.getMethod();
        String uri = request.getRequestURI();

        if (HttpMethod.GET.matches(method) ||
            HttpMethod.OPTIONS.matches(method) || 
            HttpMethod.HEAD.matches(method)) {
            filterChain.doFilter(request, response);
            return;
        }

        if (uri.startsWith("/api/auth/") || uri.startsWith("/api/companies/public/")) {
            filterChain.doFilter(request, response);
            return;
        }

        User user = securityUtil.getCurrentUser();
        Long companyId = securityUtil.getCurrentCompanyId();

        if (user != null && companyId != null) {
            Company company = companyRepository.findById(companyId).orElse(null);

            // Status must be checked as well as subscriptionEnd, or a ToS/fraud suspension has no effect until the unrelated billing date expires.
            boolean adminSuspended = company != null
                    && (company.getStatus() == CompanyStatus.SUSPENDED
                        || company.getStatus() == CompanyStatus.DEACTIVATED);

            // isTrialExpired() also covers a TRIAL that never started (no end date); the demo tenant is exempt because it is read-only anyway.
            boolean expired = company != null && company.isTrialExpired() && !demoAccount.isDemoCompany(company);
            if (company != null && (adminSuspended || expired)) {
                // These exceptions let a company pay its way out of a billing lapse, so an admin-suspended company gets none of them - a suspension for cause must not be escapable via the payment endpoint.
                boolean isAllowedEndpoint = !adminSuspended && (
                                            uri.matches("^/api/support/tickets.*") ||
                                            uri.matches("^/api/invoices.*") ||
                                            uri.matches("^/api/payment.*") ||
                                            uri.matches("^/api/wallet.*"));

                if (!isAllowedEndpoint) {
                    response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                    response.setContentType("application/json");

                    Map<String, String> error = new HashMap<>();
                    error.put("error", adminSuspended ? "Account Suspended" : "Subscription Expired");
                    error.put("message", adminSuspended
                            ? "Your account has been suspended. Please contact support."
                            : "Your subscription or trial has expired. The system is in read-only mode. Please process payment or contact support to continue.");

                    response.getWriter().write(objectMapper.writeValueAsString(error));
                    return;
                }
            }
        }

        filterChain.doFilter(request, response);
    }
}
