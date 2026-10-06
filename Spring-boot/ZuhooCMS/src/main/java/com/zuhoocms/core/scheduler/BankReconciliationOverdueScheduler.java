package com.zuhoocms.core.scheduler;

import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.finance.reconciliation.BankReconciliation;
import com.zuhoocms.modules.finance.reconciliation.BankReconciliationRepository;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;

/** Notifies the company owner once a reconciliation has been unreconciled for OVERDUE_DAYS; otherwise it only surfaced when someone visited the Bank Reconciliation page. */
@Component
@RequiredArgsConstructor
public class BankReconciliationOverdueScheduler {

    private static final int OVERDUE_DAYS = 7;

    private final BankReconciliationRepository reconciliationRepository;
    private final CompanyRepository companyRepository;
    private final NotificationService notificationService;

    @Scheduled(cron = "0 0 8 * * *")
    @Transactional
    public void flagOverdueReconciliations() {
        LocalDate today = LocalDate.now();
        LocalDate threshold = today.minusDays(OVERDUE_DAYS);

        for (Company company : companyRepository.findAll()) {
            if (company.isPlatformTenant() || company.getOwner() == null) continue;

            // Whole backlog, not an exact-day match that lost a skipped run's reminders; overdueNotifiedAt keeps it to one reminder each.
            List<BankReconciliation> overdue = reconciliationRepository
                    .findByCompanyIdAndReconciledFalseAndOverdueNotifiedAtIsNullAndReconciliationDateLessThanEqual(
                            company.getId(), threshold);

            for (BankReconciliation reconciliation : overdue) {
                String accountName = reconciliation.getBankAccount() != null
                        ? reconciliation.getBankAccount().getAccountName() : "a bank account";
                long daysPending = ChronoUnit.DAYS.between(reconciliation.getReconciliationDate(), today);
                notificationService.send(CreateNotificationRequest.of(
                        NotificationType.RECONCILIATION_OVERDUE,
                        "Bank reconciliation overdue",
                        "The reconciliation for " + accountName + " dated " + reconciliation.getReconciliationDate()
                                + " has been pending for " + daysPending + " days.",
                        "/finance/bank-reconciliation",
                        company.getOwner().getId(),
                        company.getId()));

                // Stamp AFTER a successful send so a failed notification is retried tomorrow.
                reconciliation.setOverdueNotifiedAt(LocalDateTime.now());
                reconciliationRepository.save(reconciliation);
            }
        }
    }
}
