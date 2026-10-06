package com.zuhoocms.modules.dashboard;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.util.List;

@Getter @Setter @Builder
public class PlatformSummaryResponse {

    long totalCompanies;
    long activeCompanies;
    long trialCompanies;
    long suspendedCompanies;
    long pendingVerificationCompanies;

    // Trials whose subscription window ends within the next 7 days
    long trialsExpiringWithin7Days;

    // Dynamic, not fixed fields: Super Admin can add/remove plans at runtime - see SubscriptionPlanDefinition.
    List<PlanCompanyCount> companiesByPlan;

    // SaaS staff accounts (all platform roles)
    long totalPlatformUsers;

    // Recorded subscription revenue (SUM of SubscriptionHistory.amountPaid)
    BigDecimal totalRevenue;
    BigDecimal revenueThisMonth;
}
