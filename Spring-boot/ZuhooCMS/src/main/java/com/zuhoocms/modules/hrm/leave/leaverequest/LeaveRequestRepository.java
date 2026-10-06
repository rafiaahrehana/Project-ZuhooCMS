package com.zuhoocms.modules.hrm.leave.leaverequest;

import com.zuhoocms.enums.LeaveRequestStatus;
import com.zuhoocms.enums.LeaveType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface LeaveRequestRepository extends JpaRepository<LeaveRequest, Long> {

    Optional<LeaveRequest> findByIdAndCompanyId(Long id, Long companyId);

    Page<LeaveRequest> findByCompanyId(Long companyId, Pageable pageable);

    Page<LeaveRequest> findByCompanyIdAndStatus(
        Long companyId, LeaveRequestStatus status, Pageable pageable);

    long countByCompanyIdAndStatus(Long companyId, LeaveRequestStatus status);

    /** Requests by status whose leave dates fall in a window, not when raised, so the dashboard's "this month" means leave taken this month. */
    long countByCompanyIdAndStatusAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
        Long companyId, LeaveRequestStatus status,
        java.time.LocalDate to, java.time.LocalDate from);

    long countByCompanyIdAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
        Long companyId, java.time.LocalDate to, java.time.LocalDate from);

    Page<LeaveRequest> findByCompanyIdAndEmployeeId(
        Long companyId, Long employeeId, Pageable pageable);

    /** Approved leave days taken in a window; COALESCE returns 0 rather than null when there is no leave at all. */
    @Query("""
        SELECT COALESCE(SUM(lr.totalDays), 0) FROM LeaveRequest lr
        WHERE lr.company.id = :companyId
          AND lr.employee.id = :employeeId
          AND lr.status = com.zuhoocms.enums.LeaveRequestStatus.APPROVED
          AND lr.startDate <= :to AND lr.endDate >= :from
          AND lr.deleted = false
        """)
    Integer sumApprovedLeaveDaysInRange(
        @Param("companyId") Long companyId,
        @Param("employeeId") Long employeeId,
        @Param("from") java.time.LocalDate from,
        @Param("to") java.time.LocalDate to);

    @Query("""
        SELECT SUM(lr.totalDays) FROM LeaveRequest lr
        WHERE lr.employee.id = :employeeId
          AND lr.leaveType = :leaveType
          AND lr.status = :status
          AND YEAR(lr.startDate) = :year
          AND lr.deleted = false
        """)
    Optional<Integer> sumDaysByEmployeeAndTypeAndStatusAndYear(
        @Param("employeeId") Long employeeId,
        @Param("leaveType") LeaveType leaveType,
        @Param("status") LeaveRequestStatus status,
        @Param("year") int year);

    @Query("""
        SELECT COUNT(lr) > 0 FROM LeaveRequest lr
        WHERE lr.employee.id = :employeeId
          AND lr.status NOT IN :excludedStatuses
          AND lr.startDate <= :endDate
          AND lr.endDate >= :startDate
          AND lr.deleted = false
        """)
    boolean hasOverlappingLeave(
        @Param("employeeId") Long employeeId,
        @Param("startDate") LocalDate startDate,
        @Param("endDate") LocalDate endDate,
        @Param("excludedStatuses") java.util.List<LeaveRequestStatus> excludedStatuses);

    /** Used by DailyAbsenteeScheduler to skip employees on approved leave rather than marking them ABSENT. */
    @Query("""
        SELECT COUNT(lr) > 0 FROM LeaveRequest lr
        WHERE lr.employee.id = :employeeId
          AND lr.status = :status
          AND lr.startDate <= :date
          AND lr.endDate >= :date
          AND lr.deleted = false
        """)
    boolean existsApprovedForEmployeeAndDate(
        @Param("employeeId") Long employeeId,
        @Param("date") LocalDate date,
        @Param("status") LeaveRequestStatus status);

    /**
     * Approved requests overlapping a date range, for the dashboard's monthly summary; per-day overlap is clamped in Java.
     *
     * <p>company_id is in the predicate rather than left to Hibernate's tenantFilter: the filter is only on the session
     * of an authenticated tenant user, and these totals are also computed from payroll and report paths, so on the
     * employee id alone another tenant's leave could be counted into this company's summary.
     */
    @Query("""
        SELECT lr FROM LeaveRequest lr
        WHERE lr.company.id = :companyId
          AND lr.employee.id = :employeeId
          AND lr.status = :status
          AND lr.startDate <= :rangeEnd
          AND lr.endDate >= :rangeStart
          AND lr.deleted = false
        """)
    List<LeaveRequest> findApprovedOverlapping(
        @Param("companyId") Long companyId,
        @Param("employeeId") Long employeeId,
        @Param("status") LeaveRequestStatus status,
        @Param("rangeStart") LocalDate rangeStart,
        @Param("rangeEnd") LocalDate rangeEnd);

    /** Approved requests of one type overlapping [from, to]; scoped on company_id for the same reason as the overload above. */
    @Query("""
        SELECT lr FROM LeaveRequest lr
        WHERE lr.company.id = :companyId
          AND lr.employee.id = :employeeId
          AND lr.status = com.zuhoocms.enums.LeaveRequestStatus.APPROVED
          AND lr.leaveType = :leaveType
          AND lr.startDate <= :to
          AND lr.endDate >= :from
          AND lr.deleted = false
        """)
    java.util.List<LeaveRequest> findApprovedOverlapping(
        @Param("companyId") Long companyId,
        @Param("employeeId") Long employeeId,
        @Param("leaveType") com.zuhoocms.enums.LeaveType leaveType,
        @Param("from") java.time.LocalDate from,
        @Param("to") java.time.LocalDate to);
}
