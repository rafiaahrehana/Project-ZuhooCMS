package com.zuhoocms.core.scheduler;

import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.itam.software.LicenseRenewalType;
import com.zuhoocms.modules.itam.software.LicenseStatus;
import com.zuhoocms.modules.itam.software.SoftwareLicense;
import com.zuhoocms.modules.itam.software.SoftwareLicenseRepository;
import com.zuhoocms.modules.itam.software.SoftwareLicenseSeatRepository;
import com.zuhoocms.shared.email.EmailService;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;

/**
 * Transitions licence status daily and notifies the owner only when a licence newly crosses into a state, not every day after.
 * autoRenew (non-PERPETUAL) past expiry advances expiry and nextRenewalDate by whole periods until today or later.
 * ACTIVE -> EXPIRING_SOON within 30 days of licenseExpiryDate (today and day 30 included); ACTIVE/EXPIRING_SOON -> EXPIRED past it.
 */
@Component
@RequiredArgsConstructor
public class LicenseExpiryScheduler {

    private static final int EXPIRING_SOON_WINDOW_DAYS = SoftwareLicense.EXPIRING_SOON_WINDOW_DAYS;
    private static final List<LicenseStatus> ACTIVE_STATUSES =
            List.of(LicenseStatus.ACTIVE, LicenseStatus.EXPIRING_SOON);

    private final SoftwareLicenseRepository licenseRepository;
    private final SoftwareLicenseSeatRepository seatRepository;
    private final CompanyRepository companyRepository;
    private final NotificationService notificationService;
    private final EmailService emailService;

    @Scheduled(cron = "0 0 8 * * *")
    @Transactional
    public void processLicenseExpiry() {
        LocalDate today = LocalDate.now();
        LocalDate cutoff = today.plusDays(EXPIRING_SOON_WINDOW_DAYS);

        // Auto-renew first, so those licences never pass through EXPIRED.
        for (Object[] due : licenseRepository.findAutoRenewDue(ACTIVE_STATUSES, today)) {
            autoRenew((Long) due[0], (Long) due[1], today);
        }

        List<SoftwareLicense> newlyExpiringSoon = licenseRepository
                .findNewlyEnteringExpiringSoon(LicenseStatus.ACTIVE, today, cutoff);
        licenseRepository.bulkMarkExpiringSoon(LicenseStatus.EXPIRING_SOON, LicenseStatus.ACTIVE, today, cutoff);

        for (SoftwareLicense license : newlyExpiringSoon) {
            alertOwner(license, NotificationType.LICENSE_EXPIRING);
        }

        List<SoftwareLicense> newlyExpired = licenseRepository.findNewlyExpired(ACTIVE_STATUSES, today);
        licenseRepository.bulkMarkExpired(LicenseStatus.EXPIRED, ACTIVE_STATUSES, today);

        for (SoftwareLicense license : newlyExpired) {
            alertOwner(license, NotificationType.LICENSE_EXPIRED);
        }
    }

    /** Re-reads the licence under its row lock (a concurrent edit may have renewed or changed it). */
    private void autoRenew(Long id, Long companyId, LocalDate today) {
        SoftwareLicense license = licenseRepository.findByIdAndCompanyIdForUpdate(id, companyId).orElse(null);
        if (license == null || !license.isAutoRenew() || license.getLicenseExpiryDate() == null
                || !license.getLicenseExpiryDate().isBefore(today)
                || !ACTIVE_STATUSES.contains(license.getLicenseStatus())) {
            return;
        }
        LicenseRenewalType type = license.getRenewalType();
        if (type == null || type == LicenseRenewalType.PERPETUAL) return;

        LocalDate expiry = license.getLicenseExpiryDate();
        LocalDate nextRenewal = license.getNextRenewalDate();
        while (expiry.isBefore(today)) {
            expiry = advance(expiry, type);
            if (nextRenewal != null) nextRenewal = advance(nextRenewal, type);
        }
        license.setLicenseExpiryDate(expiry);
        license.setNextRenewalDate(nextRenewal != null ? nextRenewal : expiry);
        license.recomputeStatusFromExpiry();
        licenseRepository.saveAndFlush(license);

        notifyRenewed(license);
    }

    private static LocalDate advance(LocalDate date, LicenseRenewalType type) {
        return switch (type) {
            case MONTHLY -> date.plusMonths(1);
            case BIENNIAL -> date.plusYears(2);
            default -> date.plusYears(1); // ANNUAL
        };
    }

    /** No "renewed" type or template exists, so this reuses LICENSE_EXPIRING with renewal wording and sends no email - the licence emails would read wrongly here. */
    private void notifyRenewed(SoftwareLicense license) {
        Company company = companyRepository.findById(license.getCompanyId()).orElse(null);
        if (company == null || company.getOwner() == null) return;
        notificationService.send(CreateNotificationRequest.of(
                NotificationType.LICENSE_EXPIRING, "Software license auto-renewed",
                license.getSoftwareName() + " was renewed automatically - new expiry date "
                        + license.getLicenseExpiryDate() + ". Turn off auto-renew if it should lapse instead.",
                "/itam/software", company.getOwner().getId(), company.getId()));
    }

    private void alertOwner(SoftwareLicense license, NotificationType type) {
        Company company = companyRepository.findById(license.getCompanyId()).orElse(null);
        if (company == null || company.getOwner() == null) return;

        String ownerEmail = company.getOwner().getEmail();
        String ownerName = company.getOwner().getFirstName();

        if (type == NotificationType.LICENSE_EXPIRING) {
            long daysLeft = license.getDaysUntilExpiry() != null ? license.getDaysUntilExpiry() : 0;
            notificationService.send(CreateNotificationRequest.of(
                    type, "Software license expiring soon",
                    license.getSoftwareName() + " expires on " + license.getLicenseExpiryDate()
                            + " (" + daysLeft + " days) - renew or cancel before it lapses.",
                    "/itam/software", company.getOwner().getId(), company.getId()));
            emailService.sendLicenseExpiryReminder(
                    ownerEmail, ownerName, license.getSoftwareName(),
                    license.getLicenseExpiryDate(), daysLeft);
        } else {
            // Real seat-record count - the stored seatsUsed column is only a cache.
            int seatsUsed = (int) seatRepository.countByLicenseIdAndReleasedAtIsNull(license.getId());
            notificationService.send(CreateNotificationRequest.of(
                    type, "Software license expired",
                    license.getSoftwareName() + " expired on " + license.getLicenseExpiryDate()
                            + " - " + seatsUsed + " assigned seat(s) may lose access.",
                    "/itam/software", company.getOwner().getId(), company.getId()));
            emailService.sendLicenseExpiredEmail(
                    ownerEmail, ownerName, license.getSoftwareName(),
                    license.getLicenseExpiryDate(), seatsUsed);
        }
    }
}
