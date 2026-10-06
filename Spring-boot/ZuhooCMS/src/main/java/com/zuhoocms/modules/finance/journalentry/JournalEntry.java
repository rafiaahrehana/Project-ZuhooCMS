package com.zuhoocms.modules.finance.journalentry;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.ColumnDefault;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

import java.math.BigDecimal;
import java.time.LocalDate;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "journal_entries", uniqueConstraints = @UniqueConstraint(columnNames = {"company_id", "journal_entry_number"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class JournalEntry extends BaseEntity {

    private Long companyId;

    @Column(name = "journal_entry_number", nullable = false)
    private String journalEntryNumber; // JE-2024-001

    private LocalDate entryDate;

    // Legacy 1:1 columns kept populated (first debit/credit line's account, total amount) because they are NOT NULL and ddl-auto=update never drops constraints; they also keep pre-lines entries displayable.
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "debit_account_id", nullable = false)
    private ChartOfAccount debitAccount;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "credit_account_id", nullable = false)
    private ChartOfAccount creditAccount;

    private BigDecimal amount; // total debits (= total credits)

    @OneToMany(mappedBy = "journalEntry", cascade = CascadeType.ALL, fetch = FetchType.LAZY, orphanRemoval = true)
    @Builder.Default
    private java.util.List<JournalEntryLine> lines = new java.util.ArrayList<>();

    private String description;
    private String notes;

    private String createdBy;
    private LocalDate createdDate;

    private String approvedBy;
    private LocalDate approvedDate;

    @Builder.Default
    private boolean approved = false;

    // Maker-checker is waived for the company owner (and an impersonating platform admin), who already hold unrestricted authority; this flags the entries that skipped a second pair of eyes for auditors.
    // @ColumnDefault is required: ddl-auto=update adds this NOT NULL column to a table that already has rows.
    @Builder.Default
    @ColumnDefault("false")
    @Column(nullable = false)
    private boolean selfApproved = false;

    @Builder.Default
    private boolean posted = false;

    private LocalDate postedDate;

    // A posted entry can be reversed once; the reversal is a second entry with debit/credit swapped, and these fields link the two.
    @Builder.Default
    private boolean reversed = false;

    private Long reversalEntryId;      // on the original: the entry that reverses it
    private Long reversedFromEntryId;  // on the reversal: the original it reverses
    private LocalDate reversedDate;

    public void markReversed(Long reversalEntryId) {
        this.reversed = true;
        this.reversalEntryId = reversalEntryId;
        this.reversedDate = LocalDate.now();
    }

    public void approve(String approverName) {
        approve(approverName, false);
    }

    /** {@code selfApproved} records that the approver was also the creator (owner override). */
    public void approve(String approverName, boolean selfApproved) {
        this.approved = true;
        this.approvedBy = approverName;
        this.approvedDate = LocalDate.now();
        this.selfApproved = selfApproved;
    }

    /** A reversal is auto-generated to offset another entry and back-links to it; reversing a reversal would re-create the original posting under a third number, so it is rejected. */
    public boolean isReversalEntry() {
        return reversedFromEntryId != null;
    }

    public void post() {
        if (!approved) {
            throw new IllegalStateException("Journal entry must be approved before posting");
        }
        this.posted = true;
        this.postedDate = LocalDate.now();
    }
}
