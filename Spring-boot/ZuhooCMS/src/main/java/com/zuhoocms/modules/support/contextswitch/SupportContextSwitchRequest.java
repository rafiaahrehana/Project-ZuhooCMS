package com.zuhoocms.modules.support.contextswitch;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SupportContextSwitchRequest {

    @NotNull(message = "Company ID is required")
    private Long viewedCompanyId;

    // Required: the switch record is only useful for accountability if it says why.
    @NotBlank(message = "Purpose is required")
    @Size(max = 255, message = "Purpose must be at most 255 characters")
    private String purpose;
}
