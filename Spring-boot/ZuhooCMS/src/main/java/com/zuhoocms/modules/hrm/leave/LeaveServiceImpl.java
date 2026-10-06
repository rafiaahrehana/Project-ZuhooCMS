package com.zuhoocms.modules.hrm.leave;

import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalance;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceMapper;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceRepository;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceResponse;
import com.zuhoocms.modules.hrm.leave.leaverequest.*;
import com.zuhoocms.modules.hrm.leave.companyleavePolicy.CompanyLeavePolicyRepository;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyLeavePolicy;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.enums.LeaveRequestStatus;
import java.util.List;

import com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignment;
import com.zuhoocms.modules.hrm.attendance.shift.WeeklyOffDays;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

@Slf4j
@Service
@RequiredArgsConstructor
public class LeaveServiceImpl implements LeaveService {

    private final LeaveRequestRepository leaveRequestRepository;
    private final LeaveBalanceRepository leaveBalanceRepository;
    private final com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceService leaveBalanceService;
    private final EmployeeRepository employeeRepository;
    private final CompanyRepository companyRepository;
    private final SecurityUtil securityUtil;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final com.zuhoocms.modules.hrm.leave.holiday.HolidayRepository holidayRepository;
    private final CompanyLeavePolicyRepository leavePolicyRepository;
    private final NotificationService notificationService;
    private final AuthorizationService authorizationService;
    private final com.zuhoocms.modules.hrm.attendance.attendance.AttendanceRepository attendanceRepository;
    private final com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignmentRepository employeeShiftAssignmentRepository;

    @Override
    @Transactional
    public LeaveRequestResponse apply(LeaveRequestDto request) {
        Long companyId = requireCompanyId();
        // Must be the record for the ACTIVE company: otherwise the request row is stamped with company A while
        // drawing down company B's leave balance.
        Employee employee = currentEmployeeInCompany(companyId);

        if (request.getEndDate().isBefore(request.getStartDate())) {
            throw new BadRequestException("End date must be on or after start date");
        }
        // Blocks self-service backdating: an employee could otherwise reclassify an unexcused ABSENT day as leave just before payroll. LEAVE_APPROVE holders may still backdate.
        if (request.getStartDate().isBefore(java.time.LocalDate.now())
                && !authorizationService.hasPermission(PermissionCode.LEAVE_APPROVE)) {
            throw new BadRequestException(
                    "Leave requests can't start in the past - ask HR to log it on your behalf if this is a retroactive request");
        }

        if (leaveRequestRepository.hasOverlappingLeave(
                employee.getId(), request.getStartDate(), request.getEndDate(),
                List.of(LeaveRequestStatus.REJECTED, LeaveRequestStatus.CANCELLED))) {
            throw new BadRequestException("You already have a leave request overlapping this period");
        }

        // Chargeable days exclude weekly off days and holidays: Thursday-to-Sunday over a FRI/SAT weekend charges 2 days, not 4.
        int totalDays = countChargeableDays(employee, companyId, request.getStartDate(), request.getEndDate());
        if (totalDays == 0) {
            throw new BadRequestException(
                    "The selected period contains only weekends and holidays - no leave balance is needed");
        }

        // Enforces maxConsecutiveDays, which was configurable but ignored - a "max 10 days" policy did not stop a 60-day request.
        // Non-blocking: no applicable policy means no cap here, though provisionBalanceFromPolicy still requires one for paid types.
        leavePolicyRepository.findApplicablePolicy(companyId, request.getLeaveType(), employee.getEmploymentType())
                .map(CompanyLeavePolicy::getMaxConsecutiveDays)
                .filter(max -> max != null && max > 0 && totalDays > max)
                .ifPresent(max -> {
                    throw new BadRequestException(
                            "This request spans " + totalDays + " day(s), exceeding the " + max
                                    + "-day consecutive limit for " + request.getLeaveType() + " leave.");
                });

        // Balance check, skipped only for UNPAID, which draws on no entitlement.
        // A missing LeaveBalance row (the default for an unprovisioned new hire) used to skip the check entirely, leaving paid leave unenforced; it is now auto-provisioned from the policy, or the request is rejected.
        if (request.getLeaveType() != com.zuhoocms.enums.LeaveType.UNPAID) {
            LeaveBalance balance = leaveBalanceRepository.findForUpdate(
                    employee.getId(), request.getLeaveType(), request.getStartDate().getYear())
                    .orElseGet(() -> provisionBalanceFromPolicy(employee, companyId, request.getLeaveType(),
                            request.getStartDate().getYear()));

            if (balance.getRemainingDays() < totalDays) {
                throw new BadRequestException("Insufficient " + request.getLeaveType()
                        + " leave balance. Available: " + balance.getRemainingDays()
                        + " days, Requested: " + totalDays + " days.");
            }
            balance.setPendingDays(balance.getPendingDays() + totalDays);
        }

        LeaveRequest lr = LeaveRequest.builder()
                .leaveType(request.getLeaveType())
                .startDate(request.getStartDate())
                .endDate(request.getEndDate())
                .totalDays(totalDays)
                .reason(request.getReason())
                .status(LeaveRequestStatus.PENDING)
                .employee(employee)
                .company(companyRef(companyId))
                .build();

        leaveRequestRepository.save(lr);
        notifyApprover(lr, employee, companyId);
        return LeaveRequestMapper.toLeaveRequestResponse(lr);
    }

