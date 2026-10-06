package com.zuhoocms.modules.servicedesk.document;

import lombok.Data;

@Data
public class RequiredDocumentRequest {
    private String docName;
    private String description;
    /** Boxed, so an update can tell "not mentioned" from "set to optional". See RequiredDocumentServiceImpl.update. */
    private Boolean mandatory;
    private Integer maxAgeDays;
    private String allowedFormats;
    /**
     * Boxed: as a primitive it defaulted to 0 on any update that omitted the key, and update assigned it
     * unconditionally, so editing one document's name silently moved it to the front and reordered the list.
     */
    private Integer sortOrder;
}
