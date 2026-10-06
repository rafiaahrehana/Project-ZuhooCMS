package com.zuhoocms.modules.finance.chartofaccounts;

import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "chart_of_accounts", uniqueConstraints = {
        @UniqueConstraint(columnNames = {"company_id", "account_code"})
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChartOfAccount extends BaseEntity {

    private Long companyId;

    /** Optimistic-lock guard on the running `balance`: GL posting already takes a PESSIMISTIC_WRITE lock (GeneralLedgerServiceImpl.recordBalancedTransaction), and this catches any other concurrent writer. */
    @Version
    @org.hibernate.annotations.ColumnDefault("0")
    @Column(nullable = false)
    @Builder.Default
    private Long version = 0L;

    @Column(nullable = false)
    private String accountCode; // e.g., "1000", "5100"

    private String accountName; // e.g., "Cash", "Salary Expense"

    @Enumerated(EnumType.STRING)
    @Column(length = 50, nullable = false)
    private AccountType type; // ASSET, LIABILITY, REVENUE, EXPENSE, etc.

    private String description;

    @Builder.Default
    private BigDecimal balance = BigDecimal.ZERO;

    @Builder.Default
    private boolean active = true;

    @Builder.Default
    private boolean isHeaderAccount = false;

    // Marks a real bank/cash account for Bank Reconciliation's picker: without it any ASSET-type account (Fixed Assets, AR, equipment) looks identical to a bank account.
    @Builder.Default
    private boolean isBankAccount = false;

    private Long parentAccountId;

    @Builder.Default
    private boolean allowDirectPosting = true;

    private String notes;

    public BigDecimal getDebitBalance() {
        return type.isCreditNormal() ? BigDecimal.ZERO : balance;
    }

    public BigDecimal getCreditBalance() {
        return type.isCreditNormal() ? balance : BigDecimal.ZERO;
    }
}