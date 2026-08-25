package com.zuhoocms.modules.servicedesk.servicetemplate;

import com.zuhoocms.enums.FormFieldType;
import lombok.Data;

@Data
public class TemplateFormFieldRequest {
    private String label;
    private FormFieldType fieldType;
    private boolean required;
    private String validationRules;
    private int sortOrder;
}
