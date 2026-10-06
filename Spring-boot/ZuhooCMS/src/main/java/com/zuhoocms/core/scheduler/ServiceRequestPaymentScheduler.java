package com.zuhoocms.core.scheduler;

import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRepository;
import com.zuhoocms.modules.finance.invoice.ClientInvoice;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestService;
import com.zuhoocms.enums.InvoiceStatus;
import com.zuhoocms.shared.email.EmailBranding;
import com.zuhoocms.shared.email.EmailService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * Unpaid service-request invoices: a reminder after 48h, automatic cancellation after 72h.
 * Not @Transactional: in one batch transaction a single bad row rolled back every reminder stamp and cancellation of that run.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ServiceRequestPaymentScheduler {

    private static final List<ServiceRequestStatus> AWAITING_PAYMENT_STATUSES =
        List.of(ServiceRequestStatus.PENDING, ServiceRequestStatus.WAITING_CLIENT);

    // Invoice states still owed: PAID needs nothing and CANCELLED/VOIDED/REFUNDED are no longer collectable.
    private static final List<InvoiceStatus> OUTSTANDING_INVOICE_STATUSES =
        List.of(InvoiceStatus.DRAFT, InvoiceStatus.ISSUED, InvoiceStatus.PARTIALLY_PAID, InvoiceStatus.OVERDUE);

    private final ServiceRequestRepository serviceRequestRepository;
    private final ServiceRequestService serviceRequestService;
    private final ClientInvoiceRepository invoiceRepository;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final PlatformTransactionManager transactionManager;

    /** Hours a request may sit unpaid before the reminder goes out; the default is the long-standing 48. */
    @Value("${app.servicerequest.payment.reminder-hours:48}")
    private long reminderHours;

    /** Hours a request may sit unpaid before it is cancelled; the default is the long-standing 72. */
    @Value("${app.servicerequest.payment.deadline-hours:72}")
    private long deadlineHours;

    /** Reminds on everything older than the reminder window and not yet stamped paymentReminderSentAt: the old exact [now-49h, now-48h] window dropped requests whose hour a delayed run missed. */
    @Scheduled(cron = "${app.servicerequest.payment.reminder-cron:0 0 * * * *}")
    public void sendPaymentReminders() {
        LocalDateTime cutoff = LocalDateTime.now().minusHours(reminderHours);

        List<ServiceRequest> requests = serviceRequestRepository
            .findAllByStatusInAndCreatedAtBeforeAndPaymentReminderSentAtIsNull(AWAITING_PAYMENT_STATUSES, cutoff);

        TransactionTemplate perItem = newTransaction();
        int sent = 0, failed = 0;
        for (ServiceRequest candidate : requests) {
            Long requestId = candidate.getId();
            try {
                Boolean didSend = perItem.execute(status -> remindOne(requestId, cutoff));
                if (Boolean.TRUE.equals(didSend)) sent++;
            } catch (Exception e) {
                failed++;
                log.error("Payment reminder failed for ServiceRequest {}: {}", requestId, e.getMessage(), e);
            }
        }
        if (sent > 0 || failed > 0) {
            log.info("Service request payment reminders: {} sent, {} failed (of {} candidates)", sent, failed, requests.size());
        }
    }

    private boolean remindOne(Long requestId, LocalDateTime cutoff) {
        ServiceRequest req = serviceRequestRepository.findById(requestId).orElse(null);
        if (req == null || req.getPaymentReminderSentAt() != null || req.getInvoiceId() == null
                || !AWAITING_PAYMENT_STATUSES.contains(req.getStatus())) {
            return false;
        }
        ClientInvoice invoice = outstandingInvoice(req).orElse(null);
        // The invoice itself must also be 48h old, so one raised later gets its own full grace period.
        if (invoice == null || invoice.getCreatedAt() == null || invoice.getCreatedAt().isAfter(cutoff)) {
            return false;
        }
        if (req.getClient() == null || req.getClient().getUser() == null) {
            return false;
        }

        EmailBranding.Data branding = emailBranding.from(req.getCompany());
        emailService.sendServiceRequestPaymentReminderEmail(
            req.getClient().getUser().getEmail(),
            req.getClient().getUser().getFirstName(),
            req.getTitle(),
            branding
        );
        req.setPaymentReminderSentAt(LocalDateTime.now());
        serviceRequestRepository.save(req);
        return true;
    }

    /** Cancels requests past the payment deadline whose invoice (itself past it) is still unpaid; each cancellation gets its own transaction from systemCancelForNonPayment. */
    @Scheduled(cron = "${app.servicerequest.payment.cancel-cron:0 30 * * * *}")
    public void cancelUnpaidRequests() {
        LocalDateTime cutoff = LocalDateTime.now().minusHours(deadlineHours);

        List<ServiceRequest> requests = serviceRequestRepository
            .findAllByStatusInAndCreatedAtBefore(AWAITING_PAYMENT_STATUSES, cutoff);

        int cancelled = 0, failed = 0;
        for (ServiceRequest req : requests) {
            if (req.getInvoiceId() == null) continue;
            try {
                Optional<ClientInvoice> invoice = outstandingInvoice(req);
                if (invoice.isEmpty() || invoice.get().getCreatedAt() == null
                        || invoice.get().getCreatedAt().isAfter(cutoff)) {
                    continue;
                }
                // The real cancellation path: status history, quota release, invoice cancel/refund and the client notification.
                serviceRequestService.systemCancelForNonPayment(req.getId(), deadlineHours);
                cancelled++;
            } catch (Exception e) {
                failed++;
                log.error("Cancellation failed for unpaid ServiceRequest {}: {}", req.getId(), e.getMessage(), e);
            }
        }
        if (cancelled > 0 || failed > 0) {
            log.info("Unpaid service request sweep: {} cancelled, {} failed", cancelled, failed);
        }
    }

    private Optional<ClientInvoice> outstandingInvoice(ServiceRequest req) {
        return invoiceRepository.findById(req.getInvoiceId())
            .filter(inv -> OUTSTANDING_INVOICE_STATUSES.contains(inv.getStatus()));
    }

    private TransactionTemplate newTransaction() {
        TransactionTemplate template = new TransactionTemplate(transactionManager);
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return template;
    }
}
