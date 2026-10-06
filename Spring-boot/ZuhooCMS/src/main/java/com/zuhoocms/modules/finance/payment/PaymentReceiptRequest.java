package com.zuhoocms.modules.finance.payment;

import com.zuhoocms.enums.PaymentMethod;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.math.BigDecimal;
import java.time.LocalDate;

@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class PaymentReceiptRequest {
    @NotNull(message = "Client ID is required")
    private Long clientId;
    private Long invoiceId;
    @NotNull(message = "Amount is required")
    // With a null invoiceId (PaymentReceiptServiceImpl.confirmPayment's unlinked branch) there is no invoice balance to validate against before the GL posting, so this is that path's only sanity check.
    @DecimalMin(value = "0.01", message = "Amount must be positive")
    private BigDecimal amount;
    @NotNull(message = "Payment date is required")
    private LocalDate paymentDate;
    @NotNull(message = "Payment method is required")
    private PaymentMethod paymentMethod;
    private String transactionReference;
    private String notes;
}
