package com.zuhoocms.modules.servicedesk.dynamicform;

import com.zuhoocms.enums.FormFieldType;
import lombok.Data;

@Data
public class ServiceFormFieldRequest {
    private String label;
    private FormFieldType fieldType;
    /** Boxed, so an update can tell "not mentioned" from "set to optional". See ServiceFormFieldServiceImpl.update. */
    private Boolean required;
    private String validationRules;
    /**
     * Boxed for the same reason as `required` above, which is the field directly before it: as a primitive it
     * defaulted to 0 on any update that omitted the key, and update assigned it unconditionally, so editing a
     * field's label silently moved it to the front and reordered the whole form.
     */
    private Integer sortOrder;
}