    /** Notifies the employee's reporting manager, else the company owner; without it requests sat PENDING until someone opened the queue. */
    private void notifyApprover(LeaveRequest lr, Employee employee, Long companyId) {
        Employee manager = employee.getReportingManager();
        User recipient = manager != null ? manager.getUser() : null;
        if (recipient == null) {
            Company company = companyRepository.findById(companyId).orElse(null);
            recipient = company != null ? company.getOwner() : null;
        }
        if (recipient == null) return;

        notificationService.send(CreateNotificationRequest.of(
                NotificationType.LEAVE_REQUESTED,
                "Leave request awaiting review",
                (employee.getUser() != null ? employee.getUser().getFullName() : "An employee")
                        + " requested " + lr.getTotalDays() + " day(s) of " + lr.getLeaveType()
                        + " leave (" + lr.getStartDate() + " to " + lr.getEndDate() + ")",
                "/leaves",
                recipient.getId(),
                companyId));
    }

    /**
     * Creates the LeaveBalance row for this type/year on first use, sized from the policy matching leave type + employment type (a company-wide policy wins over an employment-type one).
     * No applicable policy means none was set up, so the request is refused rather than let through unbounded.
     */
    private LeaveBalance provisionBalanceFromPolicy(Employee employee, Long companyId,
                                                     com.zuhoocms.enums.LeaveType leaveType, int year) {
        CompanyLeavePolicy policy = leavePolicyRepository
                .findApplicablePolicy(companyId, leaveType, employee.getEmploymentType())
                .orElseThrow(() -> new BadRequestException(
                        "No " + leaveType + " leave policy is configured for this company - "
                                + "set one up under Leave Policies before this leave type can be requested"));

        LeaveBalance balance = LeaveBalance.builder()
                .employee(employee)
                .company(companyRef(companyId))
                .leaveType(leaveType)
                .year(year)
                .totalDays(policy.getAnnualEntitlement())
                .build();
        return leaveBalanceRepository.save(balance);
    }

    /** Working days in [start, end], skipping the shift's weekly off days (FRI/SAT by default, like the Shift entity) and company holidays. */
    private int countChargeableDays(Employee employee, Long companyId,
                                    java.time.LocalDate start, java.time.LocalDate end) {
        java.util.Map<Long, java.util.Set<java.time.DayOfWeek>> offDaysByAssignment = new java.util.HashMap<>();
        java.util.Set<java.time.LocalDate> holidays = new java.util.HashSet<>();
        holidayRepository.findByCompanyAndDateRange(companyId, start, end)
                .forEach(h -> holidays.add(h.getDate()));

        int days = 0;
        for (java.time.LocalDate d = start; !d.isAfter(end); d = d.plusDays(1)) {
            if (weeklyOffDays(employee, companyId, d, offDaysByAssignment).contains(d.getDayOfWeek())) continue;
            if (holidays.contains(d)) continue;
            days++;
        }
        return days;
    }

    @Override
    @Transactional(readOnly = true)
    public int unpaidLeaveDays(Long employeeId, Long companyId, int month, int year) {
        // Scoped by id AND company: findById is an em.find, which Hibernate's tenantFilter never touches, so without
        // this an employee id from another tenant would be priced into this company's payroll.
        Employee employee = companyId != null
            ? employeeRepository.findByIdAndCompanyId(employeeId, companyId).orElse(null)
            : employeeRepository.findById(employeeId).orElse(null);
        if (employee == null || employee.getCompany() == null) return 0;
        java.time.LocalDate monthStart = java.time.LocalDate.of(year, month, 1);
        java.time.LocalDate monthEnd = monthStart.withDayOfMonth(monthStart.lengthOfMonth());

        int days = 0;
        for (var lr : leaveRequestRepository.findApprovedOverlapping(
                employee.getCompany().getId(), employeeId, com.zuhoocms.enums.LeaveType.UNPAID, monthStart, monthEnd)) {
            java.time.LocalDate from = lr.getStartDate().isBefore(monthStart) ? monthStart : lr.getStartDate();
            java.time.LocalDate to = lr.getEndDate().isAfter(monthEnd) ? monthEnd : lr.getEndDate();
            days += countChargeableDays(employee, employee.getCompany().getId(), from, to);
        }
        return days;
    }

