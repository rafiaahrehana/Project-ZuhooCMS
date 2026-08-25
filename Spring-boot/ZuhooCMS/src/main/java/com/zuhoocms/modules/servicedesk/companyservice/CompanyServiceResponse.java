package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.enums.ServicePriceType;
import com.zuhoocms.enums.ServiceRequestPriority;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Getter
@Setter
public class CompanyServiceResponse {
    private Long id;
    private String name;
    private String nameBn;
    private String description;
    private String descriptionBn;
    private BigDecimal price;
    private ServicePriceType priceType;
    private Integer estimatedDays;
    private ServiceRequestPriority defaultPriority;
    private boolean active;
    private Long categoryId;
    private String categoryName;
    private Long workflowTemplateId;
    private String workflowTemplateName;
    private LocalDateTime createdAt;

    private Long serviceTemplateId;
    private String serviceTemplateName;
    private String currency;
    private boolean featured;
    private boolean remote;
    private boolean onSite;
    private boolean online;
    private Integer maximumOrders;
    private boolean autoApproval;
    private boolean requiresQuotation;
    private boolean requiresDocuments;
    private boolean supportsCustomWorkflow;
    private boolean aiAssisted;
    private com.zuhoocms.enums.ServiceVisibility visibility;
}
