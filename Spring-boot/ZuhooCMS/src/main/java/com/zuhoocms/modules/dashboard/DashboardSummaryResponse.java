package com.zuhoocms.modules.dashboard;

import lombok.Builder;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;

@Getter @Setter @Builder
public class DashboardSummaryResponse {

    long totalLeads;
    long newLeads;
    long qualifiedLeads;
    long totalClients;
    long openOpportunities;
    BigDecimal pipelineValue;
    BigDecimal weightedForecast;

    long pendingRequests;
    long inProgressRequests;
    long completedRequestsAllTime;
    long slaBreachedOpen;
    long totalServiceRequests;

    long openTickets;
    long newTickets;

    BigDecimal outstandingInvoiceAmount;
    BigDecimal walletBalance;
    BigDecimal walletCreditBalance;

    long totalEmployees;
    long pendingLeaveApprovals;
    long payrollProcessedThisMonth;

    // Trends are percentages vs the previous window, or null when there is nothing to compare against.
    Double leadsTrend;
    Double clientsTrend;
    Double opportunitiesTrend;
    Double weightedForecastTrend;

    java.util.List<String> salesOverviewLabels;
    java.util.List<Long> salesOverviewData;
    Double salesOverviewTrend;

    long serviceDeskPendingCount;
    long serviceDeskInProgressCount;
    long serviceDeskResolvedCount;
    /** Requests parked in WAITING_CLIENT (kept under its old name for existing clients). */
    long serviceDeskOnHoldCount;
    long serviceDeskWaitingOnClientCount;

    long tasksCreatedCount;
    Double tasksCreatedTrend;
    long tasksCompletedCount;
    Double tasksCompletedTrend;
    long tasksOverdueCount;
    Double tasksOverdueTrend;

    java.util.List<InvoiceDetailDto> overdueInvoices;

    Double walletBalanceTrend;
    BigDecimal walletCredits;
    BigDecimal walletDebits;

    long employeesPresentToday;
    long employeesOnLeave;
    Double employeesTrend;

    java.util.List<AnnouncementDto> announcements;

    /*
     * Which sections could NOT be read this time: "crm", "servicedesk", "support", "finance", "hrm", "payroll".
     * Every number a failed section feeds is zero or empty in this response, and without this field a broken
     * invoice query looks exactly like a company with no invoices. Empty when everything answered.
     *
     * A section the viewer is not permitted to see is NOT listed - it was never queried. Nor is a section that
     * simply had nothing to report: that zero is the truth, not a guess.
     */
    java.util.List<String> unavailableSections;
}
