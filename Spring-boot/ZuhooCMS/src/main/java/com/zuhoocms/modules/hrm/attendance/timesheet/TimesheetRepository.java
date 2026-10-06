package com.zuhoocms.modules.hrm.attendance.timesheet;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface TimesheetRepository extends JpaRepository<Timesheet, Long> {

    Optional<Timesheet> findByIdAndCompanyId(Long id, Long companyId);

    Optional<Timesheet> findByCompanyIdAndEmployeeIdAndWorkDate(Long companyId, Long employeeId, LocalDate workDate);

    /**
     * Un-deletes a soft-deleted row so log() can reuse it instead of hitting the unique constraint.
     *
     * <p>company_id is in the predicate because this is a NATIVE update: Hibernate's tenantFilter applies to HQL and
     * Criteria only, so on employee_id alone this statement could reach across tenants entirely unfiltered.
     */
    @Modifying
    @Query(nativeQuery = true, value = "update timesheets set deleted = false, deleted_at = null "
        + "where company_id = :companyId and employee_id = :employeeId and work_date = :workDate and deleted = true")
    int reviveDeleted(@Param("companyId") Long companyId,
                      @Param("employeeId") Long employeeId,
                      @Param("workDate") LocalDate workDate);

    Page<Timesheet> findByCompanyIdAndEmployeeId(Long companyId, Long employeeId, Pageable pageable);

    List<Timesheet> findByCompanyIdAndEmployeeIdAndWorkDateBetween(
        Long companyId, Long employeeId, LocalDate from, LocalDate to);

    List<Timesheet> findByCompanyIdAndEmployeeIdAndSubmittedFalseAndApprovedFalse(Long companyId, Long employeeId);

    @Query("SELECT SUM(t.hoursWorked) FROM Timesheet t WHERE t.employee.id = :employeeId AND t.workDate BETWEEN :from AND :to AND t.deleted = false")
    Optional<Double> sumHoursWorked(
        @Param("employeeId") Long employeeId,
        @Param("from") LocalDate from,
        @Param("to") LocalDate to);

    // Only APPROVED hours are paid - a submitted-but-not-yet-approved entry doesn't count yet.
    @Query("SELECT SUM(t.billableHours) FROM Timesheet t WHERE t.employee.id = :employeeId AND t.approved = true AND t.workDate BETWEEN :from AND :to AND t.deleted = false")
    Optional<Double> sumApprovedBillableHours(
        @Param("employeeId") Long employeeId,
        @Param("from") LocalDate from,
        @Param("to") LocalDate to);
}
