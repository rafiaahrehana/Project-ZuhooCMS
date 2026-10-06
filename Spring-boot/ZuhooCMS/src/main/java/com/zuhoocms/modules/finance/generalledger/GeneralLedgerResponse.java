package com.zuhoocms.modules.finance.generalledger;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class GeneralLedgerResponse {
    private Long id;
    private Long companyId;
    private LocalDate transactionDate;
    private Long accountId;
    private String accountName;
    private String accountCode;
    private com.zuhoocms.modules.finance.chartofaccounts.AccountType accountType;
    private BigDecimal debitAmount;
    private BigDecimal creditAmount;
    private String description;
    private String referenceType;
    private Long referenceId;
    private String referenceNumber;
    // Jackson would strip the "is" prefix from isReconciled() and emit "reconciled", which doesn't match the frontend's isReconciled field.
    // The stripped "reconciled" key still ships alongside this one and is deliberately not suppressed: the Flutter app
    // reads it as a fallback (accounting_models.dart). Angular reads only the pinned "isReconciled".
    @JsonProperty("isReconciled")
    private boolean isReconciled;
    private String reconciliationNotes;
    private String postedBy;
    private LocalDate postedDate;
    private boolean posted;
}
