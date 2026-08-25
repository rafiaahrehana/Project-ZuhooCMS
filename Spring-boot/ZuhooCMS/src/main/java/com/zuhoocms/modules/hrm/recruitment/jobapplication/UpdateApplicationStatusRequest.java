package com.zuhoocms.modules.hrm.recruitment.jobapplication;

import com.zuhoocms.enums.ApplicationStatus;
import lombok.Data;

@Data
public class UpdateApplicationStatusRequest {
    private ApplicationStatus status;
    private String notes;
}
