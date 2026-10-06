package com.zuhoocms.modules.itam.offboarding;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface OffboardingChecklistRepository extends JpaRepository<OffboardingChecklist, Long> {

    Optional<OffboardingChecklist> findByIdAndCompanyId(Long id, Long companyId);

    /** Locked re-read for the step PATCHes - taken after the employee row lock. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT c FROM OffboardingChecklist c WHERE c.id = :id AND c.companyId = :companyId")
    Optional<OffboardingChecklist> findByIdAndCompanyIdForUpdate(@Param("id") Long id, @Param("companyId") Long companyId);

    /** The checklist's employee id without loading (or locking) the checklist itself. */
    @Query("SELECT c.employee.id FROM OffboardingChecklist c WHERE c.id = :id AND c.companyId = :companyId")
    Optional<Long> findEmployeeIdByIdAndCompanyId(@Param("id") Long id, @Param("companyId") Long companyId);

    /** "First by createdAt" rather than a single-result lookup, so duplicates created before creation was serialised don't 500. */
    Optional<OffboardingChecklist> findFirstByEmployeeIdAndCompanyIdOrderByCreatedAtAscIdAsc(Long employeeId, Long companyId);

    Page<OffboardingChecklist> findByCompanyId(Long companyId, Pageable pageable);

    List<OffboardingChecklist> findByCompanyIdAndCompletedFalse(Long companyId, Pageable pageable);

    Page<OffboardingChecklist> findByCompanyIdAndOffboardingDateBetween(Long companyId, LocalDate start, LocalDate end, Pageable pageable);
}
