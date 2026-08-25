package com.zuhoocms.modules.servicedesk.workflow.workflow;

import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageRequest;
import com.zuhoocms.modules.servicedesk.workflow.stage.WorkflowStageResponse;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplateRequest;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplateResponse;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.util.List;

public interface WorkflowService {

    WorkflowTemplateResponse createTemplate(WorkflowTemplateRequest request);

    WorkflowTemplateResponse getTemplateById(Long id);

    Page<WorkflowTemplateResponse> listTemplates(Pageable pageable);

    List<WorkflowTemplateResponse> listActiveTemplates();

    WorkflowTemplateResponse updateTemplate(Long id, WorkflowTemplateRequest request);

    WorkflowTemplateResponse toggleTemplate(Long id);

    void deleteTemplate(Long id);

    WorkflowStageResponse addStage(Long templateId, WorkflowStageRequest request);

    WorkflowStageResponse updateStage(Long templateId, Long stageId, WorkflowStageRequest request);

    void deleteStage(Long templateId, Long stageId);

    /** Suggest a new workflow's stages with AI, grounded in the company's existing templates */
    WorkflowSuggestionResponse suggest(WorkflowSuggestionRequest request);
}
