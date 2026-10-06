package com.zuhoocms.modules.support.audit;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

import com.zuhoocms.enums.AuditAction;
import com.zuhoocms.shared.audit.AuditLog;

/**
 * Reads the shared audit_logs table: the company-scoped variants serve tenant callers, the unscoped ones platform reviewers who see every company.
 * performedBy is fetched with the row, since the mapper reads the name, to avoid one query per log line.
 */
@Repository
public interface SupportAuditLogRepository extends JpaRepository<AuditLog, Long> {
    List<AuditLog> findByEntityIdOrderByPerformedAtDesc(Long resourceId);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByCompanyId(Long companyId, Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByCompanyIdAndEntityId(Long companyId, Long resourceId, Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByCompanyIdAndAction(Long companyId, AuditAction action, Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    List<AuditLog> findTop500ByCompanyIdAndEntityIdOrderByPerformedAtDesc(Long companyId, Long resourceId);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByCompanyIdAndPerformedAtGreaterThanEqualAndPerformedAtLessThan(
            Long companyId, LocalDateTime startInclusive, LocalDateTime endExclusive, Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByCompanyIdAndPerformedById(Long companyId, Long userId, Pageable pageable);

    @Override
    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findAll(Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByAction(AuditAction action, Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    List<AuditLog> findTop500ByEntityIdOrderByPerformedAtDesc(Long resourceId);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByPerformedAtGreaterThanEqualAndPerformedAtLessThan(
            LocalDateTime startInclusive, LocalDateTime endExclusive, Pageable pageable);

    @EntityGraph(attributePaths = {"performedBy"})
    Page<AuditLog> findByPerformedById(Long userId, Pageable pageable);
}
