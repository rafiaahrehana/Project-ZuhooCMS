package com.zuhoocms.modules.hrm.attendance.attendance;

import jakarta.validation.constraints.NotNull;
import lombok.*;
import java.time.LocalDate;
import java.time.LocalTime;

// AllArgsConstructor is package-private (see ChartOfAccountRequest): a public one becomes Jackson's creator and fails on any missing primitive field.
@Data
@NoArgsConstructor
@AllArgsConstructor(access = AccessLevel.PACKAGE)
@Builder
public class AttendanceRequest {

    @NotNull(message = "Employee ID is required")
    private Long employeeId;

    @NotNull(message = "Attendance date is required")
    private LocalDate attendanceDate;

    private LocalTime checkInTime;
    private LocalTime checkOutTime;

    private AttendanceMethod checkInMethod;
    private AttendanceMethod checkOutMethod;

    @NotNull(message = "Status is required")
    private AttendanceStatus status;

    private ShiftType shiftType;

    /** Accepts "isLate", matching what the manual-entry form sends. */
    @com.fasterxml.jackson.annotation.JsonProperty("isLate")
    private boolean isLate;
    private long lateMinutes;
    private String lateReason;

    private boolean isOvertime;
    private java.math.BigDecimal overtimeHours;

    private boolean leftEarly;
    private long earlyMinutes;
    private String earlyDepartureReason;

    private String adminNotes;
}
