package com.zuhoocms.modules.hrm.leave;

import com.zuhoocms.enums.LeaveRequestStatus;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class ReviewLeaveRequest {
    @NotNull(message = "Status is required")
    private LeaveRequestStatus status;
    private String rejectionReason;
}
