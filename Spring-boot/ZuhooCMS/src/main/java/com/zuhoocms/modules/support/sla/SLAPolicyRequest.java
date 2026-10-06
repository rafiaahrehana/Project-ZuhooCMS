package com.zuhoocms.modules.support.sla;

import com.zuhoocms.modules.support.ticket.TicketPriority;
import jakarta.validation.constraints.NotNull;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

// AllArgsConstructor is package-private: a public one is picked up by Jackson as a creator and fails on a missing primitive with "Cannot map null into type int".
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor(access = AccessLevel.PACKAGE)
public class SLAPolicyRequest {

    @NotNull(message = "Policy name is required")
    private String policyName;

    private String description;

    @NotNull(message = "Applicable priority is required")
    private TicketPriority applicablePriority;

    private int firstResponseTimeHours;
    private int resolutionTimeHours;
    private boolean businessHoursOnly;
    // Boolean, not boolean: an update without "active" keeps the current value instead of silently deactivating the policy.
    private Boolean active;
    private String notes;
}
