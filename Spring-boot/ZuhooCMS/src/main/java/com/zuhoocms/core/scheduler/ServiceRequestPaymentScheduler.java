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
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.shared.exception.BadRequestException;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Component
@RequiredArgsConstructor
public class ServiceRequestPaymentScheduler {

    private final ServiceRequestRepository serviceRequestRepository;
    private final ServiceRequestService serviceRequestService;
    private final ClientInvoiceRepository invoiceRepository;
    private final EmailService emailService;
    private final EmailBranding emailBranding;
    private final CompanyRepository companyRepository;

    /**
     * Run every hour.
     * Check for requests that are older than 48 hours but less than 49 hours.
     * Send payment reminder.
     */
    @Scheduled(cron = "0 0 * * * *")
    @Transactional
    public void sendPaymentReminders() {
        
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime lowerBound = now.minusHours(49);
        LocalDateTime upperBound = now.minusHours(48);

        List<ServiceRequest> requests = serviceRequestRepository.findAllByStatusInAndCreatedAtBetween(
            List.of(ServiceRequestStatus.PENDING, ServiceRequestStatus.WAITING_CLIENT),
            lowerBound,
            upperBound
        );

        for (ServiceRequest req : requests) {
            if (req.getInvoiceId() != null) {
                Optional<ClientInvoice> invoiceOpt = invoiceRepository.findById(req.getInvoiceId());
                if (invoiceOpt.isPresent() && invoiceOpt.get().getStatus() != InvoiceStatus.PAID) {
                    try {
                        EmailBranding.Data branding = emailBranding.from(req.getCompany());
                        emailService.sendServiceRequestPaymentReminderEmail(
                            req.getClient().getUser().getEmail(),
                            req.getClient().getUser().getFirstName(),
                            req.getTitle(),
                            branding
                        );
                    } catch (Exception e) {
                        throw new BadRequestException("Payment reminder failed for ServiceRequest: " + req.getId() + " - " + e.getMessage());
                    }
                }
            }
        }
    }

    /**
     * Run every hour.
     * Check for requests that are older than 72 hours.
     * Cancel the request if invoice is not paid.
     */
    @Scheduled(cron = "0 30 * * * *")
    @Transactional
    public void cancelUnpaidRequests() {
        
        LocalDateTime cutoff = LocalDateTime.now().minusHours(72);

        List<ServiceRequest> requests = serviceRequestRepository.findAllByStatusInAndCreatedAtBefore(
            List.of(ServiceRequestStatus.PENDING, ServiceRequestStatus.WAITING_CLIENT),
            cutoff
        );

        for (ServiceRequest req : requests) {
            if (req.getInvoiceId() != null) {
                Optional<ClientInvoice> invoiceOpt = invoiceRepository.findById(req.getInvoiceId());
                if (invoiceOpt.isPresent() && invoiceOpt.get().getStatus() != InvoiceStatus.PAID) {
                    try {
                        // Goes through the real cancellation path now - status history,
                        // subscription-quota release, and invoice cancel/refund all used to
                        // be skipped here because this used to write the entity directly
                        // ("for simplicity") instead of calling the service.
                        serviceRequestService.systemCancelForNonPayment(req.getId());
                    } catch (Exception e) {
                        throw new BadRequestException("Cancellation failed for unpaid ServiceRequest: " + req.getId() + " - " + e.getMessage());
                    }
                }
            }
        }
    }
}