    private java.util.Set<java.time.DayOfWeek> weeklyOffDays(Employee employee, Long companyId, java.time.LocalDate date,
                                                             java.util.Map<Long, java.util.Set<java.time.DayOfWeek>> cache) {
        // Shift comes from EmployeeShiftAssignment, as in AttendanceServiceImpl/AbsenteeMarkingService; Employee.shift is a second, unsynced field that drifts from the roster.
        // Resolved per date because the shift can change inside the leave period.
        EmployeeShiftAssignment esa = employeeShiftAssignmentRepository
                .findEffectiveOn(companyId, employee.getId(), date)
                .orElse(null);
        if (esa == null) return WeeklyOffDays.parse(null);
        return cache.computeIfAbsent(esa.getId(), k -> WeeklyOffDays.parse(esa.getShift().getWeeklyOffDays()));
    }

    @Override
    @Transactional(readOnly = true)
    public LeaveRequestResponse getById(Long id) {
        return LeaveRequestMapper.toLeaveRequestResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeaveRequestResponse> listAll(LeaveRequestStatus status, Pageable pageable) {
        Long companyId = requireCompanyId();
        Page<LeaveRequest> page = status != null
                ? leaveRequestRepository.findByCompanyIdAndStatus(companyId, status, pageable)
                : leaveRequestRepository.findByCompanyId(companyId, pageable);
        return page.map(LeaveRequestMapper::toLeaveRequestResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<LeaveRequestResponse> listMyLeaves(Pageable pageable) {
        Long companyId = requireCompanyId();
        // Company-scoped below anyway, but resolving the other tenant's record here returned a silent empty page
        // instead of saying the profile is for a different company.
        Employee emp = currentEmployeeInCompany(companyId);
        return leaveRequestRepository.findByCompanyIdAndEmployeeId(companyId, emp.getId(), pageable)
                .map(LeaveRequestMapper::toLeaveRequestResponse);
    }

    @Override
    @Transactional
    public LeaveRequestResponse review(Long id, ReviewLeaveRequest request) {
        LeaveRequest lr = findInTenant(id);
        if (lr.getStatus() != LeaveRequestStatus.PENDING) {
            throw new BadRequestException("Only PENDING leave requests can be reviewed");
        }
        if (request.getStatus() != LeaveRequestStatus.APPROVED && request.getStatus() != LeaveRequestStatus.REJECTED) {
            throw new BadRequestException("Leave requests can only be approved or rejected");
        }
        if (request.getStatus() == LeaveRequestStatus.REJECTED
                && (request.getRejectionReason() == null || request.getRejectionReason().isBlank())) {
            throw new BadRequestException("Rejection reason is required when rejecting a leave requeststatus");
        }

        User reviewer = securityUtil.getCurrentUser();
        // Scoped to the request's company: resolving the reviewer's OTHER tenant's employee record gave a
        // non-matching id and waved the self-review guard through.
        Employee reviewerEmployee = reviewer != null
                ? employeeRepository.findByUserId(reviewer.getId())
                        .filter(e -> e.getCompany() != null && lr.getCompany() != null
                                && e.getCompany().getId().equals(lr.getCompany().getId()))
                        .orElse(null)
                : null;
        if (reviewerEmployee != null && lr.getEmployee() != null
                && reviewerEmployee.getId().equals(lr.getEmployee().getId())) {
            throw new ForbiddenException("You cannot review your own leave request");
        }

        lr.setStatus(request.getStatus());
        lr.setRejectionReason(request.getStatus() == LeaveRequestStatus.APPROVED ? null : request.getRejectionReason());
        lr.setReviewedBy(reviewer);
        lr.setReviewedAt(LocalDateTime.now());

        leaveBalanceRepository.findForUpdate(
                lr.getEmployee().getId(), lr.getLeaveType(), lr.getStartDate().getYear())
                .ifPresent(balance -> {
                    balance.setPendingDays(Math.max(0, balance.getPendingDays() - lr.getTotalDays()));
                    if (request.getStatus() == LeaveRequestStatus.APPROVED) {
                        balance.setUsedDays(balance.getUsedDays() + lr.getTotalDays());
                    }
                });

        if (request.getStatus() == LeaveRequestStatus.APPROVED) {
            // Backdated approval can cover days the nightly job already marked ABSENT; flip those rows to ON_LEAVE so payroll and reports reflect the approval.
            attendanceRepository.reconcileAbsentToOnLeave(
                    lr.getEmployee().getId(), lr.getStartDate(), lr.getEndDate(),
                    com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus.ABSENT,
                    com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus.ON_LEAVE);
        }

        if (lr.getEmployee().getUser() != null) {
            try {
                EmailBranding.Data branding = emailBranding.from(lr.getCompany());
                if (request.getStatus() == LeaveRequestStatus.APPROVED) {
                    emailService.sendLeaveApprovalEmail(
                            lr.getEmployee().getUser().getEmail(),
                            lr.getEmployee().getUser().getFirstName(), branding);
                } else if (request.getStatus() == LeaveRequestStatus.REJECTED) {
                    // Without this a rejected employee only finds out by re-checking the leave list.
                    emailService.sendLeaveRejectionEmail(
                            lr.getEmployee().getUser().getEmail(),
                            lr.getEmployee().getUser().getFirstName(),
                            lr.getRejectionReason(), branding);
                }
            } catch (Exception ex) {
                log.warn("Leave review email failed for employee {}: {}", lr.getEmployee().getUser().getEmail(), ex.getMessage());
            }
        }

        return LeaveRequestMapper.toLeaveRequestResponse(lr);
    }

    @Override
    @Transactional
    public void cancel(Long id) {
        LeaveRequest lr = findInTenant(id);
        boolean cancellable = lr.getStatus() == LeaveRequestStatus.PENDING
                || (lr.getStatus() == LeaveRequestStatus.APPROVED
                        && lr.getStartDate().isAfter(java.time.LocalDate.now()));
        if (!cancellable) {
            throw new BadRequestException("Only pending or not-yet-started approved leave can be cancelled");
        }
        leaveBalanceRepository.findForUpdate(
                lr.getEmployee().getId(), lr.getLeaveType(), lr.getStartDate().getYear())
                .ifPresent(balance -> {
                    if (lr.getStatus() == LeaveRequestStatus.PENDING) {
                        balance.setPendingDays(Math.max(0, balance.getPendingDays() - lr.getTotalDays()));
                    } else if (lr.getStatus() == LeaveRequestStatus.APPROVED) {
                        balance.setUsedDays(Math.max(0, balance.getUsedDays() - lr.getTotalDays()));
                    }
                });
        lr.setStatus(LeaveRequestStatus.CANCELLED);
    }

    /**
     * GET /api/hr/leaves/balances/my. Delegates to {@link LeaveBalanceService#listMine(int)}, which serves the
     * identical GET /api/hr/leave-balances/my: both paths must stay (Angular calls this one, Flutter the other),
     * but only one may own the query, so the tenant rule cannot drift between them again. This copy previously
     * resolved the employee by user id alone and read whatever company that record belonged to.
     */
    @Override
    @Transactional(readOnly = true)
    public List<LeaveBalanceResponse> getMyBalances(int year) {
        return leaveBalanceService.listMine(year);
    }

    @Override
    @Transactional(readOnly = true)
    public List<LeaveBalanceResponse> getBalancesForEmployee(Long employeeId, int year) {
        Long companyId = requireCompanyId();
        Employee emp = employeeRepository.findByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found"));
        return leaveBalanceRepository.findByEmployeeIdAndYear(emp.getId(), year)
                .stream().map(LeaveBalanceMapper::toLeaveBalanceResponse).toList();
    }

    private LeaveRequest findInTenant(Long id) {
        return leaveRequestRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Leave requeststatus not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null)
            throw new BadRequestException("No company context");
        return id;
    }

    /**
     * The caller's employee record in the active company. findByUserId alone is not enough: a user may hold an
     * employee record in more than one tenant, and the one it returns is whichever the database hands back.
     * Same rule as LeaveBalanceServiceImpl.listMine.
     */
    private Employee currentEmployeeInCompany(Long companyId) {
        Employee me = employeeRepository.findByUserId(securityUtil.getCurrentUser().getId())
                .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        if (me.getCompany() == null || !me.getCompany().getId().equals(companyId)) {
            throw new BadRequestException("Employee profile does not belong to the active company");
        }
        return me;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }
}
