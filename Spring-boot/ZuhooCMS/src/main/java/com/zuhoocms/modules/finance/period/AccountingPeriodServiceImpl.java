package com.zuhoocms.modules.finance.period;

import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.finance.chartofaccounts.AccountType;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccountRepository;
import com.zuhoocms.modules.finance.chartofaccounts.DefaultAccountResolver;
import com.zuhoocms.modules.finance.generalledger.GeneralLedger;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerRepository;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AccountingPeriodServiceImpl implements AccountingPeriodService {

    /** Sanity bounds for any fiscal year accepted from a request - see requireSaneFiscalYear(). */
    private static final int MIN_FISCAL_YEAR = 2000;
    private static final int MAX_FISCAL_YEAR = 2100;

    /** Namespace salt for the per-company year-end-close advisory lock - see yearEndCloseLockKey(). */
    private static final long YEAR_END_CLOSE_LOCK_SALT = 0x5945_4143L; // "YEAC"

    private final AccountingPeriodRepository periodRepository;
    private final CompanyRepository companyRepository;
    private final ChartOfAccountRepository coaRepository;
    private final GeneralLedgerRepository glRepository;
    private final GeneralLedgerService glService;
    private final DefaultAccountResolver accountResolver;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final PeriodLockChecker periodLockChecker;

    @Override
    @Transactional
    public List<AccountingPeriodResponse> listForYear(int fiscalYear) {
        authorizationService.checkPermission(PermissionCode.ACCOUNTING_PERIOD_VIEW);
        requireSaneFiscalYear(fiscalYear);
        Long companyId = requireCompanyId();
        List<AccountingPeriod> periods = ensureYearExists(companyId, fiscalYear);
        return periods.stream().map(AccountingPeriodMapper::toResponse).collect(Collectors.toList());
    }

    /** Generates missing monthly periods from fiscalYearStartMonth; convention is start-year: FY Y period 1 starts (fiscalYearStartMonth, Y), so a July-start FY2026 is Jul 2026 - Jun 2027. */
    private List<AccountingPeriod> ensureYearExists(Long companyId, int fiscalYear) {
        List<AccountingPeriod> existing = periodRepository.findByCompanyIdAndFiscalYearOrderByPeriodNumberAsc(companyId, fiscalYear);
        Map<Integer, AccountingPeriod> byNumber = new HashMap<>();
        existing.forEach(p -> byNumber.put(p.getPeriodNumber(), p));
        if (byNumber.size() == 12) return existing;

        Company company = companyRepository.findById(companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
        int startMonth = company.getFiscalYearStartMonth() != null ? company.getFiscalYearStartMonth() : 1;

        // Compare actual dates, not year numbers, and refuse before writing: after fiscalYearStartMonth changes, a regenerated year's months can fall inside a stored year's periods.
        LocalDate yearStart = LocalDate.of(fiscalYear, startMonth, 1);
        LocalDate yearEnd = yearStart.plusMonths(12).minusDays(1);
        List<AccountingPeriod> clashes = periodRepository.findOverlappingOtherYears(companyId, fiscalYear, yearStart, yearEnd);
        if (!clashes.isEmpty()) {
            AccountingPeriod first = clashes.get(0);
            throw new BadRequestException("Fiscal year " + fiscalYear + " (" + yearStart + " to " + yearEnd
                    + ") overlaps periods already generated for fiscal year " + first.getFiscalYear()
                    + " (period " + first.getPeriodNumber() + ": " + first.getStartDate() + " to " + first.getEndDate()
                    + "). The fiscal year start month appears to have changed - delete the conflicting periods first.");
        }

        List<AccountingPeriod> result = new ArrayList<>();
        LocalDate cursor = yearStart;
        for (int i = 1; i <= 12; i++) {
            AccountingPeriod period = byNumber.get(i);
            if (period == null) {
                LocalDate end = cursor.plusMonths(1).minusDays(1);
                period = periodRepository.save(AccountingPeriod.builder()
                        .companyId(companyId)
                        .fiscalYear(fiscalYear)
                        .periodNumber(i)
                        .startDate(cursor)
                        .endDate(end)
                        .status(PeriodStatus.OPEN)
                        .build());
            }
            result.add(period);
            cursor = cursor.plusMonths(1);
        }
        return result;
    }

    @Override
    @Transactional(readOnly = true)
    public List<FiscalYearSummary> listFiscalYears() {
        authorizationService.checkPermission(PermissionCode.ACCOUNTING_PERIOD_VIEW);
        Long companyId = requireCompanyId();
        LocalDate today = LocalDate.now();

        Map<Integer, List<AccountingPeriod>> byYear = periodRepository
                .findByCompanyIdOrderByFiscalYearAscPeriodNumberAsc(companyId)
                .stream()
                .collect(Collectors.groupingBy(AccountingPeriod::getFiscalYear,
                        java.util.LinkedHashMap::new, Collectors.toList()));

        List<FiscalYearSummary> summaries = new ArrayList<>();
        for (Map.Entry<Integer, List<AccountingPeriod>> entry : byYear.entrySet()) {
            int year = entry.getKey();
            List<AccountingPeriod> periods = entry.getValue();
            LocalDate start = periods.get(0).getStartDate();
            LocalDate end = periods.get(periods.size() - 1).getEndDate();
            int closed = (int) periods.stream().filter(p -> p.getStatus() == PeriodStatus.CLOSED).count();

            boolean yearEndPosted = !glRepository.findByCompanyIdAndReferenceTypeAndReferenceId(
                    companyId, GlReferenceType.YEAR_END_CLOSE.name(), (long) year).isEmpty();
            boolean current = !today.isBefore(start) && !today.isAfter(end);

            String status;
            if (yearEndPosted) status = "CLOSED";
            else if (current || closed > 0) status = "ACTIVE";
            else status = "DRAFT";

            summaries.add(FiscalYearSummary.builder()
                    .fiscalYear(year)
                    .name("FY " + year)
                    .startDate(start)
                    .endDate(end)
                    .totalPeriods(periods.size())
                    .openPeriods(periods.size() - closed)
                    .closedPeriods(closed)
                    .status(status)
                    .yearEndPosted(yearEndPosted)
                    .current(current)
                    .createdAt(periods.get(0).getCreatedAt())
                    .build());
        }
        return summaries;
    }

    @Override
    @Transactional
    public AccountingPeriodResponse closePeriod(Long id) {
        authorizationService.checkPermission(PermissionCode.ACCOUNTING_PERIOD_CLOSE);
        Long companyId = requireCompanyId();
        AccountingPeriod period = findInTenant(id, companyId);

        if (period.getStatus() == PeriodStatus.CLOSED) {
            throw new BadRequestException("This period is already closed");
        }

        // Close strictly in date order, else someone backdates into the still-open earlier gap and contradicts financials already reported as final.
        // Scoped across ALL fiscal years by date: per-year scoping left December of the old year open while January of the new year could close.
        LocalDate periodStart = period.getStartDate();
        boolean earlierStillOpen = periodRepository.existsByCompanyIdAndStartDateLessThanAndStatus(
                companyId, periodStart, PeriodStatus.OPEN);
        if (earlierStillOpen) {
            throw new BadRequestException("Close earlier periods first - periods must be closed in date order");
        }

        period.setStatus(PeriodStatus.CLOSED);
        period.setClosedBy(securityUtil.getCurrentUser().getUsername());
        period.setClosedAt(java.time.LocalDateTime.now());
        period = periodRepository.save(period);
        return AccountingPeriodMapper.toResponse(period);
    }

    @Override
    @Transactional
    public AccountingPeriodResponse reopenPeriod(Long id) {
        authorizationService.checkPermission(PermissionCode.ACCOUNTING_PERIOD_CLOSE);
        Long companyId = requireCompanyId();
        AccountingPeriod period = findInTenant(id, companyId);

        if (period.getStatus() != PeriodStatus.CLOSED) {
            throw new BadRequestException("This period isn't closed");
        }
        // Posting into a reopened period would invalidate the already-posted YEAR_END_CLOSE entry, which cannot be regenerated since closeFiscalYear refuses to run twice.
        if (isFiscalYearClosed(companyId, period.getFiscalYear())) {
            throw new BadRequestException(
                    "Fiscal year " + period.getFiscalYear() + " has already been closed - its periods can no longer be reopened");
        }
        // Reopen in reverse date order, mirroring closePeriod: the violation is a LATER period still being CLOSED, not one already OPEN.
        // Scoped across ALL fiscal years by date: December of the old year must not reopen while January of the new year is still closed.
        LocalDate periodStart = period.getStartDate();
        boolean laterStillClosed = periodRepository.existsByCompanyIdAndStartDateGreaterThanAndStatus(
                companyId, periodStart, PeriodStatus.CLOSED);
        if (laterStillClosed) {
            throw new BadRequestException("Reopen later periods first - periods must be reopened in reverse date order");
        }

        period.setStatus(PeriodStatus.OPEN);
        period.setReopenedBy(securityUtil.getCurrentUser().getUsername());
        period.setReopenedAt(java.time.LocalDateTime.now());
        period = periodRepository.save(period);
        return AccountingPeriodMapper.toResponse(period);
    }

    @Override
    @Transactional
    public void closeFiscalYear(int fiscalYear) {
        authorizationService.checkPermission(PermissionCode.ACCOUNTING_PERIOD_CLOSE);
        requireSaneFiscalYear(fiscalYear);
        Long companyId = requireCompanyId();

        // Serialise the close per company BEFORE the "already closed" GL read, else two rapid clicks both post a closing entry and double the year's profit into Retained Earnings. Transaction-scoped, so no unlock needed.
        periodRepository.acquireYearEndCloseLock(yearEndCloseLockKey(companyId));

        List<AccountingPeriod> periods = periodRepository.findByCompanyIdAndFiscalYearOrderByPeriodNumberAsc(companyId, fiscalYear);
        if (periods.size() < 12) {
            throw new BadRequestException("Not all 12 periods exist yet for fiscal year " + fiscalYear);
        }
        boolean allClosed = periods.stream().allMatch(p -> p.getStatus() == PeriodStatus.CLOSED);
        if (!allClosed) {
            throw new BadRequestException("All 12 periods must be closed before closing fiscal year " + fiscalYear);
        }

        // Read AFTER the advisory lock: the loser of the race sees the winner's committed closing entry and is rejected.
        if (isFiscalYearClosed(companyId, fiscalYear)) {
            throw new BadRequestException("Fiscal year " + fiscalYear + " has already been closed");
        }

        LocalDate start = periods.get(0).getStartDate();
        LocalDate end = periods.get(periods.size() - 1).getEndDate();
        String description = "Fiscal year " + fiscalYear + " (" + start + " to " + end + ") closing entry";

        // Zero every Revenue/Contra-Revenue/Expense movement for the year into Retained Earnings, so next year's P&L starts from zero.
        // Posted as one recordBalancedTransaction() call so the whole closing entry lands atomically and balanced, or not at all.
        List<LedgerLine> lines = new ArrayList<>();
        BigDecimal netIncome = BigDecimal.ZERO;
        netIncome = netIncome.add(closeAccountsOfType(companyId, AccountType.REVENUE, start, end, lines));
        netIncome = netIncome.subtract(closeAccountsOfType(companyId, AccountType.CONTRA_REVENUE, start, end, lines));
        netIncome = netIncome.subtract(closeAccountsOfType(companyId, AccountType.EXPENSE, start, end, lines));

        ChartOfAccount retainedEarnings = accountResolver.retainedEarnings(companyId);
        if (netIncome.compareTo(BigDecimal.ZERO) > 0) {
            lines.add(LedgerLine.credit(retainedEarnings.getId(), netIncome));
        } else if (netIncome.compareTo(BigDecimal.ZERO) < 0) {
            lines.add(LedgerLine.debit(retainedEarnings.getId(), netIncome.negate()));
        } else if (lines.isEmpty()) {
            // A year with no movement at all must still post a marker row: isFiscalYearClosed() looks for a GL row tagged YEAR_END_CLOSE/<fiscalYear>, and posting nothing left it false forever.
            // recordBalancedTransaction keeps the first line of an all-zero batch as that marker.
            lines.add(LedgerLine.debit(retainedEarnings.getId(), BigDecimal.ZERO));
        }

        glService.recordBalancedTransaction(companyId, lines, description,
                GlReferenceType.YEAR_END_CLOSE, (long) fiscalYear, "FY" + fiscalYear, end);
    }

    private boolean isFiscalYearClosed(Long companyId, int fiscalYear) {
        return !glRepository
                .findByCompanyIdAndReferenceTypeAndReferenceId(companyId, GlReferenceType.YEAR_END_CLOSE.name(), (long) fiscalYear)
                .isEmpty();
    }

    /** Appends zeroing lines for every account of one type and returns the total normal-direction movement closed out. */
    private BigDecimal closeAccountsOfType(Long companyId, AccountType type, LocalDate start, LocalDate end,
                                            List<LedgerLine> lines) {
        boolean creditNormal = type.isCreditNormal();
        BigDecimal total = BigDecimal.ZERO;

        for (ChartOfAccount account : coaRepository.findByCompanyIdAndType(companyId, type)) {
            List<GeneralLedger> entries = glRepository.findByCompanyIdAndAccountIdAndTransactionDateBetween(
                    companyId, account.getId(), start, end);
            BigDecimal movement = entries.stream()
                    .map(gl -> creditNormal
                            ? nz(gl.getCreditAmount()).subtract(nz(gl.getDebitAmount()))
                            : nz(gl.getDebitAmount()).subtract(nz(gl.getCreditAmount())))
                    .reduce(BigDecimal.ZERO, BigDecimal::add);

            if (movement.compareTo(BigDecimal.ZERO) == 0) continue;

            // Zero this account's contribution by posting the opposite side of its movement.
            if (creditNormal) {
                if (movement.compareTo(BigDecimal.ZERO) > 0) {
                    lines.add(LedgerLine.debit(account.getId(), movement));
                } else {
                    lines.add(LedgerLine.credit(account.getId(), movement.negate()));
                }
            } else {
                if (movement.compareTo(BigDecimal.ZERO) > 0) {
                    lines.add(LedgerLine.credit(account.getId(), movement));
                } else {
                    lines.add(LedgerLine.debit(account.getId(), movement.negate()));
                }
            }
            total = total.add(movement);
        }
        return total;
    }

    @Override
    @Transactional(readOnly = true)
    public boolean isDateInClosedPeriod(Long companyId, LocalDate date) {
        return periodLockChecker.isDateInClosedPeriod(companyId, date);
    }

    private AccountingPeriod findInTenant(Long id, Long companyId) {
        return periodRepository.findByIdAndCompanyId(id, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Accounting period not found: " + id));
    }

    /** A query-string typo like 202 or 20266 reached LocalDate.of() as a 500, or generated far-future periods that blocked later years as overlaps; 2000..2100 keeps it a clear 400. */
    private void requireSaneFiscalYear(int fiscalYear) {
        if (fiscalYear < MIN_FISCAL_YEAR || fiscalYear > MAX_FISCAL_YEAR) {
            throw new BadRequestException("Fiscal year must be between " + MIN_FISCAL_YEAR + " and " + MAX_FISCAL_YEAR
                    + " - got " + fiscalYear);
        }
    }

    /** pg_advisory_xact_lock() keys share one global 64-bit namespace, so the company id is salted: otherwise company 7's close blocks on any feature locking key 7. */
    private static long yearEndCloseLockKey(Long companyId) {
        return YEAR_END_CLOSE_LOCK_SALT * 31L + companyId;
    }

    private Long requireCompanyId() {
        Long id = securityUtil.getCurrentCompanyId();
        if (id == null) throw new BadRequestException("No company context");
        return id;
    }

    private static BigDecimal nz(BigDecimal v) {
        return v != null ? v : BigDecimal.ZERO;
    }
}
