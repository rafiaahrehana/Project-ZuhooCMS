package com.zuhoocms.modules.finance.expense;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.auth.user.User;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity(name = "FinanceExpense")
@Table(name = "expenses", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "expense_number"}))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Expense extends BaseEntity {

    private Long companyId;

    /** Optimistic-lock guard on the approve -> pay state machine: concurrent requests both pass the status guard and post their GL transaction twice, so the version check fails the second writer. */
    @Version
    @org.hibernate.annotations.ColumnDefault("0")
    @Column(nullable = false)
    @Builder.Default
    private Long version = 0L;

    @Column(name = "expense_number", nullable = false)
    private String expenseNumber; // EXP-2024-001

    private String title;

    @Builder.Default
    private String currency = "BDT";

    @ManyToOne(fetch = FetchType.LAZY, optional = true)
    @JoinColumn(name = "employee_id", nullable = true)
    private Employee submittedBy;

    private String description;
    private BigDecimal amount;

    private String vendorName;

    private String category; // TRAVEL, MEALS, OFFICE_SUPPLIES, LICENSING, etc.

    // The COA expense account this posts to when paid; optional, falling back to generic Operating Expenses rather than letting the category label decide where it lands in the P&L.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "expense_account_id")
    private com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount expenseAccount;

    private LocalDate expenseDate;
    private String receiptUrl;

    @Builder.Default
    @Enumerated(EnumType.STRING)
    @Column(length = 50)
    private ExpenseStatus status = ExpenseStatus.PENDING;

    private LocalDateTime submittedAt;

    // Who keyed the expense in, which can differ from submittedBy when it is raised on a colleague's behalf; maker-checker bars the creator too, not just the named claimant. Nullable for pre-existing rows.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "created_by_user_id")
    private User createdBy;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "approved_by_id")
    private User approvedBy;

    private LocalDate approvedDate;
    private String approvalNotes;

    private LocalDate reimbursedDate;
    private String reimbursementMethod;
    private String referenceNumber; // Bank tx id, wire id

    private String notes;

    public void approve(User approver) {
        this.approvedBy = approver;
        this.approvedDate = LocalDate.now();
        this.status = ExpenseStatus.APPROVED;
    }

    public void reject() {
        this.status = ExpenseStatus.REJECTED;
    }

    public void markAsPaid(String reimbursementMethod, String referenceNumber) {
        this.status = ExpenseStatus.PAID;
        this.reimbursedDate = LocalDate.now();
        this.reimbursementMethod = reimbursementMethod;
        this.referenceNumber = referenceNumber;
    }
}
