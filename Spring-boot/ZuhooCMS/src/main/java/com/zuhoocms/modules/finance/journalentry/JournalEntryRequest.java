package com.zuhoocms.modules.finance.journalentry;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
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
public class JournalEntryRequest {

    @NotNull(message = "Entry date is required")
    private LocalDate entryDate;

    /** Multi-line form: at least 2 lines, total debits must equal total credits; if omitted the server synthesizes 2 lines from the legacy fields below, so older API callers keep working. */
    @Valid
    private List<JournalEntryLineRequest> lines;

    // Legacy 1:1 form, used only when `lines` is absent.
    private Long debitAccountId;
    private Long creditAccountId;
    @Positive(message = "Amount must be positive")
    private BigDecimal amount;

    private String description;

    private String notes;
}
