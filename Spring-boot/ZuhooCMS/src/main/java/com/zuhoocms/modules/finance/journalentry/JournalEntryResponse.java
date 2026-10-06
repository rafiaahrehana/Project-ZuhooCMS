package com.zuhoocms.modules.finance.journalentry;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class JournalEntryResponse {
    private Long id;
    private Long companyId;
    private String journalEntryNumber;
    private LocalDate entryDate;

    // Authoritative multi-line breakdown; pre-lines entries have it synthesized from the legacy fields so every entry renders the same way.
    private List<JournalEntryLineResponse> lines;

    // Legacy 1:1 summary fields (first debit/credit account, total amount)
    private Long debitAccountId;
    private String debitAccountName;

    private Long creditAccountId;
    private String creditAccountName;

    private BigDecimal amount;
    private String description;
    private String notes;
    
    private String createdBy;
    private LocalDate createdDate;
    
    private String approvedBy;
    private LocalDate approvedDate;
    private boolean approved;

    // True when the creator approved their own entry (only the company owner or an impersonating platform admin may), so the UI and auditors can flag it.
    private boolean selfApproved;


    private boolean posted;
    private LocalDate postedDate;

    private boolean reversed;
    private Long reversalEntryId;
    private Long reversedFromEntryId;
    private LocalDate reversedDate;
}
