package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.enums.BillingCycle;
import com.zuhoocms.enums.SubscriptionStatus;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/** A client's subscription to a ServicePackage for one billing period; past cycles are kept, but only one may be ACTIVE per package (enforced in ServicePackageServiceImpl.subscribe()). */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(
    name = "package_subscriptions",
    indexes = {
        @Index(name = "idx_sub_client_package", columnList = "client_id, package_id"),
        @Index(name = "idx_sub_status",         columnList = "status"),
        @Index(name = "idx_sub_end_date",        columnList = "end_date")
    }
)
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PackageSubscription extends BaseEntity {

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "package_id", nullable = false)
    private ServicePackage servicePackage;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "client_id", nullable = false)
    private Client client;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private SubscriptionStatus status = SubscriptionStatus.PENDING_PAYMENT;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private BillingCycle billingCycle;

    @Column(nullable = false)
    private LocalDate startDate;

    /** Calculated from startDate + billingCycle. NULL for indefinite ONE_TIME packages. */
    private LocalDate endDate;

    private LocalDate nextBillingDate;

    /** Price locked at subscription time, immune to later package price changes. */
    @Column(precision = 12, scale = 2, nullable = false)
    private BigDecimal pricePaid;

    /** Copied from the package at subscription time; NULL = unlimited. */
    private Integer requestQuota;

    /** Requests raised under this subscription in the current billing period. */
    @Builder.Default
    @Column(nullable = false)
    private int requestsUsed = 0;

    @Builder.Default
    private boolean autoRenew = true;

    /** Set when payment is confirmed. */
    private LocalDateTime activatedAt;

    /** Set on cancellation or suspension. */
    private LocalDateTime cancelledAt;

    @Column(columnDefinition = "TEXT")
    private String cancellationReason;

    /** Renewal-billing idempotency: the period start already invoiced, and that invoice's id, so a period is never invoiced twice. */
    private LocalDate lastRenewalInvoicedPeriodStart;

    private Long lastRenewalInvoiceId;

    public boolean isUsable() {
        return status == SubscriptionStatus.ACTIVE
            && (endDate == null || !LocalDate.now().isAfter(endDate));
    }

    /** NULL quota = unlimited. */
    public boolean hasRemainingQuota() {
        return requestQuota == null || requestsUsed < requestQuota;
    }

    /** Returns Integer.MAX_VALUE for an unlimited quota. */
    public int getRemainingRequests() {
        if (requestQuota == null) return Integer.MAX_VALUE;
        return Math.max(0, requestQuota - requestsUsed);
    }
}
