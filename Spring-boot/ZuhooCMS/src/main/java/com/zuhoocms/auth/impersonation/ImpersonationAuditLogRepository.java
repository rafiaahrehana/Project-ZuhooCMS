package com.zuhoocms.auth.impersonation;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface ImpersonationAuditLogRepository extends JpaRepository<ImpersonationAuditLog, Long> {

    @EntityGraph(attributePaths = {"admin", "company"})
    Optional<ImpersonationAuditLog> findByImpersonationSessionId(String impersonationSessionId);

    /** Per-request revocation check for impersonation tokens (JwtAuthFilter): ending a session invalidates its token immediately. */
    @Query("SELECT COUNT(l) > 0 FROM ImpersonationAuditLog l WHERE l.impersonationSessionId = :sessionId "
            + "AND l.admin.id = :adminId AND l.company.id = :companyId AND l.endedAt IS NULL")
    boolean isSessionActive(@Param("sessionId") String sessionId,
                            @Param("adminId") Long adminId,
                            @Param("companyId") Long companyId);

    // Read path for the impersonation compliance record, which would otherwise be written but never reviewed.
    @EntityGraph(attributePaths = {"admin", "company"})
    Page<ImpersonationAuditLog> findAllByOrderByStartedAtDesc(Pageable pageable);

    @EntityGraph(attributePaths = {"admin", "company"})
    Page<ImpersonationAuditLog> findByCompanyIdOrderByStartedAtDesc(Long companyId, Pageable pageable);
}
