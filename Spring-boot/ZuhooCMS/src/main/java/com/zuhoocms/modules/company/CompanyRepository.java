package com.zuhoocms.modules.company;

import com.zuhoocms.enums.CompanyStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface CompanyRepository extends JpaRepository<Company, Long> {

    Optional<Company> findBySubdomain(String subdomain);

    Optional<Company> findByOwnerId(Long userId);

    boolean existsBySubdomain(String subdomain);

    /** Case-insensitive, and counts soft-deleted companies too - they still hold the unique subdomain. */
    @Query(value = "select exists(select 1 from companies where lower(subdomain) = lower(:subdomain))", nativeQuery = true)
    boolean existsAnyBySubdomain(@Param("subdomain") String subdomain);

    Page<Company> findByStatus(CompanyStatus status, Pageable pageable);

    /** Public company picker: verified-owner ACTIVE/TRIAL tenants, minus the platform and demo tenants, with the logo joined in to avoid an N+1. */
    @Query("""
        SELECT new com.zuhoocms.modules.company.CompanyPublicListItem(c.id, c.companyName, c.subdomain, ws.logoUrl)
        FROM Company c JOIN c.owner o
        LEFT JOIN com.zuhoocms.modules.website.WebsiteSettings ws ON ws.companyId = c.id
        WHERE c.status IN :statuses AND c.isPlatformTenant = false
          AND (o.emailVerified = true OR c.status = com.zuhoocms.enums.CompanyStatus.ACTIVE)
          AND o.id <> :excludedOwnerId
        ORDER BY c.companyName ASC, c.id ASC
        """)
    List<CompanyPublicListItem> findPublicList(@Param("statuses") List<CompanyStatus> statuses,
                                               @Param("excludedOwnerId") Long excludedOwnerId,
                                               Pageable pageable);

    /** Companies a prospective client can register under (public registration picker). */
    List<Company> findByStatusInOrderByCompanyNameAsc(List<CompanyStatus> statuses);

    Page<Company> findBySubscriptionPlan(String plan, Pageable pageable);

    /** Null-safe filtering: any of status/plan/keyword may be omitted; keyword matches name, email or subdomain case-insensitively. */
    @Query("""
        SELECT c FROM Company c
        WHERE (:status IS NULL OR c.status = :status)
          AND (:plan IS NULL OR c.subscriptionPlan = :plan)
          AND (:keyword IS NULL OR :keyword = ''
               OR LOWER(c.companyName) LIKE LOWER(CONCAT('%', :keyword, '%'))
               OR LOWER(c.companyEmail) LIKE LOWER(CONCAT('%', :keyword, '%'))
               OR LOWER(c.subdomain) LIKE LOWER(CONCAT('%', :keyword, '%')))
        """)
    Page<Company> findFiltered(
        @Param("status") CompanyStatus status,
        @Param("plan") String plan,
        @Param("keyword") String keyword,
        Pageable pageable);

    /** Enums are passed as typed parameters: a JPQL string literal ('TRIAL') does not reliably compare against an @Enumerated(STRING) column. */
    @Query("""
        SELECT c FROM Company c
        WHERE c.subscriptionEnd < :today
          AND c.status IN :statuses
          AND c.deleted = false
          AND c.isPlatformTenant = false
        """)
    List<Company> findExpiredSubscriptions(
        @Param("today") LocalDate today,
        @Param("statuses") List<CompanyStatus> statuses
    );

    @Query("""
        SELECT c FROM Company c
        WHERE c.subscriptionEnd <= :cutoffDate
          AND c.subscriptionEnd >= :today
          AND c.status = :status
          AND c.trialReminderSentAt IS NULL
          AND c.deleted = false
          AND c.isPlatformTenant = false
        """)
    List<Company> findTrialExpiringBetween(
        @Param("today") LocalDate today,
        @Param("cutoffDate") LocalDate cutoffDate,
        @Param("status") CompanyStatus status
    );

    /** Self sign-ups whose owner never verified, registered before the cutoff (UnverifiedSignupCleanupJob); platform tenant excluded, owner fetched in the same query. */
    @Query("""
        SELECT c FROM Company c JOIN FETCH c.owner o
        WHERE o.role = com.zuhoocms.auth.role.enums.Role.COMPANY_OWNER AND o.emailVerified = false
          AND o.createdAt < :cutoff AND c.status IN :statuses AND c.isPlatformTenant = false
        """)
    List<Company> findStaleUnverifiedSignups(@Param("cutoff") java.time.LocalDateTime cutoff,
                                             @Param("statuses") List<CompanyStatus> statuses);

    /** Platform KPIs over real tenants only: excludes the platform tenant, the demo (owner id passed in) and unverified TRIAL/PENDING_VERIFICATION sign-ups; status/plan optional. */
    @Query("""
        SELECT COUNT(c) FROM Company c JOIN c.owner o
        WHERE c.isPlatformTenant = false AND o.id <> :excludedOwnerId
          AND NOT (o.emailVerified = false AND c.status IN (com.zuhoocms.enums.CompanyStatus.TRIAL,
                                                           com.zuhoocms.enums.CompanyStatus.PENDING_VERIFICATION))
          AND (:status IS NULL OR c.status = :status)
          AND (:plan IS NULL OR c.subscriptionPlan = :plan)
        """)
    long countTenants(@Param("status") CompanyStatus status, @Param("plan") String plan,
                      @Param("excludedOwnerId") Long excludedOwnerId);

    @Query("""
        SELECT COUNT(c) FROM Company c JOIN c.owner o
        WHERE c.isPlatformTenant = false AND o.id <> :excludedOwnerId AND o.emailVerified = true
          AND c.status = com.zuhoocms.enums.CompanyStatus.TRIAL
          AND c.subscriptionEnd BETWEEN :from AND :to
        """)
    long countTenantTrialsEndingBetween(@Param("from") LocalDate from, @Param("to") LocalDate to,
                                        @Param("excludedOwnerId") Long excludedOwnerId);

    long countByStatus(CompanyStatus status);

    long countBySubscriptionPlan(String plan);

    long countByStatusAndSubscriptionEndBetween(CompanyStatus status, LocalDate from, LocalDate to);
}
