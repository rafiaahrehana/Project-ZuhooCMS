package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.modules.servicedesk.servicecategory.ServiceCategory;
import com.zuhoocms.core.base.BaseEntity;
import com.zuhoocms.modules.servicedesk.workflow.template.WorkflowTemplate;
import com.zuhoocms.modules.company.Company;
import com.zuhoocms.enums.ServicePriceType;
import com.zuhoocms.enums.ServiceRequestPriority;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Filter;
import org.hibernate.annotations.FilterDef;
import org.hibernate.annotations.ParamDef;

@FilterDef(name = "tenantFilter", parameters = @ParamDef(name = "companyId", type = Long.class))
@Filter(name = "tenantFilter", condition = "company_id = :companyId")
@Entity
@Table(name = "company_services")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CompanyService extends BaseEntity {

    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    private String iconUrl;

    @Column(precision = 12, scale = 2)
    private java.math.BigDecimal price;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private ServicePriceType priceType = ServicePriceType.FIXED;

    private Integer estimatedDays;

    @Enumerated(EnumType.STRING)
    @Builder.Default
    private ServiceRequestPriority defaultPriority = ServiceRequestPriority.NORMAL;

    @Builder.Default
    private boolean active = true;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", nullable = false)
    private Company company;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id")
    private ServiceCategory category;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "workflow_template_id")
    private WorkflowTemplate workflowTemplate;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "service_template_id")
    private com.zuhoocms.modules.servicedesk.servicetemplate.ServiceTemplate serviceTemplate;

    @Column(length = 3)
    @Builder.Default
    private String currency = "USD";

    @Builder.Default
    private boolean featured = false;

    @Builder.Default
    private boolean remote = false;

    @Builder.Default
    private boolean onSite = false;

    @Builder.Default
    private boolean online = true;

    private Integer maximumOrders;

    @Builder.Default
    private boolean autoApproval = false;

    @Builder.Default
    private boolean requiresQuotation = false;

    @Builder.Default
    private boolean requiresDocuments = false;

    @Builder.Default
    private boolean supportsCustomWorkflow = false;

    @Builder.Default
    private boolean aiAssisted = false;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private com.zuhoocms.enums.ServiceVisibility visibility = com.zuhoocms.enums.ServiceVisibility.DRAFT;

    // Multi-language support
    private String nameBn;

    @Column(columnDefinition = "TEXT")
    private String descriptionBn;
}
