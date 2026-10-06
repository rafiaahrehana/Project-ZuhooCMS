package com.zuhoocms.modules.hrm.attendance.shift;

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
public interface EmployeeShiftAssignmentRepository extends JpaRepository<EmployeeShiftAssignment, Long> {

    Optional<EmployeeShiftAssignment> findByIdAndCompanyId(Long id, Long companyId);

    /**
     * The employee's shift as of a given date; the date window is part of the condition because `active` is set by hand and long-expired assignments stay flagged active, which drove late detection.
     * Ordered newest-first and returned as a list, since overlapping windows would otherwise make the query blow up on a non-unique result.
     */
    @Query("""
            SELECT esa FROM EmployeeShiftAssignment esa
            WHERE esa.companyId = :companyId
              AND esa.employee.id = :employeeId
              AND (esa.active = true OR esa.assignmentEndDate IS NOT NULL)
              AND esa.deleted = false
              AND (esa.assignmentStartDate IS NULL OR esa.assignmentStartDate <= :onDate)
              AND (esa.assignmentEndDate IS NULL OR esa.assignmentEndDate >= :onDate)
            ORDER BY esa.assignmentStartDate DESC, esa.id DESC
            """)
    List<EmployeeShiftAssignment> findEffectiveAssignments(@Param("companyId") Long companyId,
                                                           @Param("employeeId") Long employeeId,
                                                           @Param("onDate") LocalDate onDate);

    /** The shift in force for this employee today, if any. */
    default Optional<EmployeeShiftAssignment> findByCompanyIdAndEmployeeIdAndActive(Long companyId, Long employeeId) {
        return findEffectiveOn(companyId, employeeId, LocalDate.now());
    }

    /** The shift in force for this employee on the given date, if any. */
    default Optional<EmployeeShiftAssignment> findEffectiveOn(Long companyId, Long employeeId, LocalDate date) {
        return findEffectiveAssignments(companyId, employeeId, date)
                .stream()
                .findFirst();
    }

    Page<EmployeeShiftAssignment> findByCompanyIdAndShiftIdAndActiveTrue(Long companyId, Long shiftId, Pageable pageable);

    Page<EmployeeShiftAssignment> findByCompanyId(Long companyId, Pageable pageable);
}
