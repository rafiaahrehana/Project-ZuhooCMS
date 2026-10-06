package com.zuhoocms.modules.finance.generalledger;

import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccountRepository;
import com.zuhoocms.modules.finance.period.PeriodLockChecker;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class GeneralLedgerServiceImpl implements GeneralLedgerService {

    private final GeneralLedgerRepository glRepository;
    private final ChartOfAccountRepository coaRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final PeriodLockChecker periodLockChecker;

    /** The only entry point into the ledger: validates the whole batch before writing, then posts every line under pessimistic row locks taken in id-ascending order. */
    @Override
    @Transactional
    public void recordBalancedTransaction(Long companyId, List<LedgerLine> lines, String description,
                                           GlReferenceType referenceType, Long referenceId, String referenceNumber,
                                           LocalDate transactionDate) {
        if (lines == null || lines.isEmpty()) {
            throw new BadRequestException("A transaction needs at least one line");
        }

        BigDecimal totalDebits = BigDecimal.ZERO;
        BigDecimal totalCredits = BigDecimal.ZERO;
        for (LedgerLine line : lines) {
            BigDecimal debit = nz(line.debitAmount());
            BigDecimal credit = nz(line.creditAmount());
            if (line.accountId() == null) {
                throw new BadRequestException("Every ledger line needs an account");
            }
            if (debit.signum() < 0 || credit.signum() < 0) {
                throw new BadRequestException("Line amounts cannot be negative");
            }
            if (debit.signum() > 0 && credit.signum() > 0) {
                throw new BadRequestException("A line can be a debit or a credit, not both");
            }
            totalDebits = totalDebits.add(debit);
            totalCredits = totalCredits.add(credit);
        }

        // Exactly, not "within a cent": amounts here are scale-2, so a tolerance only ever let a real one-cent posting bug through and skewed the books.
        if (totalDebits.compareTo(totalCredits) != 0) {
            throw new BadRequestException("Transaction does not balance: debits " + totalDebits
                    + " vs credits " + totalCredits + " - rejected before posting anything");
        }

        // A zero/zero line is a no-op, so drop it; an ENTIRELY zero batch (year-end close of a year with no movement) keeps its first line as the marker row, or the year can never be recorded as closed.
        List<LedgerLine> postable = lines.stream()
                .filter(l -> nz(l.debitAmount()).signum() != 0 || nz(l.creditAmount()).signum() != 0)
                .collect(Collectors.toList());
        if (postable.isEmpty()) {
            postable = List.of(lines.get(0));
        }
        lines = postable;

        LocalDate date = transactionDate != null ? transactionDate : LocalDate.now();

        // The year-end close is the one entry type allowed to post into the period it finalizes; everything else is blocked from backdating into a closed period.
        if (referenceType != GlReferenceType.YEAR_END_CLOSE && periodLockChecker.isDateInClosedPeriod(companyId, date)) {
            throw new BadRequestException(
                    "Cannot post to " + date + " - that accounting period is closed. Reopen it first if this entry truly belongs there.");
        }

        // Load each target account once, locked FOR UPDATE, so concurrent postings can't both read the same starting balance and lose an update; id-ascending order prevents deadlocks on overlapping account sets.
        List<Long> accountIds = lines.stream()
                .map(LedgerLine::accountId)
                .distinct()
                .sorted()
                .collect(Collectors.toList());
        List<ChartOfAccount> locked = coaRepository.lockByIdsAndCompanyId(accountIds, companyId);
        Map<Long, ChartOfAccount> byId = new LinkedHashMap<>();
        locked.forEach(a -> byId.put(a.getId(), a));

        for (Long accountId : accountIds) {
            ChartOfAccount account = byId.get(accountId);
            if (account == null) {
                throw new ResourceNotFoundException("Chart of Account not found");
            }
            requirePostable(account);
        }

        var currentUser = securityUtil.getCurrentUser();
        String postedBy = currentUser != null ? currentUser.getUsername() : "System";
        LocalDate postedDate = LocalDate.now();

        List<GeneralLedger> entries = new ArrayList<>();
        for (LedgerLine line : lines) {
            ChartOfAccount account = byId.get(line.accountId());
            BigDecimal debit = nz(line.debitAmount());
            BigDecimal credit = nz(line.creditAmount());

            entries.add(GeneralLedger.builder()
                    .companyId(companyId)
                    .transactionDate(date)
                    .account(account)
                    .debitAmount(debit)
                    .creditAmount(credit)
                    .description(description)
                    .referenceType(referenceType.name())
                    .referenceId(referenceId)
                    .referenceNumber(referenceNumber)
                    .posted(true)
                    // No authenticated user for system entry points (e.g. payment gateway callbacks).
                    .postedBy(postedBy)
                    .postedDate(postedDate)
                    .build());

            applyToBalance(account, debit, credit);
        }

        glRepository.saveAll(entries);
        coaRepository.saveAll(byId.values());
    }

    /** Mirrors JournalEntryServiceImpl's rule on every posting path: header/rollup, non-directly-postable and deactivated accounts must never receive ledger entries. */
    private void requirePostable(ChartOfAccount account) {
        if (account.isHeaderAccount() || !account.isAllowDirectPosting()) {
            throw new BadRequestException(
                    "\"" + account.getAccountName() + "\" (" + account.getAccountCode()
                            + ") does not allow direct posting - it's a header/rollup account. Post to one of its child accounts instead.");
        }
        if (!account.isActive()) {
            throw new BadRequestException(
                    "\"" + account.getAccountName() + "\" (" + account.getAccountCode()
                            + ") is inactive - reactivate it before posting to it.");
        }
    }

    private static BigDecimal nz(BigDecimal value) {
        return value != null ? value : BigDecimal.ZERO;
    }

    @Override
    @Transactional(readOnly = true)
    public GeneralLedgerResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.GENERAL_LEDGER_VIEW);
        GeneralLedger entry = glRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("GL entry not found"));
        return GeneralLedgerMapper.toResponse(entry);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<GeneralLedgerResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.GENERAL_LEDGER_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return glRepository.findByCompanyId(companyId, pageable)
                .map(GeneralLedgerMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<GeneralLedgerResponse> getByAccount(Long accountId, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.GENERAL_LEDGER_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return glRepository.findByCompanyIdAndAccountId(companyId, accountId, pageable)
                .map(GeneralLedgerMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public Page<GeneralLedgerResponse> getByDateRange(LocalDate start, LocalDate end, Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.GENERAL_LEDGER_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return glRepository.findByCompanyIdAndTransactionDateBetween(companyId, start, end, pageable)
                .map(GeneralLedgerMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<GeneralLedgerResponse> getByReference(GlReferenceType referenceType, Long referenceId) {
        authorizationService.checkPermission(PermissionCode.GENERAL_LEDGER_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return glRepository.findByCompanyIdAndReferenceTypeAndReferenceId(companyId, referenceType.name(), referenceId)
                .stream()
                .map(GeneralLedgerMapper::toResponse)
                .collect(Collectors.toList());
    }

    @Override
    @Transactional
    public void reconcile(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.GENERAL_LEDGER_RECONCILE);
        GeneralLedger entry = glRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("GL entry not found"));
        entry.setReconciled(true);
        entry.setReconciliationNotes(notes);
        glRepository.save(entry);
    }

    @Override
    @Transactional(readOnly = true)
    public BigDecimal getAccountBalance(Long accountId) {
        ChartOfAccount account = coaRepository.findByIdAndCompanyId(accountId, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Account not found"));
        return account.getBalance();
    }

    @Override
    @Transactional(readOnly = true)
    public BigDecimal getAccountBalanceAsOf(Long companyId, Long accountId, LocalDate asOfDate) {
        ChartOfAccount account = coaRepository.findByIdAndCompanyId(accountId, companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found"));
        BigDecimal signed = glRepository.sumSignedUpToDate(companyId, accountId, asOfDate);
        BigDecimal net = signed != null ? signed : BigDecimal.ZERO;
        // sumSignedUpToDate returns debits - credits; flip it for credit-normal accounts to match ChartOfAccount.balance's normal-side convention.
        return account.getType().isCreditNormal() ? net.negate() : net;
    }

    /** Debit-normal accounts increase with a debit, credit-normal ones with a credit; the classification lives on AccountType.isCreditNormal(). */
    private void applyToBalance(ChartOfAccount account, BigDecimal debit, BigDecimal credit) {
        BigDecimal currentBalance = account.getBalance() != null ? account.getBalance() : BigDecimal.ZERO;

        if (account.getType().isCreditNormal()) {
            currentBalance = currentBalance.add(credit).subtract(debit);
        } else {
            currentBalance = currentBalance.add(debit).subtract(credit);
        }

        account.setBalance(currentBalance);
    }
}
