package com.zuhoocms.modules.servicedesk.servicetemplate;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
// Lombok's isFinalStage() emits the stripped "finalStage", which no client reads; only the pinned "isFinalStage" below
// is part of the contract, so the duplicate is suppressed (as in SupportMessageResponse).
@JsonIgnoreProperties({"finalStage"})
public class TemplateWorkflowStageResponse {
    private Long id;
    private Long serviceTemplateId;
    private String stageName;
    private String stageDescription;
    private int stageOrder;
    private boolean requiresClientAction;
    private boolean requiresPayment;
    /**
     * Pinned like AttendanceResponse.isLate: unpinned, this shipped only as "finalStage", while the Angular templates
     * screen reads isFinalStage - so the "Final" flag never showed on a saved stage.
     */
    @JsonProperty("isFinalStage")
    private boolean isFinalStage;
}
