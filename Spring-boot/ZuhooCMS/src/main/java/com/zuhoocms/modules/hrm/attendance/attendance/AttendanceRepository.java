package com.zuhoocms.modules.hrm.attendance.attendance;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface AttendanceRepository extends JpaRepository<Attendance, Long> {

    /** Tenant-scoped lookup - used for all single-record operations to prevent cross-tenant data access. */
    Optional<Attendance> findByIdAndCompanyId(Long id, Long companyId);

    List<Attendance> findByEmployeeIdAndAttendanceDate(Long employeeId, LocalDate date);

    Page<Attendance> findByCompanyIdAndEmployeeId(Long companyId, Long employeeId, Pageable pageable);

    @Query(value = "SELECT a FROM Attendance a LEFT JOIN FETCH a.employee e WHERE a.companyId = :companyId AND a.deleted = false",
           countQuery = "SELECT COUNT(a) FROM Attendance a WHERE a.companyId = :companyId AND a.deleted = false")
    Page<Attendance> findByCompanyId(@Param("companyId") Long companyId, Pageable pageable);

    @Query(value = "SELECT a FROM Attendance a " +
           "LEFT JOIN FETCH a.employee e " +
           "LEFT JOIN e.user u " +
           "WHERE a.companyId = :companyId " +
           "AND a.status = :status " +
           "AND a.attendanceDate BETWEEN :startDate AND :endDate " +
           "AND (" +
           "    LOWER(u.firstName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(u.lastName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(CONCAT(u.firstName, ' ', u.lastName)) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(e.employeeNumber) LIKE LOWER(CONCAT('%', :search, '%'))" +
           ")",
           countQuery = "SELECT COUNT(a) FROM Attendance a " +
           "LEFT JOIN a.employee e " +
           "LEFT JOIN e.user u " +
           "WHERE a.companyId = :companyId " +
           "AND a.status = :status " +
           "AND a.attendanceDate BETWEEN :startDate AND :endDate " +
           "AND (" +
           "    LOWER(u.firstName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(u.lastName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(CONCAT(u.firstName, ' ', u.lastName)) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(e.employeeNumber) LIKE LOWER(CONCAT('%', :search, '%'))" +
           ")")
    Page<Attendance> searchAttendanceRecordsWithStatusAndDate(
            @Param("companyId") Long companyId,
            @Param("status") AttendanceStatus status,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate,
            @Param("search") String search,
            Pageable pageable);

    @Query(value = "SELECT a FROM Attendance a " +
           "LEFT JOIN FETCH a.employee e " +
           "LEFT JOIN e.user u " +
           "WHERE a.companyId = :companyId " +
           "AND a.attendanceDate BETWEEN :startDate AND :endDate " +
           "AND (" +
           "    LOWER(u.firstName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(u.lastName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(CONCAT(u.firstName, ' ', u.lastName)) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(e.employeeNumber) LIKE LOWER(CONCAT('%', :search, '%'))" +
           ")",
           countQuery = "SELECT COUNT(a) FROM Attendance a " +
           "LEFT JOIN a.employee e " +
           "LEFT JOIN e.user u " +
           "WHERE a.companyId = :companyId " +
           "AND a.attendanceDate BETWEEN :startDate AND :endDate " +
           "AND (" +
           "    LOWER(u.firstName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(u.lastName) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(CONCAT(u.firstName, ' ', u.lastName)) LIKE LOWER(CONCAT('%', :search, '%')) OR " +
           "    LOWER(e.employeeNumber) LIKE LOWER(CONCAT('%', :search, '%'))" +
           ")")
    Page<Attendance> searchAttendanceRecordsWithoutStatusAndDate(
            @Param("companyId") Long companyId,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate,
            @Param("search") String search,
            Pageable pageable);

    @Query(value = "SELECT a FROM Attendance a LEFT JOIN FETCH a.employee e WHERE a.companyId = :companyId AND a.attendanceDate BETWEEN :start AND :end AND a.deleted = false",
           countQuery = "SELECT COUNT(a) FROM Attendance a WHERE a.companyId = :companyId AND a.attendanceDate BETWEEN :start AND :end AND a.deleted = false")
    Page<Attendance> findByCompanyIdAndAttendanceDateBetween(
        @Param("companyId") Long companyId,
        @Param("start") LocalDate start,
        @Param("end") LocalDate end,
        Pageable pageable
    );

    @Query("SELECT a FROM Attendance a LEFT JOIN FETCH a.employee e WHERE a.companyId = :companyId AND a.attendanceDate BETWEEN :start AND :end AND a.deleted = false")
    List<Attendance> findListByCompanyIdAndAttendanceDateBetween(
        @Param("companyId") Long companyId,
        @Param("start") LocalDate start,
        @Param("end") LocalDate end
    );

    @Query(value = "SELECT a FROM Attendance a " +
           "LEFT JOIN FETCH a.employee e " +
           "WHERE a.companyId = :companyId " +
           "AND a.status = :status " +
           "AND a.attendanceDate BETWEEN :start AND :end " +
           "AND a.deleted = false",
           countQuery = "SELECT COUNT(a) FROM Attendance a " +
           "WHERE a.companyId = :companyId " +
           "AND a.status = :status " +
           "AND a.attendanceDate BETWEEN :start AND :end " +
           "AND a.deleted = false")
    Page<Attendance> searchByStatusAndDateRange(
            @Param("companyId") Long companyId,
            @Param("status") AttendanceStatus status,
            @Param("start") LocalDate start,
            @Param("end") LocalDate end,
            Pageable pageable);

    Page<Attendance> findByCompanyIdAndStatus(Long companyId, AttendanceStatus status, Pageable pageable);

    List<Attendance> findByCompanyIdAndStatusAndAttendanceDateBetween(
        Long companyId, AttendanceStatus status, LocalDate start, LocalDate end
    );

    /** Uses JPQL enum comparison, not a string literal, for type safety. */
    @Query("""
        SELECT a FROM Attendance a
        WHERE a.companyId = :companyId
          AND a.attendanceDate = :date
          AND a.status = com.zuhoocms.modules.hrm.attendance.attendance.AttendanceStatus.LATE
          AND a.deleted = false
        """)
    List<Attendance> findLateAttendances(
        @Param("companyId") Long companyId,
        @Param("date") LocalDate date
    );

    /**
     * Scoped on company_id as well as the employee: the id alone leaned entirely on Hibernate's tenantFilter, which is
     * absent on any thread without an authenticated tenant user (schedulers, the payroll and report paths reached from
     * one), so a stray employee id could mix another tenant's attendance into this company's totals.
     */
    @Query("""
        SELECT a FROM Attendance a
        WHERE a.companyId = :companyId
          AND a.employee.id = :employeeId
          AND a.attendanceDate BETWEEN :start AND :end
          AND a.deleted = false
        """)
    List<Attendance> findByEmployeeAndDateRange(
        @Param("companyId") Long companyId,
        @Param("employeeId") Long employeeId,
        @Param("start") LocalDate start,
        @Param("end") LocalDate end
    );

    @Query("""
        SELECT COUNT(a) FROM Attendance a
        WHERE a.companyId = :companyId
          AND a.status = :status
          AND a.attendanceDate = :date
          AND a.deleted = false
        """)
    long countByCompanyIdAndStatusAndDate(
        @Param("companyId") Long companyId,
        @Param("status") AttendanceStatus status,
        @Param("date") LocalDate date
    );

    long countByEmployeeIdAndStatusAndAttendanceDateBetween(
        Long employeeId, AttendanceStatus status, LocalDate start, LocalDate end
    );

    /** COALESCE because overtimeHours is nullable on rows predating overtime tracking, and SUM over no rows returns null rather than zero. */
    @Query("""
            SELECT COALESCE(SUM(a.overtimeHours), 0) FROM Attendance a
            WHERE a.employee.id = :employeeId
              AND a.attendanceDate BETWEEN :start AND :end
              AND a.deleted = false
            """)
    BigDecimal sumOvertimeHours(@Param("employeeId") Long employeeId,
                                @Param("start") LocalDate start,
                                @Param("end") LocalDate end);

    /** Bulk-marks employees with no record for today as ABSENT; used by DailyAbsenteeScheduler. */
    @Modifying
    @Query("""
        UPDATE Attendance a SET a.status = :absent
        WHERE a.companyId = :companyId
          AND a.attendanceDate = :date
          AND a.status = :unmarked
          AND a.deleted = false
        """)
    int bulkMarkAbsent(
        @Param("companyId") Long companyId,
        @Param("date") LocalDate date,
        @Param("absent") AttendanceStatus absent,
        @Param("unmarked") AttendanceStatus unmarked
    );

    // Approving backdated leave must clear stale ABSENT rows, or payroll's absence deduction and attendance % keep counting an absence the approval just excused.
    @Modifying
    @Query("""
        UPDATE Attendance a SET a.status = :onLeave
        WHERE a.employee.id = :employeeId
          AND a.attendanceDate BETWEEN :start AND :end
          AND a.status = :absent
          AND a.deleted = false
        """)
    int reconcileAbsentToOnLeave(
        @Param("employeeId") Long employeeId,
        @Param("start") LocalDate start,
        @Param("end") LocalDate end,
        @Param("absent") AttendanceStatus absent,
        @Param("onLeave") AttendanceStatus onLeave
    );
}