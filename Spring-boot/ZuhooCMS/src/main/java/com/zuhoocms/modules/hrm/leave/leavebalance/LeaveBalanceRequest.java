package com.zuhoocms.modules.hrm.leave.leavebalance;

import com.zuhoocms.enums.LeaveType;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class LeaveBalanceRequest {
    @NotNull(message = "Employee is required")
    private Long employeeId;
    @NotNull(message = "Leave type is required")
    private LeaveType leaveType;
    @NotNull(message = "Year is required")
    private Integer year;
    @NotNull(message = "Total days is required")
    @Min(value = 0, message = "Total days cannot be negative")
    private Integer totalDays;
}
