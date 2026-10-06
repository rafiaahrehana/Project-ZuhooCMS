package com.zuhoocms.modules.hrm.dashboard;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * Everything the HR dashboard renders, in one round trip; aggregated live on read, nothing stored, so nothing can drift.
 * Counts that can legitimately be zero are primitives; genuinely unknown values are boxed and null so the UI shows a dash, not 0%.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class HrDashboardResponse {

    private long totalEmployees;
    private long newHiresThisMonth;
    private long presentToday;
    private long onLeaveToday;
    private long absentToday;
    private long openPositions;

    /** Share of today's recorded attendance that is present. Null when nothing is recorded yet. */
    private Double presentTodayPercent;
    /** Share on leave today. Null when nothing is recorded yet. */
    private Double onLeaveTodayPercent;

    /** Net payroll for the current month. Null when no payroll has been generated. */
    private BigDecimal monthlyPayrollTotal;
    private int payrollMonth;
    private int payrollYear;

    private List<DepartmentSlice> departmentDistribution;
    private LeaveSummary leaveSummary;
    private List<JoinerItem> recentJoiners;
    private List<UpcomingItem> upcomingItems;
    /** Month-to-date headcount, one point per elapsed day. */
    private List<TrendPoint> headcountTrend;
    /** Applications by stage: Applied -> Screening -> Interview -> Offer -> Hired. */
    private List<PipelineStage> recruitmentPipeline;
    /** Oldest pending leave requests, the actionable inbox. */
    private List<PendingApproval> pendingApprovals;

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class PipelineStage {
        private String stage;
        private long count;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class PendingApproval {
        private Long id;
        private String employeeName;
        private String leaveType;
        private LocalDate startDate;
        private LocalDate endDate;
        private int totalDays;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class DepartmentSlice {
        private String department;
        private long count;
        /** Share of employees who have a department assigned. */
        private double percent;
    }

    /** Leave requests raised in the current month, by outcome. */
    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class LeaveSummary {
        private long total;
        private long approved;
        private long pending;
        private long rejected;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class JoinerItem {
        private Long employeeId;
        private String name;
        private String jobTitle;
        private String department;
        private LocalDate hireDate;
    }

    /** A dated item needing HR's attention; kind is BIRTHDAY or PROBATION_END only, as review cycles and payroll runs are not scheduled anywhere. */
    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class UpcomingItem {
        private String kind;
        private String title;
        private String subtitle;
        private LocalDate date;
        private long daysAway;
    }

    @Data @Builder @NoArgsConstructor @AllArgsConstructor
    public static class TrendPoint {
        private LocalDate date;
        private long headcount;
    }
}
