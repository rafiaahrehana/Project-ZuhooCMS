package com.zuhoocms.modules.servicedesk.requeststatus;

import com.zuhoocms.enums.ServiceRequestStatus;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class ChangeRequestStatusRequest {

    @NotNull(message = "New status is required")
    private ServiceRequestStatus status;

    private String reason;
}
