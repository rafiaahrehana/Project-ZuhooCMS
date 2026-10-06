package com.zuhoocms.modules.servicedesk.companyservice;

import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class SubscribeRequest {

    @NotNull(message = "Package ID is required")
    private Long packageId;

    /** Set only when staff subscribe on a client's behalf; a CLIENT caller is resolved from the JWT. */
    private Long clientId;

    /** Overrides the package-level autoRenew setting when set. */
    private Boolean autoRenew;
}
