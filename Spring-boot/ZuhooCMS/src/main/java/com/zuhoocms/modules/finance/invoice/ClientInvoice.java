package com.zuhoocms.modules.finance.invoice;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.crm.client.Client;
import com.zuhoocms.modules.servicedesk.servicerequest.ServiceRequest;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.List;
import com.zuhoocms.enums.InvoiceStatus;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "client_invoices", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "invoice_number"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class ClientInvoice extends BaseEntity {

    private Long companyId;

    @Column(name = "invoice_number", nullable = false)
    private String invoiceNumber; // INV-2024-001

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "client_id", nullable = false)
    private Client client;

    private LocalDate invoiceDate;
    private LocalDate dueDate;

    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, fetch = FetchType.LAZY, orphanRemoval = true)
    @Builder.Default
    private List<ClientInvoiceItem> items = new java.util.ArrayList<>();

    @Builder.Default
    private BigDecimal subtotal = BigDecimal.ZERO;

    // If set, taxAmount is recomputed from subtotal on every calculateTotals(); null keeps the manually typed tax amount.
    private BigDecimal taxRatePercent;
    @Builder.Default
    private BigDecimal taxAmount = BigDecimal.ZERO;

    @Builder.Default
    private BigDecimal discountAmount = BigDecimal.ZERO;

    @Builder.Default
    @Column(length = 10)
    private String currency = "BDT";

    // Base-currency units per unit of `currency` at issue time (1 for base-currency invoices); GL postings multiply by this to stay single-currency - see ClientInvoiceServiceImpl#toBase.
    @Builder.Default
    @Column(precision = 15, scale = 6)
    private BigDecimal exchangeRate = BigDecimal.ONE;

    @Builder.Default
    private BigDecimal totalAmount = BigDecimal.ZERO;

    @Builder.Default
    private BigDecimal paidAmount = BigDecimal.ZERO;

    // Cumulative amount written off via credit notes: reduces the balance owed without reversing revenue/cash the way a refund does.
    @Builder.Default
    private BigDecimal creditedAmount = BigDecimal.ZERO;

    @Builder.Default
    private BigDecimal balanceAmount = BigDecimal.ZERO;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private InvoiceStatus status = InvoiceStatus.DRAFT;

    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private PaymentTerms paymentTerms;

    private String description;
    private String notes;

    private LocalDate sentDate;
    private LocalDate paidDate;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "service_request_id")
    private ServiceRequest serviceRequest;

    /**
     * True once the issue-time revenue posting (Dr AR / Cr Revenue [+ Cr Tax]) has reached the GL; without it a re-sent invoice booked its revenue twice.
     * Nullable with a DB default so ddl-auto can add it to a populated table; pre-column invoices count as posted by their non-DRAFT status (see ClientInvoiceServiceImpl#isRevenuePosted).
     */
    @org.hibernate.annotations.ColumnDefault("false")
    @Column(name = "revenue_posted")
    private Boolean revenuePosted;

    // Concurrent recordPaymentForCompany() calls both read the same outstanding balance and each added their payment on top, together overpaying the invoice.
    // @Version puts the version in the UPDATE's WHERE clause, so the second committer fails with an optimistic-lock conflict (see GlobalExceptionHandler) instead of overpaying.
    // columnDefinition backfills a default for existing rows, since ddl-auto=update alters this table in place rather than through a scripted migration.
    @jakarta.persistence.Version
    @Column(name = "version", nullable = false, columnDefinition = "bigint default 0")
    @Builder.Default
    private Long version = 0L;

    public void calculateTotals() {
        if (items != null) {
            subtotal = items.stream()
                    .map(ClientInvoiceItem::getLineTotal)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
        }
        BigDecimal discount = discountAmount != null ? discountAmount : BigDecimal.ZERO;
        BigDecimal taxableBase = subtotal.subtract(discount).max(BigDecimal.ZERO);

        if (taxRatePercent != null) {
            taxAmount = taxableBase.multiply(taxRatePercent)
                    .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        }

        totalAmount = taxableBase.add(taxAmount != null ? taxAmount : BigDecimal.ZERO);
        BigDecimal paid = paidAmount != null ? paidAmount : BigDecimal.ZERO;
        BigDecimal credited = creditedAmount != null ? creditedAmount : BigDecimal.ZERO;
        balanceAmount = totalAmount.subtract(paid).subtract(credited);
    }

    public boolean isOverdue() {
        return dueDate != null && LocalDate.now().isAfter(dueDate) &&
                !InvoiceStatus.PAID.equals(status);
    }
}
