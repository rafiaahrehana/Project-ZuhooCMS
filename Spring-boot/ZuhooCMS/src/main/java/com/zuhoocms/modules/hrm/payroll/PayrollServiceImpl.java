package com.zuhoocms.modules.hrm.payroll;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.DefaultAccountResolver;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.payroll.loan.LoanAdvance;
import com.zuhoocms.modules.hrm.payroll.loan.LoanAdvanceRepository;
import com.zuhoocms.modules.hrm.payroll.loan.LoanRepayment;
import com.zuhoocms.modules.hrm.payroll.loan.LoanRepaymentRepository;
import com.zuhoocms.modules.hrm.payroll.run.PayrollRun;
import com.zuhoocms.modules.hrm.payroll.run.PayrollRunRepository;
import com.zuhoocms.modules.hrm.payroll.run.PayrollRunTotals;
import com.zuhoocms.enums.PayrollStatus;
import com.zuhoocms.enums.PaymentMethod;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import lombok.RequiredArgsConstructor;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import lombok.extern.slf4j.Slf4j;

@Slf4j
@Service
@RequiredArgsConstructor
public class PayrollServiceImpl implements PayrollService {

    private final PayrollRepository payrollRepository;
    private final EmployeeRepository employeeRepository;
    private final SecurityUtil securityUtil;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final com.zuhoocms.shared.notification.NotificationService notificationService;
    private final GeneralLedgerService glService;
    private final DefaultAccountResolver accountResolver;
    private final PayslipPdfService payslipPdfService;
    private final com.zuhoocms.auth.role.service.AuthorizationService authorizationService;
    private final LoanAdvanceRepository loanAdvanceRepository;
    private final LoanRepaymentRepository loanRepaymentRepository;
    private final PayrollCalculator calculator;
    private final PayrollRunRepository runRepository;
    private final PayrollRunTotals runTotals;
    private final PlatformTransactionManager transactionManager;

