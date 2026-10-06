package com.zuhoocms.modules.finance.journalentry;

import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccountRepository;
import com.zuhoocms.modules.finance.generalledger.DocumentNumberService;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
import com.zuhoocms.modules.finance.generalledger.GlReferenceType;
import com.zuhoocms.modules.finance.generalledger.LedgerLine;
import com.zuhoocms.auth.role.enums.PermissionCode;
import com.zuhoocms.auth.role.enums.Role;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.auth.user.User;
import com.zuhoocms.modules.finance.period.PeriodLockChecker;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class JournalEntryServiceImpl implements JournalEntryService {

    private final JournalEntryRepository jeRepository;
    private final ChartOfAccountRepository coaRepository;
    private final GeneralLedgerService glService;
    private final DocumentNumberService documentNumberService;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final PeriodLockChecker periodLockChecker;

    @Override
    @Transactional
    public JournalEntryResponse create(JournalEntryRequest request) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_CREATE);
        Long companyId = securityUtil.getCurrentCompanyId();

        // Normalize to the multi-line form: an explicit lines list, or two lines synthesized from the legacy single debit/credit fields.
        List<JournalEntryLineRequest> lineRequests = normalizeLines(request);
        validateLines(lineRequests);

        LocalDate entryDate = request.getEntryDate() != null ? request.getEntryDate() : LocalDate.now();
        String jeNumber = generateJENumber(companyId, entryDate);
        JournalEntry je = JournalEntry.builder()
                .companyId(companyId)
                .journalEntryNumber(jeNumber)
                .entryDate(entryDate)
                .description(request.getDescription())
                .notes(request.getNotes())
                .createdBy(securityUtil.getCurrentUser().getUsername())
                .createdDate(LocalDate.now())
                .approved(false)
                .posted(false)
                .build();

        BigDecimal totalDebits = BigDecimal.ZERO;
        ChartOfAccount firstDebitAccount = null;
        ChartOfAccount firstCreditAccount = null;

        for (JournalEntryLineRequest lineRequest : lineRequests) {
            ChartOfAccount account = coaRepository.findByIdAndCompanyId(lineRequest.getAccountId(), companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Account not found: " + lineRequest.getAccountId()));
            requireDirectPostingAllowed(account);

            BigDecimal debit = nz(lineRequest.getDebitAmount());
            BigDecimal credit = nz(lineRequest.getCreditAmount());
            totalDebits = totalDebits.add(debit);
            if (firstDebitAccount == null && debit.compareTo(BigDecimal.ZERO) > 0) firstDebitAccount = account;
            if (firstCreditAccount == null && credit.compareTo(BigDecimal.ZERO) > 0) firstCreditAccount = account;

            je.getLines().add(JournalEntryLine.builder()
                    .journalEntry(je)
                    .account(account)
                    .debitAmount(debit)
                    .creditAmount(credit)
                    .lineDescription(lineRequest.getLineDescription())
                    .build());
        }

        // Legacy NOT NULL columns - kept as a summary (see JournalEntry field comment).
        je.setDebitAccount(firstDebitAccount);
        je.setCreditAccount(firstCreditAccount);
        je.setAmount(totalDebits);

        je = jeRepository.save(je);
        return JournalEntryMapper.toResponse(je);
    }

    /** Server-side enforcement of isHeaderAccount / !allowDirectPosting: posting a manual entry to a rollup account breaks its hierarchy. System postings resolve to leaf accounts via DefaultAccountResolver, so only hand-picked accounts need guarding. */
    private void requireDirectPostingAllowed(ChartOfAccount account) {
        if (account.isHeaderAccount() || !account.isAllowDirectPosting()) {
            throw new BadRequestException(
                    "\"" + account.getAccountName() + "\" (" + account.getAccountCode()
                            + ") does not allow direct posting - it's a header/rollup account. Post to one of its child accounts instead.");
        }
    }

    /** Re-runs the account check at POST time: between drafting and posting an account can be deactivated or turned into a header account. Applies to reversals too, which reuse the original's accounts. */
    private void requirePostableAccount(ChartOfAccount account) {
        if (account == null) {
            throw new BadRequestException("Journal entry line has no account");
        }
        if (!account.isActive()) {
            throw new BadRequestException(
                    "\"" + account.getAccountName() + "\" (" + account.getAccountCode()
                            + ") is no longer active - it cannot be posted to. Edit the entry to use an active account.");
        }
        requireDirectPostingAllowed(account);
    }

    /** Either the explicit lines list, or two lines built from the legacy 1:1 fields. */
    private List<JournalEntryLineRequest> normalizeLines(JournalEntryRequest request) {
        if (request.getLines() != null && !request.getLines().isEmpty()) {
            return request.getLines();
        }
        if (request.getDebitAccountId() == null || request.getCreditAccountId() == null || request.getAmount() == null) {
            throw new BadRequestException(
                    "Provide either a lines list (at least 2 lines) or the legacy debitAccountId/creditAccountId/amount fields");
        }
        return List.of(
                JournalEntryLineRequest.builder()
                        .accountId(request.getDebitAccountId())
                        .debitAmount(request.getAmount())
                        .creditAmount(BigDecimal.ZERO)
                        .build(),
                JournalEntryLineRequest.builder()
                        .accountId(request.getCreditAccountId())
                        .debitAmount(BigDecimal.ZERO)
                        .creditAmount(request.getAmount())
                        .build());
    }

    private void validateLines(List<JournalEntryLineRequest> lines) {
        if (lines.size() < 2) {
            throw new BadRequestException("A journal entry needs at least 2 lines");
        }
        BigDecimal totalDebits = BigDecimal.ZERO;
        BigDecimal totalCredits = BigDecimal.ZERO;
        for (JournalEntryLineRequest line : lines) {
            BigDecimal debit = nz(line.getDebitAmount());
            BigDecimal credit = nz(line.getCreditAmount());
            if (debit.compareTo(BigDecimal.ZERO) < 0 || credit.compareTo(BigDecimal.ZERO) < 0) {
                throw new BadRequestException("Line amounts cannot be negative");
            }
            if (debit.compareTo(BigDecimal.ZERO) > 0 && credit.compareTo(BigDecimal.ZERO) > 0) {
                throw new BadRequestException("A line can be a debit or a credit, not both");
            }
            if (debit.compareTo(BigDecimal.ZERO) == 0 && credit.compareTo(BigDecimal.ZERO) == 0) {
                throw new BadRequestException("Every line needs a debit or credit amount");
            }
            totalDebits = totalDebits.add(debit);
            totalCredits = totalCredits.add(credit);
        }
        if (totalDebits.subtract(totalCredits).abs().compareTo(new BigDecimal("0.01")) > 0) {
            throw new BadRequestException("Journal entry does not balance: debits " + totalDebits
                    + " vs credits " + totalCredits);
        }
    }

    private static BigDecimal nz(BigDecimal value) {
        return value != null ? value : BigDecimal.ZERO;
    }

    @Override
    @Transactional(readOnly = true)
    public JournalEntryResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_VIEW);
        return JournalEntryMapper.toResponse(findInTenant(id));
    }

    private JournalEntry findInTenant(Long id) {
        return jeRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Journal entry not found"));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<JournalEntryResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return jeRepository.findByCompanyId(companyId, pageable)
                .map(JournalEntryMapper::toResponse);
    }

    @Override
    @Transactional
    public void approve(Long id) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_APPROVE);
        JournalEntry je = findInTenant(id);

        if (je.isApproved()) {
            throw new BadRequestException("Journal entry is already approved");
        }

        // Maker-checker: the writer of an entry must not approve it, or one user can move money through the books alone.
        // The company owner is exempt (they already hold every tenant permission - see AuthorizationServiceImpl); their self-approvals are flagged instead.
        String approver = securityUtil.getCurrentUser().getUsername();
        boolean selfApproval = approver != null && approver.equalsIgnoreCase(je.getCreatedBy());
        if (selfApproval && !canSelfApprove()) {
            throw new BadRequestException("You created this journal entry - a different user must approve it");
        }

        je.approve(approver, selfApproval);
        jeRepository.save(je);
    }

    /** Only the company owner and an impersonating platform admin (impersonation mints owner-level authority - see ImpersonationServiceImpl) may waive maker-checker; CustomRole holders always need a second person. */
    private boolean canSelfApprove() {
        if (securityUtil.isImpersonating()) {
            return true;
        }
        User user = securityUtil.getCurrentUser();
        return user != null && user.getRole() == Role.COMPANY_OWNER;
    }

    @Override
    @Transactional
    public void post(Long id) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_POST);
        JournalEntry je = findInTenant(id);

        if (!je.isApproved()) {
            throw new BadRequestException("Journal entry must be approved before posting");
        }

        if (je.isPosted()) {
            throw new BadRequestException("Journal entry is already posted");
        }

        postToLedger(je);
        jeRepository.save(je);
    }

    /** Records the GL lines as one balanced batch (rejected if debits != credits) and flips to posted; shared by {@link #post} and {@link #reverse}, with pre-lines entries falling back to the legacy 1:1 columns. */
    private void postToLedger(JournalEntry je) {
        LocalDate transactionDate = je.getEntryDate() != null ? je.getEntryDate() : LocalDate.now();

        List<LedgerLine> ledgerLines;
        if (je.getLines() != null && !je.getLines().isEmpty()) {
            je.getLines().forEach(line -> requirePostableAccount(line.getAccount()));
            ledgerLines = je.getLines().stream()
                    .map(line -> new LedgerLine(line.getAccount().getId(),
                            nz(line.getDebitAmount()), nz(line.getCreditAmount())))
                    .collect(java.util.stream.Collectors.toList());
        } else {
            requirePostableAccount(je.getDebitAccount());
            requirePostableAccount(je.getCreditAccount());
            ledgerLines = List.of(
                    LedgerLine.debit(je.getDebitAccount().getId(), je.getAmount()),
                    LedgerLine.credit(je.getCreditAccount().getId(), je.getAmount()));
        }

        glService.recordBalancedTransaction(je.getCompanyId(), ledgerLines, je.getDescription(),
                GlReferenceType.JOURNAL_ENTRY, je.getId(), je.getJournalEntryNumber(), transactionDate);

        je.post();
    }

    @Override
    @Transactional
    public JournalEntryResponse reverse(Long id) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_POST);
        JournalEntry original = findInTenant(id);

        if (!original.isPosted()) {
            throw new BadRequestException("Only posted journal entries can be reversed");
        }
        if (original.isReversed()) {
            throw new BadRequestException("Journal entry is already reversed");
        }
        // Reversing a reversal re-posts the original amounts under a third number, leaving the audit trail an unreadable chain.
        if (original.isReversalEntry()) {
            throw new BadRequestException(
                    "This entry is itself a reversal and cannot be reversed. Create a new journal entry instead.");
        }

        Long companyId = original.getCompanyId();
        String actor = securityUtil.getCurrentUser().getUsername();
        LocalDate today = LocalDate.now();

        // Date the reversal on the original's date so the two cancel inside the same period; once that period is closed PeriodLockChecker rejects it, so it falls to today.
        LocalDate reversalDate = periodLockChecker.isDateInClosedPeriod(companyId, original.getEntryDate())
                ? today
                : original.getEntryDate();
        if (reversalDate == null) {
            reversalDate = today;
        }

        // Mirrors the original with debit and credit swapped for an exact offsetting movement; created pre-approved and posted immediately.
        JournalEntry reversal = JournalEntry.builder()
                .companyId(companyId)
                .journalEntryNumber(generateJENumber(companyId, reversalDate))
                .entryDate(reversalDate)
                .debitAccount(original.getCreditAccount())
                .creditAccount(original.getDebitAccount())
                .amount(original.getAmount())
                .description("Reversal of " + original.getJournalEntryNumber()
                        + (original.getDescription() != null ? " — " + original.getDescription() : ""))
                .notes("Auto-generated reversal")
                .createdBy(actor)
                .createdDate(today)
                .reversedFromEntryId(original.getId())
                .approved(true)
                .approvedBy(actor)
                .approvedDate(today)
                .posted(false)
                .build();

        // A multi-line original needs a matching multi-line reversal, not just the summary pair.
        if (original.getLines() != null && !original.getLines().isEmpty()) {
            for (JournalEntryLine line : original.getLines()) {
                reversal.getLines().add(JournalEntryLine.builder()
                        .journalEntry(reversal)
                        .account(line.getAccount())
                        .debitAmount(nz(line.getCreditAmount()))
                        .creditAmount(nz(line.getDebitAmount()))
                        .lineDescription(line.getLineDescription())
                        .build());
            }
        }

        reversal = jeRepository.save(reversal);

        postToLedger(reversal);
        reversal = jeRepository.save(reversal);

        original.markReversed(reversal.getId());
        jeRepository.save(original);

        return JournalEntryMapper.toResponse(reversal);
    }

    @Override
    @Transactional
    public JournalEntryResponse delete(Long id) {
        authorizationService.checkPermission(PermissionCode.JOURNAL_ENTRY_DELETE);
        JournalEntry je = findInTenant(id);

        if (je.isPosted()) {
            throw new BadRequestException("Cannot delete posted journal entries");
        }

        je.softDelete();
        jeRepository.save(je);
        return JournalEntryMapper.toResponse(je);
    }

    /** The year comes from the entry's own date, not today, or a backdated entry lands in the wrong year's sequence and the JE register reads non-chronologically. Counter is a locked sequence row, not MAX+1 - see DocumentNumberService. */
    private String generateJENumber(Long companyId, LocalDate entryDate) {
        int year = (entryDate != null ? entryDate : LocalDate.now()).getYear();
        String prefix = "JE-" + year + "-";
        return documentNumberService.next(companyId, DocumentNumberService.JOURNAL_ENTRY, year, prefix,
                () -> seedFrom(jeRepository.findMaxJENumberByCompanyAndPrefix(companyId, prefix).orElse(null), prefix));
    }

    /** First value for a brand-new counter: one past whatever the old MAX+1 scheme already issued. */
    private static long seedFrom(String maxNumber, String prefix) {
        if (maxNumber == null || !maxNumber.startsWith(prefix)) return 1L;
        try {
            return Long.parseLong(maxNumber.substring(prefix.length())) + 1L;
        } catch (NumberFormatException e) {
            return 1L;
        }
    }
}

