package com.zuhoocms.modules.servicedesk.servicerequest;

import com.zuhoocms.enums.ServiceRequestPriority;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class CreateServiceRequestRequest {

    @NotBlank(message = "Request title is required")
    @Size(max = 255)
    private String title;

    private String description;

    @NotNull(message = "Service ID is required")
    private Long hubServiceId;

    private ServiceRequestPriority priority;

    @DecimalMin(value = "0.00")
    private BigDecimal agreedPrice;

    private LocalDateTime slaDeadline;

    /** Optional: when set, quota is consumed and agreedPrice becomes ZERO (included in the package). */
    private Long subscriptionId;

    /** Not read by the create flow: an invoice is generated automatically when agreedPrice > 0. */
    private com.zuhoocms.enums.PaymentChoice paymentChoice;

    private com.zuhoocms.enums.PaymentMethod paymentMethod;

    /** Keyed by ServiceFormField id; required fields are validated server-side. */
    private java.util.Map<String, String> formData;
}
