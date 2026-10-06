package com.zuhoocms.modules.servicedesk.servicerequest;

import com.zuhoocms.enums.ServiceRequestPriority;
import com.zuhoocms.enums.ServiceRequestStatus;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Getter
@Setter
public class ServiceRequestResponse {
    private Long id;
    private String title;
    private String description;
    private ServiceRequestStatus status;
    private ServiceRequestPriority priority;
    private BigDecimal agreedPrice;
    private LocalDateTime slaDeadline;
    private boolean slaBreach;
    private Integer slaBreachCount;
    private LocalDateTime firstSlaBreachedAt;
    private LocalDateTime slaPausedAt;
    private LocalDateTime assignedAt;
    private LocalDateTime completedAt;
    private int resubmitCount;
    private boolean permanentlyClosed;
    private Long companyId;
    private Long clientId;
    private String clientName;
    private Long hubServiceId;
    private String hubServiceName;
    private Long assignedEmployeeId;
    private String assignedEmployeeName;
    private long taskCount;
    private long completedTaskCount;

    // Null for standalone (pay-per-request) requests.
    private Long subscriptionId;
    private String packageName;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    
    private String paymentRedirectUrl;
    private Long invoiceId;

    // Filing reference from the government authority, e.g. type "Trade License Application" / number "TL-2026-4471".
    private String govRefNumber;
    private String govRefType;

    private BigDecimal quotationAmount;
    private String quotationCurrency;
    private String quotationNotes;
    private LocalDateTime quotationValidUntil;
    private com.zuhoocms.enums.QuotationStatus quotationStatus;

    // Keyed by ServiceFormField id.
    private java.util.Map<String, String> formData;

    private String aiSummary;
}
