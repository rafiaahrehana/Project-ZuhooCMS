package com.zuhoocms.modules.finance.generalledger;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface GeneralLedgerRepository extends JpaRepository<GeneralLedger, Long> {

    Optional<GeneralLedger> findByIdAndCompanyId(Long id, Long companyId);

    Page<GeneralLedger> findByCompanyIdAndAccountId(Long companyId, Long accountId, Pageable pageable);

    Page<GeneralLedger> findByCompanyIdAndTransactionDateBetween(Long companyId, LocalDate start, LocalDate end, Pageable pageable);

    Page<GeneralLedger> findByCompanyId(Long companyId, Pageable pageable);

    List<GeneralLedger> findByCompanyIdAndReferenceTypeAndReferenceId(Long companyId, String type, Long id);

    boolean existsByAccountIdAndCompanyId(Long accountId, Long companyId);

    boolean existsByCompanyId(Long companyId);

    @Query("SELECT gl FROM GeneralLedger gl WHERE gl.companyId = :companyId AND gl.transactionDate BETWEEN :start AND :end")
    List<GeneralLedger> findTransactionsBetweenDates(@Param("companyId") Long companyId, @Param("start") LocalDate start, @Param("end") LocalDate end);

    /** Used by FinancialReportServiceImpl.generateBalanceSheetReport for an account type's balance as of a date, not its live balance. */
    @Query("SELECT gl FROM GeneralLedger gl WHERE gl.companyId = :companyId AND gl.account.id IN :accountIds AND gl.transactionDate <= :date")
    List<GeneralLedger> findByCompanyIdAndAccountIdsUpToDate(
        @Param("companyId") Long companyId, @Param("accountIds") List<Long> accountIds, @Param("date") LocalDate date);

    /** Used by FinancialReportServiceImpl.generateAccountLedger for the opening balance: transactions strictly before the start date. */
    @Query("SELECT gl FROM GeneralLedger gl WHERE gl.companyId = :companyId AND gl.account.id = :accountId AND gl.transactionDate < :date")
    List<GeneralLedger> findByCompanyIdAndAccountIdBeforeDate(
        @Param("companyId") Long companyId, @Param("accountId") Long accountId, @Param("date") LocalDate date);

    /** Candidate "outstanding" lines for bank reconciliation: posted on or before the as-of date and not yet cleared (isReconciled = false). */
    List<GeneralLedger> findByCompanyIdAndAccountIdAndIsReconciledFalseAndTransactionDateLessThanEqualOrderByTransactionDateAsc(
        Long companyId, Long accountId, LocalDate asOfDate);

    /** Used by year-end closing (AccountingPeriodServiceImpl) for one account's movement over exactly the fiscal year being closed. */
    List<GeneralLedger> findByCompanyIdAndAccountIdAndTransactionDateBetween(
        Long companyId, Long accountId, LocalDate start, LocalDate end);

    /** One account's signed movement (debits - credits) up to a date: bank reconciliation must compare as of the statement date, not against the live all-time balance. */
    @Query("SELECT COALESCE(SUM(gl.debitAmount), 0) - COALESCE(SUM(gl.creditAmount), 0) FROM GeneralLedger gl " +
           "WHERE gl.companyId = :companyId AND gl.account.id = :accountId AND gl.transactionDate <= :date")
    java.math.BigDecimal sumSignedUpToDate(
        @Param("companyId") Long companyId, @Param("accountId") Long accountId, @Param("date") LocalDate date);

    /** Rows of [accountId, totalDebit, totalCredit] for every account with activity up to a date, in one query: the per-account N+1 also omitted deactivated accounts, so the Trial Balance columns didn't foot. */
    @Query("SELECT gl.account.id, COALESCE(SUM(gl.debitAmount), 0), COALESCE(SUM(gl.creditAmount), 0) " +
           "FROM GeneralLedger gl WHERE gl.companyId = :companyId AND gl.transactionDate <= :date " +
           "GROUP BY gl.account.id")
    List<Object[]> sumByAccountUpToDate(@Param("companyId") Long companyId, @Param("date") LocalDate date);

    /** One account's entries within a window, filtered and ordered in the database rather than by pulling the whole ledger into memory. */
    @Query("SELECT gl FROM GeneralLedger gl WHERE gl.companyId = :companyId AND gl.account.id = :accountId " +
           "AND gl.transactionDate BETWEEN :start AND :end ORDER BY gl.transactionDate ASC, gl.id ASC")
    List<GeneralLedger> findByAccountAndDateRangeOrdered(
        @Param("companyId") Long companyId, @Param("accountId") Long accountId,
        @Param("start") LocalDate start, @Param("end") LocalDate end);

    /** Entries within a window across a set of accounts - used by the cash-flow statement. */
    @Query("SELECT gl FROM GeneralLedger gl WHERE gl.companyId = :companyId AND gl.account.id IN :accountIds " +
           "AND gl.transactionDate BETWEEN :start AND :end ORDER BY gl.transactionDate ASC, gl.id ASC")
    List<GeneralLedger> findByAccountsAndDateRangeOrdered(
        @Param("companyId") Long companyId, @Param("accountIds") List<Long> accountIds,
        @Param("start") LocalDate start, @Param("end") LocalDate end);

    @Query("SELECT COALESCE(SUM(gl.debitAmount), 0) - COALESCE(SUM(gl.creditAmount), 0) FROM GeneralLedger gl " +
           "WHERE gl.companyId = :companyId AND gl.account.id IN :accountIds AND gl.transactionDate < :date")
    java.math.BigDecimal sumSignedBeforeDateForAccounts(
        @Param("companyId") Long companyId, @Param("accountIds") List<Long> accountIds, @Param("date") LocalDate date);

    /**
     * Ledger movement in a window excluding one reference type: the P&amp;L skips YEAR_END_CLOSE rows, which would make a closed year read as zero and double-count across the close.
     * JOIN FETCH on the account because the report filters by account type and would otherwise lazy-load one account per ledger row.
     */
    @Query("SELECT gl FROM GeneralLedger gl JOIN FETCH gl.account WHERE gl.companyId = :companyId " +
           "AND gl.transactionDate BETWEEN :start AND :end " +
           "AND (gl.referenceType IS NULL OR gl.referenceType <> :excludedReferenceType)")
    List<GeneralLedger> findTransactionsBetweenDatesExcludingReferenceType(
        @Param("companyId") Long companyId, @Param("start") LocalDate start, @Param("end") LocalDate end,
        @Param("excludedReferenceType") String excludedReferenceType);
}