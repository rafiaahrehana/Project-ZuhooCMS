package com.zuhoocms.modules.finance.period;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface AccountingPeriodRepository extends JpaRepository<AccountingPeriod, Long> {

    Optional<AccountingPeriod> findByCompanyIdAndFiscalYearAndPeriodNumber(Long companyId, int fiscalYear, int periodNumber);

    List<AccountingPeriod> findByCompanyIdAndFiscalYearOrderByPeriodNumberAsc(Long companyId, int fiscalYear);

    Optional<AccountingPeriod> findByIdAndCompanyId(Long id, Long companyId);

    /** The period whose date range contains the given date, if it's ever been created. */
    Optional<AccountingPeriod> findByCompanyIdAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
        Long companyId, LocalDate date1, LocalDate date2);

    List<AccountingPeriod> findByCompanyIdOrderByFiscalYearAscPeriodNumberAsc(Long companyId);

    /** Periods of OTHER fiscal years overlapping [start, end]: after fiscalYearStartMonth changes a regenerated year can cover days an older year owns, making "is this date in a closed period?" depend on which row is found first. */
    @Query("SELECT p FROM AccountingPeriod p WHERE p.companyId = :companyId AND p.fiscalYear <> :fiscalYear "
            + "AND p.startDate <= :end AND p.endDate >= :start ORDER BY p.startDate ASC")
    List<AccountingPeriod> findOverlappingOtherYears(@Param("companyId") Long companyId,
                                                     @Param("fiscalYear") int fiscalYear,
                                                     @Param("start") LocalDate start,
                                                     @Param("end") LocalDate end);

    /** Ordering guards compare by DATE across all fiscal years, not periodNumber within one: otherwise FY2025's last period and FY2026's first are unordered and either can close or reopen out of sequence. */
    boolean existsByCompanyIdAndStartDateLessThanAndStatus(Long companyId, LocalDate startDate, PeriodStatus status);

    boolean existsByCompanyIdAndStartDateGreaterThanAndStatus(Long companyId, LocalDate startDate, PeriodStatus status);

    /**
     * Serialises the year-end close per company, making the GL-reading "already closed?" check and the post atomic: two rapid clicks otherwise both post a closing entry and double the year's profit into Retained Earnings.
     * Transaction-scoped, so it needs no unlock and cannot leak on rollback; same native-query shape as FinanceDocumentSequenceRepository.acquireSequenceLock().
     */
    @Query(value = "SELECT 1 FROM (SELECT pg_advisory_xact_lock(:key)) AS locked", nativeQuery = true)
    Integer acquireYearEndCloseLock(@Param("key") long key);
}
