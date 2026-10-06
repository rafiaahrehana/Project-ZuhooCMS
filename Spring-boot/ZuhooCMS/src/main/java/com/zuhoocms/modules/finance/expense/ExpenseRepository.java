package com.zuhoocms.modules.finance.expense;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository("financeExpenseRepository")
public interface ExpenseRepository extends JpaRepository<Expense, Long> {

    Optional<Expense> findByIdAndCompanyId(Long id, Long companyId);

    Optional<Expense> findByCompanyIdAndExpenseNumber(Long companyId, String number);

    /**
     * Seed for the EXP- counter (see DocumentNumberService): the highest running number under this company/prefix, <b>soft-deleted rows included</b>.
     * <p>Only a seed: MAX is not safe on its own, because two concurrent creators read the same maximum inside their own transactions and build the same number. The locked counter row, not this query, is what makes numbers unique.
     * <p>Native, so BaseEntity's {@code @SQLRestriction} cannot hide a soft-deleted expense that the unique constraint still counts.
     */
    @Query(value = """
        SELECT MAX(CASE WHEN SUBSTRING(expense_number FROM :start) ~ '^[0-9]+$'
                        THEN CAST(SUBSTRING(expense_number FROM :start) AS BIGINT) END)
        FROM expenses
        WHERE company_id = :companyId AND expense_number LIKE CONCAT(:prefix, '%')
        """, nativeQuery = true)
    Long findMaxExpenseSequenceIncludingDeleted(@Param("companyId") Long companyId,
                                                @Param("prefix") String prefix,
                                                @Param("start") int start);

    Page<Expense> findByCompanyIdAndStatus(Long companyId, ExpenseStatus status, Pageable pageable);

    Page<Expense> findByCompanyIdAndSubmittedByIdAndStatus(Long companyId, Long employeeId, ExpenseStatus status, Pageable pageable);
    Page<Expense> findByCompanyIdAndSubmittedById(Long companyId, Long employeeId, Pageable pageable);

    Page<Expense> findByCompanyId(Long companyId, Pageable pageable);

    List<Expense> findByCompanyIdAndExpenseDateBetween(Long companyId, LocalDate start, LocalDate end);

    Page<Expense> findByCompanyIdAndVendorName(Long companyId, String vendorName, Pageable pageable);

    // Platform expenses have no owning company, and `company_id = :companyId` never matches NULL rows in SQL, so they need their own IS NULL variants.
    Optional<Expense> findByIdAndCompanyIdIsNull(Long id);

    Page<Expense> findByCompanyIdIsNull(Pageable pageable);

    Page<Expense> findByCompanyIdIsNullAndStatus(ExpenseStatus status, Pageable pageable);

    Page<Expense> findByCompanyIdIsNullAndVendorName(String vendorName, Pageable pageable);

    /** Platform variant of {@link #findMaxExpenseSequenceIncludingDeleted}: {@code company_id = :companyId} never matches NULL rows in SQL. */
    @Query(value = """
        SELECT MAX(CASE WHEN SUBSTRING(expense_number FROM :start) ~ '^[0-9]+$'
                        THEN CAST(SUBSTRING(expense_number FROM :start) AS BIGINT) END)
        FROM expenses
        WHERE company_id IS NULL AND expense_number LIKE CONCAT(:prefix, '%')
        """, nativeQuery = true)
    Long findMaxPlatformExpenseSequenceIncludingDeleted(@Param("prefix") String prefix,
                                                        @Param("start") int start);

    /** Actual spend in a category over a date window - used for budget-vs-actual. */
    @Query("SELECT COALESCE(SUM(e.amount), 0) FROM FinanceExpense e " +
           "WHERE e.companyId = :companyId AND LOWER(e.category) = LOWER(:category) " +
           "AND e.expenseDate BETWEEN :start AND :end AND e.status IN :statuses")
    java.math.BigDecimal sumByCategoryAndDateRange(
            @Param("companyId") Long companyId, @Param("category") String category,
            @Param("start") LocalDate start, @Param("end") LocalDate end,
            @Param("statuses") List<ExpenseStatus> statuses);
}
