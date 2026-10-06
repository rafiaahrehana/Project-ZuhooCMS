package com.zuhoocms.modules.finance.invoice;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

/** Staff-raised refund against a PAID or PARTIALLY_PAID invoice, filed as REQUESTED and then processed/rejected like any client-originated refund. */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RefundCreateRequest {

    /** In the invoice's currency; may not exceed what has actually been paid. */
    @NotNull(message = "Refund amount is required")
    @DecimalMin(value = "0.01", message = "Refund amount must be positive")
    private BigDecimal amount;

    @Size(max = 255, message = "Reason must be at most 255 characters")
    private String reason;

    /** true = credit the company wallet when processed; false/absent = paid out externally. */
    private Boolean toWallet;
}
