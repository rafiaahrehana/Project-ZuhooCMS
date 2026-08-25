package com.zuhoocms.modules.hrm.leave.leavebalance;

import com.zuhoocms.enums.LeaveType;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class LeaveBalanceResponse {
    private Long id;
    private Long employeeId;
    private String employeeName;
    private LeaveType leaveType;
    private int year;
    private int entitledDays;
    private int usedDays;
    private int pendingDays;
    private int remainingDays;
}
