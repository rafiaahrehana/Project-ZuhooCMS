package com.zuhoocms.modules.hrm.leave;

import com.zuhoocms.auth.user.User;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.enums.LeaveType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalance;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceRepository;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceResponse;
import com.zuhoocms.modules.hrm.leave.leavebalance.LeaveBalanceServiceImpl;
import com.zuhoocms.modules.hrm.leave.leaverequest.LeaveRequestRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.notification.NotificationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.*;

/**
 * The two endpoints that answer "my leave balances" - GET /api/hr/leaves/balances/my (Angular) via
 * {@link LeaveServiceImpl#getMyBalances} and GET /api/hr/leave-balances/my (Flutter) via
 * {@link LeaveBalanceServiceImpl#listMine} - must apply the same tenant rule.
 *
 * <p>The Angular one used to resolve the employee with {@code findByUserId} and read whatever company that record
 * belonged to, so a user holding an employee record in two tenants could be served the wrong tenant's balances.
 * Covered here rather than over HTTP because the two-employee-records state is not reachable through the API
 * (both {@code POST /api/auth/register} and {@code POST /api/employees} refuse an email that already has an
 * account), so no request sequence can demonstrate the refusal end to end.
 */
class MyLeaveBalanceTenantScopeTest {

    private static final long ACTIVE_COMPANY = 74L;
    private static final long OTHER_COMPANY = 75L;
    private static final long USER_ID = 227L;

    private LeaveBalanceRepository leaveBalanceRepository;
    private EmployeeRepository employeeRepository;
    private SecurityUtil securityUtil;
    private LeaveBalanceServiceImpl leaveBalanceService;
    private LeaveServiceImpl leaveService;

    @BeforeEach
    void setUp() {
        leaveBalanceRepository = mock(LeaveBalanceRepository.class);
        employeeRepository = mock(EmployeeRepository.class);
        securityUtil = mock(SecurityUtil.class);

        User user = User.builder().email("leakcheck.owner@example.com").firstName("Leakcheck").lastName("Owner").build();
        ReflectionTestUtils.setField(user, "id", USER_ID);
        when(securityUtil.getCurrentUser()).thenReturn(user);
        when(securityUtil.getCurrentCompanyId()).thenReturn(ACTIVE_COMPANY);

        leaveBalanceService = new LeaveBalanceServiceImpl(
                leaveBalanceRepository, employeeRepository, securityUtil, mock(AuthorizationService.class));

        // Field order of LeaveServiceImpl's @RequiredArgsConstructor. Only the balance service, employee repo and
        // SecurityUtil matter here; the rest exist so the bean can be built.
        leaveService = new LeaveServiceImpl(
                mock(LeaveRequestRepository.class),
                leaveBalanceRepository,
                leaveBalanceService,
                employeeRepository,
                mock(CompanyRepository.class),
                securityUtil,
                mock(EmailService.class),
                mock(EmailBranding.class),
                mock(com.zuhoocms.modules.hrm.leave.holiday.HolidayRepository.class),
                mock(com.zuhoocms.modules.hrm.leave.companyleavePolicy.CompanyLeavePolicyRepository.class),
                mock(NotificationService.class),
                mock(AuthorizationService.class),
                mock(com.zuhoocms.modules.hrm.attendance.attendance.AttendanceRepository.class),
                mock(com.zuhoocms.modules.hrm.attendance.shift.EmployeeShiftAssignmentRepository.class));
    }

    private Employee employeeIn(long companyId, long employeeId) {
        Company company = new Company();
        company.setId(companyId);
        User user = User.builder().firstName("Leakcheck").lastName("Owner").build();
        ReflectionTestUtils.setField(user, "id", USER_ID);
        Employee e = Employee.builder().user(user).company(company).build();
        ReflectionTestUtils.setField(e, "id", employeeId);
        return e;
    }

    private void balancesExistFor(Employee employee) {
        LeaveBalance lb = LeaveBalance.builder()
                .employee(employee).company(employee.getCompany())
                .leaveType(LeaveType.ANNUAL).year(2026).totalDays(21).usedDays(0).pendingDays(0)
                .build();
        ReflectionTestUtils.setField(lb, "id", 92L);
        when(leaveBalanceRepository.findByEmployeeIdAndYear(employee.getId(), 2026)).thenReturn(List.of(lb));
    }

    @Test
    void bothEndpointsServeTheActiveCompanysBalances() {
        Employee me = employeeIn(ACTIVE_COMPANY, 184L);
        when(employeeRepository.findByUserId(USER_ID)).thenReturn(Optional.of(me));
        balancesExistFor(me);

        List<LeaveBalanceResponse> viaLeaveBalances = leaveBalanceService.listMine(2026);
        List<LeaveBalanceResponse> viaLeaves = leaveService.getMyBalances(2026);

        assertEquals(1, viaLeaves.size());
        assertEquals(184L, viaLeaves.get(0).getEmployeeId());
        assertEquals(21, viaLeaves.get(0).getEntitledDays());
        // Same rule, same query, same mapper - the two spellings must not drift apart again.
        assertEquals(viaLeaveBalances.get(0).getId(), viaLeaves.get(0).getId());
        assertEquals(viaLeaveBalances.get(0).getRemainingDays(), viaLeaves.get(0).getRemainingDays());
    }

    /** The leak: the caller's only employee record is in another tenant, so the active company has nothing to show. */
    @Test
    void leavesBalancesMyRefusesAnotherTenantsEmployeeRecord() {
        when(employeeRepository.findByUserId(USER_ID)).thenReturn(Optional.of(employeeIn(OTHER_COMPANY, 999L)));

        BadRequestException ex = assertThrows(BadRequestException.class, () -> leaveService.getMyBalances(2026));
        assertTrue(ex.getMessage().contains("does not belong to the active company"), ex.getMessage());
        // The point of the fix: the other tenant's balances are never even queried.
        verify(leaveBalanceRepository, never()).findByEmployeeIdAndYear(anyLong(), anyInt());
    }

    /** The twin behaves identically, so switching an app between the two paths changes nothing. */
    @Test
    void leaveBalancesMyRefusesAnotherTenantsEmployeeRecordToo() {
        when(employeeRepository.findByUserId(USER_ID)).thenReturn(Optional.of(employeeIn(OTHER_COMPANY, 999L)));

        assertThrows(BadRequestException.class, () -> leaveBalanceService.listMine(2026));
        verify(leaveBalanceRepository, never()).findByEmployeeIdAndYear(anyLong(), anyInt());
    }

    /** An employee row with no company at all must fail closed rather than fall through the comparison. */
    @Test
    void anEmployeeRecordWithNoCompanyIsRefused() {
        Employee orphan = Employee.builder().build();
        ReflectionTestUtils.setField(orphan, "id", 1000L);
        when(employeeRepository.findByUserId(USER_ID)).thenReturn(Optional.of(orphan));

        assertThrows(BadRequestException.class, () -> leaveService.getMyBalances(2026));
        verify(leaveBalanceRepository, never()).findByEmployeeIdAndYear(anyLong(), anyInt());
    }

    /** No company on the token is a refusal, not an unscoped read - the old getMyBalances never asked. */
    @Test
    void noActiveCompanyIsRefusedBeforeAnyLookup() {
        when(securityUtil.getCurrentCompanyId()).thenReturn(null);

        assertThrows(BadRequestException.class, () -> leaveService.getMyBalances(2026));
        verifyNoInteractions(employeeRepository);
        verify(leaveBalanceRepository, never()).findByEmployeeIdAndYear(anyLong(), anyInt());
    }
}
