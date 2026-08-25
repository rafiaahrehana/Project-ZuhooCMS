package com.zuhoocms.modules.hrm.leave.companyleavePolicy;

import lombok.Data;

@Data
public class LeavePolicyDraftRequest {
    private boolean remoteWorkAllowed;
    private String additionalContext;
}
