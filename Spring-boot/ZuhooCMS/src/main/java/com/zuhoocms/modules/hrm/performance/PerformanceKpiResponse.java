package com.zuhoocms.modules.hrm.performance;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

/**
 * Objective KPIs for one employee over a review period, aggregated from attendance, leave, service-desk tasks, service requests and client reviews.
 * Nothing is stored on the review; it is recomputed on read, so the same period always aggregates the same way.
 * Fields are nullable on purpose: null means "no data for this period" and must render as a dash, not a zero.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PerformanceKpiResponse {

    private Long employeeId;
    private LocalDate periodStart;
    private LocalDate periodEnd;

    /** Days marked PRESENT, LATE or WORK_FROM_HOME. */
    private long daysPresent;
    /** Days marked ABSENT. */
    private long daysAbsent;
    /** Working days with an attendance record of any kind. */
    private long workingDaysRecorded;
    /** daysPresent / workingDaysRecorded, 0-100. Null when nothing was recorded. */
    private Double attendancePercent;

    private long lateArrivals;
    private int  leaveDaysTaken;

    private long tasksCompleted;
    private long projectsCompleted;

    /** Mean client rating (1-5) of this employee's work. Null when unrated. */
    private Double customerSatisfaction;
}
