package com.zuhoocms.modules.servicedesk.companyservice;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import com.zuhoocms.enums.SubscriptionStatus;

import java.util.List;

public interface ServicePackageService {

    ServicePackageResponse create(ServicePackageRequest request);

    ServicePackageResponse getById(Long id);

    Page<ServicePackageResponse> listAll(Pageable pageable);

    List<ServicePackageResponse> listActive();

    ServicePackageResponse update(Long id, ServicePackageRequest request);

    ServicePackageResponse toggleActive(Long id);

    void delete(Long id);

    /** A client subscribes, or staff subscribe on a client's behalf. */
    PackageSubscriptionResponse subscribe(SubscribeRequest request);

    /** Activates a PENDING_PAYMENT subscription by hand, standing in for payment confirmation. */
    PackageSubscriptionResponse activate(Long subscriptionId);

    /** System entry point (payment gateway callbacks) - no security context. */
    PackageSubscriptionResponse activateForCompany(Long companyId, Long subscriptionId);

    PackageSubscriptionResponse suspend(Long subscriptionId, String reason);

    PackageSubscriptionResponse cancel(Long subscriptionId, String reason);

    PackageSubscriptionResponse reactivate(Long subscriptionId);

    /** System entry point (scheduler) — renews an ACTIVE, auto-renew subscription past its endDate. No security context. */
    PackageSubscription renewSubscription(Long subscriptionId);

    /** System entry point (scheduler) — expires an ACTIVE subscription past its endDate. No security context. */
    PackageSubscription expireSubscription(Long subscriptionId);

    PackageSubscriptionResponse getSubscriptionById(Long id);

    Page<PackageSubscriptionResponse> listSubscriptions(
        SubscriptionStatus status, Pageable pageable);

    Page<PackageSubscriptionResponse> listMySubscriptions(Pageable pageable);

    /** Validates quota and increments requestsUsed when a request is raised under a subscription. */
    PackageSubscription consumeQuota(Long subscriptionId);

    /** Called by ServiceRequestServiceImpl.cancel() to give back a quota unit consumed by a request that was never fulfilled. */
    PackageSubscription releaseQuota(Long subscriptionId);

    /** Same as releaseQuota() with an explicit tenant - for system paths with no security context (schedulers). */
    PackageSubscription releaseQuotaForCompany(Long companyId, Long subscriptionId);
}
