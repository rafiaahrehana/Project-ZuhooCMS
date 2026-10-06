package com.zuhoocms.modules.company;

import com.zuhoocms.enums.CompanyStatus;
import com.zuhoocms.shared.subscription.SubscriptionPlanDefinition;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;

public interface CompanyService {
    CompanyPublicResponse getBySubdomain(String subdomain);

    /** Companies a prospective client can pick from during public client registration. */
    java.util.List<CompanyPublicListItem> getPublicList();

    java.util.List<com.zuhoocms.modules.servicedesk.companyservice.CompanyServiceResponse> getPublicServices(String subdomain);
    CompanyResponse getById(Long id);
    CompanyResponse update(Long id, UpdateCompanyRequest request);
    CompanyResponse registerByAdmin(RegisterCompanyRequest request);
    Page<CompanyResponse> listAll(CompanyStatus status, String plan, String keyword, Pageable pageable);

    /** planCode must match a SubscriptionPlanDefinition.code - its billingCycle
     * determines whether subscriptionEnd becomes +1 month or +1 year from today. */
    CompanyResponse changePlan(Long id, String planCode, BigDecimal amountPaid, String transactionRef);

    /** Paid checkout upgrade (SslCommerzServiceImpl.handleSuccess): unlike changePlan(), it also reactivates a TRIAL/SUSPENDED company. */
    void applyPaidPlanUpgrade(Long companyId, SubscriptionPlanDefinition plan, BigDecimal amountPaid,
                              String transactionRef, Long changedByUserId);

    CompanyResponse changeStatus(Long id, CompanyStatus status);
    void deactivate(Long id);
}
