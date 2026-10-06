package com.zuhoocms.modules.support.category;

import com.fasterxml.jackson.annotation.JsonIgnore;
import lombok.Data;

/** Accepts the category name as either {@code name} (what the Angular form sends) or {@code categoryName} (the original API key), or every create from the UI 400s. */
@Data
public class SupportCategoryRequest {
    private String categoryName;
    private String name;
    private String description;
    private boolean active = true;
    private String icon;

    /** {@code name} wins when both are present: the Angular edit form spreads the loaded response, which carries both keys, and only edits {@code name}. */
    @JsonIgnore
    public String getEffectiveName() {
        String value = name != null && !name.isBlank() ? name : categoryName;
        return value != null ? value.trim() : null;
    }
}
