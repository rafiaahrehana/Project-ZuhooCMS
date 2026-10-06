package com.zuhoocms.modules.servicedesk.workflow.stage;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class WorkflowStageRequest {

    @NotBlank(message = "Stage name is required")
    @Size(max = 100, message = "Stage name must not exceed 100 characters")
    private String name;

    @Size(max = 500, message = "Description must not exceed 500 characters")
    private String description;

    @NotNull(message = "Stage order is required")
    @Min(value = 1, message = "Stage order must be at least 1")
    private Integer stageOrder;

    @Min(value = 1, message = "Estimated days must be at least 1")
    private Integer estimatedDays;

    @Min(value = 1, message = "SLA hours must be at least 1")
    private Integer slaHours;

    /**
     * Boxed AND left uninitialised, which is the whole point. Initialised to false it could never arrive null, so
     * it read as a guarded field while behaving like a primitive: updateStage assigned it unconditionally, and an
     * update that omitted the key turned the approval gate off and answered 200. Absent must mean "not mentioned";
     * create treats absent as false explicitly.
     */
    private Boolean requiresApproval;

    // String, not the Role enum: WorkflowStage stores a plain VARCHAR label that need not map 1:1 to Role.
    private String assigneeRole;

    /** Uninitialised for the same reason as requiresApproval: an omitted key silently turned milestone billing off. */
    private Boolean requiresPayment;

    @Min(value = 1, message = "Payment percent must be at least 1")
    @jakarta.validation.constraints.Max(value = 100, message = "Payment percent cannot exceed 100")
    private Integer paymentPercent;
}
