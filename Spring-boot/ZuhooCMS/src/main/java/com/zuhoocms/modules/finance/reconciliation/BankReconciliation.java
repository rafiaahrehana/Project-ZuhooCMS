package com.zuhoocms.modules.finance.reconciliation;

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
@Table(name = "bank_reconciliations")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class BankReconciliation extends BaseEntity {

    private Long companyId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "bank_account_id", nullable = false)
    private ChartOfAccount bankAccount;

    private LocalDate reconciliationDate;

    private BigDecimal glBalance;
    private BigDecimal bankStatementBalance;

    // glBalance - (bankStatementBalance + outstandingDepositsTotal - outstandingChecksTotal); must be zero before this can be marked reconciled - see BankReconciliationServiceImpl.markAsReconciled.
    private BigDecimal difference;

    // Computed live from this account's GeneralLedger entries still isReconciled=false as of reconciliationDate, not hand-typed.
    @Builder.Default
    private BigDecimal outstandingDepositsTotal = BigDecimal.ZERO;
    @Builder.Default
    private BigDecimal outstandingChecksTotal = BigDecimal.ZERO;

    @Builder.Default
    private boolean reconciled = false;

    private String discrepancyNotes;
    private LocalDate reconciledDate;
    private String reconciledBy;

    // The bank statement this was matched against: audit trail for what the bank said at the time, not derivable from the GL.
    private String statementFileName;
    private String statementFileUrl;
    private java.time.LocalDateTime statementUploadedAt;

    // When the overdue reminder was sent: the scheduler fires for ANY open reconciliation past the threshold (an exact-day match lost the reminder on a missed run) and stamps this to keep it to one reminder each.
    // Nullable on purpose - existing rows must stay un-notified, so no @ColumnDefault.
    private java.time.LocalDateTime overdueNotifiedAt;

    public void markAsReconciled(String reconciledByName) {
        this.reconciled = true;
        this.reconciledDate = LocalDate.now();
        this.reconciledBy = reconciledByName;
    }

    public boolean hasDiscrepancy() {
        return difference != null && difference.compareTo(BigDecimal.ZERO) != 0;
    }
}