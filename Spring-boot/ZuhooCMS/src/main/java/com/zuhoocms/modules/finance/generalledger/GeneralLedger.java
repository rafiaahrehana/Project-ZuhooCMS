package com.zuhoocms.modules.finance.generalledger;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
import java.math.BigDecimal;
import java.time.LocalDate;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "general_ledger", indexes = {
        @Index(name = "idx_gl_account", columnList = "chart_of_account_id"),
        @Index(name = "idx_gl_date", columnList = "transaction_date"),
        @Index(name = "idx_gl_reference", columnList = "reference_type, reference_id")
})
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class GeneralLedger extends BaseEntity {

    private Long companyId;

    private LocalDate transactionDate;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "chart_of_account_id", nullable = false)
    private ChartOfAccount account;

    @Builder.Default
    private BigDecimal debitAmount = BigDecimal.ZERO;
    @Builder.Default
    private BigDecimal creditAmount = BigDecimal.ZERO;

    private String description; // e.g., "Payment for invoice #INV-001"

    private String referenceType; // EXPENSE, INVOICE, SALARY, VENDOR_PAYMENT, JOURNAL_ENTRY
    private Long referenceId;

    private String referenceNumber; // e.g., "INV-001", "EXP-005"

    @Builder.Default
    private boolean isReconciled = false;

    private String reconciliationNotes;

    // Which BankReconciliation cleared this line, so its "still outstanding" set is computed live instead of hand-typed.
    // A plain id rather than a @ManyToOne, to avoid a cross-package dependency on the reconciliation module - same pattern as referenceId.
    private Long reconciledInReconciliationId;

    private String postedBy;
    private LocalDate postedDate;

    @Builder.Default
    private boolean posted = true;

    public BigDecimal getAmount() {
        if (debitAmount.compareTo(BigDecimal.ZERO) > 0) {
            return debitAmount;
        }
        return creditAmount;
    }

    public String getType() {
        if (debitAmount.compareTo(BigDecimal.ZERO) > 0) {
            return "DEBIT";
        }
        return "CREDIT";
    }
}