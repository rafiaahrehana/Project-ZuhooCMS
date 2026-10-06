package com.zuhoocms.modules.hrm.payroll.loan;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** Employee loans/advances recovered through payroll; installment computation and PAID-time settlement live in PayrollServiceImpl, the only place payroll status changes. */
@Service
@RequiredArgsConstructor
public class LoanAdvanceService {

    private final LoanAdvanceRepository loanRepository;
    private final LoanRepaymentRepository repaymentRepository;
    private final EmployeeRepository employeeRepository;
    private final SecurityUtil securityUtil;
    private final jakarta.persistence.EntityManager entityManager;

    @Transactional
    public LoanAdvanceResponse create(CreateLoanRequest request) {
        Long companyId = requireCompanyId();
        Employee employee = employeeRepository.findByIdAndCompanyId(request.getEmployeeId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + request.getEmployeeId()));

        if (request.getMonthlyInstallment() != null && request.getPrincipalAmount() != null
                && request.getMonthlyInstallment().compareTo(request.getPrincipalAmount()) > 0) {
            throw new BadRequestException("Monthly installment cannot exceed the principal amount");
        }

        // One ACTIVE loan per employee, so this month's deduction is unambiguous; checked under row locks on the employee (serializing two first-ever loans) and every existing loan row.
        entityManager.lock(employee, jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
        boolean hasActive = loanRepository.lockAllForEmployee(employee.getId()).stream()
                .anyMatch(l -> l.getStatus() == LoanAdvance.Status.ACTIVE);
        if (hasActive) {
            throw new BadRequestException(
                    employeeDisplayName(employee) + " already has an active loan/advance - close or cancel it first");
        }

        LoanAdvance loan = LoanAdvance.builder()
                .company(companyRef(companyId))
                .employee(employee)
                .type(request.getType())
                .principalAmount(request.getPrincipalAmount())
                .disbursedDate(request.getDisbursedDate())
                .monthlyInstallment(request.getMonthlyInstallment())
                .remainingBalance(request.getPrincipalAmount())
                .status(LoanAdvance.Status.ACTIVE)
                .reason(request.getReason())
                .notes(request.getNotes())
                .build();
        loanRepository.save(loan);
        return LoanAdvanceMapper.toResponse(loan);
    }

    @Transactional(readOnly = true)
    public List<LoanAdvanceResponse> list() {
        return loanRepository.findByCompanyIdOrderByCreatedAtDesc(requireCompanyId())
                .stream().map(LoanAdvanceMapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<LoanAdvanceResponse> listForEmployee(Long employeeId) {
        Long companyId = requireCompanyId();
        employeeRepository.findByIdAndCompanyId(employeeId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + employeeId));
        return loanRepository.findByEmployeeIdOrderByCreatedAtDesc(employeeId)
                .stream().map(LoanAdvanceMapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public LoanAdvanceResponse getById(Long id) {
        return LoanAdvanceMapper.toResponse(findInTenant(id));
    }

    @Transactional(readOnly = true)
    public List<LoanRepaymentResponse> repaymentHistory(Long loanId) {
        findInTenant(loanId); // tenant check
        return repaymentRepository.findByLoanIdOrderByPaidDateDesc(loanId)
                .stream().map(LoanAdvanceMapper::toResponse).toList();
    }

    /** Only legal before any installment has been recovered - once payroll has paid one, the money is partly out and the loan must run to completion. */
    @Transactional
    public LoanAdvanceResponse cancel(Long id) {
        LoanAdvance loan = findInTenant(id);
        if (loan.getStatus() != LoanAdvance.Status.ACTIVE) {
            throw new BadRequestException("Only an active loan can be cancelled");
        }
        if (!repaymentRepository.findByLoanIdOrderByPaidDateDesc(id).isEmpty()) {
            throw new BadRequestException("Cannot cancel: this loan already has recorded repayments");
        }
        loan.setStatus(LoanAdvance.Status.CANCELLED);
        loanRepository.save(loan);
        return LoanAdvanceMapper.toResponse(loan);
    }

    private LoanAdvance findInTenant(Long id) {
        return loanRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Loan/advance not found: " + id));
    }

    private String employeeDisplayName(Employee employee) {
        return employee.getUser() != null ? employee.getUser().getFullName() : "Employee #" + employee.getId();
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }
}
