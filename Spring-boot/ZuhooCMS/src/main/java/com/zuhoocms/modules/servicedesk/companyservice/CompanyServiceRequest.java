package com.zuhoocms.modules.servicedesk.companyservice;

import com.zuhoocms.enums.ServicePriceType;
import com.zuhoocms.enums.ServiceRequestPriority;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.math.BigDecimal;

@Data
public class CompanyServiceRequest {

    @NotBlank(message = "Service name is required")
    @Size(max = 150)
    private String name;

    @Size(max = 150)
    private String nameBn;

    private String description;
    private String descriptionBn;

    @DecimalMin(value = "0.00", message = "Price must be zero or positive")
    private BigDecimal price;

    private ServicePriceType priceType;
    private Integer estimatedDays;
    private ServiceRequestPriority defaultPriority;
    private Long categoryId;
    private Long workflowTemplateId;
    private Long serviceTemplateId;

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
