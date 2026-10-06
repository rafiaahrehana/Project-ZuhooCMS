package com.zuhoocms.modules.finance.invoice;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Data @NoArgsConstructor @AllArgsConstructor @Builder
public class ClientInvoiceRequest {

    @NotNull(message = "Client ID is required")
    private Long clientId;

    @NotNull(message = "Invoice date is required")
    private LocalDate invoiceDate;

    // Optional for non-CUSTOM paymentTerms, where the server derives it from invoiceDate (DUE_ON_RECEIPT = same day, NET_n = +n days); an explicit value always wins, and CUSTOM without a date is a 400.
    private LocalDate dueDate;

    @NotEmpty(message = "Invoice must have at least one item")
    private List<ClientInvoiceItemRequest> items;

    @DecimalMin(value = "0.0")
    @Builder.Default
    private BigDecimal taxAmount = BigDecimal.ZERO;

    // If provided, overrides taxAmount: tax is recomputed as (subtotal - discountAmount) * rate / 100.
    @DecimalMin(value = "0.0")
    private BigDecimal taxRatePercent;

    @DecimalMin(value = "0.0")
    @Builder.Default
    private BigDecimal discountAmount = BigDecimal.ZERO;

    private String currency;

    // Required (>0) when currency differs from the company's base currency; forced to 1 otherwise.
    @DecimalMin(value = "0.000001", message = "Exchange rate must be positive")
    private BigDecimal exchangeRate;

    private PaymentTerms paymentTerms;
    private String description;
    private String notes;

    // Set internally for an auto-generated service-request invoice (see ClientInvoiceServiceImpl#createForServiceRequest), not user-supplied.
    private Long serviceRequestId;
}