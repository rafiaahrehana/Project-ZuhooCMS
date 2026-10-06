package com.zuhoocms.modules.hrm.payroll;

import com.zuhoocms.enums.PayrollStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

public interface PayrollRepository extends JpaRepository<Payroll, Long> {

    Optional<Payroll> findByIdAndCompanyId(Long id, Long companyId);

    java.util.List<Payroll> findAllByCompanyIdAndPayMonthAndPayYear(Long companyId, int payMonth, int payYear);

    java.util.List<Payroll> findByRunId(Long runId);

    Optional<Payroll> findByEmployeeIdAndPayMonthAndPayYear(
        Long employeeId, int payMonth, int payYear);

    Page<Payroll> findByCompanyId(Long companyId, Pageable pageable);

    /** Payrolls for a period in one status with employee and bank details fetched eagerly - the disbursement export would otherwise fire a query per employee. */
    @Query("""
        SELECT p FROM Payroll p
        LEFT JOIN FETCH p.employee e
        LEFT JOIN FETCH e.user
        WHERE p.company.id = :companyId
          AND p.payMonth = :month AND p.payYear = :year
          AND p.status = :status
        ORDER BY e.employeeNumber ASC
        """)
    List<Payroll> findForDisbursement(
        @Param("companyId") Long companyId,
        @Param("month") int month,
        @Param("year") int year,
        @Param("status") PayrollStatus status);

    Page<Payroll> findByCompanyIdAndPayMonthAndPayYear(
        Long companyId, int payMonth, int payYear, Pageable pageable);

    long countByCompanyIdAndPayMonthAndPayYearAndStatusIn(
        Long companyId, int payMonth, int payYear, java.util.List<PayrollStatus> statuses);

    Page<Payroll> findByCompanyIdAndEmployeeId(
        Long companyId, Long employeeId, Pageable pageable);

    @Query("SELECT SUM(p.netSalary) FROM Payroll p WHERE p.company.id = :companyId AND p.payMonth = :month AND p.payYear = :year AND p.status = :status AND p.deleted = false")
    Optional<BigDecimal> sumNetSalaryByCompanyAndPeriod(
        @Param("companyId") Long companyId,
        @Param("month") int month,
        @Param("year") int year,
        @Param("status") PayrollStatus status);

    /** Row-locked load for markPaid - two concurrent pays serialize on this row. */
    @org.springframework.data.jpa.repository.Lock(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT p FROM Payroll p WHERE p.id = :id AND p.company.id = :companyId")
    Optional<Payroll> findByIdAndCompanyIdForUpdate(@Param("id") Long id, @Param("companyId") Long companyId);

    /** A soft-deleted line still holds the (employee_id, pay_month, pay_year) unique key; native so @SQLRestriction(deleted = false) does not hide it. */
    @Query(value = "SELECT id FROM payrolls WHERE employee_id = :employeeId AND pay_month = :month "
            + "AND pay_year = :year AND deleted = true LIMIT 1", nativeQuery = true)
    Optional<Long> findSoftDeletedId(@Param("employeeId") Long employeeId,
                                     @Param("month") int month, @Param("year") int year);

    @org.springframework.data.jpa.repository.Modifying(flushAutomatically = true)
    @Query(value = "UPDATE payrolls SET deleted = false, deleted_at = NULL WHERE id = :id", nativeQuery = true)
    int reviveById(@Param("id") Long id);

    /** Installment money earmarked on not-yet-paid lines; paid lines have already reduced remainingBalance. */
    @Query("""
        SELECT COALESCE(SUM(p.loanDeductionAmount), 0) FROM Payroll p
        WHERE p.loanAdvance.id = :loanId
          AND p.status <> com.zuhoocms.enums.PayrollStatus.PAID
          AND p.id <> :excludeId
          AND p.deleted = false
        """)
    BigDecimal sumReservedLoanDeduction(@Param("loanId") Long loanId, @Param("excludeId") Long excludeId);
}
