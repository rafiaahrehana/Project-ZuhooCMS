package com.zuhoocms.modules.finance.reconciliation;

import jakarta.validation.constraints.NotNull;
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
public class BankReconciliationRequest {

    @NotNull
    private Long bankAccountId;

    @NotNull
    private BigDecimal bankStatementBalance;

    /** The date the statement was drawn to, defaulting to today: the GL book balance and the outstanding set are both computed as of this date, since a statement dated the 31st must be compared against the books as they stood then. */
    private LocalDate statementDate;
}
