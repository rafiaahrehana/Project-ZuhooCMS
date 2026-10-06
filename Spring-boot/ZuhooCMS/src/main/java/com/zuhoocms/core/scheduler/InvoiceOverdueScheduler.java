package com.zuhoocms.core.scheduler;

import com.zuhoocms.enums.NotificationType;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.modules.finance.invoice.ClientInvoice;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRepository;
import com.zuhoocms.shared.notification.CreateNotificationRequest;
import com.zuhoocms.shared.notification.NotificationRepository;
import com.zuhoocms.shared.notification.NotificationService;
import lombok.RequiredArgsConstructor;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import lombok.extern.slf4j.Slf4j;

import com.zuhoocms.enums.InvoiceStatus;
import java.time.LocalDate;
import java.util.List;
import java.time.LocalDateTime;

@Component
@RequiredArgsConstructor
@Slf4j
public class InvoiceOverdueScheduler {

    private final ClientInvoiceRepository invoiceRepository;
    private final NotificationRepository  notificationRepository;
    private final CompanyRepository companyRepository;
    private final NotificationService notificationService;
    private final PlatformTransactionManager transactionManager;

    private static final List<InvoiceStatus> OVERDUE_ELIGIBLE =
            List.of(InvoiceStatus.ISSUED, InvoiceStatus.PARTIALLY_PAID);

    /**
     * Flips overdue invoices and notifies the owner once per invoice - a flipped invoice is no longer in an eligible status.
     * Per-entity, not a bulk JPQL UPDATE: that skipped the deleted filter and bypassed @Version, putting a just-PAID invoice back to OVERDUE.
     */
    @Scheduled(cron = "0 30 1 * * *")
    public void markOverdueInvoices() {
        LocalDate today = LocalDate.now();
        List<Long> candidateIds = invoiceRepository.findNewlyOverdue(today, OVERDUE_ELIGIBLE)
                .stream().map(ClientInvoice::getId).toList();

        TransactionTemplate perInvoice = new TransactionTemplate(transactionManager);
        perInvoice.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);

        for (Long id : candidateIds) {
            ClientInvoice flipped;
            try {
                flipped = perInvoice.execute(status -> {
                    // Re-read inside the transaction: the invoice may have been paid, cancelled or deleted since the candidate query ran.
                    ClientInvoice invoice = invoiceRepository.findById(id).orElse(null);
                    if (invoice == null
                            || !OVERDUE_ELIGIBLE.contains(invoice.getStatus())
                            || invoice.getDueDate() == null
                            || !invoice.getDueDate().isBefore(today)) {
                        return null;
                    }
                    invoice.setStatus(InvoiceStatus.OVERDUE);
                    return invoiceRepository.saveAndFlush(invoice); // version-checked UPDATE
                });
            } catch (Exception e) {
                log.warn("Overdue sweep: could not mark invoice {} overdue: {}", id, e.getMessage());
                continue;
            }
            if (flipped == null) {
                continue;
            }
            try {
                // Own transaction: lazy company/owner need a session, and a failed notification must not undo the committed status change.
                final ClientInvoice notifyFor = flipped;
                perInvoice.executeWithoutResult(status -> notifyOwner(notifyFor));
            } catch (Exception e) {
                log.warn("Overdue sweep: invoice {} marked overdue but owner notification failed: {}",
                        id, e.getMessage());
            }
        }
    }

    private void notifyOwner(ClientInvoice invoice) {
        Company company = companyRepository.findById(invoice.getCompanyId()).orElse(null);
        if (company == null || company.getOwner() == null) return;

        notificationService.send(CreateNotificationRequest.of(
                NotificationType.PAYMENT_DUE,
                "Invoice overdue",
                "Invoice " + invoice.getInvoiceNumber() + " (" + invoice.getBalanceAmount()
                        + " outstanding) was due " + invoice.getDueDate() + " and is now overdue.",
                "/finance/invoices",
                company.getOwner().getId(),
                company.getId()));
    }

    /** Cleans up read notifications older than 90 days. */
    @Scheduled(cron = "0 30 3 1 * *")
    @Transactional
    public void cleanOldNotifications() {
        LocalDateTime cutoff = LocalDateTime.now().minusDays(90);
        int count = notificationRepository.deleteReadOlderThan(cutoff);
        if (count > 0) {
            log.info("Notification cleanup: removed {} read notifications older than {}", count, cutoff.toLocalDate());
        }
    }
}
