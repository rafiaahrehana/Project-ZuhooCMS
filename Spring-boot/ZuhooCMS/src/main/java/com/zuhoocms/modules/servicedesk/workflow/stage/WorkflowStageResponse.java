package com.zuhoocms.modules.servicedesk.workflow.stage;

import lombok.Getter;
import lombok.Setter;

import java.time.LocalDateTime;

@Getter
@Setter
public class WorkflowStageResponse {
    private Long id;
    private String name;
    private String description;
    private Integer stageOrder;
    private Integer estimatedDays;
    private Integer slaHours;
    private Boolean requiresApproval;
    // String, not the Role enum, to match WorkflowStage and WorkflowStageRequest.
    private String assigneeRole;
    private Boolean requiresPayment;
    private Integer paymentPercent;
    private LocalDateTime createdAt;
}
