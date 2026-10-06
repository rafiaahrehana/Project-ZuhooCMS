package com.zuhoocms.modules.hrm.payroll.loan;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface LoanAdvanceRepository extends JpaRepository<LoanAdvance, Long> {

    Optional<LoanAdvance> findByIdAndCompanyId(Long id, Long companyId);

    List<LoanAdvance> findByCompanyIdOrderByCreatedAtDesc(Long companyId);

    List<LoanAdvance> findByEmployeeIdOrderByCreatedAtDesc(Long employeeId);

    Optional<LoanAdvance> findFirstByEmployeeIdAndStatus(Long employeeId, LoanAdvance.Status status);

    boolean existsByEmployeeIdAndStatus(Long employeeId, LoanAdvance.Status status);

    /** Row-locked load used when a paid payroll settles an installment. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT l FROM LoanAdvance l WHERE l.id = :id")
    Optional<LoanAdvance> findByIdForUpdate(@Param("id") Long id);

    /** Locks every existing loan row of the employee while the one-active rule is checked. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT l FROM LoanAdvance l WHERE l.employee.id = :employeeId")
    List<LoanAdvance> lockAllForEmployee(@Param("employeeId") Long employeeId);
}
