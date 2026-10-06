package com.zuhoocms.modules.finance.reconciliation;

import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccountRepository;
import com.zuhoocms.modules.finance.generalledger.GeneralLedger;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerMapper;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerRepository;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerResponse;
import com.zuhoocms.modules.finance.generalledger.GeneralLedgerService;
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
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class BankReconciliationServiceImpl implements BankReconciliationService {

    // Only for pairing an imported statement line against a GL line, where the bank's rounding can differ by a cent; NOT used when closing - see markAsReconciled, which demands exact zero.
    private static final BigDecimal TOLERANCE = new BigDecimal("0.01");

    private final BankReconciliationRepository reconciliationRepository;
    private final ChartOfAccountRepository coaRepository;
    private final GeneralLedgerService glService;
    private final GeneralLedgerRepository glRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    @Override
    @Transactional
    public BankReconciliationResponse create(BankReconciliationRequest request) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_CREATE);
        Long companyId = securityUtil.getCurrentCompanyId();

        ChartOfAccount account = coaRepository.findByIdAndCompanyId(request.getBankAccountId(), companyId)
                .orElseThrow(() -> new ResourceNotFoundException("Bank account not found"));

        // Only a bank/cash account has a statement to compare against; the picker's isBankAccount flag must also be enforced server-side.
        if (!account.isBankAccount()) {
            throw new BadRequestException("'" + account.getAccountName() + "' is not a bank account. "
                    + "Only accounts flagged as bank accounts on the chart of accounts can be reconciled.");
        }

        // One open reconciliation per account: two sessions each clear a different subset of the same uncleared GL lines, so neither can ever reach a zero difference.
        reconciliationRepository.findFirstByCompanyIdAndBankAccountIdAndReconciledFalse(companyId, account.getId())
                .ifPresent(open -> {
                    throw new BadRequestException("There is already an open reconciliation (#" + open.getId()
                            + ", dated " + open.getReconciliationDate() + ") for '" + account.getAccountName()
                            + "'. Close or complete it before starting another.");
                });

        // statementDate is optional; everything below is computed as of this date, never as of "now".
        LocalDate statementDate = request.getStatementDate() != null ? request.getStatementDate() : LocalDate.now();

        BigDecimal glBalance = glService.getAccountBalanceAsOf(companyId, account.getId(), statementDate);

        BankReconciliation reconciliation = BankReconciliation.builder()
                .companyId(companyId)
                .bankAccount(account)
                .reconciliationDate(statementDate)
                .glBalance(glBalance)
                .bankStatementBalance(request.getBankStatementBalance())
                .reconciled(false)
                .build();

        recompute(reconciliation);
        reconciliation = reconciliationRepository.save(reconciliation);
        return BankReconciliationMapper.toResponse(reconciliation);
    }

    @Override
    @Transactional(readOnly = true)
    public BankReconciliationResponse getById(Long id) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_VIEW);
        return BankReconciliationMapper.toResponse(findInTenant(id));
    }

    private BankReconciliation findInTenant(Long id) {
        return reconciliationRepository.findByIdAndCompanyId(id, securityUtil.getCurrentCompanyId())
                .orElseThrow(() -> new ResourceNotFoundException("Reconciliation not found"));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<BankReconciliationResponse> getAll(Pageable pageable) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        return reconciliationRepository.findByCompanyId(companyId, pageable)
                .map(BankReconciliationMapper::toResponse);
    }

    @Override
    @Transactional(readOnly = true)
    public List<GeneralLedgerResponse> getUnclearedTransactions(Long id) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_VIEW);
        BankReconciliation reconciliation = findInTenant(id);
        return uncleared(reconciliation).stream()
                .map(GeneralLedgerMapper::toResponse)
                .collect(Collectors.toList());
    }

    private List<GeneralLedger> uncleared(BankReconciliation reconciliation) {
        return glRepository.findByCompanyIdAndAccountIdAndIsReconciledFalseAndTransactionDateLessThanEqualOrderByTransactionDateAsc(
                reconciliation.getCompanyId(), reconciliation.getBankAccount().getId(), reconciliation.getReconciliationDate());
    }

    @Override
    @Transactional
    public BankReconciliationResponse toggleTransactionCleared(Long id, Long glEntryId, boolean cleared) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_RECONCILE);
        BankReconciliation reconciliation = findInTenant(id);
        if (reconciliation.isReconciled()) {
            throw new BadRequestException("This reconciliation is already closed - reopening it isn't supported, start a new one instead");
        }

        Long reconciliationCompanyId = reconciliation.getCompanyId();
        Long reconciliationAccountId = reconciliation.getBankAccount().getId();
        GeneralLedger entry = glRepository.findById(glEntryId)
                .filter(e -> Objects.equals(e.getCompanyId(), reconciliationCompanyId))
                .filter(e -> Objects.equals(e.getAccount().getId(), reconciliationAccountId))
                .orElseThrow(() -> new ResourceNotFoundException("Transaction not found on this account: " + glEntryId));

        if (cleared) {
            // A line cleared by a DIFFERENT reconciliation must not be stolen: it rewrites that one's outstanding set and counts the bank transaction as cleared twice.
            if (entry.isReconciled()
                    && entry.getReconciledInReconciliationId() != null
                    && !Objects.equals(entry.getReconciledInReconciliationId(), reconciliation.getId())) {
                throw new BadRequestException("Transaction " + glEntryId
                        + " was already cleared by reconciliation #" + entry.getReconciledInReconciliationId()
                        + " and cannot be cleared again here.");
            }
            entry.setReconciled(true);
            entry.setReconciledInReconciliationId(reconciliation.getId());
        } else {
            // Only un-clear a line this reconciliation cleared itself, or it could reopen a different, already-closed one.
            if (!Objects.equals(entry.getReconciledInReconciliationId(), reconciliation.getId())) {
                throw new BadRequestException("This transaction wasn't cleared by this reconciliation");
            }
            entry.setReconciled(false);
            entry.setReconciledInReconciliationId(null);
        }
        glRepository.save(entry);

        recompute(reconciliation);
        reconciliation = reconciliationRepository.save(reconciliation);
        return BankReconciliationMapper.toResponse(reconciliation);
    }

    /** adjustedBankBalance = statement balance + uncleared debits - uncleared credits; difference is what stays unexplained, and markAsReconciled() requires it to be zero. */
    private void recompute(BankReconciliation reconciliation) {
        List<GeneralLedger> outstanding = uncleared(reconciliation);
        BigDecimal deposits = outstanding.stream()
                .map(GeneralLedger::getDebitAmount)
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal checks = outstanding.stream()
                .map(GeneralLedger::getCreditAmount)
                .filter(Objects::nonNull)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal bankStatementBalance = reconciliation.getBankStatementBalance() != null
                ? reconciliation.getBankStatementBalance() : BigDecimal.ZERO;
        BigDecimal adjustedBankBalance = bankStatementBalance.add(deposits).subtract(checks);
        // Re-read, not the snapshot taken at session creation: an entry backdated into the account after opening leaves the difference permanently unresolvable.
        // Re-read AS OF the statement date, not live: postings after the statement was printed can never be explained by it.
        BigDecimal glBalance = glService.getAccountBalanceAsOf(
                reconciliation.getCompanyId(),
                reconciliation.getBankAccount().getId(),
                reconciliation.getReconciliationDate());
        reconciliation.setGlBalance(glBalance);

        reconciliation.setOutstandingDepositsTotal(deposits);
        reconciliation.setOutstandingChecksTotal(checks);
        reconciliation.setDifference(glBalance.subtract(adjustedBankBalance));
    }

    @Override
    @Transactional
    public BankReconciliationResponse attachStatement(Long id, AttachStatementRequest request) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_RECONCILE);
        BankReconciliation reconciliation = findInTenant(id);
        reconciliation.setStatementFileName(request.getFileName());
        reconciliation.setStatementFileUrl(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getFileUrl(), reconciliation.getStatementFileUrl()));
        reconciliation.setStatementUploadedAt(java.time.LocalDateTime.now());
        reconciliation = reconciliationRepository.save(reconciliation);
        return BankReconciliationMapper.toResponse(reconciliation);
    }

    @Override
    @Transactional
    public StatementImportResult importStatement(Long id, org.springframework.web.multipart.MultipartFile file) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_RECONCILE);
        BankReconciliation reconciliation = findInTenant(id);
        if (reconciliation.isReconciled()) {
            throw new BadRequestException("This reconciliation is already closed");
        }
        if (file == null || file.isEmpty()) {
            throw new BadRequestException("No file uploaded");
        }

        String content;
        try {
            content = new String(file.getBytes(), java.nio.charset.StandardCharsets.UTF_8);
        } catch (java.io.IOException e) {
            throw new BadRequestException("Could not read the uploaded file");
        }

        List<GeneralLedger> candidates = new java.util.ArrayList<>(uncleared(reconciliation));
        List<StatementImportResult.UnmatchedLine> unmatched = new java.util.ArrayList<>();
        int totalLines = 0;
        int matched = 0;

        // Sniff the delimiter from the first non-empty line, counting separators outside quotes only: "Smith, John Ltd" made a comma file look like it had extra columns.
        char delimiter = detectDelimiter(content);

        for (String rawLine : content.split("\r?\n")) {
            String line = rawLine.trim();
            if (line.isEmpty()) continue;

            // Proper CSV splitting, not String.split(delimiter): quoted descriptions contain the delimiter, so the amount column was read from mid-description and the line fell through as unmatched.
            List<String> cols = splitCsvLine(line, delimiter);
            if (cols.size() < 2) continue;
            String amountText = cols.get(cols.size() - 1);

            BigDecimal amount = parseStatementAmount(amountText);
            if (amount == null) {
                // Non-numeric last column: a header row ("date,description,amount") - skip silently.
                continue;
            }

            totalLines++;
            String date = cols.get(0);
            String description = cols.size() >= 3
                    ? String.join(" ", cols.subList(1, cols.size() - 1)).trim()
                    : "";
            LocalDate statementLineDate = parseStatementDate(date);

            // Positive statement amount = money in = a debit on the bank's GL account, negative = a credit; one statement line consumes at most one GL entry.
            boolean deposit = amount.compareTo(BigDecimal.ZERO) >= 0;
            BigDecimal absAmount = amount.abs();

            // Prefer a same-amount entry on the same day, falling back to nearest date: "first uncleared entry with this amount" mis-paired recurring equal-value transactions (rent, payroll) with the wrong month.
            GeneralLedger match = null;
            long bestDistance = Long.MAX_VALUE;
            for (GeneralLedger entry : candidates) {
                BigDecimal entryAmount = deposit ? entry.getDebitAmount() : entry.getCreditAmount();
                if (entryAmount == null || entryAmount.compareTo(BigDecimal.ZERO) <= 0) continue;
                if (entryAmount.subtract(absAmount).abs().compareTo(TOLERANCE) > 0) continue;

                long distance;
                if (statementLineDate == null || entry.getTransactionDate() == null) {
                    // Unparseable statement date: first (earliest) wins.
                    distance = Long.MAX_VALUE - 1;
                } else {
                    distance = Math.abs(java.time.temporal.ChronoUnit.DAYS.between(
                            entry.getTransactionDate(), statementLineDate));
                }
                if (distance < bestDistance) {
                    bestDistance = distance;
                    match = entry;
                    if (distance == 0) break; // exact same-date hit - can't do better
                }
            }

            if (match != null) {
                match.setReconciled(true);
                match.setReconciledInReconciliationId(reconciliation.getId());
                match.setReconciliationNotes("Auto-matched from statement import"
                        + (description.isEmpty() ? "" : ": " + description));
                glRepository.save(match);
                candidates.remove(match);
                matched++;
            } else {
                unmatched.add(StatementImportResult.UnmatchedLine.builder()
                        .date(date)
                        .description(description)
                        .amount(amount)
                        .reason("No uncleared " + (deposit ? "deposit" : "withdrawal") + " of this amount in the books")
                        .build());
            }
        }

        if (totalLines == 0) {
            throw new BadRequestException(
                    "No transaction rows found - expected CSV columns: date, description, amount (negative = withdrawal)");
        }

        recompute(reconciliation);
        reconciliation = reconciliationRepository.save(reconciliation);

        return StatementImportResult.builder()
                .totalLines(totalLines)
                .matched(matched)
                .unmatchedCount(unmatched.size())
                .unmatchedLines(unmatched)
                .reconciliation(BankReconciliationMapper.toResponse(reconciliation))
                .build();
    }

    /** Picks the separator from the first non-empty line, counting only separators outside quotes: a `line.contains(";")` check flipped the file to semicolons whenever a description held one. */
    private static char detectDelimiter(String content) {
        for (String raw : content.split("\r?\n")) {
            String line = raw.trim();
            if (line.isEmpty()) continue;
            int commas = 0, semis = 0, tabs = 0;
            boolean inQuotes = false;
            for (char c : line.toCharArray()) {
                if (c == '"') inQuotes = !inQuotes;
                else if (!inQuotes) {
                    if (c == ',') commas++;
                    else if (c == ';') semis++;
                    else if (c == '\t') tabs++;
                }
            }
            if (semis > commas && semis >= tabs) return ';';
            if (tabs > commas && tabs > semis) return '\t';
            return ',';
        }
        return ',';
    }

    /** Minimal RFC-4180 splitter (quoted fields, delimiters inside quotes, doubled "" escape) returning unquoted trimmed fields; String.split() corrupted rows with a quoted description. */
    private static List<String> splitCsvLine(String line, char delimiter) {
        List<String> fields = new java.util.ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean inQuotes = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < line.length() && line.charAt(i + 1) == '"') {
                        current.append('"'); // "" inside quotes = one literal quote
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    current.append(c);
                }
            } else if (c == '"') {
                inQuotes = true;
            } else if (c == delimiter) {
                fields.add(current.toString().trim());
                current.setLength(0);
            } else {
                current.append(c);
            }
        }
        fields.add(current.toString().trim());
        return fields;
    }

    /** Parses bank amount formats: "1,234.00", "(1,234.00)", "1234.00-", currency symbols, European "1.234,56"; null when not a number, which is how a header row is skipped. */
    private static BigDecimal parseStatementAmount(String raw) {
        if (raw == null) return null;
        String text = raw.trim();
        if (text.isEmpty()) return null;

        boolean negative = false;
        if (text.startsWith("(") && text.endsWith(")")) { // accounting-style negative
            negative = true;
            text = text.substring(1, text.length() - 1).trim();
        }
        if (text.endsWith("-")) { // trailing-minus exports
            negative = true;
            text = text.substring(0, text.length() - 1).trim();
        }
        if (text.startsWith("-")) {
            negative = true;
            text = text.substring(1).trim();
        } else if (text.startsWith("+")) {
            text = text.substring(1).trim();
        }

        // Drop currency symbols / spaces / non-breaking spaces; keep only digits and separators.
        text = text.replaceAll("[^0-9.,]", "");
        if (text.isEmpty()) return null;

        int lastDot = text.lastIndexOf('.');
        int lastComma = text.lastIndexOf(',');
        if (lastDot >= 0 && lastComma >= 0) {
            // Whichever separator comes last is the decimal point; the other groups thousands.
            if (lastComma > lastDot) {
                text = text.replace(".", "").replace(',', '.');
            } else {
                text = text.replace(",", "");
            }
        } else if (lastComma >= 0) {
            // A lone comma is a decimal point only in "123,45" form; otherwise it groups.
            boolean decimalComma = text.length() - lastComma - 1 == 2 && text.indexOf(',') == lastComma;
            text = decimalComma ? text.replace(',', '.') : text.replace(",", "");
        }

        try {
            BigDecimal value = new BigDecimal(text);
            return negative ? value.negate() : value;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    // dd/MM is tried before MM/dd and both are STRICT, so "13/05/2024" resolves correctly instead of being accepted as an invalid month.
    private static final java.time.format.DateTimeFormatter[] STATEMENT_DATE_FORMATS = {
            dateFormat("uuuu-MM-dd"), dateFormat("uuuu/MM/dd"),
            dateFormat("dd/MM/uuuu"), dateFormat("MM/dd/uuuu"),
            dateFormat("dd-MM-uuuu"), dateFormat("MM-dd-uuuu"),
            dateFormat("dd.MM.uuuu"), dateFormat("dd-MMM-uuuu"), dateFormat("dd MMM uuuu")
    };

    private static java.time.format.DateTimeFormatter dateFormat(String pattern) {
        return java.time.format.DateTimeFormatter.ofPattern(pattern, java.util.Locale.ENGLISH)
                .withResolverStyle(java.time.format.ResolverStyle.STRICT);
    }

    /** Best-effort statement-line date; null when the column isn't a date we recognise. */
    private static LocalDate parseStatementDate(String raw) {
        if (raw == null) return null;
        String text = raw.trim();
        if (text.isEmpty()) return null;
        for (java.time.format.DateTimeFormatter format : STATEMENT_DATE_FORMATS) {
            try {
                return LocalDate.parse(text, format);
            } catch (java.time.format.DateTimeParseException ignored) {
                // try the next known layout
            }
        }
        return null;
    }

    @Override
    @Transactional
    public void markAsReconciled(Long id, String notes) {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_RECONCILE);
        BankReconciliation reconciliation = findInTenant(id);
        if (reconciliation.isReconciled()) {
            throw new BadRequestException("Already reconciled");
        }

        // Recompute fresh rather than trusting the last saved value: a GL entry could have posted since this was opened.
        recompute(reconciliation);
        // EXACTLY zero, no tolerance: ledger amounts are scale-2, so a one-cent window only lets a real unexplained cent be signed off.
        if (reconciliation.getDifference().compareTo(BigDecimal.ZERO) != 0) {
            throw new BadRequestException(
                    "Cannot close this reconciliation - the books and the bank statement still differ by "
                            + reconciliation.getDifference().abs()
                            + " after accounting for outstanding items. Clear more transactions against the "
                            + "bank statement, or post a journal entry for any bank fee/interest not yet recorded, then try again.");
        }

        reconciliation.markAsReconciled(securityUtil.getCurrentUser().getUsername());
        reconciliation.setDiscrepancyNotes(notes);
        reconciliationRepository.save(reconciliation);
    }

    @Override
    @Transactional(readOnly = true)
    public List<BankReconciliationResponse> getPendingReconciliations() {
        authorizationService.checkPermission(PermissionCode.BANK_RECONCILIATION_VIEW);
        Long companyId = securityUtil.getCurrentCompanyId();
        // Map inside the transaction: bankAccount is FetchType.LAZY, so mapping in the controller throws LazyInitializationException on getBankAccount().
        return reconciliationRepository.findByCompanyIdAndReconciledFalse(companyId)
                .stream()
                .map(BankReconciliationMapper::toResponse)
                .collect(Collectors.toList());
    }
}
