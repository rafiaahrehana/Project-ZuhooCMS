package com.zuhoocms.modules.servicedesk.servicerequest;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class ServiceRequestReplyDraftRequest {
    @NotBlank
    private String roughNotes;
}
