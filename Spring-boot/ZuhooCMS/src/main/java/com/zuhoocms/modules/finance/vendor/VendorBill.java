package com.zuhoocms.modules.finance.vendor;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDate;

/** A bill received FROM a vendor (Accounts Payable), the mirror of ClientInvoice: approval posts Dr Expense / Cr AP, payment posts Dr AP / Cr Cash. */
@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "vendor_bills", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "bill_number"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class VendorBill extends BaseEntity {

    private Long companyId;

    /** Optimistic-lock guard on the status/paidAmount transitions: approve/pay/cancel take a PESSIMISTIC_WRITE lock (VendorBillRepository.lockByIdAndCompanyId), and this catches any other concurrent path that would double-recognize the expense or pay the vendor twice. */
    @Version
    @org.hibernate.annotations.ColumnDefault("0")
    @Column(nullable = false)
    @Builder.Default
    private Long version = 0L;

    @Column(name = "bill_number", nullable = false)
    private String billNumber; // BILL-2026-000001

    // The vendor's own invoice/reference number on their paperwork
    private String vendorReference;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "vendor_id", nullable = false)
    private Vendor vendor;

    private LocalDate billDate;
    private LocalDate dueDate;

    // The COA expense account this bill's cost posts to on approval; optional, falling back to generic Operating Expenses.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "expense_account_id")
    private com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount expenseAccount;

    @Builder.Default
    private BigDecimal subtotal = BigDecimal.ZERO;
    @Builder.Default
    private BigDecimal taxAmount = BigDecimal.ZERO;
    @Builder.Default
    private BigDecimal totalAmount = BigDecimal.ZERO;
    @Builder.Default
    private BigDecimal paidAmount = BigDecimal.ZERO;
    @Builder.Default
    private BigDecimal balanceAmount = BigDecimal.ZERO;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 30)
    private VendorBillStatus status = VendorBillStatus.DRAFT;

    private String description;

    private String createdBy;
    private String approvedBy;
    private LocalDate approvedDate;

    public void calculateTotals() {
        BigDecimal sub = subtotal != null ? subtotal : BigDecimal.ZERO;
        BigDecimal tax = taxAmount != null ? taxAmount : BigDecimal.ZERO;
        totalAmount = sub.add(tax);
        balanceAmount = totalAmount.subtract(paidAmount != null ? paidAmount : BigDecimal.ZERO);
    }
}
