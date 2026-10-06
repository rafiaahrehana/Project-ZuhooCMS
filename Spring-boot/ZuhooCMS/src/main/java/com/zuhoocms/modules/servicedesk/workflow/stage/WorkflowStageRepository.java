package com.zuhoocms.modules.servicedesk.workflow.stage;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/** findByIdAndCompanyId keeps a stage from another company from being linked to a task in this one. */
public interface WorkflowStageRepository extends JpaRepository<WorkflowStage, Long> {

    List<WorkflowStage> findByWorkflowTemplateIdOrderByStageOrderAsc(Long templateId);

    boolean existsByWorkflowTemplateIdAndStageOrder(Long templateId, Integer stageOrder);

    Optional<WorkflowStage> findByIdAndCompanyId(Long id, Long companyId);
}
