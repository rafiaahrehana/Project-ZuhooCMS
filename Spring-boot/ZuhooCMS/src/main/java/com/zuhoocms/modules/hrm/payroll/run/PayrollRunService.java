package com.zuhoocms.modules.hrm.payroll.run;

import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.enums.PayrollStatus;
import com.zuhoocms.enums.PaymentMethod;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.hrm.payroll.Payroll;
import com.zuhoocms.modules.hrm.payroll.PayrollCalculator;
import com.zuhoocms.modules.hrm.payroll.PayrollPeriods;
import com.zuhoocms.modules.hrm.payroll.PayrollRepository;
import com.zuhoocms.modules.hrm.payroll.PayrollService;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static com.zuhoocms.modules.hrm.payroll.run.PayrollRun.RunStatus.*;

/**
 * The payroll batch workflow: create generates/adopts the period's lines, recalculate recomputes DRAFTs, then submit -> approve -> pay. Lines lock from PENDING_APPROVAL on.
 * Paying the run pays each line in its own transaction so one failure cannot roll back money already recorded for everyone else.
 */
@Service
@RequiredArgsConstructor
public class PayrollRunService {

    private final PayrollRunRepository runRepository;
    private final PayrollRepository payrollRepository;
    private final PayrollService payrollService;
    private final PayrollRunTotals runTotals;
    private final CompanyRepository companyRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final PlatformTransactionManager transactionManager;

    public List<PayrollRun> list() {
        authorizationService.checkPermission(PermissionCode.PAYROLL_VIEW);
        return runRepository.findByCompanyIdOrderByPayYearDescPayMonthDesc(securityUtil.getCurrentCompanyId());
    }

