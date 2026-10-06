package com.zuhoocms.modules.servicedesk.companyservice;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import com.zuhoocms.enums.SubscriptionStatus;
import jakarta.persistence.LockModeType;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface PackageSubscriptionRepository
        extends JpaRepository<PackageSubscription, Long> {

    Optional<PackageSubscription> findByIdAndCompanyId(Long id, Long companyId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM PackageSubscription s WHERE s.id = :id AND s.company.id = :companyId")
    Optional<PackageSubscription> findByIdAndCompanyIdForUpdate(@Param("id") Long id, @Param("companyId") Long companyId);

    Page<PackageSubscription> findByCompanyId(Long companyId, Pageable pageable);

    Page<PackageSubscription> findByCompanyIdAndStatus(
        Long companyId, SubscriptionStatus status, Pageable pageable);

    Page<PackageSubscription> findByCompanyIdAndClientId(
        Long companyId, Long clientId, Pageable pageable);

    /** Enforces the one-active-subscription-per-package rule. */
    Optional<PackageSubscription> findByCompanyIdAndClientIdAndServicePackageIdAndStatus(
        Long companyId, Long clientId, Long packageId, SubscriptionStatus status);

    List<PackageSubscription> findByCompanyIdAndClientIdAndStatus(
        Long companyId, Long clientId, SubscriptionStatus status);

    /** Still ACTIVE past endDate - the scheduler's auto-expire candidates. */
    @Query("""
        SELECT s FROM PackageSubscription s
        WHERE s.status = 'ACTIVE'
          AND s.endDate IS NOT NULL
          AND s.endDate < :today
          AND s.deleted = false
        """)
    List<PackageSubscription> findExpired(@Param("today") LocalDate today);

    /** Bulk-expire in one UPDATE rather than loading every row. */
    @Modifying
    @Query("""
        UPDATE PackageSubscription s SET s.status = 'EXPIRED'
        WHERE s.status = 'ACTIVE'
          AND s.endDate IS NOT NULL
          AND s.endDate < :today
          AND s.deleted = false
        """)
    int bulkExpireSubscriptions(@Param("today") LocalDate today);

    long countByCompanyIdAndStatus(Long companyId, SubscriptionStatus status);

    boolean existsByServicePackageIdAndStatus(Long packageId, SubscriptionStatus status);
}
