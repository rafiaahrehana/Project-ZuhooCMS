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
    /*
     * All nine boxed, so an update can tell "not mentioned" from "set to false". As primitives they were assigned
     * unconditionally while every other field on this request was null-guarded, so a partial edit silently reset
     * them all - and three of these change how an order behaves: requiresDocuments stops asking a customer for
     * paperwork, requiresQuotation turns a quoted service into an instant one, and autoApproval starts accepting
     * orders nobody has looked at. See CompanyServiceServiceImpl.update.
     */
    private Boolean featured;
    private Boolean remote;
    private Boolean onSite;
    private Boolean online;
    private Integer maximumOrders;
    private Boolean autoApproval;
    private Boolean requiresQuotation;
    private Boolean requiresDocuments;
    private Boolean supportsCustomWorkflow;
    private Boolean aiAssisted;
    private com.zuhoocms.enums.ServiceVisibility visibility;
}
