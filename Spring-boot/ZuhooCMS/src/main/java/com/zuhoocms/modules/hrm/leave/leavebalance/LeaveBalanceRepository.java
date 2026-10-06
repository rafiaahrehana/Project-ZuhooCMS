package com.zuhoocms.modules.hrm.leave.leavebalance;

import com.zuhoocms.enums.LeaveType;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface LeaveBalanceRepository extends JpaRepository<LeaveBalance, Long> {

    List<LeaveBalance> findByEmployeeIdAndYear(Long employeeId, int year);

    Optional<LeaveBalance> findByEmployeeIdAndLeaveTypeAndYear(
        Long employeeId, LeaveType leaveType, int year);

    /** Row-locked variant so concurrent apply/review/cancel can't lose pending/used updates. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT b FROM LeaveBalance b WHERE b.employee.id = :employeeId AND b.leaveType = :leaveType AND b.year = :year")
    Optional<LeaveBalance> findForUpdate(@Param("employeeId") Long employeeId,
                                         @Param("leaveType") LeaveType leaveType,
                                         @Param("year") int year);

    /** Un-deletes a soft-deleted row so create can reuse it instead of hitting the unique constraint. */
    @Modifying
    @Query(nativeQuery = true, value = "update leave_balances set deleted = false, deleted_at = null "
            + "where employee_id = :employeeId and leave_type = :leaveType and year = :year and deleted = true")
    int reviveDeleted(@Param("employeeId") Long employeeId,
                      @Param("leaveType") String leaveType,
                      @Param("year") int year);

    List<LeaveBalance> findByCompanyIdAndYear(Long companyId, int year);

    Page<LeaveBalance> findByCompanyIdAndYear(Long companyId, int year, Pageable pageable);

    Optional<LeaveBalance> findByIdAndCompanyId(Long id, Long companyId);
}
