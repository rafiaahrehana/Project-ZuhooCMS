package com.zuhoocms.modules.servicedesk.dynamicform;

import com.zuhoocms.enums.FormFieldType;
import lombok.Data;

@Data
public class ServiceFormFieldRequest {
    private String label;
    private FormFieldType fieldType;
    private boolean required;
    private String validationRules;
    private int sortOrder;
}
