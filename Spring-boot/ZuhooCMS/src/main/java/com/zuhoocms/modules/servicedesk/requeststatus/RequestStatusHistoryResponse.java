package com.zuhoocms.modules.servicedesk.requeststatus;

import com.zuhoocms.enums.ServiceRequestStatus;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

@Getter
@Setter
public class RequestStatusHistoryResponse {
    private Long id;
    private ServiceRequestStatus oldStatus;
    private ServiceRequestStatus newStatus;
    private String reason;
    private Long changedById;
    private String changedByName;
    private LocalDateTime changedAt;
}
