package com.zuhoocms.modules.finance.generalledger;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public interface GeneralLedgerService {

    /**
     * Posts a whole multi-line transaction atomically, rejecting the batch up front unless it balances.
     * The ONLY way to post to the ledger: single-leg recordTransaction() overloads are private, so no caller can create a half-transaction.
     * <p>Throws BadRequestException if:
     * <ul>
     *   <li>debits != credits <em>exactly</em> (no tolerance - amounts are scale-2, so a one-cent window only hid real bugs),</li>
     *   <li>any line carries a negative amount, or both a debit and a credit,</li>
     *   <li>any line targets an inactive, header/rollup, or allowDirectPosting = false account,</li>
     *   <li>transactionDate falls in a closed period (except YEAR_END_CLOSE, which may post into the period it finalizes).</li>
     * </ul>
     */
    void recordBalancedTransaction(Long companyId, List<LedgerLine> lines, String description,
                                    GlReferenceType referenceType, Long referenceId, String referenceNumber,
                                    LocalDate transactionDate);

    GeneralLedgerResponse getById(Long id);

    Page<GeneralLedgerResponse> getAll(Pageable pageable);

    Page<GeneralLedgerResponse> getByAccount(Long accountId, Pageable pageable);

    Page<GeneralLedgerResponse> getByDateRange(LocalDate start, LocalDate end, Pageable pageable);

    List<GeneralLedgerResponse> getByReference(GlReferenceType referenceType, Long referenceId);

    void reconcile(Long id, String notes);

    BigDecimal getAccountBalance(Long accountId);

    /** The balance rebuilt from the ledger as of a date rather than the cached live balance, for bank reconciliation, which compares against a statement as of the statement's date. */
    BigDecimal getAccountBalanceAsOf(Long companyId, Long accountId, LocalDate asOfDate);
}
