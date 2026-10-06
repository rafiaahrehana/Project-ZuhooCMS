package com.zuhoocms.modules.servicedesk.workflow.stage;

import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplate;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.core.base.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "workflow_stages",
    uniqueConstraints = @UniqueConstraint(
        columnNames = {"workflow_template_id", "stage_order"},
        name = "uq_stage_order_per_template"
    )
)
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class WorkflowStage extends BaseEntity {

    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(nullable = false)
    private Integer stageOrder;

    private Integer estimatedDays;
    private Integer slaHours;
    private Boolean requiresApproval;

    @Column(length = 100)
    private String assigneeRole;

    // Milestone billing: advanceStage() notifies the client that paymentPercent of agreedPrice is due; collection stays manual because agreedPrice may not be set yet.
    private Boolean requiresPayment;
    private Integer paymentPercent;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "workflow_template_id", nullable = false)
    private WorkflowTemplate workflowTemplate;
}
