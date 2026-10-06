package com.zuhoocms.modules.hrm.payroll.run;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PayrollRunRepository extends JpaRepository<PayrollRun, Long> {
    Optional<PayrollRun> findByCompanyIdAndPayMonthAndPayYear(Long companyId, int month, int year);
    List<PayrollRun> findByCompanyIdOrderByPayYearDescPayMonthDesc(Long companyId);
    long countByCompanyId(Long companyId);

    /** A cancelled (soft-deleted) run still holds the (company, month, year) unique key. */
    @Query(value = "SELECT id FROM payroll_runs WHERE company_id = :companyId AND pay_month = :month "
            + "AND pay_year = :year AND deleted = true LIMIT 1", nativeQuery = true)
    Optional<Long> findSoftDeletedIdForPeriod(@Param("companyId") Long companyId,
                                              @Param("month") int month, @Param("year") int year);

    @Modifying(flushAutomatically = true)
    @Query(value = "UPDATE payroll_runs SET deleted = false, deleted_at = NULL WHERE id = :id", nativeQuery = true)
    int reviveById(@Param("id") Long id);

    /** Every run number the company ever used, deleted rows included. */
    @Query(value = "SELECT run_number FROM payroll_runs WHERE company_id = :companyId", nativeQuery = true)
    List<String> findAllRunNumbersIncludingDeleted(@Param("companyId") Long companyId);

    @Query(value = "SELECT COUNT(*) FROM payroll_runs WHERE company_id = :companyId AND run_number = :runNumber",
            nativeQuery = true)
    long countRunNumberIncludingDeleted(@Param("companyId") Long companyId, @Param("runNumber") String runNumber);
}
