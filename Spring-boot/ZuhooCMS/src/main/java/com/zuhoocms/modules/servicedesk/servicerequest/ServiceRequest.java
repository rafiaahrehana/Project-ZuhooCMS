package com.zuhoocms.modules.servicedesk.servicerequest;

import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.servicedesk.companyservice.CompanyService;
import com.zuhoocms.modules.servicedesk.companyservice.PackageSubscription;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.servicedesk.task.Task;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.enums.ServiceRequestPriority;
import com.zuhoocms.enums.ServiceRequestStatus;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "service_requests")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
@EqualsAndHashCode(onlyExplicitlyIncluded = true, callSuper = false)
public class ServiceRequest extends BaseEntity {

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private ServiceRequestStatus status = ServiceRequestStatus.PENDING;

    @Enumerated(EnumType.STRING)
    @Builder.Default
    private ServiceRequestPriority priority = ServiceRequestPriority.NORMAL;

    private LocalDate deadline;
    private LocalDateTime assignedAt;
    private LocalDateTime completedAt;

    @Column(precision = 12, scale = 2)
    private java.math.BigDecimal agreedPrice;

    @Builder.Default
    private Integer currentStage = 0;

    private Integer slaHours;
    private LocalDateTime slaDeadline;
    @Builder.Default
    private boolean slaBreach = false;

    // Breach history: slaBreach only flags the current deadline and is cleared on a new stage, so these keep the total record.
    private LocalDateTime firstBreachedAt;

    @org.hibernate.annotations.ColumnDefault("0")
    private Integer breachCount;

    // Set while in WAITING_CLIENT: the SLA clock is paused and the deadline is pushed out by the paused duration on resume.
    private LocalDateTime slaPausedAt;

    // Stamped when the 48h unpaid-invoice reminder goes out, so a delayed or skipped scheduler run can't drop or repeat it.
    private LocalDateTime paymentReminderSentAt;

    // True when this request consumed a unit beyond the subscription quota, decided at create time; overageInvoiceId records the completion invoice so it is billed exactly once.
    @org.hibernate.annotations.ColumnDefault("false")
    private Boolean overageConsumed;

    private Long overageInvoiceId;

    private String govRefNumber;
    private String govRefType;

    @Column(precision = 12, scale = 2)
    private java.math.BigDecimal quotationAmount;
    
    @Builder.Default
    private String quotationCurrency = "USD";
    
    @Column(columnDefinition = "TEXT")
    private String quotationNotes;
    
    private LocalDateTime quotationValidUntil;
    
    @Enumerated(EnumType.STRING)
    private com.zuhoocms.enums.QuotationStatus quotationStatus;

    private Integer clientRating;

    @Column(columnDefinition = "TEXT")
    private String clientFeedback;

    private LocalDateTime ratedAt;

    /** Client answers to the dynamic form fields, keyed by ServiceFormField id, serialized as a JSON object. */
    @Column(columnDefinition = "TEXT")
    private String formDataJson;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "hub_service_id", nullable = false)
    private CompanyService companyService;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "client_id", nullable = false)
    private Client client;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "assigned_employee_id")
    private Employee assignedEmployee;

    /** Set when raised under a package subscription (NULL = standalone pay-per-request), in which case create() calls packageService.consumeQuota(). */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "subscription_id")
    private PackageSubscription subscription;

    @OneToMany(mappedBy = "serviceRequest", fetch = FetchType.LAZY,
               cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<Task> tasks = new ArrayList<>();

    @Builder.Default
    private int resubmitCount = 0;

    @Builder.Default
    private boolean permanentlyClosed = false;

    private Long invoiceId;

    /** Marks the current deadline as breached and keeps the breach history. */
    public void markSlaBreached(LocalDateTime at) {
        this.slaBreach = true;
        this.breachCount = (this.breachCount != null ? this.breachCount : 0) + 1;
        if (this.firstBreachedAt == null) this.firstBreachedAt = at;
    }

    public void submitQuotation(java.math.BigDecimal amount, String currency, String notes, LocalDateTime validUntil) {
        this.quotationAmount = amount;
        if (currency != null) this.quotationCurrency = currency;
        this.quotationNotes = notes;
        this.quotationValidUntil = validUntil;
        this.quotationStatus = com.zuhoocms.enums.QuotationStatus.PENDING;
        this.status = ServiceRequestStatus.QUOTATION_PENDING;
    }

    public void acceptQuotation() {
        this.quotationStatus = com.zuhoocms.enums.QuotationStatus.ACCEPTED;
        this.agreedPrice = this.quotationAmount;
        this.status = ServiceRequestStatus.PENDING;
    }

    public void rejectQuotation(String reason) {
        this.quotationStatus = com.zuhoocms.enums.QuotationStatus.REJECTED;
        this.clientFeedback = reason;
        this.status = ServiceRequestStatus.PENDING;
    }
}
