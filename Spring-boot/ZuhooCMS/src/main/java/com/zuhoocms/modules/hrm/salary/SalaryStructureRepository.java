package com.zuhoocms.modules.hrm.salary;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import com.zuhoocms.modules.hrm.employee.Employee;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface SalaryStructureRepository extends JpaRepository<SalaryStructure, Long> {

    Optional<SalaryStructure> findByIdAndCompanyId(Long id, Long companyId);

    Page<SalaryStructure> findByCompanyIdAndEmployeeId(Long companyId, Long employeeId, Pageable pageable);

    /**
     * Every structure in the company, newest first. The fetch joins avoid 2N+1 queries, since SalaryStructureMapper reads the LAZY employee.user.fullName and approvedBy.fullName.
     * All ManyToOne, so Hibernate still paginates in SQL rather than in memory. Soft-deleted rows are excluded by @SQLRestriction on BaseEntity.
     */
    @Query(value = """
        SELECT s FROM SalaryStructure s
        LEFT JOIN FETCH s.employee e
        LEFT JOIN FETCH e.user
        LEFT JOIN FETCH s.approvedBy
        WHERE s.company.id = :companyId
        """,
        countQuery = "SELECT COUNT(s) FROM SalaryStructure s WHERE s.company.id = :companyId")
    Page<SalaryStructure> findAllInCompany(@Param("companyId") Long companyId, Pageable pageable);

    /** The currently active structure - effectiveTo IS NULL. */
    Optional<SalaryStructure> findByEmployeeIdAndEffectiveToIsNull(Long employeeId);

    @Query("""
        SELECT s FROM SalaryStructure s
        WHERE s.employee.id = :employeeId
          AND s.effectiveFrom <= :date
          AND (s.effectiveTo IS NULL OR s.effectiveTo >= :date)
          AND s.deleted = false
        """)
    Optional<SalaryStructure> findActiveForEmployeeOnDate(
        @Param("employeeId") Long employeeId,
        @Param("date") LocalDate date);

    List<SalaryStructure> findByEmployeeIdOrderByEffectiveFromDesc(Long employeeId);

    // The two unscoped lookups above rely on Hibernate's tenantFilter; these also take companyId explicitly.

    List<SalaryStructure> findByCompanyIdAndEmployeeIdOrderByEffectiveFromDesc(Long companyId, Long employeeId);

    /** Open-ended structures (effectiveTo IS NULL), newest first. More than one only exists in legacy data. */
    List<SalaryStructure> findByCompanyIdAndEmployeeIdAndEffectiveToIsNullOrderByEffectiveFromDesc(Long companyId, Long employeeId);

    @Query("""
        SELECT s FROM SalaryStructure s
        WHERE s.company.id = :companyId
          AND s.employee.id = :employeeId
          AND s.effectiveFrom <= :date
          AND (s.effectiveTo IS NULL OR s.effectiveTo >= :date)
        ORDER BY s.effectiveFrom DESC
        """)
    List<SalaryStructure> findInEffectForEmployeeOnDate(
        @Param("companyId") Long companyId,
        @Param("employeeId") Long employeeId,
        @Param("date") LocalDate date);

    /** Row lock on the employee, so even the first create (with no structure row to lock) serialises and two concurrent creates cannot both leave an open-ended structure. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT e FROM Employee e WHERE e.id = :employeeId AND e.company.id = :companyId")
    Optional<Employee> lockEmployee(@Param("employeeId") Long employeeId, @Param("companyId") Long companyId);

    /** Cross-company (scheduler, no tenant context): structures in effect on :date that are not yet the employee's current one. */
    @Query("""
        SELECT s FROM SalaryStructure s JOIN FETCH s.employee e
        WHERE s.effectiveFrom <= :date
          AND (s.effectiveTo IS NULL OR s.effectiveTo >= :date)
          AND (e.salaryStructure IS NULL OR e.salaryStructure.id <> s.id)
        """)
    List<SalaryStructure> findDueNotYetApplied(@Param("date") LocalDate date);
}
