package com.zuhoocms.modules.crm.lead;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDate;

/** Convert a Qualified Lead into an Opportunity. No Client is created at this point. */
@Getter @Setter
public class ConvertToOpportunityRequest {

    @NotBlank(message = "Opportunity name is required")
    private String opportunityName;

    /** @DecimalMin as well as @NotNull: convertToOpportunity hand-builds an OpportunityRequest and calls the service directly, bypassing that DTO's own @DecimalMin, so a negative value reached the forecast. */
    @NotNull(message = "Expected value is required")
    @DecimalMin(value = "0.0", message = "Expected value cannot be negative")
    private BigDecimal expectedValue;

    @NotNull(message = "Expected close date is required")
    private LocalDate expectedCloseDate;
}