    public PayrollRun getForPeriod(int month, int year) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_VIEW);
        PayrollPeriods.validate(month, year);
        return runRepository.findByCompanyIdAndPayMonthAndPayYear(securityUtil.getCurrentCompanyId(), month, year)
                .orElse(null);
    }

    /** Creates the period's run; an earlier cancelled run is revived and reset because, soft-deleted, it still holds the (company, month, year) unique key. */
    @Transactional
    public PayrollRun create(int month, int year, String remarks) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_PROCESS);
        PayrollPeriods.validate(month, year);
        Long companyId = securityUtil.getCurrentCompanyId();
        runRepository.findByCompanyIdAndPayMonthAndPayYear(companyId, month, year).ifPresent(r -> {
            throw new BadRequestException("A payroll run for " + month + "/" + year + " already exists (" + r.getRunNumber() + ")");
        });

        // Generate rows for everyone who has a structure and no payroll yet.
        payrollService.generateForAllEmployees(month, year);

        PayrollRun run = runRepository.findSoftDeletedIdForPeriod(companyId, month, year)
                .map(deletedId -> {
                    runRepository.reviveById(deletedId);
                    PayrollRun revived = runRepository.findById(deletedId)
                            .orElseThrow(() -> new ResourceNotFoundException("Payroll run not found"));
                    revived.setDeleted(false);
                    revived.setDeletedAt(null);
                    return revived;
                })
                .orElseGet(() -> PayrollRun.builder().company(companyRepository.getReferenceById(companyId)).build());

        YearMonth ym = YearMonth.of(year, month);
        run.setRunNumber(nextRunNumber(companyId, year, month));
        run.setPayMonth(month);
        run.setPayYear(year);
        run.setPayPeriodStart(ym.atDay(1));
        run.setPayPeriodEnd(ym.atEndOfMonth());
        run.setPaymentDate(null);
        run.setRemarks(remarks);
        run.setRejectionReason(null);
        run.setCreatedById(securityUtil.getCurrentUser() != null ? securityUtil.getCurrentUser().getId() : null);
        run.setApprovedById(null);
        run.setApprovedAt(null);
        run.setTotalEmployees(0);
        run.setTotalGross(BigDecimal.ZERO);
        run.setTotalDeduction(BigDecimal.ZERO);
        run.setTotalNet(BigDecimal.ZERO);
        run.setStatus(DRAFT);
        run = runRepository.save(run);

        adoptUnassignedLines(run, companyId);
        runTotals.refresh(run);
        run.setStatus(CALCULATED);
        return runRepository.save(run);
    }

    /** Recomputes DRAFT lines from fresh inputs, generates missing ones, adopts strays and refreshes totals; rejected once submitted, as lines lock from PENDING_APPROVAL on. */
    @Transactional
    public PayrollRun recalculate(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_PROCESS);
        PayrollRun run = owned(id);
        requireStatus(run, "recalculate", DRAFT, CALCULATED, REJECTED);
        payrollService.recalculateDraftLines(run.getId());
        payrollService.generateForAllEmployees(run.getPayMonth(), run.getPayYear());
        adoptUnassignedLines(run, run.getCompany().getId());
        runTotals.refresh(run);
        if (run.getStatus() == DRAFT || run.getStatus() == REJECTED) run.setStatus(CALCULATED);
        return runRepository.save(run);
    }

    @Transactional
    public PayrollRun submit(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_PROCESS);
        PayrollRun run = owned(id);
        requireStatus(run, "submit", DRAFT, CALCULATED, REJECTED);
        if (payrollRepository.findByRunId(run.getId()).isEmpty())
            throw new BadRequestException("Run has no payroll lines - recalculate first");
        runTotals.refresh(run);
        run.setStatus(PENDING_APPROVAL);
        run.setRejectionReason(null);
        return runRepository.save(run);
    }

    /** Approves the run and every DRAFT line in it. Only a submitted run can be approved. */
    @Transactional
    public PayrollRun approve(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_APPROVE);
        PayrollRun run = owned(id);
        requireStatus(run, "approve", PENDING_APPROVAL);
        for (Payroll p : payrollRepository.findByRunId(run.getId())) {
            if (p.getStatus() == PayrollStatus.DRAFT) payrollService.approveForRun(p.getId(), run.getId());
        }
        runTotals.refresh(run);
        run.setStatus(APPROVED);
        run.setApprovedById(securityUtil.getCurrentUser() != null ? securityUtil.getCurrentUser().getId() : null);
        run.setApprovedAt(LocalDateTime.now());
        return runRepository.save(run);
    }

    @Transactional
    public PayrollRun reject(Long id, String reason) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_APPROVE);
        PayrollRun run = owned(id);
        requireStatus(run, "reject", PENDING_APPROVAL);
        run.setStatus(REJECTED);
        run.setRejectionReason(reason);
        return runRepository.save(run);
    }

    /** Cancels the run and frees the period: DRAFT lines soft-deleted (a later create revives them), approved/paid lines detached, run soft-deleted so the month can be re-run. */
    @Transactional
    public PayrollRun cancel(Long id) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_PROCESS);
        PayrollRun run = owned(id);
        requireStatus(run, "cancel", DRAFT, CALCULATED, PENDING_APPROVAL, REJECTED);
        for (Payroll p : payrollRepository.findByRunId(run.getId())) {
            if (p.getStatus() == PayrollStatus.DRAFT) {
                p.softDelete();
            } else {
                p.setRun(null);
            }
            payrollRepository.save(p);
        }
        run.setTotalEmployees(0);
        run.setTotalGross(BigDecimal.ZERO);
        run.setTotalDeduction(BigDecimal.ZERO);
        run.setTotalNet(BigDecimal.ZERO);
        run.setStatus(CANCELLED);
        run.softDelete();
        return runRepository.save(run);
    }

    /** Pays every unpaid line in its own transaction (see PayrollService.payForRun); deliberately not @Transactional, so partial success leaves the run APPROVED and repayable. */
    public PayrollRun pay(Long id, PaymentMethod method, String referencePrefix, LocalDate paymentDate) {
        authorizationService.checkPermission(PermissionCode.PAYROLL_APPROVE);
        TransactionTemplate readTx = new TransactionTemplate(transactionManager);
        readTx.setReadOnly(true);

        record Line(Long id, String name, PayrollStatus status) {}
        record Snapshot(Long runId, String runNumber, List<Line> lines) {}

        Snapshot snap = readTx.execute(status -> {
            PayrollRun run = owned(id);
            requireStatus(run, "pay", APPROVED);
            List<Line> lines = payrollRepository.findByRunId(run.getId()).stream()
                    .sorted(Comparator.comparing(Payroll::getId))
                    .map(p -> new Line(p.getId(), PayrollCalculator.displayName(p.getEmployee()), p.getStatus()))
                    .toList();
            return new Snapshot(run.getId(), run.getRunNumber(), lines);
        });

        LocalDate payDate = paymentDate != null ? paymentDate : LocalDate.now();
        String prefix = referencePrefix == null || referencePrefix.isBlank() ? snap.runNumber() : referencePrefix;
        List<String> failed = new ArrayList<>();
        for (int i = 0; i < snap.lines().size(); i++) {
            Line line = snap.lines().get(i);
            if (line.status() == PayrollStatus.PAID || line.status() == PayrollStatus.CANCELLED) continue;
            String ref = prefix + "-" + String.format("%03d", i + 1);
            try {
                payrollService.payForRun(line.id(), snap.runId(), ref, method, payDate);
            } catch (RuntimeException ex) {
                failed.add(line.name() + " (" + ex.getMessage() + ")");
            }
        }

        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        PayrollRun result = writeTx.execute(status -> {
            PayrollRun run = owned(id);
            runTotals.refresh(run);
            if (failed.isEmpty()) {
                run.setPaymentDate(payDate);
                run.setStatus(PAID);
            }
            return runRepository.save(run);
        });
        if (!failed.isEmpty()) {
            throw new BadRequestException("Payroll run was not fully paid - it stays APPROVED. Failed for: "
                    + String.join(", ", failed));
        }
        return result;
    }

    private void adoptUnassignedLines(PayrollRun run, Long companyId) {
        for (Payroll p : payrollRepository.findAllByCompanyIdAndPayMonthAndPayYear(
                companyId, run.getPayMonth(), run.getPayYear())) {
            if (p.getRun() == null) {
                p.setRun(run);
                payrollRepository.save(p);
            }
        }
    }

    /** "PR-" + yyyyMM + "-" + (highest sequence ever used + 1); counting rows repeated numbers after deletes, so the max includes deleted rows. (company_id, run_number) is unique in the DB. */
    private String nextRunNumber(Long companyId, int year, int month) {
        int max = 0;
        for (String rn : runRepository.findAllRunNumbersIncludingDeleted(companyId)) {
            if (rn == null) continue;
            int dash = rn.lastIndexOf('-');
            if (dash < 0 || dash == rn.length() - 1) continue;
            try {
                max = Math.max(max, Integer.parseInt(rn.substring(dash + 1)));
            } catch (NumberFormatException ignored) {
                // not one of ours
            }
        }
        String prefix = "PR-" + year + String.format("%02d", month) + "-";
        int seq = max + 1;
        for (int attempt = 0; attempt < 100; attempt++, seq++) {
            String candidate = prefix + seq;
            if (runRepository.countRunNumberIncludingDeleted(companyId, candidate) == 0) {
                return candidate;
            }
        }
        throw new BadRequestException("Could not allocate a payroll run number - please try again");
    }

    private PayrollRun owned(Long id) {
        PayrollRun run = runRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Payroll run not found"));
        if (!run.getCompany().getId().equals(securityUtil.getCurrentCompanyId()))
            throw new ResourceNotFoundException("Payroll run not found");
        return run;
    }

    private void requireStatus(PayrollRun run, String action, PayrollRun.RunStatus... allowed) {
        for (PayrollRun.RunStatus s : allowed) if (run.getStatus() == s) return;
        throw new BadRequestException("Cannot " + action + " a " + run.getStatus() + " payroll run");
    }
}
