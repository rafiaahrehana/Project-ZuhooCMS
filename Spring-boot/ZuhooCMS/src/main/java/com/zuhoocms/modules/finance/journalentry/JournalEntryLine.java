package com.zuhoocms.modules.finance.journalentry;

import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.finance.chartofaccounts.ChartOfAccount;
import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;

/** One line of a multi-line journal entry: the single debitAccount/creditAccount/amount model could only express a 1:1 entry, not one debit split across several credits. */
@Entity
@Table(name = "journal_entry_lines")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class JournalEntryLine extends BaseEntity {

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "journal_entry_id", nullable = false)
    private JournalEntry journalEntry;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "account_id", nullable = false)
    private ChartOfAccount account;

    @Builder.Default
    private BigDecimal debitAmount = BigDecimal.ZERO;

    @Builder.Default
    private BigDecimal creditAmount = BigDecimal.ZERO;

    private String lineDescription;
}
