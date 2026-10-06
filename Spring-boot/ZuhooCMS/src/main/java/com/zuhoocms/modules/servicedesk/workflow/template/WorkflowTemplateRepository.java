package com.zuhoocms.modules.servicedesk.workflow.template;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/** Every query here must filter by companyId: the unscoped findAll(Pageable) and findByActiveTrue() returned every tenant's workflow templates. */
public interface WorkflowTemplateRepository extends JpaRepository<WorkflowTemplate, Long> {

    Page<WorkflowTemplate> findByCompanyId(Long companyId, Pageable pageable);

    List<WorkflowTemplate> findByCompanyIdAndActiveTrue(Long companyId);

    Optional<WorkflowTemplate> findByIdAndCompanyId(Long id, Long companyId);

    boolean existsByCompanyIdAndName(Long companyId, String name);
}
