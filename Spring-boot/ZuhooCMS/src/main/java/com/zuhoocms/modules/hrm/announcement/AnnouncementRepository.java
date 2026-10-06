package com.zuhoocms.modules.hrm.announcement;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import com.zuhoocms.modules.hrm.employee.Employee;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface AnnouncementRepository extends JpaRepository<Announcement, Long> {

    Optional<Announcement> findByIdAndCompanyId(Long id, Long companyId);

    Page<Announcement> findByCompanyId(Long companyId, Pageable pageable);

    @Query("""
        SELECT a FROM Announcement a
        WHERE a.company.id = :companyId
          AND a.published = true
          AND (a.expiresAt IS NULL OR a.expiresAt > :now)
          AND a.deleted = false
        ORDER BY a.publishedAt DESC
        """)
    List<Announcement> findActiveByCompanyId(
        @Param("companyId") Long companyId,
        @Param("now") LocalDateTime now);

    // Cross-company: runs outside an HTTP request context (scheduler), as in LicenseExpiryScheduler.
    List<Announcement> findByPublishedFalseAndDeletedFalseAndScheduledAtLessThanEqual(LocalDateTime now);

    /** Conditional publish: returns 1 only for the caller that flipped published, so a manual publish racing the scheduler can't notify twice. */
    @Modifying
    @Query("""
        UPDATE Announcement a SET a.published = true, a.publishedAt = :now
        WHERE a.id = :id AND a.published = false AND a.deleted = false
        """)
    int markPublishedIfUnpublished(@Param("id") Long id, @Param("now") LocalDateTime now);

    @Query("SELECT e FROM Employee e WHERE e.company.id = :companyId AND e.active = true AND e.deleted = false")
    Page<Employee> findActiveEmployees(@Param("companyId") Long companyId, Pageable pageable);

    @Query("""
        SELECT e FROM Employee e
        WHERE e.company.id = :companyId AND e.department.id = :departmentId
          AND e.active = true AND e.deleted = false
        """)
    Page<Employee> findActiveEmployeesInDepartment(@Param("companyId") Long companyId,
                                                   @Param("departmentId") Long departmentId,
                                                   Pageable pageable);
}
