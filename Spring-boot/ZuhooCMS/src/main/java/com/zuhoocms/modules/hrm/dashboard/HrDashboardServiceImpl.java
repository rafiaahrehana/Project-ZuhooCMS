package com.zuhoocms.modules.hrm.dashboard;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.enums.LeaveRequestStatus;
import com.zuhoocms.enums.PayrollStatus;
import com.zuhoocms.enums.JobPostingStatus;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceRepository;
import com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import com.zuhoocms.modules.hrm.payroll.PayrollRepository;
import com.zuhoocms.modules.hrm.recruitment.jobpost.JobPostingRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class HrDashboardServiceImpl implements HrDashboardService {

    private static final DateTimeFormatter MM_DD = DateTimeFormatter.ofPattern("MM-dd");
    /** How far ahead to look for birthdays and probation endings. */
    private static final int UPCOMING_WINDOW_DAYS = 30;

    private final EmployeeRepository employeeRepository;
    private final AttendanceRepository attendanceRepository;
    private final LeaveRequestRepository leaveRequestRepository;
    private final PayrollRepository payrollRepository;
    private final JobPostingRepository jobPostingRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final com.zuhoocms.modules.hrm.recruitment.jobapplication.JobApplicationRepository jobApplicationRepository;
    private final jakarta.persistence.EntityManager entityManager;

    @Override
    @Transactional(readOnly = true)
    public HrDashboardResponse getSummary() {
        // One gate for the whole dashboard: EMPLOYEE_VIEW marks "may see the workforce"; ordinary employees have their own dashboard.
        authorizationService.checkPermission(PermissionCode.EMPLOYEE_VIEW);
        Long companyId = requireCompanyId();

        LocalDate today = LocalDate.now();
        YearMonth month = YearMonth.from(today);
        LocalDate monthStart = month.atDay(1);
        LocalDate monthEnd = month.atEndOfMonth();

        // Active employees only: countByCompanyId counted resigned/deactivated people, disagreeing with every other widget.
        long totalEmployees = entityManager.createQuery("""
                SELECT COUNT(e) FROM Employee e
                 WHERE e.company.id = :companyId AND e.active = true AND e.deleted = false
                """, Long.class)
                .setParameter("companyId", companyId)
                .getSingleResult();
        long newHires = employeeRepository
                .countByCompanyIdAndActiveTrueAndHireDateBetween(companyId, monthStart, monthEnd);

        long present = attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.PRESENT, today)
                + attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.LATE, today)
                + attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.WORK_FROM_HOME, today);
        long onLeave = attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.ON_LEAVE, today);
        long absent = attendanceRepository.countByCompanyIdAndStatusAndDate(companyId, AttendanceStatus.ABSENT, today);

        // Percentages are of RECORDED attendance, not headcount: most rows don't exist early in the day, which would show a near-zero rate every morning.
        long recorded = present + onLeave + absent;
        Double presentPct = recorded == 0 ? null : round1(present * 100.0 / recorded);
        Double leavePct = recorded == 0 ? null : round1(onLeave * 100.0 / recorded);

        return HrDashboardResponse.builder()
                .totalEmployees(totalEmployees)
                .newHiresThisMonth(newHires)
                .presentToday(present)
                .onLeaveToday(onLeave)
                .absentToday(absent)
                .presentTodayPercent(presentPct)
                .onLeaveTodayPercent(leavePct)
                .openPositions(countOpenPositions(companyId))
                .monthlyPayrollTotal(monthlyPayroll(companyId, month))
                .payrollMonth(month.getMonthValue())
                .payrollYear(month.getYear())
                .departmentDistribution(departmentDistribution(companyId))
                .leaveSummary(leaveSummary(companyId, monthStart, monthEnd))
                .recentJoiners(recentJoiners(companyId))
                .upcomingItems(upcomingItems(companyId, today))
                .headcountTrend(headcountTrend(companyId, monthStart, today))
                .recruitmentPipeline(recruitmentPipeline(companyId))
                .pendingApprovals(pendingApprovals(companyId))
                .build();
    }

    private long countOpenPositions(Long companyId) {
        return jobPostingRepository.findByCompanyIdAndStatus(companyId, JobPostingStatus.OPEN).size();
    }

    /** Net payroll actually paid or approved this month. Null when none exists yet. */
    private BigDecimal monthlyPayroll(Long companyId, YearMonth month) {
        BigDecimal paid = payrollRepository.sumNetSalaryByCompanyAndPeriod(
                companyId, month.getMonthValue(), month.getYear(), PayrollStatus.PAID).orElse(null);
        BigDecimal approved = payrollRepository.sumNetSalaryByCompanyAndPeriod(
                companyId, month.getMonthValue(), month.getYear(), PayrollStatus.APPROVED).orElse(null);

        if (paid == null && approved == null) return null;
        return (paid != null ? paid : BigDecimal.ZERO)
                .add(approved != null ? approved : BigDecimal.ZERO);
    }

    private List<HrDashboardResponse.DepartmentSlice> departmentDistribution(Long companyId) {
        List<Object[]> rows = employeeRepository.countByDepartment(companyId);
        long assigned = rows.stream().mapToLong(r -> ((Number) r[1]).longValue()).sum();

        List<HrDashboardResponse.DepartmentSlice> slices = new ArrayList<>();
        for (Object[] row : rows) {
            long count = ((Number) row[1]).longValue();
            slices.add(HrDashboardResponse.DepartmentSlice.builder()
                    .department((String) row[0])
                    .count(count)
                    .percent(assigned == 0 ? 0 : round1(count * 100.0 / assigned))
                    .build());
        }
        return slices;
    }

    private HrDashboardResponse.LeaveSummary leaveSummary(Long companyId, LocalDate from, LocalDate to) {
        return HrDashboardResponse.LeaveSummary.builder()
                .total(leaveRequestRepository
                        .countByCompanyIdAndStartDateLessThanEqualAndEndDateGreaterThanEqual(companyId, to, from))
                .approved(countLeave(companyId, LeaveRequestStatus.APPROVED, from, to))
                .pending(countLeave(companyId, LeaveRequestStatus.PENDING, from, to))
                .rejected(countLeave(companyId, LeaveRequestStatus.REJECTED, from, to))
                .build();
    }

    private long countLeave(Long companyId, LeaveRequestStatus status, LocalDate from, LocalDate to) {
        return leaveRequestRepository
                .countByCompanyIdAndStatusAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
                        companyId, status, to, from);
    }

    private List<HrDashboardResponse.JoinerItem> recentJoiners(Long companyId) {
        return employeeRepository.findRecentJoiners(companyId, PageRequest.of(0, 5)).stream()
                .map(e -> HrDashboardResponse.JoinerItem.builder()
                        .employeeId(e.getId())
                        .name(displayName(e))
                        .jobTitle(e.getJobTitle())
                        .department(e.getDepartment() != null ? e.getDepartment().getName() : null)
                        .hireDate(e.getHireDate())
                        .build())
                .toList();
    }

    /** Birthdays and probation endings in the next 30 days; a window wrapping across new year is queried as two MM-DD ranges, since one string comparison cannot express it. */
    private List<HrDashboardResponse.UpcomingItem> upcomingItems(Long companyId, LocalDate today) {
        LocalDate horizon = today.plusDays(UPCOMING_WINDOW_DAYS);
        List<HrDashboardResponse.UpcomingItem> items = new ArrayList<>();

        List<Employee> birthdays = new ArrayList<>();
        if (horizon.getYear() == today.getYear()) {
            birthdays.addAll(employeeRepository.findBirthdaysBetween(
                    companyId, today.format(MM_DD), horizon.format(MM_DD)));
        } else {
            birthdays.addAll(employeeRepository.findBirthdaysBetween(companyId, today.format(MM_DD), "12-31"));
            birthdays.addAll(employeeRepository.findBirthdaysBetween(companyId, "01-01", horizon.format(MM_DD)));
        }
        for (Employee e : birthdays) {
            // Next occurrence on or after today; MonthDay.atYear maps 29 Feb to 28 Feb in non-leap years.
            java.time.MonthDay md = java.time.MonthDay.from(e.getDateOfBirth());
            LocalDate next = md.atYear(today.getYear());
            if (next.isBefore(today)) next = md.atYear(today.getYear() + 1);
            if (next.isAfter(horizon)) continue;
            items.add(HrDashboardResponse.UpcomingItem.builder()
                    .kind("BIRTHDAY")
                    .title(displayName(e) + "'s birthday")
                    .subtitle(e.getDepartment() != null ? e.getDepartment().getName() : e.getJobTitle())
                    .date(next)
                    .daysAway(ChronoUnit.DAYS.between(today, next))
                    .build());
        }

        for (Employee e : employeeRepository.findProbationEndingBetween(companyId, today, horizon)) {
            items.add(HrDashboardResponse.UpcomingItem.builder()
                    .kind("PROBATION_END")
                    .title(displayName(e) + " - probation ending")
                    .subtitle(e.getJobTitle())
                    .date(e.getProbationEndDate())
                    .daysAway(ChronoUnit.DAYS.between(today, e.getProbationEndDate()))
                    .build());
        }

        items.sort((a, b) -> Long.compare(a.getDaysAway(), b.getDaysAway()));
        return items.size() > 6 ? items.subList(0, 6) : items;
    }

    /**
     * Month-to-date headcount of ACTIVE employees, reconstructed from hire dates in one grouped query.
     * Employee has no termination date, so someone deactivated mid-month is counted on no day; active employees with no hire date form the baseline, so the last point equals totalEmployees.
     */
    private List<HrDashboardResponse.TrendPoint> headcountTrend(Long companyId, LocalDate from, LocalDate today) {
        List<Object[]> rows = entityManager.createQuery("""
                SELECT e.hireDate, COUNT(e) FROM Employee e
                 WHERE e.company.id = :companyId AND e.active = true AND e.deleted = false
                   AND (e.hireDate IS NULL OR e.hireDate <= :today)
                 GROUP BY e.hireDate
                """, Object[].class)
                .setParameter("companyId", companyId)
                .setParameter("today", today)
                .getResultList();

        long running = 0;
        java.util.Map<LocalDate, Long> hiredOn = new java.util.HashMap<>();
        for (Object[] row : rows) {
            LocalDate hireDate = (LocalDate) row[0];
            long count = ((Number) row[1]).longValue();
            if (hireDate == null || hireDate.isBefore(from)) {
                running += count;
            } else {
                hiredOn.merge(hireDate, count, Long::sum);
            }
        }

        List<HrDashboardResponse.TrendPoint> points = new ArrayList<>();
        for (LocalDate d = from; !d.isAfter(today); d = d.plusDays(1)) {
            running += hiredOn.getOrDefault(d, 0L);
            points.add(HrDashboardResponse.TrendPoint.builder()
                    .date(d)
                    .headcount(running)
                    .build());
        }
        return points;
    }

    /** An employee's name lives on their linked User; falls back to the employee number so a record with no user isn't a blank row. */
    private String displayName(Employee e) {
        if (e.getUser() != null) {
            String full = e.getUser().getFullName();
            if (full != null && !full.isBlank()) return full;
        }
        return e.getEmployeeNumber() != null ? e.getEmployeeNumber() : "Employee #" + e.getId();
    }

    private double round1(double v) {
        return Math.round(v * 10.0) / 10.0;
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    /** Applied -> Screening -> Interview -> Offer -> Hired: five readable stages folded from nine raw statuses. */
    private java.util.List<HrDashboardResponse.PipelineStage> recruitmentPipeline(Long companyId) {
        // Same status grouping as the recruitment KPI report (RecruitmentPipelineStages), which used to leave OFFER_REJECTED out of Offer.
        java.util.Map<com.zuhoocms.enums.ApplicationStatus, Long> perStatus = new java.util.EnumMap<>(
                com.zuhoocms.enums.ApplicationStatus.class);
        for (Object[] row : jobApplicationRepository.countByStatus(companyId)) {
            perStatus.put((com.zuhoocms.enums.ApplicationStatus) row[0], ((Number) row[1]).longValue());
        }
        return com.zuhoocms.modules.hrm.recruitment.kpi.RecruitmentPipelineStages.countByStage(perStatus)
                .entrySet().stream()
                .map(e -> stage(e.getKey(), e.getValue()))
                .toList();
    }

    private HrDashboardResponse.PipelineStage stage(String name, long count) {
        return HrDashboardResponse.PipelineStage.builder().stage(name).count(count).build();
    }

    /** Oldest pending leave requests first - the actionable inbox, capped at 6. */
    private java.util.List<HrDashboardResponse.PendingApproval> pendingApprovals(Long companyId) {
        return leaveRequestRepository.findByCompanyIdAndStatus(companyId,
                        com.zuhoocms.enums.LeaveRequestStatus.PENDING,
                        org.springframework.data.domain.PageRequest.of(0, 6,
                                org.springframework.data.domain.Sort.by("createdAt").ascending()))
                .map(lr -> HrDashboardResponse.PendingApproval.builder()
                        .id(lr.getId())
                        .employeeName(lr.getEmployee() != null && lr.getEmployee().getUser() != null
                                ? lr.getEmployee().getUser().getFullName() : "-")
                        .leaveType(lr.getLeaveType() != null ? lr.getLeaveType().name() : "-")
                        .startDate(lr.getStartDate())
                        .endDate(lr.getEndDate())
                        .totalDays(lr.getTotalDays())
                        .build())
                .getContent();
    }
}
