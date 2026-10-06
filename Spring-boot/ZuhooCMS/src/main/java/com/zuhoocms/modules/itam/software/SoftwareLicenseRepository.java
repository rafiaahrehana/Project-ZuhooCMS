package com.zuhoocms.modules.itam.software;

import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface SoftwareLicenseRepository extends JpaRepository<SoftwareLicense, Long> {

    Optional<SoftwareLicense> findByLicenseKey(String licenseKey);
    Optional<SoftwareLicense> findByCompanyIdAndLicenseKey(Long companyId, String licenseKey);
    Optional<SoftwareLicense> findByIdAndCompanyId(Long id, Long companyId);

    /** Locked lookup for assignSeat()/releaseSeat() - prevents a lost update on seatsUsed/seatsAvailable under concurrent seat operations. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT s FROM SoftwareLicense s WHERE s.id = :id AND s.companyId = :companyId")
    Optional<SoftwareLicense> findByIdAndCompanyIdForUpdate(@Param("id") Long id, @Param("companyId") Long companyId);

    Page<SoftwareLicense> findByCompanyIdAndLicenseStatus(Long companyId, LicenseStatus status, Pageable pageable);
    Page<SoftwareLicense> findByCompanyId(Long companyId, Pageable pageable);

    @Query("SELECT s FROM SoftwareLicense s WHERE s.companyId = :companyId AND s.licenseExpiryDate BETWEEN :start AND :end")
    List<SoftwareLicense> findExpiringBetweenDates(@Param("companyId") Long companyId, @Param("start") LocalDate start, @Param("end") LocalDate end);

    /** Expiry passed OR status EXPIRED, so licences the scheduler already transitioned still show up. */
    @Query("SELECT s FROM SoftwareLicense s WHERE s.companyId = :companyId " +
           "AND (s.licenseExpiryDate < :date OR s.licenseStatus = com.zuhoocms.modules.itam.software.LicenseStatus.EXPIRED) " +
           "ORDER BY s.licenseExpiryDate ASC NULLS LAST, s.id ASC")
    List<SoftwareLicense> findExpiredLicenses(@Param("companyId") Long companyId, @Param("date") LocalDate date);

    /** Auto-renewing licences past expiry, renewed instead of marked EXPIRED; returns [id, companyId] only so each is reloaded under its row lock. */
    @Query("""
        SELECT s.id, s.companyId FROM SoftwareLicense s
        WHERE s.autoRenew = true
          AND s.renewalType IS NOT NULL
          AND s.renewalType <> com.zuhoocms.modules.itam.software.LicenseRenewalType.PERPETUAL
          AND s.licenseStatus IN :activeStatuses
          AND s.licenseExpiryDate < :today
          AND s.deleted = false
        """)
    List<Object[]> findAutoRenewDue(
        @Param("activeStatuses") List<LicenseStatus> activeStatuses,
        @Param("today") LocalDate today);

    long countByCompanyIdAndLicenseStatus(Long companyId, LicenseStatus status);

    /** Queried BEFORE the bulk update below so only the licences that just entered the window are notified, once rather than daily. */
    @Query("""
        SELECT s FROM SoftwareLicense s
        WHERE s.licenseStatus = :active
          AND s.licenseExpiryDate BETWEEN :today AND :cutoff
          AND s.deleted = false
        """)
    List<SoftwareLicense> findNewlyEnteringExpiringSoon(
        @Param("active") LicenseStatus active,
        @Param("today") LocalDate today,
        @Param("cutoff") LocalDate cutoff);

    @Modifying
    @Query("""
        UPDATE SoftwareLicense s SET s.licenseStatus = :expiringSoon
        WHERE s.licenseStatus = :active
          AND s.licenseExpiryDate BETWEEN :today AND :cutoff
          AND s.deleted = false
        """)
    int bulkMarkExpiringSoon(
        @Param("expiringSoon") LicenseStatus expiringSoon,
        @Param("active") LicenseStatus active,
        @Param("today") LocalDate today,
        @Param("cutoff") LocalDate cutoff);

    /** Past expiry but not yet EXPIRED; queried BEFORE the bulk update below for the same one-time-notify reason. */
    @Query("""
        SELECT s FROM SoftwareLicense s
        WHERE s.licenseStatus IN :activeStatuses
          AND s.licenseExpiryDate < :today
          AND s.deleted = false
        """)
    List<SoftwareLicense> findNewlyExpired(
        @Param("activeStatuses") List<LicenseStatus> activeStatuses,
        @Param("today") LocalDate today);

    @Modifying
    @Query("""
        UPDATE SoftwareLicense s SET s.licenseStatus = :expired
        WHERE s.licenseStatus IN :activeStatuses
          AND s.licenseExpiryDate < :today
          AND s.deleted = false
        """)
    int bulkMarkExpired(
        @Param("expired") LicenseStatus expired,
        @Param("activeStatuses") List<LicenseStatus> activeStatuses,
        @Param("today") LocalDate today);
}