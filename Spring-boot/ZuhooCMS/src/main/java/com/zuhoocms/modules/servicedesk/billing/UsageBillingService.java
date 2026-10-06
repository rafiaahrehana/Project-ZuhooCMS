package com.zuhoocms.modules.servicedesk.billing;
import com.zuhoocms.enums.ServiceRequestStatus;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscription;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscriptionRepository;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequestRepository;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceRequest;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceItemRequest;
import com.zuhoocms.modules.finance.invoice.ClientInvoiceService;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Service
@RequiredArgsConstructor
public class UsageBillingService {

    private final ServiceRequestRepository   serviceRequestRepository;
    private final PackageSubscriptionRepository subscriptionRepository;
    private final ClientInvoiceService       invoiceService;

    /**
     * Bills the overage unit of a completed request, once: overage is decided at consume time (ServiceRequest.overageConsumed) and the invoice id is stored on the request, since comparing the live requestsUsed counter billed quota 10 / 12 requests as 12 invoices.
     * Runs from an @Async listener with no security context, so it uses the company-explicit invoice entry points rather than invoiceService.create(), which needs a logged-in INVOICE_CREATE holder.
     */
    @Transactional
    public void handleCompletion(Long serviceRequestId, Long companyId) {
        ServiceRequest request = serviceRequestRepository.findByIdAndCompanyId(serviceRequestId, companyId)
            .orElseThrow(() -> new ResourceNotFoundException("Service request not found: " + serviceRequestId));

        if (request.getStatus() != ServiceRequestStatus.COMPLETED) {
            return;
        }
        if (!Boolean.TRUE.equals(request.getOverageConsumed())) {
            return; // this request was covered by the quota
        }
        if (request.getOverageInvoiceId() != null) {
            return; // already billed
        }

        PackageSubscription sub = request.getSubscription();
        if (sub == null) {
            return;
        }

        if (request.getCompany() != null && request.getCompany().isPlatformTenant()) {
            return;
        }

        sub = subscriptionRepository.findById(sub.getId())
            .orElseThrow(() -> new ResourceNotFoundException("Subscription not found"));

        BigDecimal overageRate = sub.getServicePackage().getOverageRate();
        if (overageRate == null || overageRate.compareTo(BigDecimal.ZERO) <= 0) {
            return;
        }

        ClientInvoiceItemRequest item = ClientInvoiceItemRequest.builder()
            .description("Overage Charge")
            .quantity(BigDecimal.ONE)
            .unitPrice(overageRate)
            .build();

        ClientInvoiceRequest invoice = ClientInvoiceRequest.builder()
            .clientId(request.getClient().getId())
            .invoiceDate(LocalDate.now())
            .dueDate(LocalDate.now().plusDays(30))
            .currency(request.getCompanyService() != null ? request.getCompanyService().getCurrency() : null)
            .notes("Overage charge: service request #" + serviceRequestId
                + " exceeded the quota of " + sub.getRequestQuota() + " requests for subscription #" + sub.getId()
                + " (" + sub.getServicePackage().getName() + ")")
            .items(List.of(item))
            .build();

        try {
            var created = invoiceService.createForCompany(companyId, invoice);
            invoiceService.sendInvoiceForCompany(companyId, created.getId());
            request.setOverageInvoiceId(created.getId());
            serviceRequestRepository.save(request);
        } catch (Exception e) {
            throw new BadRequestException(
                "Failed to generate overage invoice for request " + serviceRequestId + ": " + e.getMessage());
        }
    }
}
