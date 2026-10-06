package com.zuhoocms.modules.itam.software;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "software_licenses", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "license_key"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class SoftwareLicense extends BaseEntity {

    /** Same window the scheduler uses: expiring soon = expiry date between today and today+30, inclusive. */
    public static final int EXPIRING_SOON_WINDOW_DAYS = 30;

    private Long companyId;

    @Column(name = "license_key", nullable = false)
    private String licenseKey;

    private String softwareName;
    private String publisher;
    private String version;

    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private LicenseType licenseType;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private LicenseStatus licenseStatus = LicenseStatus.ACTIVE;

    // seatsUsed/seatsAvailable are a denormalised cache: some rows hold counts with no seat records, so the real count comes from software_license_seats (released_at IS NULL).
    private int totalSeatsLicensed;
    private int seatsUsed;
    private int seatsAvailable;

    private LocalDate licensePurchaseDate;
    private BigDecimal licenseCost;

    private LocalDate licenseExpiryDate;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private LicenseRenewalType renewalType = LicenseRenewalType.ANNUAL;

    private LocalDate nextRenewalDate;
    private BigDecimal renewalCost;

    private String vendor;
    private String accountEmail;
    private String licenseUrl;

    // username / password_hash columns still exist in the table but were never read or written, so they are no longer mapped.

    private String installationLocation;
    private int estimatedUserCount;
    private String complianceNotes;

    private String notes;
    private String renewalNotes;

    @Builder.Default
    private boolean active = true;

    @Builder.Default
    private boolean autoRenew = true;

    public boolean isExpiringSoon() {
        if (licenseExpiryDate == null) return false;
        LocalDate today = LocalDate.now();
        return !licenseExpiryDate.isBefore(today)
                && !licenseExpiryDate.isAfter(today.plusDays(EXPIRING_SOON_WINDOW_DAYS));
    }

    public boolean isExpired() {
        return licenseExpiryDate != null && licenseExpiryDate.isBefore(LocalDate.now());
    }

    /** Days until expiry, or null for a licence with no expiry date (perpetual/open source). */
    public Long getDaysUntilExpiry() {
        if (licenseExpiryDate == null) return null;
        return ChronoUnit.DAYS.between(LocalDate.now(), licenseExpiryDate);
    }

    /** Status implied by an expiry date alone (ACTIVE / EXPIRING_SOON / EXPIRED), matching the scheduler. */
    public static LicenseStatus statusForExpiry(LocalDate expiryDate, LocalDate today) {
        if (expiryDate == null) return LicenseStatus.ACTIVE;
        if (expiryDate.isBefore(today)) return LicenseStatus.EXPIRED;
        if (!expiryDate.isAfter(today.plusDays(EXPIRING_SOON_WINDOW_DAYS))) return LicenseStatus.EXPIRING_SOON;
        return LicenseStatus.ACTIVE;
    }

    /** Recomputes status from the expiry date, unless it was set by hand to SUSPENDED/REVOKED. */
    public void recomputeStatusFromExpiry() {
        if (licenseStatus == LicenseStatus.SUSPENDED || licenseStatus == LicenseStatus.REVOKED) return;
        licenseStatus = statusForExpiry(licenseExpiryDate, LocalDate.now());
    }

    /** Refreshes the cached counters from the real (seat-record) count. */
    public void applySeatCounts(long activeSeats) {
        this.seatsUsed = (int) activeSeats;
        this.seatsAvailable = (int) Math.max(0, totalSeatsLicensed - activeSeats);
    }
}