    @Override
    @Transactional
    public PayrollResponse create(CreatePayrollRequest request) {
        Long companyId = requireCompanyId();
        PayrollPeriods.validate(request.getPayMonth(), request.getPayYear());
        int month = request.getPayMonth();
        int year = request.getPayYear();

        if (payrollRepository.findByEmployeeIdAndPayMonthAndPayYear(request.getEmployeeId(), month, year).isPresent()) {
            throw new BadRequestException("Payroll already exists for this employee and period");
        }

        Employee employee = employeeRepository.findByIdAndCompanyId(request.getEmployeeId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Employee not found: " + request.getEmployeeId()));

        PayrollRun run = openRunForNewLines(companyId, month, year);

        Payroll payroll = obtainLine(employee, companyId, month, year);
        PayrollCalculator.Result result = calculator.calculate(employee, companyId, month, year,
                PayrollCalculator.ManualInputs.from(request), payroll.getId(), true);
        calculator.apply(result, payroll);
        payroll.setNotes(request.getNotes());
        payroll.setRun(run);
        payroll = payrollRepository.save(payroll);

        if (run != null) {
            runTotals.refreshAndSave(run);
        }
        return PayrollMapper.toPayrollResponse(payroll);
    }

    @Override
    @Transactional
    public BulkPayrollResult generateForAllEmployees(int month, int year) {
        PayrollPeriods.validate(month, year);
        Long companyId = requireCompanyId();
        List<Employee> employees = employeeRepository.findByCompanyIdAndActiveTrue(companyId);

        List<String> created = new ArrayList<>();
        List<String> skippedAlreadyExists = new ArrayList<>();
        List<String> skippedNoStructure = new ArrayList<>();
        PayrollRun run = null;
        boolean runChecked = false;

        for (Employee employee : employees) {
            String name = PayrollCalculator.displayName(employee);

            if (payrollRepository.findByEmployeeIdAndPayMonthAndPayYear(employee.getId(), month, year).isPresent()) {
                skippedAlreadyExists.add(name);
                continue;
            }
            if (calculator.activeStructure(employee.getId(), month, year).isEmpty()) {
                skippedNoStructure.add(name);
                continue;
            }
            if (!runChecked) {
                // Only matters once a line is actually about to be added.
                run = openRunForNewLines(companyId, month, year);
                runChecked = true;
            }

            Payroll line = obtainLine(employee, companyId, month, year);
            PayrollCalculator.Result result = calculator.calculate(employee, companyId, month, year,
                    PayrollCalculator.ManualInputs.none(), line.getId(), true);
            calculator.apply(result, line);
            line.setRun(run);
            payrollRepository.save(line);
            created.add(name);
        }

        if (run != null && !created.isEmpty()) {
            runTotals.refreshAndSave(run);
        }

        return BulkPayrollResult.builder()
                .created(created)
                .skippedAlreadyExists(skippedAlreadyExists)
                .skippedNoSalaryStructure(skippedNoStructure)
                .build();
    }

    @Override
    @Transactional
    public void recalculateDraftLines(Long runId) {
        Long companyId = requireCompanyId();
        for (Payroll p : payrollRepository.findByRunId(runId)) {
            if (p.getStatus() != PayrollStatus.DRAFT) continue;
            if (p.getCompany() == null || !companyId.equals(p.getCompany().getId())) continue;
            Employee employee = p.getEmployee();
            boolean hasStructure = calculator.activeStructure(employee.getId(), p.getPayMonth(), p.getPayYear()).isPresent();
            // With a structure the fixed components, tax and PF come fresh from it; without one the line's own figures are the only source.
            // Bonus, manual deductions and insurance are never part of a structure, so they carry over either way.
            PayrollCalculator.ManualInputs manual = new PayrollCalculator.ManualInputs(
                    hasStructure ? null : p.getBasicSalary(),
                    hasStructure ? null : p.getHouseRent(),
                    hasStructure ? null : p.getMedicalAllowance(),
                    hasStructure ? null : p.getTransportAllowance(),
                    hasStructure ? null : p.getFoodAllowance(),
                    hasStructure ? null : p.getSpecialAllowance(),
                    p.getBonus(), p.getDeductions(),
                    hasStructure ? null : p.getTaxDeduction(),
                    p.getInsuranceDeduction(),
                    hasStructure ? null : p.getProvidentFundDeduction());
            PayrollCalculator.Result result = calculator.calculate(employee, companyId,
                    p.getPayMonth(), p.getPayYear(), manual, p.getId(), true);
            calculator.apply(result, p);
            payrollRepository.save(p);
        }
    }

    /** The period's run when lines may still attach (DRAFT/CALCULATED/REJECTED), null when none is live, 400 once submitted/approved/paid - the line set is frozen. */
    private PayrollRun openRunForNewLines(Long companyId, int month, int year) {
        PayrollRun run = runRepository.findByCompanyIdAndPayMonthAndPayYear(companyId, month, year).orElse(null);
        if (run == null) return null;
        return switch (run.getStatus()) {
            case DRAFT, CALCULATED, REJECTED -> run;
            case CANCELLED -> null;
            case PENDING_APPROVAL, APPROVED, PAID -> throw new BadRequestException(
                    "Payroll run " + run.getRunNumber() + " for " + month + "/" + year + " is " + run.getStatus()
                            + " - payroll lines can no longer be added to this period");
        };
    }

    /** A new unsaved line, or a soft-deleted row for the same employee+period revived and reset to blank DRAFT - it still holds the unique key. */
    private Payroll obtainLine(Employee employee, Long companyId, int month, int year) {
        Optional<Long> deletedId = payrollRepository.findSoftDeletedId(employee.getId(), month, year);
        if (deletedId.isEmpty()) {
            return Payroll.builder()
                    .employee(employee)
                    .company(companyRef(companyId))
                    .payMonth(month)
                    .payYear(year)
                    .status(PayrollStatus.DRAFT)
                    .build();
        }
        Long id = deletedId.get();
        payrollRepository.reviveById(id);
        Payroll p = payrollRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Payroll not found: " + id));
        p.setDeleted(false);
        p.setDeletedAt(null);
        p.setEmployee(employee);
        p.setStatus(PayrollStatus.DRAFT);
        p.setRun(null);
        p.setApprovedBy(null);
        p.setPaymentReference(null);
        p.setPaymentMethod(null);
        p.setPaidAt(null);
        p.setGlDebitAccount(null);
        p.setGlCreditAccount(null);
        p.setNotes(null);
        p.setLoanAdvance(null);
        p.setLoanDeductionAmount(BigDecimal.ZERO);
        return p;
    }

    /**
     * Bank disbursement file for a pay period; does NOT move money - finance uploads it to the bank portal (BEFTN/RTGS) and marks rows paid afterwards.
     * APPROVED rows only: exporting DRAFT or PAID invites an unapproved amount or a double payment.
     * Employees with no bank account still appear with a flagged note, so nobody silently goes unpaid.
     */
    @Override
    @Transactional(readOnly = true)
    public String buildDisbursementCsv(int month, int year) {
        PayrollPeriods.validate(month, year);
        // Permission is checked in PayrollController, as elsewhere in this module.
        Long companyId = requireCompanyId();

        List<Payroll> rows = payrollRepository
            .findForDisbursement(companyId, month, year, PayrollStatus.APPROVED);

        StringBuilder csv = new StringBuilder();
        csv.append("Employee ID,Employee Name,Bank Name,Account Number,Routing Number,Net Salary,Currency,Reference,Note\n");

        String period = String.format("%04d-%02d", year, month);
        for (Payroll p : rows) {
            Employee e = p.getEmployee();
            String name = e != null && e.getUser() != null ? e.getUser().getFullName() : "";
            String account = e != null ? nullToEmpty(e.getBankAccountNumber()) : "";
            String note = account.isBlank() ? "MISSING BANK ACCOUNT - cannot transfer" : "";

            csv.append(csvCell(e != null ? e.getEmployeeNumber() : "")).append(',')
               .append(csvCell(name)).append(',')
               .append(csvCell(e != null ? e.getBankName() : "")).append(',')
               .append(csvCell(account)).append(',')
               .append(csvCell(e != null ? e.getBankRoutingNumber() : "")).append(',')
               .append(p.getNetSalary() != null ? p.getNetSalary().toPlainString() : "0.00").append(',')
               .append("BDT,")
               .append(csvCell("SALARY-" + period)).append(',')
               .append(csvCell(note)).append('\n');
        }

        return csv.toString();
    }

    private String nullToEmpty(String s) {
        return s == null ? "" : s;
    }

    /** Quotes a CSV cell; a leading =, +, - or @ is escaped with a quote so a name like "=cmd" is not run as a formula (CSV injection). */
    private String csvCell(String raw) {
        String v = nullToEmpty(raw);
        if (!v.isEmpty() && "=+-@".indexOf(v.charAt(0)) >= 0) {
            v = "'" + v;
        }
        if (v.contains(",") || v.contains("\"") || v.contains("\n")) {
            return '"' + v.replace("\"", "\"\"") + '"';
        }
        return v;
    }

    /** PaymentMethod is shared app-wide, so it lists collection rails: SSLCOMMERZ has no payout API and WALLET no per-employee counterparty. */
    private void guardPayoutMethod(PaymentMethod method) {
        if (method == PaymentMethod.SSLCOMMERZ || method == PaymentMethod.WALLET) {
            throw new BadRequestException(
                method.name() + " cannot be used to pay salary - it is a collection method, not a payout. "
                    + "Use BANK_TRANSFER, BKASH, NAGAD, ROCKET, CHEQUE or CASH.");
        }
    }

    @Override
    @Transactional(readOnly = true)
    public PayrollResponse getById(Long id) {
        return PayrollMapper.toPayrollResponse(findInTenant(id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PayrollResponse> listByPeriod(int month, int year, Pageable pageable) {
        PayrollPeriods.validate(month, year);
        return payrollRepository.findByCompanyIdAndPayMonthAndPayYear(
                requireCompanyId(), month, year, pageable)
                .map(PayrollMapper::toPayrollResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<PayrollResponse> listForEmployee(Long employeeId, Pageable pageable) {
        return payrollRepository.findByCompanyIdAndEmployeeId(requireCompanyId(), employeeId, pageable)
                .map(PayrollMapper::toPayrollResponse);
    }

    @Override
    @Transactional
    public PayrollResponse approve(Long id) {
        Payroll p = findInTenant(id);
        rejectIfInRun(p);
        return doApprove(p);
    }

    @Override
    @Transactional
    public PayrollResponse approveForRun(Long id, Long runId) {
        Payroll p = findInTenant(id);
        requireInRun(p, runId);
        return doApprove(p);
    }

    private PayrollResponse doApprove(Payroll p) {
        if (p.getStatus() != PayrollStatus.DRAFT) {
            throw new BadRequestException("Only DRAFT payrolls can be approved");
        }
        // Scoped: approvedBy is persisted on this tenant's payroll row, so the approver must be provably in it.
        // p comes from findInTenant, so its company is the active one.
        Employee approver = employeeRepository.findByUserIdAndCompanyId(
                        securityUtil.getCurrentUser().getId(), requireCompanyId())
                .orElseThrow(() -> new BadRequestException("Employee profile not found"));
        p.setStatus(PayrollStatus.APPROVED);
        p.setApprovedBy(approver);
        payrollRepository.save(p);
        return PayrollMapper.toPayrollResponse(p);
    }

    private void rejectIfInRun(Payroll p) {
        if (p.getRun() != null) {
            throw new BadRequestException("This payroll belongs to payroll run " + p.getRun().getRunNumber()
                    + " - approve and pay it through the run");
        }
    }

    private void requireInRun(Payroll p, Long runId) {
        if (p.getRun() == null || !p.getRun().getId().equals(runId)) {
            throw new BadRequestException("Payroll " + p.getId() + " does not belong to this payroll run");
        }
    }

    /** What the employee is told once a payment has committed - captured inside the transaction. */
    private record PaidNotice(String email, String firstName, Long userId, Long companyId, EmailBranding.Data branding) {}

    private record PayOutcome(PayrollResponse response, PaidNotice notice) {}

    @Override
    public PayrollResponse markPaid(Long id, String paymentReference, PaymentMethod paymentMethod) {
        return payInOwnTransaction(id, null, paymentReference, paymentMethod, LocalDate.now());
    }

    @Override
    public PayrollResponse payForRun(Long id, Long runId, String paymentReference, PaymentMethod paymentMethod,
                                     LocalDate paidAt) {
        return payInOwnTransaction(id, runId, paymentReference, paymentMethod,
                paidAt != null ? paidAt : LocalDate.now());
    }

    /** Pays in a REQUIRES_NEW transaction, notifying only after commit, so nobody is told about a payment that later rolled back. */
    private PayrollResponse payInOwnTransaction(Long id, Long runId, String paymentReference,
                                                PaymentMethod paymentMethod, LocalDate paidAt) {
        guardPayoutMethod(paymentMethod);
        TransactionTemplate tx = new TransactionTemplate(transactionManager);
        tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        PayOutcome outcome = tx.execute(status -> doPay(id, runId, paymentReference, paymentMethod, paidAt));
        if (outcome == null) {
            throw new BadRequestException("Payment could not be recorded");
        }
        sendPaidNotice(outcome.notice());
        return outcome.response();
    }

    private PayOutcome doPay(Long id, Long runId, String paymentReference, PaymentMethod paymentMethod,
                             LocalDate paidAt) {
        Long companyId = requireCompanyId();
        // Row lock: a second concurrent pay waits here, then sees PAID below.
        Payroll p = payrollRepository.findByIdAndCompanyIdForUpdate(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Payroll not found: " + id));
        if (runId == null) {
            rejectIfInRun(p);
        } else {
            requireInRun(p, runId);
        }
        if (p.getStatus() == PayrollStatus.PAID) {
            throw new BadRequestException("Payroll is already paid");
        }
        if (p.getStatus() != PayrollStatus.APPROVED) {
            throw new BadRequestException("Only APPROVED payrolls can be marked as paid");
        }
        p.setStatus(PayrollStatus.PAID);
        p.setPaymentReference(paymentReference);
        p.setPaymentMethod(paymentMethod);
        p.setPaidAt(paidAt);

        // Settle first: a loan closed/cancelled since pricing releases the unrecoverable part back into net pay before the ledger entry is built.
        settleLoanInstallment(p);
        postPayrollToLedger(p, paidAt);
        payrollRepository.save(p);

        return new PayOutcome(PayrollMapper.toPayrollResponse(p), buildNotice(p));
    }

    private PaidNotice buildNotice(Payroll p) {
        Employee e = p.getEmployee();
        if (e == null || e.getUser() == null) return null;
        EmailBranding.Data branding = null;
        try {
            branding = emailBranding.from(p.getCompany());
        } catch (Exception ex) {
            log.warn("Could not resolve email branding for payroll {}: {}", p.getId(), ex.getMessage());
        }
        return new PaidNotice(e.getUser().getEmail(), e.getUser().getFirstName(), e.getUser().getId(),
                p.getCompany().getId(), branding);
    }

    private void sendPaidNotice(PaidNotice n) {
        if (n == null) return;
        if (n.branding() != null) {
            try {
                emailService.sendPayrollEmail(n.email(), n.firstName(), n.branding());
            } catch (Exception ex) {
                log.warn("Payroll email failed for employee {}: {}", n.email(), ex.getMessage());
            }
        }
        // Independent of the email: the notification-center record must land even when SMTP fails.
        try {
            notificationService.send(com.zuhoocms.shared.notification.CreateNotificationRequest.of(
                    com.zuhoocms.enums.NotificationType.PAYSLIP_READY,
                    "Payslip ready",
                    "Your payslip for this pay period has been processed and is ready to view.",
                    "/payroll/my-payslips",
                    n.userId(),
                    n.companyId()));
        } catch (Exception ex) {
            log.warn("Payslip notification failed for user {}: {}", n.userId(), ex.getMessage());
        }
    }

    /** Dr Salaries and Wages (gross) / Cr Cash (net) / Cr Payroll Payable (tax, deductions, loan installment), dated with the actual payment date. */
    private void postPayrollToLedger(Payroll p, LocalDate transactionDate) {
        Long companyId = p.getCompany().getId();
        BigDecimal gross = orZero(p.getBasicSalary()).add(orZero(p.getHouseRent())).add(orZero(p.getMedicalAllowance()))
                .add(orZero(p.getTransportAllowance())).add(orZero(p.getFoodAllowance())).add(orZero(p.getSpecialAllowance()))
                .add(orZero(p.getBonus()))
                .add(orZero(p.getBillablePay()))
                .add(orZero(p.getOvertimePay()))
                .add(orZero(p.getOtherEarnings()))
                .subtract(orZero(p.getAttendanceDeduction()));
        BigDecimal withheld = orZero(p.getDeductions()).add(orZero(p.getTaxDeduction()))
                .add(orZero(p.getInsuranceDeduction())).add(orZero(p.getProvidentFundDeduction()))
                .add(orZero(p.getOtherDeductions())).add(orZero(p.getLoanDeductionAmount()));
        String description = "Payroll " + p.getPayMonth() + "/" + p.getPayYear()
                + " for " + ledgerName(p.getEmployee());

        ChartOfAccount salaryExpense = accountResolver.salaryExpense(companyId);
        ChartOfAccount cash = accountResolver.cash(companyId);

        List<LedgerLine> lines = new ArrayList<>();
        lines.add(LedgerLine.debit(salaryExpense.getId(), gross));
        lines.add(LedgerLine.credit(cash.getId(), p.getNetSalary()));
        if (withheld.compareTo(BigDecimal.ZERO) > 0) {
            ChartOfAccount payable = accountResolver.payrollPayable(companyId);
            lines.add(LedgerLine.credit(payable.getId(), withheld));
        }
        glService.recordBalancedTransaction(companyId, lines, description,
                GlReferenceType.PAYROLL, p.getId(), p.getPaymentReference(),
                transactionDate != null ? transactionDate : LocalDate.now());

        p.setGlDebitAccount(salaryExpense.getAccountCode());
        p.setGlCreditAccount(cash.getAccountCode());
    }

    private String ledgerName(Employee e) {
        if (e == null) return "employee";
        if (e.getUser() != null && e.getUser().getFullName() != null) return e.getUser().getFullName();
        if (e.getEmployeeNumber() != null) return e.getEmployeeNumber();
        return "employee #" + e.getId();
    }

    /** Recovers the installment against the row-locked loan and logs a LoanRepayment; a non-ACTIVE loan is untouched and the unrecovered part goes back into net pay. */
    private void settleLoanInstallment(Payroll p) {
        LoanAdvance ref = p.getLoanAdvance();
        BigDecimal due = orZero(p.getLoanDeductionAmount());
        if (ref == null || due.signum() <= 0) {
            return;
        }
        LoanAdvance loan = loanAdvanceRepository.findByIdForUpdate(ref.getId()).orElse(null);
        BigDecimal applied = BigDecimal.ZERO;
        if (loan != null && loan.getStatus() == LoanAdvance.Status.ACTIVE) {
            applied = due.min(orZero(loan.getRemainingBalance())).max(BigDecimal.ZERO);
        }

        if (applied.compareTo(due) < 0) {
            p.setNetSalary(orZero(p.getNetSalary()).add(due.subtract(applied)));
            p.setLoanDeductionAmount(applied);
            if (applied.signum() == 0) {
                p.setLoanAdvance(null);
            }
        }
        if (applied.signum() <= 0) {
            return;
        }

        BigDecimal newBalance = loan.getRemainingBalance().subtract(applied).max(BigDecimal.ZERO);
        loan.setRemainingBalance(newBalance);
        if (newBalance.signum() == 0) {
            loan.setStatus(LoanAdvance.Status.CLOSED);
        }
        loanAdvanceRepository.save(loan);

        loanRepaymentRepository.save(LoanRepayment.builder()
                .loan(loan)
                .payroll(p)
                .amount(applied)
                .paidDate(p.getPaidAt())
                .balanceAfter(newBalance)
                .build());
    }

    @Override
    @Transactional
    public void delete(Long id) {
        Payroll p = findInTenant(id);
        if (p.getStatus() == PayrollStatus.PAID) {
            throw new BadRequestException("Cannot delete a paid payroll");
        }
        // Lines lock once the run is submitted for approval (or further along).
        PayrollRun run = p.getRun();
        if (run != null) {
            PayrollRun.RunStatus rs = run.getStatus();
            if (rs == PayrollRun.RunStatus.PENDING_APPROVAL
                    || rs == PayrollRun.RunStatus.APPROVED
                    || rs == PayrollRun.RunStatus.PAID) {
                throw new BadRequestException("This payroll belongs to a " + rs + " run and is locked");
            }
        }
        p.softDelete();
        payrollRepository.save(p);
        if (run != null) {
            runTotals.refreshAndSave(run);
        }
    }

    @Override
    @Transactional(readOnly = true)
    public PayslipDocument generatePayslipPdf(Long id) {
        Payroll payroll = findInTenant(id);

        // PAYROLL_VIEW sees anyone's payslip, everyone else only their own; enforced here so no other caller can reach the PDF unchecked.
        if (!authorizationService.hasPermission(
                com.zuhoocms.auth.role.enums.PermissionCode.PAYROLL_VIEW)) {
            var currentUser = securityUtil.getCurrentUser();
            Employee mine = currentUser != null
                    ? employeeRepository.findByUserId(currentUser.getId()).orElse(null)
                    : null;
            Long ownerId = payroll.getEmployee() != null ? payroll.getEmployee().getId() : null;
            if (mine == null || ownerId == null || !mine.getId().equals(ownerId)) {
                throw new com.zuhoocms.shared.exception.ForbiddenException(
                        "Access denied: you can only download your own payslip");
            }
        }

        // A DRAFT is unapproved: its figures can still change, so it must not be handed out as a payslip.
        if (payroll.getStatus() == PayrollStatus.DRAFT
                && !authorizationService.hasPermission(
                        com.zuhoocms.auth.role.enums.PermissionCode.PAYROLL_VIEW)) {
            throw new BadRequestException("This payslip is not available yet - it has not been approved.");
        }

        Company company = payroll.getCompany();
        EmailBranding.Data branding = emailBranding.from(company);
        byte[] pdf = payslipPdfService.generate(payroll, company, branding);
        return new PayslipDocument(pdf, payslipPdfService.fileName(payroll));
    }

    private Payroll findInTenant(Long id) {
        return payrollRepository.findByIdAndCompanyId(id, requireCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Payroll not found: " + id));
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null)
            throw new BadRequestException("No company context");
        return id;
    }

    private Company companyRef(Long companyId) {
        Company c = new Company();
        c.setId(companyId);
        return c;
    }

    private BigDecimal orZero(BigDecimal v) {
        return v != null ? v : BigDecimal.ZERO;
    }
}
